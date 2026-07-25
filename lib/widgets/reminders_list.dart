import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';

/// Every reminder that is due, ordered by date so the ones that are due (or
/// overdue) sit at the top. Combines proposal reminders (on a [MatchIdea]) with
/// per-person "check on them again" reminders set when someone goes on a break.
/// Shared by the reminders screen and the reminders panel from the home screen.
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
        if (match.reminderDate != null)
          _ReminderEntry.match(match, match.reminderDate!),
      for (final MapEntry<String, DateTime> reminder
          in PersonReminders.all().entries)
        if (personRepository.getById(reminder.key) != null)
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
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
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

// Hebrew month names, built without `intl`'s locale data (which is not
// initialized in this app) so this can never throw at build time.
const List<String> _hebrewMonths = <String>[
  'ינואר',
  'פברואר',
  'מרץ',
  'אפריל',
  'מאי',
  'יוני',
  'יולי',
  'אוגוסט',
  'ספטמבר',
  'אוקטובר',
  'נובמבר',
  'דצמבר',
];

String _formatReminderDate(DateTime date) {
  return '${date.day} ב${_hebrewMonths[date.month - 1]} ${date.year}';
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
      : daysDiff == 1
      ? 'מחר'
      : 'בעוד $daysDiff ימים';
  return (daysDiff: daysDiff, overdue: overdue, dueToday: dueToday, when: when);
}

Color _reminderAccent(ThemeData theme, ({int daysDiff, bool overdue, bool dueToday, String when}) timing) {
  if (timing.overdue) {
    return theme.colorScheme.error;
  }
  if (timing.dueToday) {
    return theme.colorScheme.primary;
  }
  return theme.colorScheme.onSurfaceVariant;
}

class _WhenBadge extends StatelessWidget {
  const _WhenBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
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
    final DateTime date = match.reminderDate!;
    final ({int daysDiff, bool overdue, bool dueToday, String when}) timing =
        _reminderTiming(date);
    final Color accent = _reminderAccent(theme, timing);

    final String nameA = personA?.fullName.trim().isNotEmpty == true
        ? personA!.fullName.trim()
        : 'צד א';
    final String nameB = personB?.fullName.trim().isNotEmpty == true
        ? personB!.fullName.trim()
        : 'צד ב';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.notifications_active_outlined, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$nameB · $nameA',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _WhenBadge(label: timing.when, color: accent),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _formatReminderDate(date),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if ((match.reminderNote ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  match.reminderNote!.trim(),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A per-person "check on them again" reminder (set when someone goes on a
/// break). Offers a WhatsApp shortcut and a reschedule action, and opens the
/// person's page when tapped.
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
    final ({int daysDiff, bool overdue, bool dueToday, String when}) timing =
        _reminderTiming(date);
    final Color accent = _reminderAccent(theme, timing);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        onTap: () {
          onOpenPerson?.call();
          context.push('/people/${person.id}');
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.pause_circle_outline, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      person.fullName.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _WhenBadge(label: timing.when, color: accent),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'בהפסקה — לבדוק שוב · ${_formatReminderDate(date)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openWhatsApp(context),
                      icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _reschedule(context),
                      icon: const Icon(Icons.schedule, size: 16),
                      label: const Text('תזכורת חדשה'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('אין מספר טלפון תקין לאיש הקשר')),
        );
    }
  }

  Future<void> _reschedule(BuildContext context) async {
    final PersonRepository repository = context.read<PersonRepository>();
    final ReminderChoice? choice = await ReminderPickerSheet.show(
      context,
      title: 'מתי לבדוק שוב?',
      allowClear: true,
      intervalsBuilder: ReminderPickerSheet.breakIntervals,
    );
    if (choice == null) {
      return;
    }
    if (choice.date == null) {
      await repository.clearPersonReminder(person.id);
    } else {
      await repository.setPersonReminder(person.id, choice.date!);
    }
  }
}

class EmptyReminders extends StatelessWidget {
  const EmptyReminders({super.key, required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.notifications_none,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'אין תזכורות',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'אפשר להוסיף תזכורת מתוך הצעה, והיא תופיע כאן.',
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
