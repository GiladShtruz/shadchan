import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_next_step.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 6, 10);
  final DateTime sunday = DateTime(2026, 11, 1);

  NextStepInputs inputs({
    int friends = 40,
    int access = 0,
    int unread = 0,
    List<DueFriend> dueFriends = const <DueFriend>[],
    List<NamedIdea> dueIdeas = const <NamedIdea>[],
    List<NamedIdea> stale = const <NamedIdea>[],
    int cardFriends = 0,
    int suggestions = 0,
    DateTime? lastIdea,
    DateTime? lastFriend,
    Gender? gender = Gender.female,
  }) => NextStepInputs(
    friends: friends,
    now: now,
    gender: gender,
    pendingAccessRequests: access,
    unreadNotices: unread,
    dueFriends: dueFriends,
    dueIdeas: dueIdeas,
    staleIdeas: stale,
    requestableCardFriends: cardFriends,
    databaseSuggestions: suggestions,
    lastIdeaAt: lastIdea,
    lastFriendAt: lastFriend,
    weekStart: sunday,
  );

  const NamedIdea idea = NamedIdea(
    id: 'm1',
    maleName: 'דוד',
    femaleName: 'שרה',
  );

  test('the tiers come in the order of the brief for a working database', () {
    final List<NextStep> all = HomeNextSteps.candidates(
      inputs(
        access: 1,
        stale: const <NamedIdea>[idea],
        cardFriends: 3,
        suggestions: 4,
      ),
    );
    expect(all.map((NextStep s) => s.tier).toList(), <NextStepTier>[
      NextStepTier.waiting,
      NextStepTier.openIdea,
      NextStepTier.cardFriends,
      NextStepTier.suggestions,
      NextStepTier.newIdea,
      NextStepTier.addFriends,
    ]);
    expect(all[2].text, '3 חברים שלך הוסיפו כרטיס אישי – אולי מתחילים מהם?');
  });

  test('a new database is told to grow and to start from card friends', () {
    final List<NextStep> all = HomeNextSteps.candidates(
      inputs(friends: 4, cardFriends: 2, stale: const <NamedIdea>[idea]),
    );
    expect(all.first.tier, NextStepTier.cardFriends);
    expect(all[1].tier, NextStepTier.addFriends);
    // The database's own pairs are not offered to a database this small.
    expect(
      HomeNextSteps.candidates(
        inputs(friends: 4, suggestions: 5),
      ).map((NextStep s) => s.tier),
      isNot(contains(NextStepTier.suggestions)),
    );
  });

  test('one due reminder is named; several things waiting are counted', () {
    final NextStep one = HomeNextSteps.candidates(
      inputs(
        unread: 1,
        dueFriends: const <DueFriend>[DueFriend(id: 'p1', firstName: 'דביר')],
      ),
    ).first;
    expect(one.text, 'הגיע הזמן לחזור לדביר');
    expect(one.route, '/people/p1');

    final NextStep many = HomeNextSteps.candidates(
      inputs(
        unread: 4,
        dueFriends: const <DueFriend>[DueFriend(id: 'p1', firstName: 'דביר')],
      ),
    ).first;
    expect(many.text, 'יש לך 4 בקשות ועדכונים שמחכים לך');
    expect(many.route, '/reminders');
  });

  test('no idea this week says so', () {
    final NextStep step = HomeNextSteps.candidates(
      inputs(),
    ).firstWhere((NextStep s) => s.tier == NextStepTier.newIdea);
    expect(step.text, 'עוד לא פתחת רעיון השבוע – מי יכול להתאים למי?');
    expect(step.actionLabel, 'לפתיחת רעיון');

    final NextStep after = HomeNextSteps.candidates(
      inputs(lastIdea: DateTime(2026, 11, 3), gender: Gender.male),
    ).firstWhere((NextStep s) => s.tier == NextStepTier.newIdea);
    expect(after.text, isNot(contains('עוד לא')));
  });

  test('the same recommendation does not come back visit after visit', () {
    final List<NextStep> all = HomeNextSteps.candidates(
      inputs(stale: const <NamedIdea>[idea]),
    );
    NextStepMemory memory = NextStepMemory.empty;
    final List<NextStepTier> shown = <NextStepTier>[];
    for (int visit = 0; visit < 6; visit++) {
      final NextStep step = HomeNextSteps.pick(all, memory, now)!;
      shown.add(step.tier);
      memory = memory.shown(step.key, now);
    }
    // Never more than two visits in a row for the same one.
    for (int i = 2; i < shown.length; i++) {
      expect(
        shown[i] == shown[i - 1] && shown[i - 1] == shown[i - 2],
        isFalse,
        reason: '$shown',
      );
    }
    expect(shown.first, NextStepTier.openIdea);
  });

  test('something waiting is never rotated away; an acted one rests', () {
    final List<NextStep> urgent = HomeNextSteps.candidates(inputs(access: 2));
    final NextStepMemory tired = const NextStepMemory()
        .shown('access', now)
        .shown('access', now)
        .shown('access', now)
        .acted('access', now);
    expect(HomeNextSteps.pick(urgent, tired, now)!.key, 'access');

    final List<NextStep> calm = HomeNextSteps.candidates(inputs());
    final NextStepMemory acted = NextStepMemory.empty.acted(
      calm.first.key,
      now,
    );
    expect(HomeNextSteps.pick(calm, acted, now)!.key, isNot(calm.first.key));
    expect(
      HomeNextSteps.pick(
        calm,
        acted,
        now.add(HomeNextSteps.restAfterAction),
      )!.key,
      calm.first.key,
    );
  });

  test('memory survives a round trip', () {
    final NextStepMemory m = NextStepMemory.empty
        .shown('a', now)
        .shown('a', now)
        .acted('b', now);
    final NextStepMemory back = NextStepMemory.fromJson(m.toJson());
    expect(back.key, 'a');
    expect(back.streak, 2);
    expect(back.actedKey, 'b');
    expect(back.actedAt, now);
    expect(NextStepMemory.fromJson('junk').key, isNull);
  });
}
