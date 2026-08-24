import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/dating_check_in.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_stage.dart';

/// What "יאללה לקדם" knows, asserted away from the widget tree.
///
/// The card's main button is now derived rather than fixed, which makes the
/// derivation the feature: a stage read wrong is a matchmaker told to ring
/// somebody they rang last week, and no amount of layout testing catches that.
void main() {
  MatchIdea proposal({
    MatchStatus status = MatchStatus.idea,
    DateTime? askedMaleAt,
    DateTime? askedFemaleAt,
    DateTime? updatedAt,
    DateTime? reminderDate,
    int? checkInEveryDays,
  }) {
    final DateTime now = updatedAt ?? DateTime(2026, 8, 24);
    return MatchIdea(
      id: 'm1',
      personAId: 'male',
      personBId: 'female',
      status: status,
      currentHandler: CurrentHandler.me,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: now,
      askedMaleAt: askedMaleAt,
      askedFemaleAt: askedFemaleAt,
      reminderDate: reminderDate,
      checkInEveryDays: checkInEveryDays,
    );
  }

  Person candidate(String id, String first, Gender gender) {
    return Person(
      id: id,
      firstName: first,
      lastName: 'לוי',
      gender: gender,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
    );
  }

  group('the stage', () {
    test('is read off the two dates and the status, never stored', () {
      expect(MatchStage.of(proposal()), MatchStage.newIdea);
      expect(
        MatchStage.of(proposal(askedMaleAt: DateTime(2026, 8, 20))),
        MatchStage.askedMale,
      );
      expect(
        MatchStage.of(proposal(askedFemaleAt: DateTime(2026, 8, 20))),
        MatchStage.askedFemale,
      );
      expect(
        MatchStage.of(
          proposal(
            askedMaleAt: DateTime(2026, 8, 20),
            askedFemaleAt: DateTime(2026, 8, 21),
          ),
        ),
        MatchStage.askedBoth,
      );
    });

    test('a couple who are out are past the process entirely', () {
      // Even with both dates set, and even with neither: the status wins,
      // because it is the one fact the rest of the app already acts on.
      expect(
        MatchStage.of(proposal(status: MatchStatus.dating)),
        MatchStage.dating,
      );
      expect(
        MatchStage.of(
          proposal(
            status: MatchStatus.dating,
            askedMaleAt: DateTime(2026, 8, 20),
          ),
        ),
        MatchStage.dating,
      );
    });
  });

  group('the next step', () {
    test('walks the process, boy first by default', () {
      expect(MatchStages.nextStep(proposal()), MatchNextStep.askMale);
      expect(
        MatchStages.nextStep(proposal(askedMaleAt: DateTime(2026, 8, 20))),
        MatchNextStep.askFemale,
      );
      expect(
        MatchStages.nextStep(proposal(askedFemaleAt: DateTime(2026, 8, 20))),
        MatchNextStep.askMale,
      );
      expect(
        MatchStages.nextStep(
          proposal(
            askedMaleAt: DateTime(2026, 8, 20),
            askedFemaleAt: DateTime(2026, 8, 21),
          ),
        ),
        MatchNextStep.startDating,
      );
    });

    test('a finished proposal has none, and offers no button', () {
      for (final MatchStatus status in <MatchStatus>[
        MatchStatus.rejected,
        MatchStatus.dated,
        MatchStatus.married,
      ]) {
        expect(MatchStages.nextStep(proposal(status: status)), isNull);
      }
      expect(
        MatchStages.nextStep(proposal(status: MatchStatus.dating)),
        isNull,
      );
    });

    test('the choice of which side to start with is offered exactly once', () {
      // While it is still a choice — and never afterwards, because by then the
      // remaining side is the remaining side.
      expect(MatchStages.otherFirstStep(proposal()), MatchNextStep.askFemale);
      expect(
        MatchStages.otherFirstStep(
          proposal(askedMaleAt: DateTime(2026, 8, 20)),
        ),
        isNull,
      );
      expect(
        MatchStages.otherFirstStep(proposal(status: MatchStatus.rejected)),
        isNull,
      );
    });

    test('the button says the name where there is one, and the role where '
        'there is not', () {
      expect(
        MatchStages.buttonLabel(
          MatchNextStep.askMale,
          male: candidate('male', 'דוד', Gender.male),
        ),
        'יאללה לקדם — לשאול את דוד',
      );
      // A name that vanished from the database must not produce
      // "לשאול את " with nothing after it.
      expect(
        MatchStages.buttonLabel(MatchNextStep.askFemale),
        'יאללה לקדם — לשאול את הבחורה',
      );
    });
  });

  group('a proposal nothing has happened to', () {
    test('says so after a week, and scales its wording after that', () {
      final DateTime now = DateTime(2026, 8, 24);
      String? nudgeAfter(int days) => MatchStaleness.nudge(
        proposal(updatedAt: now.subtract(Duration(days: days))),
        now: now,
      );

      expect(nudgeAfter(6), isNull);
      expect(nudgeAfter(7), 'עבר שבוע בלי עדכון – שווה לקדם את הרעיון');
      expect(nudgeAfter(21), 'עברו 3 שבועות בלי עדכון – שווה לקדם את הרעיון');
      expect(nudgeAfter(31), 'עבר חודש בלי עדכון – שווה לקדם את הרעיון');
      expect(nudgeAfter(95), 'עברו 3 חודשים בלי עדכון – שווה לקדם את הרעיון');
    });

    test('a closed proposal is never nudged', () {
      final DateTime now = DateTime(2026, 8, 24);
      expect(
        MatchStaleness.nudge(
          proposal(
            status: MatchStatus.rejected,
            updatedAt: DateTime(2026, 1, 1),
          ),
          now: now,
        ),
        isNull,
      );
    });
  });

  group('a couple who are out', () {
    MatchStatusEvent moved(DateTime at) => MatchStatusEvent(
      id: 'e${at.millisecondsSinceEpoch}',
      matchId: 'm1',
      fromStatus: MatchStatus.checking,
      toStatus: MatchStatus.dating,
      createdAt: at,
    );

    test('start when the ledger says they did, not when the record was '
        'last touched', () {
      final MatchIdea match = proposal(
        status: MatchStatus.dating,
        updatedAt: DateTime(2026, 8, 24),
      );
      expect(
        DatingCheckIn.startedAt(
          match,
          events: <MatchStatusEvent>[moved(DateTime(2026, 8, 10))],
        ),
        DateTime(2026, 8, 10),
      );
      // The latest move into "יוצאים" is the one still running: a couple who
      // stopped and started again have not been out since March.
      expect(
        DatingCheckIn.startedAt(
          match,
          events: <MatchStatusEvent>[
            moved(DateTime(2026, 3, 1)),
            moved(DateTime(2026, 8, 10)),
          ],
        ),
        DateTime(2026, 8, 10),
      );
      // Nothing in the ledger — a record written before it existed.
      expect(DatingCheckIn.startedAt(match), DateTime(2026, 8, 24));
      // And a proposal that is not dating has no start at all.
      expect(DatingCheckIn.startedAt(proposal()), isNull);
    });

    test('are described in the unit a person would use', () {
      expect(
        DatingCheckIn.headline(7),
        'הם יוצאים כבר 7 ימים 😊 בדקת איך הולך?',
      );
      expect(DatingCheckIn.headline(1), 'הם יוצאים כבר יום 😊 בדקת איך הולך?');
      expect(
        DatingCheckIn.headline(14),
        'הם יוצאים כבר שבועיים 😊 בדקת איך הולך?',
      );
      expect(
        DatingCheckIn.headline(90),
        'הם יוצאים כבר 3 חודשים 😊 בדקת איך הולך?',
      );
      // A clock that has gone backwards must not produce "כבר -2 ימים".
      expect(
        DatingCheckIn.daysOut(
          DateTime(2026, 8, 26),
          now: DateTime(2026, 8, 24),
        ),
        0,
      );
    });

    test('are asked about after a week, then on their own cadence', () {
      final DateTime started = DateTime(2026, 8, 10);

      // Inside the first week, the answer is the first check and nothing else.
      expect(
        DatingCheckIn.nextCheckAt(
          proposal(status: MatchStatus.dating),
          startedAt: started,
          now: DateTime(2026, 8, 12),
        ),
        DateTime(2026, 8, 17),
      );

      // After it, a month on from the check that has just happened.
      expect(
        DatingCheckIn.nextCheckAt(
          proposal(
            status: MatchStatus.dating,
            reminderDate: DateTime(2026, 8, 17),
          ),
          startedAt: started,
          now: DateTime(2026, 8, 18),
        ),
        DateTime(2026, 9, 16),
      );

      // A frequency the matchmaker chose is what is used.
      expect(
        DatingCheckIn.nextCheckAt(
          proposal(
            status: MatchStatus.dating,
            reminderDate: DateTime(2026, 8, 17),
            checkInEveryDays: 7,
          ),
          startedAt: started,
          now: DateTime(2026, 8, 18),
        ),
        DateTime(2026, 8, 24),
      );

      // And a proposal nobody looked at for months books its next check in the
      // future rather than one that fires the instant it is set.
      final DateTime next = DatingCheckIn.nextCheckAt(
        proposal(
          status: MatchStatus.dating,
          reminderDate: DateTime(2026, 2, 1),
        ),
        startedAt: DateTime(2026, 1, 1),
        now: DateTime(2026, 8, 24),
      );
      expect(next.isAfter(DateTime(2026, 8, 24)), isTrue);
    });
  });
}
