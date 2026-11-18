import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/utils/personal_next_step.dart';
import 'package:shadchan/utils/personal_whats_new.dart';
import 'package:shadchan/widgets/personal_home_sections.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 18, 12);

  MatchmakerFriend friend(
    String uid, {
    MatchmakerFriendState state = MatchmakerFriendState.canGrant,
    DateTime? joinedAt,
  }) => MatchmakerFriend(uid: uid, name: uid, state: state, joinedAt: joinedAt);

  test('nothing new is nothing at all', () {
    expect(
      PersonalWhatsNew.build(
        friends: <MatchmakerFriend>[
          friend('old', joinedAt: now.subtract(const Duration(days: 40))),
        ],
        singleFriends: const <CardHelper>[],
        now: now,
      ),
      isEmpty,
    );
  });

  test('a matchmaker who just joined, a friend who started, unread news', () {
    final List<PersonalWhatsNewItem> items = PersonalWhatsNew.build(
      friends: <MatchmakerFriend>[
        friend('דנה', joinedAt: now.subtract(const Duration(days: 1))),
      ],
      singleFriends: <CardHelper>[
        CardHelper(
          uid: 's',
          name: 'נועה',
          joinedAt: now.subtract(const Duration(days: 2)),
        ),
      ],
      latestNewsId: 'n1',
      latestNewsTitle: 'עדכון מהצוות',
      now: now,
    );
    expect(items.map((PersonalWhatsNewItem i) => i.text), <String>[
      'שדכן חדש מאנשי הקשר שלך: דנה',
      'גם נועה התחיל/ה להשתמש בשדכן',
      'עדכון מהצוות',
    ]);
  });

  test('never says what the next action already says', () {
    final List<MatchmakerFriend> asking = <MatchmakerFriend>[
      friend('שרה', state: MatchmakerFriendState.requested),
    ];
    expect(
      PersonalWhatsNew.build(
        friends: asking,
        singleFriends: const <CardHelper>[],
        reviewDue: true,
        nextStep: PersonalNextStepKind.request,
        now: now,
      ).map((PersonalWhatsNewItem i) => i.kind),
      <PersonalWhatsNewKind>[PersonalWhatsNewKind.review],
    );
    expect(
      PersonalWhatsNew.build(
        friends: asking,
        singleFriends: const <CardHelper>[],
        reviewDue: true,
        nextStep: PersonalNextStepKind.review,
        now: now,
      ).map((PersonalWhatsNewItem i) => i.text),
      <String>['שרה ביקש גישה לכרטיס שלך'],
    );
  });

  test('read news and hidden friends are not news; at most three lines', () {
    final List<PersonalWhatsNewItem> items = PersonalWhatsNew.build(
      friends: <MatchmakerFriend>[
        for (final String u in <String>['a', 'b', 'c', 'hidden'])
          friend(u, joinedAt: now.subtract(const Duration(hours: 3))),
      ],
      singleFriends: const <CardHelper>[],
      hidden: <String>{'hidden'},
      latestNewsId: 'n1',
      seenNews: <String>{'n1'},
      reviewDue: true,
      now: now,
    );
    expect(items, hasLength(3));
    expect(
      items.where((PersonalWhatsNewItem i) => i.friend?.uid == 'hidden'),
      isEmpty,
    );
    expect(
      items.any(
        (PersonalWhatsNewItem i) => i.kind == PersonalWhatsNewKind.news,
      ),
      isFalse,
    );
  });

  test(
    'the community lines include the matchmakers and the month\'s weddings',
    () {
      final List<String> lines =
          PersonalCommunityFigure.linesFor(<String, dynamic>{
            'matchmakers': 186,
            'hebrewMonthKey': CommunityPeriods.monthKey(now),
            'engagementsMonth': 3,
          }, now);
      expect(
        lines,
        containsAll(<String>['186 שדכנים בקהילה', '3 חתונות נוספו החודש 🎉']),
      );
      // Another month's weddings are never said as this month's.
      expect(
        PersonalCommunityFigure.linesFor(<String, dynamic>{
          'hebrewMonthKey': 'H5700-01',
          'engagementsMonth': 3,
        }, now),
        isEmpty,
      );
    },
  );
}
