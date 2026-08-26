import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// Sending one "בקשת פרטים" to a whole group of friends, one chat at a time and
/// with nobody's name typed twice.
///
/// **Why not the share sheet.** Handing the text to the system share sheet is
/// one tap for the app and a search through a contact list for the person: they
/// pick the app, then find six chats inside WhatsApp — the same six they had
/// just finished ticking here. That is the work this whole selection exists to
/// avoid.
///
/// **And why not one link.** `wa.me` addresses exactly one number, and there is
/// no broadcast address of any kind; nothing an app can launch will deliver to
/// six people at once.
///
/// So this is the closest thing that actually exists: the app holds the queue.
/// Each row is one tap that opens *that* friend's chat with the message already
/// written — the send button is the only thing left to press — and coming back
/// to the app lands on this sheet with the next name already lit up. Nobody is
/// searched for, nothing is retyped, and the queue remembers who has been
/// reached and who has not.
abstract final class BulkDetailsRequestSheet {
  /// Walks [people] one chat at a time. Returns how many chats were opened.
  static Future<int> show(BuildContext context, List<Person> people) async {
    final int? sent = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (BuildContext sheetContext) =>
          _BulkDetailsRequestView(people: people),
    );
    return sent ?? 0;
  }
}

class _BulkDetailsRequestView extends StatefulWidget {
  const _BulkDetailsRequestView({required this.people});

  final List<Person> people;

  @override
  State<_BulkDetailsRequestView> createState() =>
      _BulkDetailsRequestViewState();
}

class _BulkDetailsRequestViewState extends State<_BulkDetailsRequestView> {
  /// Who has already had their chat opened. Not "who answered" — the app never
  /// learns that — only who has been reached, which is what stops the queue
  /// offering the same friend twice.
  final Set<String> _done = <String>{};

  /// Anybody whose chat refused to open, so the row can say so instead of
  /// silently counting as reached.
  final Set<String> _failed = <String>{};

  bool _opening = false;

  Person? get _next {
    for (final Person person in widget.people) {
      if (!_done.contains(person.id)) {
        return person;
      }
    }
    return null;
  }

  Future<void> _open(Person person) async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    final bool launched = await WhatsAppUtils.openDetailsRequest(person);
    if (!mounted) {
      return;
    }
    setState(() {
      _opening = false;
      if (launched) {
        _failed.remove(person.id);
        _done.add(person.id);
      } else {
        _failed.add(person.id);
        _done.add(person.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Person? next = _next;
    final int reached = _done.length - _failed.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'בקשת פרטים בוואטסאפ',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              next == null
                  ? 'עברת על כל מי שסימנת'
                  : 'ההודעה כבר כתובה בכל צ׳אט — נשאר רק לשלוח',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.people.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final Person person = widget.people[index];
                  return _RecipientRow(
                    person: person,
                    done: _done.contains(person.id),
                    failed: _failed.contains(person.id),
                    isNext: person.id == next?.id,
                    enabled: !_opening,
                    onOpen: () => _open(person),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (next != null)
              FilledButton.icon(
                onPressed: _opening ? null : () => _open(next),
                icon: const Icon(Icons.send_rounded, size: 20),
                label: Text('פתיחת הצ׳אט עם ${_shortName(next)}'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              )
            else
              FilledButton(
                onPressed: () => Navigator.of(context).pop(reached),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('סיימתי'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(reached),
              child: Text(next == null ? 'סגירה' : 'עצירה כאן'),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortName(Person person) {
    final String first = person.firstName.trim();
    return first.isNotEmpty ? first : person.fullName.trim();
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.person,
    required this.done,
    required this.failed,
    required this.isNext,
    required this.enabled,
    required this.onOpen,
  });

  final Person person;
  final bool done;
  final bool failed;
  final bool isNext;
  final bool enabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = failed
        ? theme.colorScheme.error
        : done
        ? AppColors.statusDating
        : theme.colorScheme.primary;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onOpen : null,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isNext
                  ? accent.withValues(alpha: 0.55)
                  : theme.colorScheme.outlineVariant,
              width: isNext ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              PersonAvatar(person: person, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      person.fullName.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (failed)
                      Text(
                        'לא הצלחנו לפתוח את הצ׳אט',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      )
                    else if (done)
                      Text(
                        'הצ׳אט נפתח',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.statusDating,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                failed
                    ? Icons.error_outline
                    : done
                    ? Icons.check_circle
                    : Icons.chat_outlined,
                size: 20,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
