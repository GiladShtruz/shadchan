import 'package:shadchan/models/card_access.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/account_sync_engine.dart';
import 'package:shadchan/services/card_sync_engine.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/tag_catalog.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';
import 'package:shadchan/widgets/home_card_friends.dart';

Person _person(
  String id, {
  List<String> tags = const <String>[],
  DateTime? updatedAt,
  Gender gender = Gender.female,
}) {
  final DateTime at = updatedAt ?? DateTime(2026, 1, 1);
  return Person(
    id: id,
    firstName: id,
    lastName: '',
    gender: gender,
    tags: List<String>.of(tags),
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  group('the shared list', () {
    test('fifty tags to start with, no duplicates', () {
      expect(TagCatalog.defaults, hasLength(50));
      expect(TagCatalog.clean(TagCatalog.defaults), hasLength(50));
    });

    test('cleaning keeps the order and drops repeats and blanks', () {
      expect(TagCatalog.clean(<String>['טבע', ' ', 'טבע ', 'ספרים']), <String>[
        'טבע',
        'ספרים',
      ]);
    });
  });

  group('a personal card\'s tags on a matchmaker\'s copy', () {
    test('the card carries the owner\'s tags', () {
      final Person card = _person('me', tags: <String>['טיולים', 'ספרים']);
      final Map<String, Object?> remote = PersonalCardCodec.toRemote(
        card,
        ownerUid: 'u1',
        photoPaths: const <String>[],
      );
      expect(remote['tags'], <String>['טיולים', 'ספרים']);
    });

    test('owner adds and removes; the matchmaker\'s own tags stay', () {
      expect(
        PersonalCardCodec.mergeTags(
          local: <String>['עירוניסט/ית', 'טיולים', 'ספרים'],
          previousRemote: <String>['טיולים', 'ספרים'],
          remote: <String>['ספרים', 'מוזיקלי/ת'],
        ),
        <String>['עירוניסט/ית', 'ספרים', 'מוזיקלי/ת'],
      );
    });

    test('applying a card version merges tags field by field', () {
      final Person friend = _person('f', tags: <String>['שלי']);
      CardSyncEngine.apply(
        friend,
        <String, dynamic>{
          'firstName': 'f',
          'tags': <String>['טבע'],
        },
        ownerUid: 'owner',
        localPhotoPaths: null,
      );
      expect(friend.tags, <String>['שלי', 'טבע']);
      final Map<String, Object?> baseline = CardSyncEngine.baselineOf(
        <String, dynamic>{
          'firstName': 'f',
          'tags': <String>['טבע'],
        },
      );
      CardSyncEngine.apply(
        friend,
        <String, dynamic>{
          'firstName': 'f',
          'tags': <String>['ספרים'],
        },
        ownerUid: 'owner',
        localPhotoPaths: null,
        previousRemote: baseline,
      );
      expect(friend.tags, <String>['שלי', 'ספרים']);
    });
  });

  group('shared tags lift a candidate', () {
    test('more shared tags first, then the most recently updated', () {
      final Person source = _person(
        's',
        gender: Gender.male,
        tags: <String>['טבע', 'ספרים', 'מוזיקלי/ת'],
      );
      final Person none = _person('none', updatedAt: DateTime(2026, 5, 1));
      final Person one = _person(
        'one',
        tags: <String>['טבע'],
        updatedAt: DateTime(2026, 2, 1),
      );
      final Person two = _person(
        'two',
        tags: <String>['ספרים', 'מוזיקלי/ת'],
        updatedAt: DateTime(2026, 1, 1),
      );
      final List<Person> sorted = <Person>[none, one, two]
        ..sort(
          (Person a, Person b) =>
              MatchSuggestionUtils.byTagsThenRecency(source, a, b),
        );
      expect(sorted.map((Person p) => p.id), <String>['two', 'one', 'none']);
      expect(MatchSuggestionUtils.sharedTags(source, two), <String>[
        'ספרים',
        'מוזיקלי/ת',
      ]);
    });
  });

  group('"החברים שלך בשדכן" on the home screen', () {
    Person person(String id, {String? text = 'כרטיס', bool photo = true}) =>
        Person(
          id: id,
          firstName: id,
          lastName: '',
          gender: Gender.female,
          description: text,
          photosPaths: photo ? <String>['/p/$id.jpg'] : const <String>[],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('every full card with a photo, newest activity first', () {
      final Person old = person('old');
      final Person edited = person('edited');
      final Person approved = person('approved')..cardOwnerUid = 'approved';
      final Person byHand = person('by-hand')
        ..updatedAt = DateTime(2026, 11, 12);
      final Person hidden = person('hidden')..hidden = true;
      final List<CardFriendSlide> slides = HomeCardFriendsSection.slidesFor(
        <Person>[
          old,
          edited,
          approved,
          byHand,
          hidden,
          person('no-photo', photo: false),
          person('no-text', text: '  '),
        ],
        latestEventByPerson: <String, DateTime>{
          'edited': DateTime(2026, 11, 10),
        },
        rowOf: (String owner) => owner == 'approved'
            ? CardAccess(
                ownerUid: owner,
                matchmakerUid: 'me',
                status: CardAccessStatus.approved,
                requestedBy: 'owner',
                updatedAt: DateTime(2026, 11, 15),
              )
            : null,
      );
      expect(slides.map((CardFriendSlide s) => s.person.id), <String>[
        'approved',
        'by-hand',
        'edited',
        'old',
      ]);
    });

    test('the newest lead; the rest turn over with the visit', () {
      final List<CardFriendSlide> ranked = <CardFriendSlide>[
        for (int i = 0; i < 30; i++)
          CardFriendSlide(
            person: person('p$i'),
            lastActivityAt: DateTime(2026, 1, 30 - i),
          ),
      ];
      bool all(CardFriendSlide _) => true;
      final List<CardFriendSlide> a = HomeCardFriendsSection.pick(
        ranked,
        seed: 0,
        hasPhoto: all,
      );
      final List<CardFriendSlide> b = HomeCardFriendsSection.pick(
        ranked,
        seed: 1,
        hasPhoto: all,
      );
      expect(a, hasLength(HomeCardFriendsSection.maxSlides));
      expect(a.take(6).map((CardFriendSlide s) => s.person.id), <String>[
        'p0',
        'p1',
        'p2',
        'p3',
        'p4',
        'p5',
      ]);
      expect(
        b.take(6).map((CardFriendSlide s) => s.person.id),
        a.take(6).map((CardFriendSlide s) => s.person.id),
      );
      expect(a[6].person.id, isNot(b[6].person.id));
      expect(a.map((CardFriendSlide s) => s.person.id).toSet(), hasLength(20));
    });
  });

  test('automatic retries back off to every two minutes', () {
    expect(AccountSyncEngine.retryDelay(0), const Duration(seconds: 5));
    expect(AccountSyncEngine.retryDelay(3), const Duration(seconds: 40));
    expect(AccountSyncEngine.retryDelay(99), const Duration(minutes: 2));
  });
}
