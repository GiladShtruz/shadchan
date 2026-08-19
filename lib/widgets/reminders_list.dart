import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/contact_channel.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/reminder_alerts.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';

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
      : AppDateUtils.futureReminderLabel(date, now: todayDay);
  return (daysDiff: daysDiff, overdue: overdue, dueToday: dueToday, when: when);
}

Color _reminderAccent(
  ThemeData theme,
  ({int daysDiff, bool overdue, bool dueToday, String when}) timing,
) {
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
              const SizedBox(height: 6),
              _ReminderActions(
                onDelete: () => _markHandled(context),
                onSnooze: () => _snooze(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pushes the reminder forward instead of dropping it — the proposal leaves
  /// the list until the new date comes around.
  Future<void> _snooze(BuildContext context) async {
    final MatchRepository repository = context.read<MatchRepository>();
    final DateTime? date = await ReminderSnoozeDialog.show(context);
    if (date != null) {
      await repository.setReminder(match.id, date, note: match.reminderNote);
    }
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
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final MatchRepository repository = context.read<MatchRepository>();
    final String? previousNote = match.reminderNote;

    await repository.setReminder(match.id, null);

    _showHandledSnackBar(
      messenger,
      onUndo: () =>
          repository.setReminder(match.id, previousDate, note: previousNote),
    );
  }
}

/// The two answers to a due reminder, shared by both kinds of card: drop it, or
/// push it forward to a date that suits better.
class _ReminderActions extends StatelessWidget {
  const _ReminderActions({
    required this.onDelete,
    required this.onSnooze,
    this.extra,
  });

  final VoidCallback onDelete;
  final VoidCallback onSnooze;

  /// An optional third action (WhatsApp, on a person's reminder).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // A Wrap rather than a Row: the labels do not fit side by side on a narrow
    // phone, and wrapping beats squashing them.
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilledButton.tonalIcon(
          onPressed: onSnooze,
          icon: const Icon(Icons.schedule, size: 18),
          label: const Text('הזכר בהמשך'),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
        ),
        TextButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('מחיקה'),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            visualDensity: VisualDensity.compact,
          ),
        ),
        ?extra,
      ],
    );
  }
}

/// "מתי להזכיר שוב?" — the short list behind "הזכר בהמשך".
abstract final class ReminderSnoozeDialog {
  static Future<DateTime?> show(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime base = DateTime(now.year, now.month, now.day);
    final List<({String label, DateTime date})> options =
        <({String label, DateTime date})>[
          (label: 'מחר', date: base.add(const Duration(days: 1))),
          (label: 'בעוד שבוע', date: base.add(const Duration(days: 7))),
          (label: 'בעוד שבועיים', date: base.add(const Duration(days: 14))),
          (
            label: 'בעוד חודש',
            date: DateTime(base.year, base.month + 1, base.day),
          ),
          (
            label: 'בעוד 3 חודשים',
            date: DateTime(base.year, base.month + 3, base.day),
          ),
        ];

    return showDialog<DateTime>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('מתי להזכיר שוב?'),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final ({String label, DateTime date}) option in options)
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(option.label),
                  onTap: () => Navigator.of(dialogContext).pop(option.date),
                ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('בחירת תאריך'),
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: base.add(const Duration(days: 1)),
                    firstDate: base,
                    lastDate: DateTime(base.year + 5),
                    locale: const Locale('he'),
                  );
                  if (picked != null && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(picked);
                  }
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
          ],
        );
      },
    );
  }
}

void _showHandledSnackBar(
  ScaffoldMessengerState messenger, {
  required VoidCallback onUndo,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('התזכורת סומנה כטופלה'),
        action: SnackBarAction(label: 'ביטול', onPressed: onUndo),
      ),
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
                '${person.profileStatus.displayName} — לבדוק שוב · ${_formatReminderDate(date)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if ((PersonReminders.noteFor(person.id) ?? '')
                  .isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  PersonReminders.noteFor(person.id)!,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 6),
              _ReminderActions(
                onDelete: () => _markHandled(context),
                onSnooze: () => _snooze(context),
                // Nothing at all when there is no number: this row is a
                // reminder to act, and offering a chat that cannot open is
                // worse than offering nothing.
                extra: switch (ContactChannels.forPerson(person)) {
                  ContactChannel.whatsapp => TextButton.icon(
                    onPressed: () => _openWhatsApp(context),
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
                    label: const Text('WhatsApp'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  ContactChannel.sms => TextButton.icon(
                    onPressed: () => ContactChannels.openSms(person.phone),
                    icon: const Icon(Icons.sms_outlined, size: 16),
                    label: const Text('הודעה'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  ContactChannel.none => null,
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Clears the "check on them again" reminder, which drops this person off the
  /// active reminders list. The availability status itself is left alone.
  Future<void> _markHandled(BuildContext context) async {
    // Grabbed before the await: clearing the reminder removes this very card
    // from the list, so its own context is gone by the time we come back.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final PersonRepository repository = context.read<PersonRepository>();
    final DateTime previousDate = date;
    final String? previousNote = PersonReminders.noteFor(person.id);

    await repository.clearPersonReminder(person.id);

    _showHandledSnackBar(
      messenger,
      onUndo: () => repository.setPersonReminder(
        person.id,
        previousDate,
        note: previousNote,
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

  /// Pushes the "check on them again" reminder forward.
  Future<void> _snooze(BuildContext context) async {
    final PersonRepository repository = context.read<PersonRepository>();
    final DateTime? date = await ReminderSnoozeDialog.show(context);
    if (date == null) {
      return;
    }
    await repository.setPersonReminder(
      person.id,
      date,
      note: PersonReminders.noteFor(person.id),
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
              Icons.notifications_none,
              size: 72,
              color: theme.colorScheme.primary,
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
