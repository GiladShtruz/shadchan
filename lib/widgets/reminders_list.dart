import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';

/// Every proposal that has a reminder set, ordered by date so the ones that are
/// due (or overdue) sit at the top. Shared by the reminders screen and the
/// reminders panel opened from the home screen.
class RemindersList extends StatelessWidget {
  const RemindersList({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 24),
    this.shrinkWrap = false,
    this.onOpenMatch,
  });

  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;

  /// Runs before navigating to a proposal — used by the panel to close itself.
  final VoidCallback? onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.watch<PersonRepository>();

    final List<MatchIdea> reminders =
        matchRepository
            .getAll()
            .where((MatchIdea m) => m.reminderDate != null)
            .toList()
          ..sort(
            (MatchIdea a, MatchIdea b) =>
                a.reminderDate!.compareTo(b.reminderDate!),
          );

    if (reminders.isEmpty) {
      return EmptyReminders(theme: theme);
    }

    return ListView.separated(
      padding: padding,
      shrinkWrap: shrinkWrap,
      itemCount: reminders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final MatchIdea match = reminders[index];
        return ReminderCard(
          match: match,
          personA: personRepository.getById(match.personAId),
          personB: personRepository.getById(match.personBId),
          onTap: () {
            onOpenMatch?.call();
            context.push('/matches/${match.id}');
          },
        );
      },
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

  // Hebrew month names, built without `intl`'s locale data (which is not
  // initialized in this app) so this can never throw at build time.
  static const List<String> _hebrewMonths = <String>[
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

  static String _formatDate(DateTime date) {
    return '${date.day} ב${_hebrewMonths[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime date = match.reminderDate!;
    final DateTime today = DateTime.now();
    final DateTime dateDay = DateTime(date.year, date.month, date.day);
    final DateTime todayDay = DateTime(today.year, today.month, today.day);
    final int daysDiff = dateDay.difference(todayDay).inDays;
    final bool overdue = daysDiff < 0;
    final bool dueToday = daysDiff == 0;

    final String nameA = personA?.fullName.trim().isNotEmpty == true
        ? personA!.fullName.trim()
        : 'צד א';
    final String nameB = personB?.fullName.trim().isNotEmpty == true
        ? personB!.fullName.trim()
        : 'צד ב';

    final Color accent = overdue
        ? theme.colorScheme.error
        : dueToday
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final String when = overdue
        ? 'עבר זמנו'
        : dueToday
        ? 'היום'
        : daysDiff == 1
        ? 'מחר'
        : 'בעוד $daysDiff ימים';

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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      when,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _formatDate(date),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if ((match.reminderNote ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(match.reminderNote!.trim(), style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
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
