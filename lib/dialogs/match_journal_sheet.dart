import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/utils/app_colors.dart';

/// "יומן ההצעה" — one proposal's whole history, as a chat.
///
/// **A chat rather than a list, because that is what it actually is.** Every
/// move on a proposal now writes a line here — the idea being opened, a status
/// changing, a reminder set, a contact added, a card sent — and the matchmaker
/// writes their own lines in between. Read top to bottom that is a
/// conversation about one couple, so it is drawn as one: oldest first, newest
/// at the bottom, the composer under it, and the view opening already scrolled
/// to the end where the news is.
///
/// The two kinds of line are told apart by shape, not by a label. What the app
/// wrote is a quiet centred strip, the way a chat marks that somebody joined;
/// what the matchmaker wrote is a bubble on their own side. Neither is more
/// important — but a wall of identical cards is unreadable, and the eye needs
/// somewhere to skip to.
///
/// **Everything here is still the matchmaker's to change.** An automatic line
/// opens the same editor a hand-written one does. It is their journal; the app
/// only starts the sentences.
abstract final class MatchJournalSheet {
  static Future<void> show(BuildContext context, MatchIdea match) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _MatchJournal(matchId: match.id),
    );
  }
}

class _MatchJournal extends StatefulWidget {
  const _MatchJournal({required this.matchId});

  final String matchId;

  @override
  State<_MatchJournal> createState() => _MatchJournalState();
}

class _MatchJournalState extends State<_MatchJournal> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final DateFormat _time = DateFormat('dd.MM · HH:mm');

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The newest line is the one worth reading, so the journal opens on it.
  void _jumpToEnd({bool animate = false}) {
    if (!_scroll.hasClients) {
      return;
    }
    final double end = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(
        end,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }
    _scroll.jumpTo(end);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository repository = context.watch<MatchRepository>();
    final List<MatchNote> notes = repository.getNotesForMatch(widget.matchId);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.forum_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'יומן ההצעה',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: notes.isEmpty
                  ? _EmptyJournal(theme: theme)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                      itemCount: notes.length,
                      itemBuilder: (BuildContext context, int index) {
                        final MatchNote note = notes[index];
                        return _JournalLine(
                          note: note,
                          timestamp: _time.format(note.createdAt),
                          onEdit: () => _edit(repository, note),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'מה קרה עם ההצעה?',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'הוספה ליומן',
                    onPressed: _controller.text.trim().isEmpty
                        ? null
                        : () => _send(repository),
                    icon: const Icon(Icons.send_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(MatchRepository repository) async {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    _controller.clear();
    await repository.addNote(widget.matchId, text);
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _jumpToEnd(animate: true),
    );
  }

  /// One dialog per line: reword it, or remove it. Deleting offers an undo
  /// rather than a confirmation, because a mis-tap here costs a record the
  /// matchmaker cannot rebuild.
  Future<void> _edit(MatchRepository repository, MatchNote note) async {
    final _JournalEdit? result = await showDialog<_JournalEdit>(
      context: context,
      builder: (BuildContext context) => _JournalEditDialog(note: note),
    );
    if (result == null) {
      return;
    }

    if (result.delete) {
      await repository.deleteNote(note.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('השורה נמחקה מהיומן'),
            action: SnackBarAction(
              label: 'ביטול',
              onPressed: () => repository.restoreNote(note),
            ),
          ),
        );
      return;
    }

    final String text = result.text.trim();
    if (text.isNotEmpty && text != note.text.trim()) {
      await repository.updateNote(note.id, text);
    }
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.forum_outlined,
              size: 46,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'היומן עוד ריק',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'כל פעולה בהצעה תיכתב כאן מעצמה, ואפשר גם להוסיף הערות משלך.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the journal: a centred strip for what the app recorded, a
/// bubble for what the matchmaker wrote, and a warmer bubble for a "מזל טוב"
/// that arrived from another matchmaker.
class _JournalLine extends StatelessWidget {
  const _JournalLine({
    required this.note,
    required this.timestamp,
    required this.onEdit,
  });

  final MatchNote note;
  final String timestamp;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final String? from = note.mazelTovFrom;

    if (from != null) {
      final Color tone = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
      return _Bubble(
        onTap: onEdit,
        color: tone.withValues(alpha: dark ? 0.20 : 0.12),
        borderColor: tone.withValues(alpha: 0.45),
        alignment: AlignmentDirectional.centerStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.celebration_rounded, size: 15, color: tone),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'מזל טוב מ$from',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tone,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(note.text),
            const SizedBox(height: 3),
            _Stamp(timestamp: timestamp, theme: theme),
          ],
        ),
      );
    }

    if (note.isAutomatic) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Center(
          child: InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: dark ? 0.55 : 0.8,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${note.text} · $timestamp',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _Bubble(
      onTap: onEdit,
      color: theme.colorScheme.primaryContainer.withValues(
        alpha: dark ? 0.45 : 0.7,
      ),
      borderColor: theme.colorScheme.primary.withValues(alpha: 0.28),
      alignment: AlignmentDirectional.centerEnd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(note.text),
          const SizedBox(height: 3),
          _Stamp(timestamp: timestamp, theme: theme),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.child,
    required this.color,
    required this.borderColor,
    required this.alignment,
    required this.onTap,
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final AlignmentGeometry alignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: borderColor),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.timestamp, required this.theme});

  final String timestamp;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      timestamp,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// What the editor returned: an edit, or a delete.
class _JournalEdit {
  const _JournalEdit.save(this.text) : delete = false;
  const _JournalEdit.remove() : text = '', delete = true;

  final String text;
  final bool delete;
}

class _JournalEditDialog extends StatefulWidget {
  const _JournalEditDialog({required this.note});

  final MatchNote note;

  @override
  State<_JournalEditDialog> createState() => _JournalEditDialogState();
}

class _JournalEditDialogState extends State<_JournalEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.note.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('שורה ביומן'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(hintText: 'תוכן השורה'),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      // Three buttons handed to `AlertDialog` rather than laid out by hand in a
      // `Row`. The row version fitted a tablet and overflowed a phone by fifty
      // pixels — an `OverflowBar` stacks them instead, which is exactly what
      // this dialog wants on the narrow screen it actually opens on.
      actionsOverflowButtonSpacing: 4,
      actions: <Widget>[
        TextButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(const _JournalEdit.remove()),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          icon: const Icon(Icons.delete_outline, size: 19),
          label: const Text('מחיקה'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_JournalEdit.save(_controller.text)),
          child: const Text('שמירה'),
        ),
      ],
    );
  }
}
