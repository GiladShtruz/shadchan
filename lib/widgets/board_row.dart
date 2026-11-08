import 'package:flutter/material.dart';
import 'package:shadchan/widgets/accent_stripe.dart';

/// One row the way "הלוח שלי" draws it: an accent bar in the person's colour
/// (two, one on each edge, for a couple), the face or faces, a bold title with
/// one small mark beside it saying why the row is there, one quiet line under
/// it, and the row's own menu at the end.
///
/// Shared by the board and the reminders panel, so a reminder looks the same
/// in both places and is acted on the same way.
class BoardRow extends StatelessWidget {
  const BoardRow({
    super.key,
    required this.leading,
    required this.title,
    required this.startAccent,
    required this.onTap,
    required this.menu,
    this.onLongPress,
    this.endAccent,
    this.subtitle,
    this.subtitleColor,
    this.subtitleMaxLines = 1,
    this.mark,
    this.titleColor,
    this.centerText = false,
    this.boldTitle = true,
    this.fresh = false,
    this.flat = false,
  });

  final Widget leading;
  final String title;
  final Color startAccent;
  final VoidCallback onTap;
  final Widget menu;

  /// Handed the row's own context, so a menu can hang from the row.
  final ValueChanged<BuildContext>? onLongPress;
  final Color? endAccent;
  final String? subtitle;

  /// For a line that means something by its colour.
  final Color? subtitleColor;

  /// Null shows the whole line — a reminder's note is read in full.
  final int? subtitleMaxLines;
  final IconData? mark;
  final Color? titleColor;

  /// The title and the line under it centred in the row, as the
  /// notifications page draws them — so rows of different lengths still read
  /// as one balanced column.
  final bool centerText;

  /// False on "הלוח שלי", where the names keep their size but not the weight —
  /// a column of bold names reads as a column of headlines.
  final bool boldTitle;

  /// Something happened in it that the matchmaker has not opened yet: a small
  /// dot before the name. Nothing else about the row changes.
  final bool fresh;

  /// The home screen's list of what to do next: drawn the way a chat list is —
  /// on the bare page, no frame, no coloured bars, the face at the start, two
  /// short lines and a small arrow at the end. The list draws the hairline
  /// between rows. [menu] is drawn before the arrow when it is not just the
  /// row's "⋯" (a direct action such as "בקשת גישה").
  final bool flat;

  @override
  Widget build(BuildContext context) {
    if (flat) {
      return _buildFlat(context);
    }
    final ThemeData theme = Theme.of(context);
    final String? sub = subtitle?.trim();
    final Color? end = endAccent;
    final IconData? why = mark;
    final ValueChanged<BuildContext>? longPress = onLongPress;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: Builder(
          builder: (BuildContext rowContext) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            onLongPress: longPress == null ? null : () => longPress(rowContext),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: <Widget>[
                  AccentStripe(color: startAccent, height: AccentBar.rowHeight),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 10),
                    child: leading,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: centerText
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: centerText
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.start,
                            children: <Widget>[
                              if (fresh) ...<Widget>[
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: boldTitle
                                        ? FontWeight.bold
                                        : FontWeight.w400,
                                    color: titleColor,
                                  ),
                                ),
                              ),
                              if (why != null) ...<Widget>[
                                const SizedBox(width: 5),
                                Icon(
                                  why,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ],
                          ),
                          if (sub != null && sub.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              sub,
                              maxLines: subtitleMaxLines,
                              textAlign: centerText ? TextAlign.center : null,
                              overflow: subtitleMaxLines == null
                                  ? null
                                  : TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: subtitleColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  menu,
                  if (end != null) ...<Widget>[
                    const SizedBox(width: 4),
                    AccentStripe(
                      color: end,
                      atStart: false,
                      height: AccentBar.rowHeight,
                    ),
                  ] else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlat(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? sub = subtitle?.trim();
    final ValueChanged<BuildContext>? longPress = onLongPress;
    return Builder(
      builder: (BuildContext rowContext) => InkWell(
        onTap: onTap,
        onLongPress: longPress == null ? null : () => longPress(rowContext),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          if (fresh) ...<Widget>[
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: titleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (sub != null && sub.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          maxLines: subtitleMaxLines ?? 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                menu,
                Icon(
                  // Material's chevrons mirror themselves in RTL: this one
                  // points left, into the item.
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
