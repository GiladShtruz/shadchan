import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/matchmaker_share.dart';
import 'package:shadchan/utils/known_matchmakers.dart';

const String me = 'me';

MatchmakerShare share(
  String owner,
  String reader,
  MatchmakerShareMode mode, {
  int count = 0,
  String ownerName = '',
  DateTime? updatedAt,
}) => MatchmakerShare(
  ownerUid: owner,
  readerUid: reader,
  mode: mode,
  count: count,
  ownerName: ownerName,
  updatedAt: updatedAt,
);

void main() {
  final DateTime now = DateTime(2026, 11, 20, 12);

  test('one row per direction', () {
    expect(MatchmakerShare.idFor('a', 'b'), 'a_b');
    expect(MatchmakerShare.idFor('b', 'a'), 'b_a');
    expect(MatchmakerShareMode.all.isActive, isTrue);
    expect(MatchmakerShareMode.requested.isActive, isFalse);
    expect(MatchmakerShareMode.none.isActive, isFalse);
  });

  test('everybody in the contacts is known — no request needed', () {
    final KnownMatchmakerGroups groups = KnownMatchmakers.build(
      me: me,
      helpers: <CardHelper>[
        const CardHelper(uid: 'a', name: 'אבי'),
        const CardHelper(uid: 'b', name: 'בתיה'),
      ],
      shares: const <MatchmakerShare>[],
    );
    expect(groups.connected, isEmpty);
    expect(groups.others.map((KnownMatchmaker m) => m.uid).toSet(), <String>{
      'a',
      'b',
    });
  });

  test('"connected" is at least one active share, either way', () {
    final KnownMatchmakerGroups groups = KnownMatchmakers.build(
      me: me,
      helpers: <CardHelper>[
        const CardHelper(uid: 'a', name: 'אבי'),
        const CardHelper(uid: 'b', name: 'בתיה'),
        const CardHelper(uid: 'c', name: 'כרמל'),
        const CardHelper(uid: 'd', name: 'דנה'),
      ],
      shares: <MatchmakerShare>[
        share('a', me, MatchmakerShareMode.all, count: 12),
        share(me, 'b', MatchmakerShareMode.selected, count: 3),
        share('c', me, MatchmakerShareMode.none),
        share(me, 'd', MatchmakerShareMode.requested),
      ],
    );
    expect(groups.connected.map((KnownMatchmaker m) => m.uid).toSet(), <String>{
      'a',
      'b',
    });
    final KnownMatchmaker a = groups.all.firstWhere(
      (KnownMatchmaker m) => m.uid == 'a',
    );
    expect(a.sharesWithMe, isTrue);
    expect(a.sharedWithMeCount, 12);
    expect(a.iShareWith, isFalse);
    final KnownMatchmaker b = groups.all.firstWhere(
      (KnownMatchmaker m) => m.uid == 'b',
    );
    expect(b.iShareCount, 3);
    // A stopped share is not a connection; a request leads the others.
    expect(groups.others.first.uid, 'd');
    expect(groups.others.first.askedMe, isTrue);
    expect(groups.requestCount, 1);
  });

  test('a share row with a stranger lists them; a stopped one does not', () {
    final KnownMatchmakerGroups groups = KnownMatchmakers.build(
      me: me,
      helpers: const <CardHelper>[],
      shares: <MatchmakerShare>[
        share('x', me, MatchmakerShareMode.all, ownerName: 'יונתן'),
        share('y', me, MatchmakerShareMode.none, ownerName: 'משה'),
      ],
    );
    expect(groups.all.map((KnownMatchmaker m) => m.uid), <String>['x']);
    expect(groups.connected.single.name, 'יונתן');
  });

  test('the database size is shown only once the two share something', () {
    final KnownMatchmakerGroups groups = KnownMatchmakers.build(
      me: me,
      helpers: <CardHelper>[
        CardHelper(uid: 'a', name: 'אבי', databaseCount: 40, lastActiveAt: now),
        CardHelper(
          uid: 'b',
          name: 'בתיה',
          databaseCount: 50,
          lastActiveAt: now,
        ),
      ],
      shares: <MatchmakerShare>[share('a', me, MatchmakerShareMode.all)],
    );
    final KnownMatchmaker a = groups.connected.single;
    final KnownMatchmaker b = groups.others.single;
    expect(a.detailsLine, contains('40'));
    expect(b.detailsLine.contains('50'), isFalse);
  });

  test(
    'the home carousel: new first, then most recently active, minus hidden',
    () {
      final KnownMatchmakerGroups groups = KnownMatchmakers.build(
        me: me,
        helpers: <CardHelper>[
          CardHelper(
            uid: 'old',
            name: 'ותיק',
            lastActiveAt: now.subtract(const Duration(days: 1)),
            joinedAt: now.subtract(const Duration(days: 300)),
          ),
          CardHelper(
            uid: 'active',
            name: 'פעיל',
            lastActiveAt: now,
            joinedAt: now.subtract(const Duration(days: 100)),
          ),
          CardHelper(
            uid: 'new',
            name: 'חדש',
            lastActiveAt: now.subtract(const Duration(days: 3)),
            joinedAt: now.subtract(const Duration(days: 2)),
          ),
          const CardHelper(uid: 'hidden', name: 'מוסתר'),
        ],
        shares: const <MatchmakerShare>[],
      );
      final List<KnownMatchmaker> row = KnownMatchmakers.carousel(
        groups,
        hidden: <String>{'hidden'},
        now: now,
      );
      expect(row.map((KnownMatchmaker m) => m.uid), <String>[
        'new',
        'active',
        'old',
      ]);
      expect(row.first.isNew(now), isTrue);
    },
  );

  test('a name saved in this phone wins over the one they gave themselves', () {
    final KnownMatchmakerGroups groups = KnownMatchmakers.build(
      me: me,
      helpers: <CardHelper>[
        const CardHelper(uid: 'a', name: 'Avi', phoneHash: 'h'),
      ],
      shares: const <MatchmakerShare>[],
      nameOf: (CardHelper h) => h.phoneHash == 'h' ? 'אבי מהעבודה' : null,
    );
    expect(groups.all.single.name, 'אבי מהעבודה');
  });
}
