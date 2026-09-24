import 'package:flutter/material.dart';
import 'package:shadchan/utils/enums.dart';

/// A person's religious style: one of [ReligiousLevels.global], or — only on
/// an older record — a style that is no longer offered ([ReligiousLevel.other]
/// plus the label a matchmaker once typed, or a retired built-in).
class ReligiousLevelChoice {
  const ReligiousLevelChoice(this.level, [this.customLabel]);

  final ReligiousLevel? level;
  final String? customLabel;

  bool get isEmpty => level == null;
}

/// The chip row used wherever a person's religious style is chosen.
///
/// It offers the one global list. A record that still carries a retired style
/// shows it as an extra, already-selected chip at the start, so opening an
/// older card never silently changes what it says; picking any other chip
/// replaces it for good.
class ReligiousLevelPicker extends StatelessWidget {
  const ReligiousLevelPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.showTitle = true,
  });

  final ReligiousLevelChoice selected;
  final ValueChanged<ReligiousLevelChoice> onChanged;

  /// Off where the surrounding form already heads the row with its own label —
  /// two "סגנון דתי" titles one above the other is what this flag exists for.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ReligiousLevel? current = selected.level;
    final bool legacy = ReligiousLevels.isLegacy(current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('סגנון דתי', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (legacy)
              ChoiceChip(
                label: Text(
                  ReligiousLevels.labelOf(current!, selected.customLabel),
                ),
                selected: true,
                onSelected: (bool value) {
                  if (!value) {
                    onChanged(const ReligiousLevelChoice(null));
                  }
                },
              ),
            for (final ReligiousLevel level in ReligiousLevels.global)
              ChoiceChip(
                label: Text(level.displayName),
                selected: current == level,
                onSelected: (bool value) => onChanged(
                  value && current != level
                      ? ReligiousLevelChoice(level)
                      : const ReligiousLevelChoice(null),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
