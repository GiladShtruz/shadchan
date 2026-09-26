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

  @override
  Widget build(BuildContext context) {
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
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
}
