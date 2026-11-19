import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/idea_proposal.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/services/card_photo_privacy.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/services/notification_preferences.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/utils/shared_pool.dart';
import 'package:shadchan/widgets/network_ideas_list.dart';

Person _person(
  String id, {
  String first = 'נועה',
  String last = 'כהן',
  Gender gender = Gender.female,
  int age = 25,
  String? description = 'כרטיס עם טקסט',
  List<String> photos = const <String>['/photos/a.jpg'],
  String? phone,
  String? cardOwnerUid,
}) {
  final DateTime now = DateTime(2026, 11, 1);
  return Person(
    id: id,
    firstName: first,
    lastName: last,
    gender: gender,
    createdAt: now,
    updatedAt: now,
    description: description,
    photosPaths: photos,
    phone: phone,
    cardOwnerUid: cardOwnerUid,
    religiousLevel: ReligiousLevel.datiLeumi,
  )..setManualAge(age);
}

SharedCard _shared(
  String owner,
  String personId, {
  String first = 'נועה',
  String last = 'כהן',
  Gender gender = Gender.female,
  int age = 25,
  String? phone,
  String? cardOwnerUid,
  String ownerName = 'יונתן לוי',
}) {
  final Person p = _person(
    personId,
    first: first,
    last: last,
    gender: gender,
    age: age,
    phone: phone,
    cardOwnerUid: cardOwnerUid,
  );
  final Map<String, Object?> data = <String, Object?>{
    ...SharedCardCodec.values(p, ownerUid: owner, ownerName: ownerName),
    'photoPaths': <String>['sharedCards/$owner/$personId/a.jpg'],
  };
  return SharedCard.fromMap(Map<String, dynamic>.from(data))!;
}

CardAccess _row(String owner, {bool onward = false}) => CardAccess(
  ownerUid: owner,
  matchmakerUid: 'me',
  status: CardAccessStatus.approved,
  requestedBy: 'matchmaker',
  shareOnward: onward,
);

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('network_test');
    Hive.init(directory.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  group('what may be shared', () {
    test('only a complete card — a photo and text — is ever shared', () {
      expect(
        NetworkSharing.eligibilityOf(_person('a')),
        ShareEligibility.ready,
      );
      expect(
        NetworkSharing.eligibilityOf(_person('b', photos: const <String>[])),
        ShareEligibility.incomplete,
      );
      expect(
        NetworkSharing.eligibilityOf(_person('c', description: '  ')),
        ShareEligibility.incomplete,
      );
    });

    test("a single's own card needs the single's consent", () {
      final Person linked = _person('d', cardOwnerUid: 'single1');
      expect(
        NetworkSharing.eligibilityOf(linked, accessTo: (_) => null),
        ShareEligibility.awaitingConsent,
      );
      expect(
        NetworkSharing.eligibilityOf(linked, accessTo: (_) => _row('single1')),
        ShareEligibility.awaitingConsent,
      );
      expect(
        NetworkSharing.eligibilityOf(
          linked,
          accessTo: (_) => _row('single1', onward: true),
        ),
        ShareEligibility.ready,
      );
    });

    test('a photo the single keeps private does not make a card complete', () {
      final Person p = _person(
        'e',
        photos: const <String>['/photos/card_owner_1.jpg'],
      );
      CardPhotoPrivacy.set('e', private: true);
      expect(NetworkSharing.isComplete(p), isFalse);
      CardPhotoPrivacy.set('e', private: false);
      expect(NetworkSharing.isComplete(p), isTrue);
    });

    test('outside the database, married or without a gender: not shared', () {
      expect(
        NetworkSharing.eligibilityOf(_person('f')..hidden = true),
        ShareEligibility.notApplicable,
      );
      expect(
        NetworkSharing.eligibilityOf(
          _person('g')..profileStatus = ProfileStatus.mazelTov,
        ),
        ShareEligibility.notApplicable,
      );
      expect(
        NetworkSharing.eligibilityOf(_person('h', gender: Gender.unknown)),
        ShareEligibility.notApplicable,
      );
    });

    test('the three ways to share, and "share all" never shares a draft', () {
      final List<Person> people = <Person>[
        _person('a'),
        _person('b'),
        _person('c', photos: const <String>[]),
      ];
      NetworkSharing.debugReset(since: DateTime(2026, 10, 1));
      expect(NetworkSharing.sharedNow(people), isEmpty);
      NetworkSharing.setMode(ShareMode.all);
      expect(NetworkSharing.sharedNow(people).map((Person p) => p.id), <String>[
        'a',
        'b',
      ]);
      NetworkSharing.setMode(ShareMode.selected);
      NetworkSharing.setSelected(<String>{'b', 'c'});
      expect(NetworkSharing.sharedNow(people).map((Person p) => p.id), <String>[
        'b',
      ]);
      NetworkSharing.setMode(ShareMode.allExcept);
      NetworkSharing.setSelected(<String>{});
      NetworkSharing.setExcluded(<String>{'a'});
      expect(NetworkSharing.sharedNow(people).map((Person p) => p.id), <String>[
        'b',
      ]);
      NetworkSharing.debugReset();
    });

    test('cards from before sharing started never open by themselves', () {
      final List<Person> people = <Person>[_person('a'), _person('b')];
      NetworkSharing.debugReset();
      // Sharing starts now; both friends were added on 1.11.
      NetworkSharing.setMode(ShareMode.all);
      expect(NetworkSharing.since, isNotNull);
      expect(NetworkSharing.sharedNow(people), isEmpty);
      expect(
        NetworkSharing.earlierNotShared(people).map((Person p) => p.id),
        <String>['a', 'b'],
      );
      // Added by hand, in one go.
      NetworkSharing.add(<String>['a']);
      expect(NetworkSharing.sharedNow(people).map((Person p) => p.id), <String>[
        'a',
      ]);
      expect(
        NetworkSharing.earlierNotShared(people).map((Person p) => p.id),
        <String>['b'],
      );
      // A friend added after sharing started is in at once.
      final Person fresh = Person(
        id: 'n',
        firstName: 'דנה',
        lastName: 'לוי',
        gender: Gender.female,
        createdAt: DateTime.now().add(const Duration(minutes: 1)),
        updatedAt: DateTime.now(),
        description: 'כרטיס',
        photosPaths: const <String>['/photos/n.jpg'],
      );
      expect(NetworkSharing.chosen(fresh), isTrue);
      // Taken out again.
      NetworkSharing.remove(people.first);
      expect(NetworkSharing.sharedNow(people), isEmpty);
      NetworkSharing.debugReset();
    });

    test(
      "a single's consented personal card is in by default, unless kept out",
      () {
        final Person own = _person('s', cardOwnerUid: 'single');
        CardAccess? access(String owner) => _row(owner, onward: true);
        NetworkSharing.debugReset();
        NetworkSharing.setMode(ShareMode.selected);
        expect(
          NetworkSharing.sharedNow(<Person>[own], accessTo: access),
          hasLength(1),
        );
        NetworkSharing.remove(own);
        expect(NetworkSharing.excluded, contains('s'));
        expect(
          NetworkSharing.sharedNow(<Person>[own], accessTo: access),
          isEmpty,
        );
        // Sharing off: nothing, whatever the single said.
        NetworkSharing.debugReset();
        expect(
          NetworkSharing.sharedNow(<Person>[own], accessTo: access),
          isEmpty,
        );
      },
    );
  });

  group('the shared card document', () {
    test('carries the card and never a phone, a note or a go-between', () {
      final Person p = _person('a', phone: '0501234567')
        ..notes = 'פרטי מאוד'
        ..inquiryContactName = 'אמא'
        ..inquiryContactPhone = '0529999999';
      final Map<String, Object?> remote = SharedCardCodec.toRemote(
        p,
        ownerUid: 'u1',
        ownerName: 'יונתן',
        photoPaths: const <String>['sharedCards/u1/a/a.jpg'],
      );
      final String all = remote.values.map((Object? v) => '$v').join(' ');
      expect(all.contains('0501234567'), isFalse);
      expect(all.contains('פרטי מאוד'), isFalse);
      expect(all.contains('0529999999'), isFalse);
      expect(remote['identity'], PhoneIdentity.hash('0501234567'));
    });

    test('its fields are exactly the whitelist in firestore.rules', () {
      final Map<String, Object?> remote = SharedCardCodec.toRemote(
        _person('a'),
        ownerUid: 'u1',
        ownerName: 'יונתן',
        photoPaths: const <String>['sharedCards/u1/a/a.jpg'],
      );
      final String rules = File('firestore.rules').readAsStringSync();
      final String block = rules.substring(
        rules.indexOf('function sharedCardOk('),
      );
      final String list = block.substring(
        block.indexOf('hasOnly(['),
        block.indexOf('])'),
      );
      final Set<String> allowed = RegExp(
        r"'([A-Za-z]+)'",
      ).allMatches(list).map((RegExpMatch m) => m.group(1)!).toSet();
      expect(remote.keys.toSet(), allowed);
    });

    test('reads back as the same person', () {
      final SharedCard card = _shared('u1', 'a', age: 27);
      expect(card.person.fullName, 'נועה כהן');
      expect(card.person.age, 27);
      expect(card.person.gender, Gender.female);
      expect(card.person.religiousLevel, ReligiousLevel.datiLeumi);
      expect(card.ownerFirstName, 'יונתן');
    });
  });

  group('the shared pool, each person once', () {
    test('the same phone at two matchmakers is one card, for sure', () {
      final List<SharedPoolEntry> pool = SharedPool.build(<SharedCard>[
        _shared('u1', 'a', phone: '0501111111'),
        _shared('u2', 'b', phone: '050-1111111', ownerName: 'שרה'),
      ]);
      expect(pool, hasLength(1));
      expect(pool.single.certain, isTrue);
      expect(pool.single.holders, hasLength(2));
      expect(pool.single.sourceLabel, 'דרך 2 שדכנים');
    });

    test('one holder is named in full: "דרך יונתן כהן"', () {
      final List<SharedPoolEntry> pool = SharedPool.build(<SharedCard>[
        _shared('u1', 'a', ownerName: 'יונתן כהן'),
      ]);
      expect(pool.single.sourceLabel, 'דרך יונתן כהן');
    });

    test('the same personal card at two matchmakers is one card', () {
      final List<SharedPoolEntry> pool = SharedPool.build(<SharedCard>[
        _shared('u1', 'a', cardOwnerUid: 's1'),
        _shared('u2', 'b', cardOwnerUid: 's1', first: 'נעה'),
      ]);
      expect(pool, hasLength(1));
      expect(pool.single.certain, isTrue);
    });

    test('a similar name at two matchmakers is listed, never joined', () {
      final List<SharedPoolEntry> pool = SharedPool.build(<SharedCard>[
        _shared('u1', 'a'),
        _shared('u2', 'b', first: 'נועא', age: 26, ownerName: 'שרה'),
      ]);
      expect(pool, hasLength(2));
      for (final SharedPoolEntry e in pool) {
        expect(e.heldByMany, isFalse);
        expect(e.similar, hasLength(1));
        expect(e.similar.single.ownerUid, isNot(e.primary.ownerUid));
      }
    });

    test("a single's own personal card leads over a card typed by hand", () {
      final List<SharedPoolEntry> pool = SharedPool.build(<SharedCard>[
        _shared('u1', 'a', phone: '0501111111', first: 'נועה ישן'),
        _shared(
          'u2',
          'b',
          phone: '0501111111',
          cardOwnerUid: 's1',
          ownerName: 'שרה',
        ),
      ]);
      expect(pool, hasLength(1));
      expect(pool.single.primary.cardOwnerUid, 's1');
      expect(pool.single.holders, hasLength(2));
    });

    test('my own personal card at another matchmaker is not shown to me', () {
      final List<SharedPoolEntry> pool = SharedPool.build(
        <SharedCard>[_shared('u1', 'a', cardOwnerUid: 'me')],
        myCardOwners: <String>{'me'},
      );
      expect(pool, isEmpty);
    });

    test('never joined: different phones, different ages, one matchmaker', () {
      expect(
        SharedPool.build(<SharedCard>[
          _shared('u1', 'a', phone: '0501111111'),
          _shared('u2', 'b', phone: '0502222222'),
        ]),
        hasLength(2),
      );
      expect(
        SharedPool.build(<SharedCard>[
          _shared('u1', 'a', age: 22),
          _shared('u2', 'b', age: 30),
        ]),
        hasLength(2),
      );
      expect(
        SharedPool.build(<SharedCard>[_shared('u1', 'a'), _shared('u1', 'b')]),
        hasLength(2),
      );
    });

    test('a friend already in my own database is left out', () {
      final List<SharedPoolEntry> pool = SharedPool.build(
        <SharedCard>[
          _shared('u1', 'a', phone: '0501111111'),
          _shared('u1', 'b', first: 'דוד', gender: Gender.male),
        ],
        myIdentities: <String>{PhoneIdentity.hash('0501111111')!},
      );
      expect(pool, hasLength(1));
      expect(pool.single.primary.person.firstName, 'דוד');
    });
  });

  group('ideas from the connected matchmakers', () {
    test('pairs one of mine with one from the pool, never two of either', () {
      final List<Person> mine = <Person>[
        _person('m1', first: 'דוד', gender: Gender.male, age: 27),
        _person('m2', first: 'רחל', age: 25),
      ];
      final List<SharedCard> pool = <SharedCard>[
        _shared('u1', 'p1', first: 'שירה', age: 24),
        _shared('u1', 'p2', first: 'יוסי', gender: Gender.male, age: 28),
      ];
      final List<dynamic> pairs = NetworkIdeasList.pairs(
        mine: mine,
        pool: pool,
        proposals: const <IdeaProposal>[],
        myMatches: const [],
      );
      expect(pairs, isNotEmpty);
      for (final dynamic s in pairs) {
        final bool maleShared = (s.male as Person).id.startsWith('shared:');
        final bool femaleShared = (s.female as Person).id.startsWith('shared:');
        expect(maleShared != femaleShared, isTrue);
      }
    });

    test('a pair already offered is not suggested again', () {
      final List<Person> mine = <Person>[
        _person('m1', first: 'דוד', gender: Gender.male, age: 27),
      ];
      final List<SharedCard> pool = <SharedCard>[
        _shared('u1', 'p1', first: 'שירה', age: 24),
      ];
      final IdeaProposal offered = IdeaProposal(
        id: 'x',
        fromUid: 'me',
        toUid: 'u1',
        fromName: 'אני',
        toName: 'יונתן',
        status: IdeaProposalStatus.pending,
        target: <String, dynamic>{'personId': 'p1'},
        candidate: <String, dynamic>{'personId': 'm1'},
        note: '',
        sides: const <String, Map<String, dynamic>>{},
      );
      expect(
        NetworkIdeasList.pairs(
          mine: mine,
          pool: pool,
          proposals: <IdeaProposal>[offered],
          myMatches: const [],
        ),
        isEmpty,
      );
    });
  });

  test('network notices sit under their own switches', () {
    expect(
      NotificationPreferences.categoryOf('ideaProposal'),
      NotificationCategory.network,
    );
    expect(
      NotificationPreferences.categoryOf('chatMessage'),
      NotificationCategory.chats,
    );
    expect(
      NotificationPreferences.categoryOf('shareOnwardRequest'),
      NotificationCategory.access,
    );
  });
}
