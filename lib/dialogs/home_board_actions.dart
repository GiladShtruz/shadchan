import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// The actions behind "הלוח שלי", shared by the three-dots menus on a person
/// and a proposal and by the small menu on a board card itself.
///
/// Reminders here are the app's real reminders — a person's "לבדוק שוב" date
/// and a proposal's reminder date — so setting one from the board also sends
/// the push notification and shows up in the reminders panel, instead of
/// creating a second, silent kind of reminder.
abstract final class HomeBoardActions {
  /// The menu label for the current state of an item.
  static String menuLabel(HomeItemKind kind, String targetId) {
    return HomeBoardStore.instance.contains(kind, targetId)
        ? 'הסרה מהלוח שלי'
        : 'הוספה ללוח שלי';
  }

  /// Room a [PopupMenuItem] built from [menuItemChild] needs for its two lines.
  static const double menuItemHeight = 60;

  /// The board menu item's body. While an item is not on the board yet, the
  /// label is followed by one small line saying where it will turn up — "הלוח
  /// שלי" means nothing until you have seen it once.
  static Widget menuItemChild(
    BuildContext context,
    HomeItemKind kind,
    String targetId,
  ) {
    final String label = menuLabel(kind, targetId);
    if (HomeBoardStore.instance.contains(kind, targetId)) {
      return Text(label);
    }

    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label),
        const SizedBox(height: 2),
        Text(
          'יופיע בלוח המעקב האישי בעמוד הבית.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Pins or unpins. Returns whether it is pinned afterwards.
  ///
  /// No confirmation bar: the board itself is the feedback, and the menu label
  /// flips the next time it is opened.
  static bool toggle(BuildContext context, HomeItemKind kind, String targetId) {
    final bool pinned = HomeBoardStore.instance.toggle(kind, targetId);
    if (pinned) {
      context.go('/home?section=board');
      // Stateful shell branches keep their root widgets alive. Send a second,
      // explicit signal after navigation so the existing home scroll view is
      // focused too, even when the query-string route reuses that widget.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HomeBoardStore.instance.requestFocus();
      });
    }
    return pinned;
  }

  static void remove(BuildContext context, HomeItemKind kind, String targetId) {
    HomeBoardStore.instance.remove(kind, targetId);
  }

  /// Adds, edits or clears the short note shown on the board card.
  static Future<void> editNote(
    BuildContext context,
    HomeItemKind kind,
    String targetId,
  ) async {
    final String? current = HomeBoardStore.instance.noteFor(kind, targetId);
    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _BoardNoteDialog(initialText: current ?? '');
      },
    );
    if (note == null) {
      return;
    }
    HomeBoardStore.instance.setNote(kind, targetId, note);
  }

  /// **The one menu a board row carries** — a reminder, a note, the pin —
  /// opened from the row's "⋯", from a long press on the row, and from a
  /// reminder in the reminders panel, so the same item answers the same way
  /// wherever it is met.
  ///
  /// [anchor] is the widget the menu hangs from. [onHandled], when given,
  /// adds "טופל" at the top — the one extra answer a reminder that has come
  /// due needs. [removable] adds "הסרה" at the foot: it takes the row off
  /// הלוח שלי and nothing else — see [removeFromBoard].
  static Future<void> showItemMenu(
    BuildContext anchor,
    HomeItemKind kind,
    String targetId, {
    VoidCallback? onHandled,
    bool removable = false,
  }) async {
    final ThemeData theme = Theme.of(anchor);
    final RenderBox? box = anchor.findRenderObject() as RenderBox?;
    final OverlayState overlayState = Overlay.of(anchor);
    final RenderBox? overlay =
        overlayState.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize) {
      return;
    }
    final Offset topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final Rect rect = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy + box.size.height,
      box.size.width,
      0,
    );
    final RelativeRect position = RelativeRect.fromRect(
      rect,
      Offset.zero & overlay.size,
    );

    final HomeBoardStore store = HomeBoardStore.instance;
    final bool pinned = store.contains(kind, targetId);
    final bool hasNote = (store.noteFor(kind, targetId) ?? '').isNotEmpty;
    final bool hasReminder = kind == HomeItemKind.person
        ? anchor.read<PersonRepository>().personReminderFor(targetId) != null
        : anchor.read<MatchRepository>().getById(targetId)?.reminderDate !=
              null;

    final String? choice = await showMenu<String>(
      context: anchor,
      position: position,
      constraints: const BoxConstraints(minWidth: 190),
      color: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      items: <PopupMenuEntry<String>>[
        if (onHandled != null) ...<PopupMenuEntry<String>>[
          const PopupMenuItem<String>(value: 'handled', child: Text('טופל')),
          const PopupMenuDivider(),
        ],
        PopupMenuItem<String>(
          value: 'reminder',
          child: Text(hasReminder ? 'עריכת תזכורת' : 'הוספת תזכורת'),
        ),
        PopupMenuItem<String>(
          value: 'note',
          child: Text(hasNote ? 'עריכת הערה' : 'הוספת הערה'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: pinned ? 'unpin' : 'pin',
          child: Text(pinned ? 'הסרת הצמדה' : 'הצמדה'),
        ),
        if (removable)
          const PopupMenuItem<String>(value: 'remove', child: Text('הסרה')),
      ],
    );
    if (choice == null || !anchor.mounted) {
      return;
    }
    switch (choice) {
      case 'handled':
        onHandled?.call();
      case 'reminder':
        await editReminder(anchor, kind, targetId);
      case 'note':
        await editNote(anchor, kind, targetId);
      case 'pin':
        store.add(kind, targetId);
      case 'unpin':
        remove(anchor, kind, targetId);
      case 'remove':
        removeFromBoard(anchor, HomeBoardStore.itemKey(kind, targetId));
    }
  }

  /// "הסרה": takes one row off הלוח שלי — unpinning it if it was pinned — and
  /// leaves the person or the proposal itself exactly as it was. The row stays
  /// off until whatever put it there changes (see [HomeBoardStore.hide]); the
  /// notice offers the way back.
  static void removeFromBoard(BuildContext context, String key) {
    final HomeBoardStore store = HomeBoardStore.instance;
    final int split = key.indexOf(':');
    final HomeItemKind? kind = split < 0
        ? null
        : HomeItemKind.values
              .where((HomeItemKind k) => k.name == key.substring(0, split))
              .firstOrNull;
    final String targetId = split < 0 ? '' : key.substring(split + 1);
    final bool wasPinned = kind != null && store.contains(kind, targetId);
    if (wasPinned) {
      store.remove(kind, targetId);
    }
    store.hide(key);
    AppNotice.show(
      context,
      'הוסר מהלוח',
      actionLabel: 'ביטול',
      onAction: () {
        store.unhide(key);
        if (wasPinned) {
          store.add(kind, targetId);
        }
      },
    );
  }

  /// Sets or clears the reminder that the board card shows.
  static Future<void> editReminder(
    BuildContext context,
    HomeItemKind kind,
    String targetId,
  ) async {
    final PersonRepository personRepository = context.read<PersonRepository>();
    final MatchRepository matchRepository = context.read<MatchRepository>();

    final ReminderChoice? choice = await ReminderPickerSheet.show(
      context,
      title: 'מתי להזכיר לך?',
      allowClear: true,
    );
    if (choice == null) {
      return;
    }

    switch (kind) {
      case HomeItemKind.person:
        if (choice.date == null) {
          await personRepository.clearPersonReminder(targetId);
        } else {
          await personRepository.setPersonReminder(targetId, choice.date!);
        }
      case HomeItemKind.idea:
        await matchRepository.setReminder(targetId, choice.date);
    }
  }
}

/// The "⋯" at the end of a board row, opening [HomeBoardActions.showItemMenu].
class BoardItemMenuButton extends StatelessWidget {
  const BoardItemMenuButton({
    super.key,
    required this.kind,
    required this.targetId,
    this.onHandled,
    this.removable = false,
  });

  final HomeItemKind kind;
  final String targetId;
  final VoidCallback? onHandled;
  final bool removable;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (BuildContext anchor) => IconButton(
        tooltip: 'פעולות',
        icon: const Icon(Icons.more_horiz, size: 20),
        onPressed: () => HomeBoardActions.showItemMenu(
          anchor,
          kind,
          targetId,
          onHandled: onHandled,
          removable: removable,
        ),
      ),
    );
  }
}

class _BoardNoteDialog extends StatefulWidget {
  const _BoardNoteDialog({required this.initialText});

  final String initialText;

  @override
  State<_BoardNoteDialog> createState() => _BoardNoteDialogState();
}

class _BoardNoteDialogState extends State<_BoardNoteDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('הערה קצרה'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'למשל: לחזור אחרי החג'),
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('שמירה'),
        ),
      ],
    );
  }
}
