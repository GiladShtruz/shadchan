import 'package:flutter/material.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_avatar_assets.dart';

/// Lets the user replace the automatically selected no-photo illustration.
class PersonAvatarPicker extends StatelessWidget {
  const PersonAvatarPicker({
    super.key,
    required this.gender,
    required this.selectedIndex,
    required this.onChanged,
  });

  final Gender gender;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> assets = PersonAvatarAssets.forGender(gender);
    if (assets.isEmpty) {
      return Text(
        'לאחר בחירת מגדר יוצגו כאן איורי הדמות.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final int effectiveIndex = PersonAvatarAssets.normalizedIndex(
      selectedIndex,
      gender,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'אין תמונה — אפשר לבחור איור שיוצג כברירת מחדל:',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: assets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int index) {
              final bool selected = index == effectiveIndex;
              return Semantics(
                button: true,
                selected: selected,
                label: 'איור דמות ${index + 1}',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onChanged(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 68,
                    height: 68,
                    padding: EdgeInsets.all(selected ? 3 : 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(
                              color: theme.colorScheme.primary,
                              width: 3,
                            )
                          : null,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        assets[index],
                        width: 62,
                        height: 62,
                        cacheWidth: 144,
                        cacheHeight: 144,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
