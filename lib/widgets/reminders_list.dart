import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/home_board_actions.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/person_navigation.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/reminder_alerts.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/board_row.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The reminders that have come due, oldest first — a reminder set for next
/// month is not something to look at today, so it is simply not here.
///
/// Combines proposal reminders (on a [MatchIdea]) with per-person "check on
/// them again" reminders set when someone goes on a break. Shared by the
/// reminders screen and the reminders panel from the home screen.
class RemindersList extends StatelessWidget {
  const RemindersList({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 24),
    this.shrinkWrap = false,
    this.onOpenMatch,
  });

  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;

  /// Runs before navigating away — used by the panel to close itself.
  final VoidCallback? onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.watch<PersonRepository>();

    final List<_ReminderEntry> entries = <_ReminderEntry>[
      for (final MatchIdea match in matchRepository.getAll())
        if (ReminderAlerts.isDue(match.reminderDate))
          _ReminderEntry.match(match, match.reminderDate!),
      for (final MapEntry<String, DateTime> reminder
          in PersonReminders.all().entries)
        if (ReminderAlerts.isDue(reminder.value) &&
            personRepository.getById(reminder.key) != null)
          _ReminderEntry.person(
            personRepository.getById(reminder.key)!,
            reminder.value,
          ),
    ]..sort((_ReminderEntry a, _ReminderEntry b) => a.date.compareTo(b.date));

    if (entries.isEmpty) {
      return EmptyReminders(theme: theme);
    }

    return ListView.separated(
      padding: padding,
      shrinkWrap: shrinkWrap,
      // Shrink-wrapped means this list is a child of another one — the panel
      // and the notifications page both put the support inbox above it — and a
      // scrollable inside a scrollable fights the finger for every drag.
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemBuilder: (BuildContext context, int index) {
        final _ReminderEntry entry = entries[index];
        final MatchIdea? match = entry.match;
        if (match != null) {
          return ReminderCard(
            match: match,
            personA: personRepository.getById(match.personAId),
            personB: personRepository.getById(match.personBId),
            onTap: () {
              onOpenMatch?.call();
              context.push('/matches/${match.id}');
            },
          );
        }
        return PersonReminderCard(
          person: entry.person!,
          date: entry.date,
          onOpenPerson: onOpenMatch,
        );
      },
    );
  }
}

/// A reminder item is either a proposal reminder or a per-person one.
class _ReminderEntry {
  _ReminderEntry.match(this.match, this.date) : person = null;
  _ReminderEntry.person(this.person, this.date) : match = null;

  final MatchIdea? match;
  final Person? person;
  final DateTime date;
}

String _first(Person? person, String fallback) {
  final String first = (person?.firstName ?? '').trim();
  if (first.isNotEmpty) {
    return first;
  }
  final String full = (person?.fullName ?? '').trim();
  return full.isNotEmpty ? full : fallback;
}

/// How a reminder date reads relative to today: an accent-driving flag and a
/// short "when" label.
({int daysDiff, bool overdue, bool dueToday, String when}) _reminderTiming(
  DateTime date,
) {
  final DateTime today = DateTime.now();
  final DateTime dateDay = DateTime(date.year, date.month, date.day);
  final DateTime todayDay = DateTime(today.year, today.month, today.day);
  final int daysDiff = dateDay.difference(todayDay).inDays;
  final bool overdue = daysDiff < 0;
  final bool dueToday = daysDiff == 0;
  final String when = overdue
      ? 'עבר זמנו'
      : dueToday
      ? 'היום'
      : AppDateUtils.futureReminderLabel(date, now: todayDay);
  return (daysDiff: daysDiff, overdue: overdue, dueToday: dueToday, when: when);
}

class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.match,
    required this.personA,
    required this.personB,
    required this.onTap,
  });

  final MatchIdea match;
  final Person? personA;
  final Person? personB;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final DateTime date = match.reminderDate!;
    final ({int daysDiff, bool overdue, bool dueToday, String when}) timing =
        _reminderTiming(date);

    final bool swap =
        personA?.gender == Gender.female || personB?.gender == Gender.male;
    final Person? male = swap ? personB : personA;
    final Person? female = swap ? personA : personB;
    final String note = (match.reminderNote ?? '').trim();
    final MatchNextStep? step = MatchStages.nextStep(match);
    // The one line: what the matchmaker asked to be reminded of, else the
    // step the idea is waiting for, and always when.
    final String what = note.isNotEmpty
        ? note
        : step == null
        ? 'לבדוק מה קורה'
        : MatchStages.shortLabel(step, male: male, female: female);

    void handled() => _markHandled(context);

    return BoardRow(
      leading: HomeCardCoupleAvatars(
        personA: female,
        personB: male,
        radius: 16,
      ),
      title: '${_first(female, 'צד א')} & ${_first(male, 'צד ב')}',
      subtitle: '${timing.when} · $what',
      subtitleColor: timing.overdue ? theme.colorScheme.error : null,
      mark: Icons.notifications_active_outlined,
      startAccent: AppColors.genderAccent(Gender.female, dark: dark),
      endAccent: AppColors.genderAccent(Gender.male, dark: dark),
      onTap: onTap,
      onLongPress: (BuildContext anchor) => HomeBoardActions.showItemMenu(
        anchor,
        HomeItemKind.idea,
        match.id,
        onHandled: handled,
      ),
      menu: BoardItemMenuButton(
        kind: HomeItemKind.idea,
        targetId: match.id,
        onHandled: handled,
      ),
    );
  }

  /// Deletes the reminder, which is what takes the proposal off the list.
  /// Undoable from the snack bar in case of a mis-tap.
  Future<void> _markHandled(BuildContext context) async {
    final DateTime? previousDate = match.reminderDate;
    if (previousDate == null) {
      return;
    }

    // Grabbed before the await: clearing the reminder removes this very card
    // from the list, so its own context is gone by the time we come back.
    final OverlayState? notices = AppNotice.capture(context);
    final MatchRepository repository = context.read<MatchRepository>();
    final String? previousNote = match.reminderNote;

    // A live idea is looked at once a month by default, so handling this
    // reminder books the next one rather than leaving the idea with none.
    if (match.status.isArchived) {
      await repository.setReminder(match.id, null);
    } else {
      await repository.setReminder(
        match.id,
        MatchRepository.defaultReminderFrom(DateTime.now()),
        note: MatchRepository.defaultReminderNote,
        journal: false,
      );
    }

    _showHandledNotice(
      notices,
      onUndo: () =>
          repository.setReminder(match.id, previousDate, note: previousNote),
    );
  }
}

void _showHandledNotice(OverlayState? notices, {required VoidCallback onUndo}) {
  AppNotice.showOn(
    notices,
    'התזכורת סומנה כטופלה',
    actionLabel: 'ביטול',
    onAction: onUndo,
  );
}

/// A per-person "check on them again" reminder (busy or on a break).
class PersonReminderCard extends StatelessWidget {
  const PersonReminderCard({
    super.key,
    required this.person,
    required this.date,
    required this.onOpenPerson,
  });

  final Person person;
  final DateTime date;
  final VoidCallback? onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final ({int daysDiff, bool overdue, bool dueToday, String when}) timing =
        _reminderTiming(date);
    final String note = (PersonReminders.noteFor(person.id) ?? '').trim();
    final String what = note.isNotEmpty
        ? note
        : '${person.profileStatus.displayNameFor(person.gender)} — לבדוק שוב';

    void handled() => _markHandled(context);

    return BoardRow(
      leading: HomeCardAvatar(person: person, radius: 20),
      title: person.fullName.trim(),
      titleColor: AppColors.genderAccent(person.gender, dark: dark),
      subtitle: '${timing.when} · $what',
      subtitleColor: timing.overdue ? theme.colorScheme.error : null,
      mark: Icons.notifications_active_outlined,
      startAccent: AppColors.genderAccent(person.gender, dark: dark),
      onTap: () {
        onOpenPerson?.call();
        openPersonProfile(context, person.id);
      },
      onLongPress: (BuildContext anchor) => HomeBoardActions.showItemMenu(
        anchor,
        HomeItemKind.person,
        person.id,
        onHandled: handled,
      ),
      menu: BoardItemMenuButton(
        kind: HomeItemKind.person,
        targetId: person.id,
        onHandled: handled,
      ),
    );
  }

  /// Clears the "check on them again" reminder, which drops this person off the
  /// active reminders list. The availability status itself is left alone.
  Future<void> _markHandled(BuildContext context) async {
    // Grabbed before the await: clearing the reminder removes this very card
    // from the list, so its own context is gone by the time we come back.
    final OverlayState? notices = AppNotice.capture(context);
    final PersonRepository repository = context.read<PersonRepository>();
    final DateTime previousDate = date;
    final String? previousNote = PersonReminders.noteFor(person.id);

    await repository.clearPersonReminder(person.id);

    _showHandledNotice(
      notices,
      onUndo: () => repository.setPersonReminder(
        person.id,
        previousDate,
        note: previousNote,
      ),
    );
  }
}

class EmptyReminders extends StatelessWidget {
  const EmptyReminders({super.key, required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Gender? userGender = context.userGender;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.notifications_none_rounded,
              size: 48,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text(
              'אין תזכורות להיום',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '{פתח|פתחי} רעיונות עתידיים {וקבע|וקבעי} לעצמך תזכורות מתי '
                      'לבדוק אותם.'
                  .forGender(userGender),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
