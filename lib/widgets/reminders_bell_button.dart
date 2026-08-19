import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/reminders_panel.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/utils/person_reminders.dart';

/// The bell, drawn the same way in the same slot on all three main screens.
///
/// It used to be three different bells: the home screen hid its own whenever
/// no reminder existed and never carried a count, the ideas screen counted
/// only the proposals it happened to be listing, and המאגר שלי had none at
/// all. A control that moves between pages — or disappears from one of them —
/// is not a control anybody learns; it is looked for and then hunted for.
///
/// So the bell is always there, always the first action in the bar (in RTL,
/// the innermost of the left-hand group), and its badge counts everything that
/// has actually come due — reminders on people as well as on proposals, since
/// the panel behind it lists both.
class RemindersBellButton extends StatelessWidget {
  const RemindersBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    // Watched, so marking a reminder as handled inside the panel takes its
    // number off the bell without the screen being rebuilt for another reason.
    final MatchRepository matches = context.watch<MatchRepository>();
    final int due = _dueCount(matches);

    return IconButton(
      tooltip: 'תזכורות',
      icon: Badge.count(
        count: due,
        isLabelVisible: due > 0,
        child: Icon(
          // An empty bell stays quiet; a bell with something behind it is
          // filled, which is the difference the eye catches from across the
          // screen before it reads the number.
          due > 0
              ? Icons.notifications_active_rounded
              : Icons.notifications_outlined,
        ),
      ),
      onPressed: () => RemindersPanel.show(context),
    );
  }

  /// Reminders whose date has arrived — today counts, tomorrow does not.
  int _dueCount(MatchRepository repository) {
    final DateTime now = DateTime.now();
    final DateTime endOfToday = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
    );

    bool isDue(DateTime? date) => date != null && !date.isAfter(endOfToday);

    final int ideas = repository
        .getAll()
        .where(
          (MatchIdea match) =>
              !match.status.isArchived && isDue(match.reminderDate),
        )
        .length;
    final int people = PersonReminders.all().values.where(isDue).length;

    return ideas + people;
  }
}
