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
/// [compact] is the friend profile's version: the title and the three answers
/// on one line, at the page's reading size, so the banner takes a single short
/// row rather than a block of its own.
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
    this.compact = false,
  });

  final String title;
  final ProfileStatus status;
  final Gender gender;
  final ValueChanged<ProfileStatus> onSelected;
  final bool enabled;

  /// Title and answers on one line, in smaller boxes.
  final bool compact;

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

    final Widget options = Row(
      children: <Widget>[
        for (final ProfileStatus option in shown) ...<Widget>[
          Expanded(
            child: _StatusOption(
              status: option,
              gender: gender,
              selected: status == option,
              compact: compact,
              onTap: enabled && status != option
                  ? () => onSelected(option)
                  : null,
            ),
          ),
          if (option != shown.last) SizedBox(width: compact ? 6 : 8),
        ],
      ],
    );

    if (compact) {
      return HomePaperCard(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: options),
          ],
        ),
      );
    }

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
          options,
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
    this.compact = false,
  });

  final ProfileStatus status;
  final Gender gender;
  final bool selected;
  final bool compact;
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
          padding: EdgeInsets.symmetric(
            vertical: compact ? 6 : 10,
            horizontal: 4,
          ),
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
                    style:
                        (compact
                                ? theme.textTheme.bodyMedium
                                : theme.textTheme.bodyLarge)
                            ?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
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
