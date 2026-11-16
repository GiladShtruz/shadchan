import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/utils/personal_next_step.dart';
import 'package:shadchan/widgets/personal_home_sections.dart';
import 'package:shadchan/utils/community_period.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 16, 15, 0);

  Person card({int photos = 3, DateTime? touched}) => Person(
    id: 'personal-card',
    firstName: 'יעל',
    lastName: 'לוי',
    gender: Gender.female,
    photosPaths: List<String>.generate(photos, (i) => '/p/$i.jpg'),
    createdAt: touched ?? now,
    updatedAt: touched ?? now,
  );

  const MatchmakerFriend canGrant = MatchmakerFriend(
    uid: 'a',
    name: 'אורי',
    state: MatchmakerFriendState.canGrant,
  );
  const MatchmakerFriend asking = MatchmakerFriend(
    uid: 'b',
    name: 'שרה',
    state: MatchmakerFriendState.requested,
    row: CardAccess(
      ownerUid: 'me',
      matchmakerUid: 'b',
      status: CardAccessStatus.pending,
      requestedBy: 'matchmaker',
      matchmakerGender: 'female',
    ),
  );

  PersonalNextStep pick({
    Person? person,
    bool live = true,
    List<MatchmakerFriend> friends = const <MatchmakerFriend>[],
    bool hasPhone = true,
    bool loaded = true,
    bool reviewDue = false,
    DateTime? touched,
  }) => PersonalNextStep.pick(
    card: person ?? card(),
    live: live,
    friends: friends,
    hidden: const <String>{},
    hasPhone: hasPhone,
    friendsLoaded: loaded,
    lastTouched: touched ?? now,
    reviewDue: reviewDue,
    gender: Gender.female,
    now: now,
  );

  group('PersonalNextStep.pick', () {
    test('a request comes before everything', () {
      final step = pick(
        friends: const [canGrant, asking],
        live: false,
        hasPhone: false,
      );
      expect(step.kind, PersonalNextStepKind.request);
      expect(step.text, 'שרה ביקשה גישה לכרטיס שלך');
      expect(step.friend, asking);
    });

    test('a draft card comes before granting', () {
      expect(
        pick(live: false, friends: const [canGrant]).kind,
        PersonalNextStepKind.finishCard,
      );
    });

    test('one friend without access is named; several are counted', () {
      final one = pick(friends: const [canGrant]);
      expect(one.kind, PersonalNextStepKind.grant);
      expect(one.friend, canGrant);
      expect(one.text, 'אורי משדך בשדכן ועדיין לא קיבל גישה לכרטיס שלך');
      final two = pick(
        friends: const [
          canGrant,
          MatchmakerFriend(
            uid: 'c',
            name: 'דוד',
            state: MatchmakerFriendState.canGrant,
          ),
        ],
      );
      expect(two.friend, isNull);
      expect(two.text, startsWith('2 חברים שלך משדכים'));
    });

    test('friends not loaded yet are never counted as nobody or somebody', () {
      expect(
        pick(friends: const [canGrant], loaded: false).kind,
        isNot(PersonalNextStepKind.grant),
      );
    });

    test('then the number, the review, a photo, a refresh, an invite', () {
      expect(pick(hasPhone: false).kind, PersonalNextStepKind.addPhone);
      expect(pick(reviewDue: true).kind, PersonalNextStepKind.review);
      final photo = pick(person: card(photos: 1));
      expect(photo.kind, PersonalNextStepKind.refresh);
      expect(photo.action, 'הוספת תמונה');
      final stale = pick(touched: now.subtract(const Duration(days: 50)));
      expect(stale.kind, PersonalNextStepKind.refresh);
      expect(stale.action, 'לרענון הכרטיס');
      final invite = pick();
      expect(invite.kind, PersonalNextStepKind.invite);
      expect(invite.text, contains('עלייך'));
    });
  });

  group('recently active matchmakers', () {
    test('minutes and hours today, days before', () {
      String label(DateTime at, {bool female = false}) =>
          MatchmakerFriends.recentActivityLabel(at, now: now, female: female);
      expect(label(now), 'פעיל ממש עכשיו');
      expect(label(now.subtract(const Duration(minutes: 1))), 'פעיל לפני דקה');
      expect(
        label(now.subtract(const Duration(minutes: 20)), female: true),
        'פעילה לפני 20 דקות',
      );
      expect(label(now.subtract(const Duration(hours: 1))), 'פעיל לפני שעה');
      expect(label(now.subtract(const Duration(hours: 2))), 'פעיל לפני שעתיים');
      expect(
        label(now.subtract(const Duration(hours: 14))),
        'פעיל לפני 14 שעות',
      );
      expect(label(DateTime(2026, 11, 15, 23)), 'פעיל אתמול');
      expect(label(DateTime(2026, 11, 14, 9)), 'פעיל לפני יומיים');
      expect(label(DateTime(2026, 11, 10, 9)), 'פעיל לפני 6 ימים');
      // A clock running ahead never reads as the future.
      expect(label(now.add(const Duration(minutes: 3))), 'פעיל ממש עכשיו');
    });

    test('most recent first, a month at most, hidden ones left out', () {
      MatchmakerFriend f(String uid, int hoursAgo) => MatchmakerFriend(
        uid: uid,
        name: uid,
        state: MatchmakerFriendState.canGrant,
        lastActiveAt: now.subtract(Duration(hours: hoursAgo)),
      );
      final list = MatchmakerFriends.recentlyActive(
        [
          f('old', 24 * 40),
          f('b', 5),
          f('a', 1),
          f('hidden', 2),
          f('c', 30),
          f('d', 50),
          const MatchmakerFriend(
            uid: 'never',
            name: 'never',
            state: MatchmakerFriendState.canGrant,
          ),
        ],
        hidden: {'hidden'},
        now: now,
      );
      expect(list.map((x) => x.uid), ['a', 'b', 'c']);
      expect(MatchmakerFriends.databaseLabel(1), 'חבר אחד במאגר');
      expect(MatchmakerFriends.databaseLabel(12), '12 חברים במאגר');
    });
  });

  test('community figures are only real, current and above zero', () {
    final lines = PersonalCommunityFigure.linesFor({
      'singles': 42,
      'weekKey': CommunityPeriods.weekKey(),
      'newSinglesWeek': 3,
      'couplesWeek': 0,
      'engagementsWeek': 1,
      'monthKey': 'M1999-01',
      'newSinglesMonth': 9,
    });
    expect(lines, [
      '42 רווקים ורווקות מנהלים כרטיס אישי בשדכן',
      '3 רווקים ורווקות הצטרפו השבוע',
      'מזל טוב! זוג מהקהילה התארס השבוע 🎉',
    ]);
    // Last week's figures are never said as this week's.
    expect(
      PersonalCommunityFigure.linesFor({'weekKey': 'old', 'couplesWeek': 5}),
      isEmpty,
    );
  });
}
