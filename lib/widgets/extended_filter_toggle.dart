import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// "סינון מורחב" — the one control that narrows a list of candidates from
/// everybody who fits the basics to everybody who fits the whole card.
///
/// **Two filters, and the wider one is the default.** A candidate's card can
/// carry a height range, a preferred city, a region and a marital status, all
/// collected under "עריכה מורחבת". Applied automatically they hide most of the
/// database — not because those people are wrong, but because nobody ever
/// recorded their height — and the list gives no sign that it is doing it. So
/// the basic filter (gender, age, religious style) is what a list opens on, and
/// this is how the rest is asked for, in one tap, with the state of it visible.
///
/// Drawn as a chip rather than a switch: it belongs beside a count, not in a
/// settings row, and it is only ever shown where the card has something
/// extended to apply.
class ExtendedFilterToggle extends StatelessWidget {
  const ExtendedFilterToggle({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    return Material(
      color: selected
          ? ink.withValues(alpha: dark ? 0.24 : 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onChanged(!selected),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? ink.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
                size: 16,
                color: selected ? ink : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'סינון מורחב',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? ink : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
