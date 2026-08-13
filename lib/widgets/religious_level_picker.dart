import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/utils/enums.dart';

/// A person's religious style: either one of the built-in levels or a custom
/// label the matchmaker defined ([ReligiousLevel.other] plus the text).
class ReligiousLevelChoice {
  const ReligiousLevelChoice(this.level, [this.customLabel]);

  final ReligiousLevel? level;
  final String? customLabel;

  bool get isEmpty => level == null;
}

/// The chip row used wherever a person's religious style is chosen. It offers
/// only the styles enabled in settings, plus a shortcut into that screen.
class ReligiousLevelPicker extends StatelessWidget {
  const ReligiousLevelPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.showSettingsShortcut = true,
  });

  final ReligiousLevelChoice selected;
  final ValueChanged<ReligiousLevelChoice> onChanged;
  final bool showSettingsShortcut;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ReligiousLevelsProvider provider = context
        .watch<ReligiousLevelsProvider>();
    final List<ReligiousLevel> levels = provider.enabledLevels;
    final List<String> customLabels = provider.customLabels;

    final ReligiousLevel? current = selected.level;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showSettingsShortcut)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 2,
            children: <Widget>[
              Text('סגנון דתי', style: theme.textTheme.titleMedium),
              TextButton.icon(
                onPressed: () => context.push('/profile/religious-levels'),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('עריכת הגדרות דתיות'),
              ),
            ],
          )
        else
          Text('סגנון דתי', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final ReligiousLevel level in levels)
              ChoiceChip(
                label: Text(level.displayName),
                selected: current == level,
                onSelected: (bool value) => onChanged(
                  value && current != level
                      ? ReligiousLevelChoice(level)
                      : const ReligiousLevelChoice(null),
                ),
              ),
            for (final String label in customLabels)
              ChoiceChip(
                label: Text(label),
                selected:
                    current == ReligiousLevel.other &&
                    selected.customLabel == label,
                onSelected: (bool value) => onChanged(
                  value &&
                          !(current == ReligiousLevel.other &&
                              selected.customLabel == label)
                      ? ReligiousLevelChoice(ReligiousLevel.other, label)
                      : const ReligiousLevelChoice(null),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
