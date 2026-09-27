import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/home_section.dart';

/// A status banner: a title and three answers side by side — פנוי, תפוס,
/// בהפסקה — each a dot in the state's colour and the word, the current one
/// outlined in that colour.
///
/// The personal area's "הסטטוס שלי" and a friend's profile draw the same
/// banner, so the one question is always asked in one shape.
///
/// "מזל טוב" is not one of the three. It is set by a wedding, or from the
/// profile's menu; when a friend already carries it, it is drawn as a fourth,
/// selected answer so the banner never contradicts the card.
class ProfileStatusChoices extends StatelessWidget {
  const ProfileStatusChoices({
    super.key,
    required this.title,
    required this.status,
    required this.gender,
    required this.onSelected,
    this.enabled = true,
  });

  final String title;
  final ProfileStatus status;
  final Gender gender;
  final ValueChanged<ProfileStatus> onSelected;
  final bool enabled;

  static const List<ProfileStatus> choices = <ProfileStatus>[
    ProfileStatus.available,
    ProfileStatus.busy,
    ProfileStatus.onBreak,
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ProfileStatus> shown = <ProfileStatus>[
      ...choices,
      if (!choices.contains(status)) status,
    ];

    return HomePaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              for (final ProfileStatus option in shown) ...<Widget>[
                Expanded(
                  child: _StatusOption(
                    status: option,
                    gender: gender,
                    selected: status == option,
                    onTap: enabled && status != option
                        ? () => onSelected(option)
                        : null,
                  ),
                ),
                if (option != shown.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.status,
    required this.gender,
    required this.selected,
    required this.onTap,
  });

  final ProfileStatus status;
  final Gender gender;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = AppColors.profileStatusDotColor(status);
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.7)
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    status.displayNameFor(gender),
                    maxLines: 1,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
