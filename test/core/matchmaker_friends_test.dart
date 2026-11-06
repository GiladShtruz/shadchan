import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';

CardAccess row(
  String uid,
  CardAccessStatus status, {
  bool? card,
  bool looking = false,
  bool lookingRequested = false,
  bool cardRequested = false,
  List<String>? members,
  String name = '',
}) => CardAccess(
  ownerUid: 'owner',
  matchmakerUid: uid,
  status: status,
  requestedBy: 'matchmaker',
  matchmakerName: name,
  cardGranted: card,
  lookingGranted: looking,
  lookingRequested: lookingRequested,
  cardRequested: cardRequested,
  granteeUids: members ?? <String>[uid],
);

void main() {
  test('every matchmaker friend appears once, with where they stand', () {
    final friends = MatchmakerFriends.build(
      known: const <CardHelper>[
        CardHelper(uid: 'a', name: 'אבי', databaseCount: 12),
        CardHelper(uid: 'b', name: 'בתיה'),
        CardHelper(uid: 'c', name: 'כרמל'),
        CardHelper(uid: 'd', name: 'דנה'),
      ],
      rows: <CardAccess>[
        row('a', CardAccessStatus.approved),
        row('b', CardAccessStatus.pending, name: 'בתיה לוי'),
        row('d', CardAccessStatus.blocked),
        row('e', CardAccessStatus.revoked, name: 'אלי'),
      ],
    );
    final byUid = {for (final f in friends) f.uid: f};
    expect(byUid.keys.toSet(), {'a', 'b', 'c', 'e'});
    expect(byUid['a']!.state, MatchmakerFriendState.seesCard);
    expect(byUid['a']!.databaseCount, 12);
    expect(byUid['b']!.state, MatchmakerFriendState.requested);
    expect(byUid['b']!.name, 'בתיה לוי');
    expect(byUid['c']!.state, MatchmakerFriendState.canGrant);
    // Withdrawn access: a friend to give access to again, not a stranger.
    expect(byUid['e']!.state, MatchmakerFriendState.canGrant);
  });

  test('a couple folds into the row written for their shared database', () {
    final friends = MatchmakerFriends.build(
      known: const <CardHelper>[
        CardHelper(
          uid: 'husband',
          name: 'משה',
          recipientUid: 'db',
          granteeUids: <String>['husband', 'wife'],
        ),
        CardHelper(
          uid: 'wife',
          name: 'רחל',
          recipientUid: 'db',
          granteeUids: <String>['husband', 'wife'],
        ),
      ],
      rows: <CardAccess>[
        row(
          'db',
          CardAccessStatus.approved,
          members: <String>['husband', 'wife'],
          name: 'משה ורחל',
        ),
      ],
    );
    expect(friends, hasLength(1));
    expect(friends.single.name, 'משה ורחל');
  });

  test('requests lead, then the newest friends, then by name', () {
    final friends = MatchmakerFriends.build(
      known: <CardHelper>[
        CardHelper(uid: 'old', name: 'אבי', joinedAt: DateTime(2025)),
        CardHelper(uid: 'new', name: 'תמר', joinedAt: DateTime(2026, 10)),
        const CardHelper(uid: 'unknown', name: 'בני'),
      ],
      rows: <CardAccess>[row('asker', CardAccessStatus.pending, name: 'שרה')],
    );
    expect(MatchmakerFriends.sorted(friends).map((f) => f.uid), <String>[
      'asker',
      'new',
      'old',
      'unknown',
    ]);
  });

  test('a card reader asking for "מה אני מחפש/ת" stays among the approved', () {
    final friends = MatchmakerFriends.build(
      known: const <CardHelper>[],
      rows: <CardAccess>[
        row('a', CardAccessStatus.approved, lookingRequested: true),
      ],
    );
    final f = friends.single;
    expect(f.state, MatchmakerFriendState.requested);
    expect(f.asksForLooking, isTrue);
    expect(f.asksForCard, isFalse);
    expect(MatchmakerFriends.approved(friends), hasLength(1));
    expect(MatchmakerFriends.grantable(friends), isEmpty);
    expect(MatchmakerFriends.permissionsLabel(f), 'כרטיס ✓ | מה אני מחפש —');
  });

  test('hiding tidies the list and never hides a request', () {
    final friends = MatchmakerFriends.build(
      known: const <CardHelper>[
        CardHelper(uid: 'quiet', name: 'אבי'),
        CardHelper(uid: 'asker', name: 'שרה'),
      ],
      rows: <CardAccess>[row('asker', CardAccessStatus.pending)],
    );
    const hidden = <String>{'quiet', 'asker'};
    expect(
      MatchmakerFriends.grantable(friends, hidden: hidden).map((f) => f.uid),
      <String>['asker'],
    );
    expect(
      MatchmakerFriends.hiddenOf(friends, hidden).map((f) => f.uid),
      <String>['quiet'],
    );
  });

  test('activity is said the way a person would', () {
    final now = DateTime(2026, 11, 6, 9);
    String label(int days) => MatchmakerFriends.activityLabel(
      now.subtract(Duration(days: days)),
      now,
    );
    expect(label(0), 'פעיל היום');
    expect(label(1), 'פעיל אתמול');
    expect(label(3), 'לפני 3 ימים');
    expect(label(8), 'לפני שבוע');
    expect(label(21), 'לפני 3 שבועות');
    expect(
      MatchmakerFriends.detailsLine(
        MatchmakerFriend(
          uid: 'a',
          name: 'אבי',
          state: MatchmakerFriendState.canGrant,
          databaseCount: 40,
          lastActiveAt: now,
        ),
        now,
      ),
      '40 אנשים במאגר · פעיל היום',
    );
  });
}
