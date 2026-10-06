import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/notification_feed.dart';
import 'package:shadchan/services/reminder_log.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/notification_center.dart';

/// "התראות": everything that happened, in one list, newest first — the
/// personal-card notices from the server, the reminders that came due, and
/// answers from support.
///
/// **Drawn like a chat list.** One compact row each: the face, what happened
/// in a line, a very short second line when it adds anything, and when. No
/// shelves, no cards, no row of icons.
///
/// **Opening the page is reading it.** Everything on it when it opens is
/// marked read at once — the bell and the app icon count down to nothing —
/// but the rows that were new keep their tint for this visit, so the eye can
/// still find them. "סמן הכל כנקרא" lets the tint go too.
///
/// **Nothing leaves by age.** A row goes when it is swiped away or its ✕ is
/// tapped, and only then.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  /// The rows that were unread when the page opened.
  Set<String> _wasNew = <String>{};
  bool _marked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_marked) {
      return;
    }
    _marked = true;
    _wasNew = <String>{
      for (final NotificationGroup g in NotificationCenter.groups(
        context,
        listen: false,
      ))
        if (!g.read) g.id,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificationCenter.markAllRead(context);
      }
    });
  }

  void _markAll() {
    setState(() => _wasNew = <String>{});
    NotificationCenter.markAllRead(context);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: ReminderLog.instance,
      builder: (BuildContext context, _) {
        final List<NotificationGroup> groups = NotificationCenter.groups(
          context,
        );
        // A row that arrived while the page is open is new too.
        final Set<String> highlighted = <String>{
          ..._wasNew,
          for (final NotificationGroup g in groups)
            if (!g.read) g.id,
        };
        return Scaffold(
          appBar: AppBar(
            title: const Text('התראות'),
            actions: <Widget>[
              if (highlighted.isNotEmpty)
                TextButton(
                  onPressed: _markAll,
                  child: const Text('סמן הכל כנקרא'),
                ),
            ],
          ),
          body: groups.isEmpty
              ? const _EmptyNotifications()
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    thickness: 0.6,
                    indent: 72,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final NotificationGroup group = groups[index];
                    return Dismissible(
                      key: ValueKey<String>(group.id),
                      background: const _SwipeBackground(),
                      onDismissed: (_) =>
                          NotificationCenter.remove(context, group),
                      child: NotificationRow(
                        group: group,
                        highlighted: highlighted.contains(group.id),
                        onTap: () => NotificationCenter.open(context, group),
                        onRemove: () =>
                            NotificationCenter.remove(context, group),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// One row of the notifications page.
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.group,
    required this.highlighted,
    required this.onTap,
    required this.onRemove,
  });

  final NotificationGroup group;

  /// Unread when the page opened: a faint tint, and a heavier first line.
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final AppNotification line = group.latest;
    final int more = group.count - 1;
    final String? second = more > 0
        ? <String>[
            if (line.subtitle case final String s when s.isNotEmpty) s,
            more == 1 ? 'ועוד עדכון אחד' : 'ועוד $more עדכונים',
          ].join(' · ')
        : line.subtitle;
    final Color tint = (dark ? AppColors.primaryDarkDm : AppColors.primary)
        .withValues(alpha: dark ? 0.16 : 0.10);

    return Material(
      color: highlighted ? tint : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 9, 4, 9),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 46,
                child: Center(child: _Face(line: line)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      line.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: highlighted
                            ? FontWeight.w700
                            : FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    if (second != null && second.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        second,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted(dark: dark),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    AppDateUtils.notificationTime(group.time),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: highlighted
                          ? theme.colorScheme.primary
                          : AppColors.muted(dark: dark),
                      fontWeight: highlighted ? FontWeight.w700 : null,
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    height: 26,
                    child: IconButton(
                      tooltip: 'הסרה',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      onPressed: onRemove,
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.muted(dark: dark),
                      ),
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
}

/// The face on a row: the friend, the couple, or a plain disc.
class _Face extends StatelessWidget {
  const _Face({required this.line});

  final AppNotification line;

  @override
  Widget build(BuildContext context) {
    final (Person?, Person?)? couple = line.couple;
    if (couple != null) {
      return HomeCardCoupleAvatars(
        personA: couple.$1,
        personB: couple.$2,
        radius: 15,
      );
    }
    if (line.person != null) {
      return HomeCardAvatar(person: line.person, radius: 21);
    }
    final ThemeData theme = Theme.of(context);
    return CircleAvatar(
      radius: 21,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        line.source == NotificationSource.support
            ? Icons.forum_outlined
            : Icons.person_outline_rounded,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.delete_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const Spacer(),
            Icon(
              Icons.delete_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.notifications_none_rounded,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('אין התראות', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'כאן יופיעו כרטיסים חדשים של חברים ותזכורות שהגיע זמנן.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
