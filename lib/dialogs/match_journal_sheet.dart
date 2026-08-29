import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// "יומן הרעיון" — one idea's whole history, as a chat.
///
/// **A chat rather than a list, because that is what it actually is.** Every
/// move on a proposal now writes a line here — the idea being opened, a status
/// changing, a reminder set, a contact added, a card sent — and the matchmaker
/// writes their own lines in between. Read top to bottom that is the story of
/// one couple.
///
/// **Newest first.** It ran the other way, the way a chat does, which is right
/// for a window somebody is sitting inside and wrong for a history that is
/// glanced at: what a matchmaker opening a proposal wants is the last thing
/// that happened, and it was at the bottom of a list that could be forty lines
/// long. The composer stays under it either way.
///
/// The two kinds of line are told apart by the dot beside them and by the
/// weight of the words, not by a label — a wall of identical rows is
/// unreadable, and the eye needs somewhere to skip to.
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

/// The same journal, drawn in place inside a proposal's "פעולות" panel.
///
/// **Open the actions and the journal is simply there.** It used to be one of
/// six identical tiles, which made the proposal's whole history a thing to
/// remember to go and look at — and a history nobody opens is a history nobody
/// keeps. So it is not a button any more: every opening of the actions panel
/// shows what has happened to this proposal, newest line first, with the
/// composer under it.
///
/// **About seven lines, then it scrolls inside itself.** Drawing the whole
/// history in place was right while the journal was somewhere you went; inside
/// a card in a scrolling list a long one pushed the composer and the next
/// proposal off the screen. A tap anywhere on it opens [MatchJournalSheet] —
/// the same journal with a screen to itself, which is also where a line is
/// edited.
class MatchJournalView extends StatefulWidget {
  const MatchJournalView({super.key, required this.matchId});

  final String matchId;

  @override
  State<MatchJournalView> createState() => _MatchJournalViewState();
}

class _MatchJournalViewState extends State<MatchJournalView> {
  final TextEditingController _controller = TextEditingController();
  final DateFormat _time = DateFormat('dd.MM · HH:mm');

  /// About seven lines of journal, which is as much as a card in a scrolling
  /// list can hold without becoming the list.
  static const double _compactMaxHeight = 190;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository repository = context.watch<MatchRepository>();
    final List<MatchNote> notes = repository.getNotesForMatch(widget.matchId);

    // Newest first. A journal read inside a card is read from the top, and the
    // line worth reading is the last thing that happened — which was at the
    // bottom of a list that could be forty lines long.
    final List<MatchNote> newestFirst = notes.reversed.toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.28 : 0.42,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.forum_outlined,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'יומן הרעיון',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              // The "מסך מלא" link is gone. A word in the corner of a block is
              // a thing to notice before it can be used; the block itself is
              // the target now — see the tap below.
            ],
          ),
          if (notes.isEmpty)
            // Nothing at all under the heading. The line that used to sit here
            // explained the feature to somebody who had not used it yet, which
            // is the one reader who does not need to be told: the first line
            // writes itself the moment anything happens to the proposal.
            const SizedBox(height: 4)
          else
            // **Seven rows, then a scroll of its own.** Everything, always, was
            // the rule while the journal was a thing you had to go and open;
            // now that it lies open inside every proposal's actions a forty-line
            // history pushed the composer — and the next card in the list — off
            // the bottom of the screen. Seven is about a screenful of a card.
            //
            // A tap anywhere on it opens the full journal, where a line can be
            // edited. Scrolling inside it still works: a drag is not a tap.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _compactMaxHeight),
              child: GestureDetector(
                onTap: () => _openFull(repository),
                child: ListView.builder(
                  primary: false,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: newestFirst.length,
                  itemBuilder: (BuildContext context, int i) => _JournalLine(
                    note: newestFirst[i],
                    timestamp: _time.format(newestFirst[i].createdAt),
                    isFirst: i == 0,
                    isLast: i == newestFirst.length - 1,
                    onEdit: () => _openFull(repository),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  style: theme.textTheme.bodySmall,
                  decoration: const InputDecoration(
                    hintText: 'מה קרה עם הרעיון?',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'הוספה ליומן',
                visualDensity: VisualDensity.compact,
                onPressed: _controller.text.trim().isEmpty
                    ? null
                    : () => _send(repository),
                icon: const Icon(Icons.send_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openFull(MatchRepository repository) async {
    final MatchIdea? match = repository.getById(widget.matchId);
    if (match == null || !mounted) {
      return;
    }
    await MatchJournalSheet.show(context, match);
  }

  Future<void> _send(MatchRepository repository) async {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    _controller.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    await repository.addNote(widget.matchId, text);
  }

  // Editing a line is not offered here any more: a tap on the compact journal
  // opens the full one, which is where a line is reworded or removed.
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

  /// The newest line leads the list now, so "where the news is" is the top.
  void _jumpToEnd({bool animate = false}) {
    if (!_scroll.hasClients) {
      return;
    }
    const double start = 0;
    if (animate) {
      _scroll.animateTo(
        start,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }
    _scroll.jumpTo(start);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository repository = context.watch<MatchRepository>();
    // Newest first, the same way round as the journal inside a card.
    final List<MatchNote> notes = repository
        .getNotesForMatch(widget.matchId)
        .reversed
        .toList();

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
                      'יומן הרעיון',
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
                          isFirst: index == 0,
                          isLast: index == notes.length - 1,
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
                        hintText: 'מה קרה עם הרעיון?',
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
      AppNotice.show(
        context,
        'השורה נמחקה מהיומן',
        actionLabel: 'ביטול',
        onAction: () => repository.restoreNote(note),
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
            // Three words and nothing under them. The sentence that used to
            // follow described how the journal works to the one reader who has
            // not seen it work yet — and the first line writes itself the
            // moment anything happens to the proposal.
            Text(
              'היומן עוד ריק',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the journal, as one step on a single timeline.
///
/// **Every entry is the same shape now.** It used to be three: a centred grey
/// pill for what the app recorded, a bubble on the right for what the
/// matchmaker wrote, and a wider tinted bubble with a heading for a "מזל טוב".
/// Read one at a time each of those is defensible; read as a column — which is
/// the only way a journal is ever read — it is a page of boxes at three widths
/// and three heights, and the eye spends its effort on the shapes instead of on
/// what happened.
///
/// So: a rail down the start edge, a dot per entry, the time and the sentence
/// beside it. What tells the two kinds apart is the dot and the weight of the
/// text, not the box — **a hollow dot for what the app recorded, a filled one
/// in the app's own accent for what the matchmaker wrote**, with their words a
/// shade darker and heavier. A congratulation from another matchmaker keeps its
/// warm colour and its "מזל טוב מ־", inside the same row as everything else.
///
/// Everything is still editable by a tap, automatic lines included: it is the
/// matchmaker's journal and the app only starts the sentences.
class _JournalLine extends StatelessWidget {
  const _JournalLine({
    required this.note,
    required this.timestamp,
    required this.onEdit,
    this.isFirst = false,
    this.isLast = false,
  });

  final MatchNote note;
  final String timestamp;
  final VoidCallback onEdit;

  /// The rail is drawn as two half-segments per row, so the ends of the list
  /// stop rather than trailing off into the padding.
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final String? from = note.mazelTovFrom;
    final bool mine = !note.isAutomatic;

    final Color rail = theme.colorScheme.outlineVariant;
    final Color dot = from != null
        ? (dark ? AppColors.secondaryDarkDm : AppColors.secondary)
        : mine
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The rail. A fixed, narrow column so every row's text starts at
            // exactly the same place however long the sentence is — which is
            // the whole point of a timeline over a stack of bubbles.
            SizedBox(
              width: 18,
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: 7,
                    child: isFirst ? null : Center(child: _Rail(color: rail)),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Hollow for the app's own lines, filled for the
                      // matchmaker's: the difference is legible at a glance
                      // down the column and costs no space at all.
                      color: mine || from != null
                          ? dot
                          : theme.colorScheme.surface,
                      border: Border.all(color: dot, width: 1.5),
                    ),
                  ),
                  Expanded(
                    child: isLast
                        ? const SizedBox.shrink()
                        : Center(child: _Rail(color: rail)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                // **The sentence first, and the clock inside it.** The date
                // used to hold a line of its own above every entry, in the
                // same size as the text and in a heavier weight — so a journal
                // of ten lines was ten timestamps with ten sentences between
                // them, and what the eye landed on down the column was a
                // column of dates. The stamp is now the last few characters of
                // the line the entry is written on, small enough to be read
                // only when it is looked for.
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      if (from != null)
                        TextSpan(
                          text: 'מזל טוב מ$from · ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: dot,
                          ),
                        ),
                      TextSpan(
                        text: note.text,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                          fontWeight: mine ? FontWeight.w700 : FontWeight.w400,
                          color: mine
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextSpan(
                        text: '  $timestamp',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          height: 1.35,
                          fontWeight: FontWeight.w400,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One segment of the timeline's rail.
class _Rail extends StatelessWidget {
  const _Rail({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1.5, color: color);
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
