import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/contact_channel_button.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// A compact row for one person: avatar, name, age + religious level, a
/// favorite toggle and a messaging shortcut — WhatsApp, SMS, or a pencil,
/// whichever the person's number allows. See [ContactChannelButton].
///
/// The card itself stays on the light surface colour; gender is conveyed only
/// by the leading accent bar and the avatar tint, so the list reads calm even
/// when it is hundreds of rows long.
class PersonListCard extends StatelessWidget {
  const PersonListCard({
    super.key,
    required this.person,
    required this.onTap,
    this.onToggleFavorite,
    this.onOpenWhatsApp,
    this.onCompleteCard,
    this.onOpenMatches,
    this.onLongPress,
    this.onStatusPicked,
    this.heroEnabled = true,
  });

  final Person person;
  final VoidCallback onTap;

  /// The trailing buttons, each drawn only when it has somewhere to go. A row
  /// used to *pick* somebody leaves both off: favouriting from a picker is a
  /// side errand, and opening WhatsApp from one abandons the choice being made.
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onOpenWhatsApp;

  /// Where the messaging button goes when there is no number to message. Left
  /// null on a row that has no editor behind it, which simply drops the button.
  final VoidCallback? onCompleteCard;

  /// When set, the heart button opens this person's match suggestions instead
  /// of toggling the favorite flag (favoriting stays available from the
  /// long-press menu).
  final VoidCallback? onOpenMatches;
  final VoidCallback? onLongPress;

  /// Changes this person's availability from the pill on the row itself.
  ///
  /// **The status was already sitting there and was already the thing being
  /// read** — every row in המאגר שלי leads with it — but changing it meant
  /// opening the profile, finding the control and coming back. That is four
  /// taps for one word, done a dozen times after a round of phone calls, and it
  /// is exactly the cost that makes people stop keeping statuses up to date.
  /// Null leaves the pill as a plain label, which is what a picker row wants.
  final void Function(Person person, ProfileStatus status)? onStatusPicked;

  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
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
                        // The status leads the row at a fixed width, so every
                        // row's name starts at the same place however long the
                        // name before it happens to be.
                        Row(
                          children: <Widget>[
                            _StatusPill(
                              person: person,
                              onStatusPicked: onStatusPicked,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                person.fullName.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (details.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Padding(
                            // Lines up with the name rather than with the pill.
                            padding: const EdgeInsetsDirectional.only(
                              start: ProfileStatusTag.compactWidth + 8,
                            ),
                            child: Text(
                              details.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // The messaging button first and the heart after it, so in
                // RTL the heart is always the outermost control on the row.
                // The other way round it was the *messaging* button that held
                // the edge — and that button is the one that disappears, for
                // anybody with no number at all, which left the heart jumping
                // between two positions down a single list.
                if (onOpenWhatsApp != null)
                  ContactChannelButton(
                    person: person,
                    onWhatsApp: onOpenWhatsApp!,
                    onEdit: onCompleteCard,
                  ),
                if (onOpenMatches != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'התאמות',
                    icon: Icon(Icons.favorite_border, color: accent),
                    onPressed: onOpenMatches,
                  )
                else if (onToggleFavorite != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: person.isFavorite
                        ? 'הסרה ממועדפים'
                        : 'הוספה למועדפים',
                    icon: Icon(
                      person.isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: person.isFavorite ? AppColors.favorite : accent,
                    ),
                    onPressed: onToggleFavorite,
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

/// The status pill on a row, and the menu behind it when there is one.
///
/// The pill keeps its fixed width whether or not it can be tapped, so a list
/// where some rows are editable and some are not still lines up.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.person, required this.onStatusPicked});

  final Person person;
  final void Function(Person person, ProfileStatus status)? onStatusPicked;

  /// What a matchmaker may set by hand. "מזל טוב" is left out: the app writes
  /// that itself when a proposal ends in a wedding.
  static const List<ProfileStatus> _selectable = <ProfileStatus>[
    ProfileStatus.available,
    ProfileStatus.busy,
    ProfileStatus.onBreak,
  ];

  @override
  Widget build(BuildContext context) {
    final void Function(Person, ProfileStatus)? picked = onStatusPicked;
    final Widget tag = ProfileStatusTag(
      status: person.profileStatus,
      compact: true,
    );
    if (picked == null) {
      return tag;
    }

    return PopupMenuButton<ProfileStatus>(
      tooltip: 'שינוי סטטוס',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      onSelected: (ProfileStatus status) => picked(person, status),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<ProfileStatus>>[
        for (final ProfileStatus status in _selectable)
          PopupMenuItem<ProfileStatus>(
            value: status,
            child: Row(
              children: <Widget>[
                ProfileStatusTag(status: status),
                const Spacer(),
                if (status == person.profileStatus)
                  Icon(
                    Icons.check,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
      child: tag,
    );
  }
}

/// The availability status shown as a small coloured pill: green when
/// available, red when taken, amber while on a break.
class ProfileStatusTag extends StatelessWidget {
  const ProfileStatusTag({
    super.key,
    required this.status,
    this.compact = false,
  });

  final ProfileStatus status;

  /// The quiet variant used in the people list: a fixed-width pill in the
  /// palette's muted tones, borderless and a size smaller. The fixed width is
  /// what keeps a column of them lined up whatever the names next to them are.
  final bool compact;

  /// Width of the [compact] pill. Wide enough for "בהפסקה" and "מזל טוב".
  static const double compactWidth = 52;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (compact) {
      final Color color = AppColors.profileStatusSoftColor(status);
      return Container(
        width: compactWidth,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(999),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            status.displayName,
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

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
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
