import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// A compact row for one person: avatar, name, age + religious level, a
/// favorite toggle and a WhatsApp shortcut.
///
/// The card itself stays on the light surface colour; gender is conveyed only
/// by the leading accent bar and the avatar tint, so the list reads calm even
/// when it is hundreds of rows long.
class PersonListCard extends StatelessWidget {
  const PersonListCard({
    super.key,
    required this.person,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onOpenWhatsApp,
    this.onOpenMatches,
    this.onLongPress,
    this.heroEnabled = true,
  });

  final Person person;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenWhatsApp;

  /// When set, the heart button opens this person's match suggestions instead
  /// of toggling the favorite flag (favoriting stays available from the
  /// long-press menu).
  final VoidCallback? onOpenMatches;
  final VoidCallback? onLongPress;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool hasPhone = PhoneUtils.toWhatsAppNumber(person.phone) != null;
    final Color accent = AppColors.genderAccent(person.gender, dark: dark);

    final List<String> details = <String>[
      if (person.age != null) person.age!.toString(),
      if (person.religiousLevelLabel.isNotEmpty) person.religiousLevelLabel,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                // The gender hint: a thin accent bar on the reading-start edge.
                Container(
                  width: 4,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadiusDirectional.horizontal(
                      end: Radius.circular(12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 10),
                  child: heroEnabled
                      ? Hero(
                          tag: 'person-${person.id}',
                          child: PersonAvatar(person: person, radius: 22),
                        )
                      : PersonAvatar(person: person, radius: 22),
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
                                person.fullName.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ProfileStatusTag(status: person.profileStatus),
                          ],
                        ),
                        if (details.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            details.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (onOpenMatches != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'התאמות',
                    icon: Icon(Icons.favorite_border, color: accent),
                    onPressed: onOpenMatches,
                  )
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: person.isFavorite
                        ? 'הסר ממועדפים'
                        : 'הוסף למועדפים',
                    icon: Icon(
                      person.isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: person.isFavorite ? AppColors.favorite : accent,
                    ),
                    onPressed: onToggleFavorite,
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: hasPhone ? 'וואטסאפ' : 'אין מספר טלפון תקין',
                  icon: FaIcon(
                    FontAwesomeIcons.whatsapp,
                    size: 20,
                    color: hasPhone
                        ? const Color(0xFF25D366)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: hasPhone ? onOpenWhatsApp : null,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The availability status shown as a small coloured pill: green when
/// available, red when taken, amber while on a break.
class ProfileStatusTag extends StatelessWidget {
  const ProfileStatusTag({super.key, required this.status});

  final ProfileStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.profileStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        status.displayName,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
