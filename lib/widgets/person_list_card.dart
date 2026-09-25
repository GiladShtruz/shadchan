import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
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
    this.selected,
    this.trailing,
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

  /// Null on an ordinary row. Non-null puts the row into selection mode: a tick
  /// box replaces the trailing controls and the card is tinted when it is on.
  ///
  /// The buttons go rather than sit beside the tick because in selection mode
  /// the whole row means one thing — "this one too" — and a WhatsApp button
  /// that leaves the app in the middle of picking six people is a trap, not a
  /// shortcut.
  final bool? selected;

  /// One control of the caller's own at the outer end of the row.
  ///
  /// Added for the card expander on the pickers — see [CandidateCardButton] —
  /// where the row carries no messaging or favourite button and the outer edge
  /// is empty. Dropped entirely while the row is in selection mode, for the
  /// same reason the other trailing buttons are.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = AppColors.genderAccent(person.gender, dark: dark);
    final bool selecting = selected != null;
    final bool isSelected = selected ?? false;

    final List<String> details = <String>[
      if (person.age != null) person.age!.toString(),
      if (person.religiousLevelLabel.isNotEmpty) person.religiousLevelLabel,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected
            ? Color.alphaBlend(
                theme.colorScheme.primary.withValues(alpha: dark ? 0.22 : 0.10),
                theme.colorScheme.surface,
              )
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                // The gender hint: the app's one accent bar, on the
                // reading-start edge. See [AccentStripe] — every coloured rule
                // in the app is that one, so a row here and a row on the home
                // screen are evidently the same kind of thing.
                AccentStripe(color: accent, height: AccentBar.rowHeight),
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
                                // The name in its own gender's colour — the
                                // palette's blue for a man, its rose for a
                                // woman — so a list is read as "who" first.
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: person.gender == Gender.unknown
                                      ? null
                                      : AppColors.genderAccent(
                                          person.gender,
                                          dark:
                                              theme.brightness ==
                                              Brightness.dark,
                                        ),
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
                if (selecting)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                  )
                else ...<Widget>[
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
                  ?trailing,
                ],
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
      gender: person.gender,
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
                ProfileStatusTag(status: status, gender: person.gender),
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

/// The availability status: a dot for the state, and the word itself in the
/// person's own colour.
///
/// **Two things are being said at once, so two things say them.** The tag used
/// to be drawn entirely in the state's colour — green, red, amber — which made
/// a list of friends a list of traffic lights, and left nothing on the row
/// saying whose status it was. Now the *word* is the person: blue for a man,
/// rose for a woman, the same two colours the accent bar, the avatar tint and
/// the proposal cards use. The *dot* is the state: green free, brown on a
/// break, red taken. So "פנויה" in rose with a green dot is read as one
/// glance — a woman, available — where a green "פנויה" was read as neither.
class ProfileStatusTag extends StatelessWidget {
  const ProfileStatusTag({
    super.key,
    required this.status,
    this.gender,
    this.compact = false,
  });

  final ProfileStatus status;

  /// Whose status this is. Null — a row that is not about one person — leaves
  /// the word in the page's own ink.
  final Gender? gender;

  /// The quiet variant used in the people list: a fixed-width pill in the
  /// palette's muted tones, borderless and a size smaller. The fixed width is
  /// what keeps a column of them lined up whatever the names next to them are.
  final bool compact;

  /// Width of the [compact] pill. Wide enough for the dot plus "בהפסקה" or
  /// "מזל טוב".
  static const double compactWidth = 64;

  /// The dot, at whatever size the tag is drawn.
  Widget _dot(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.profileStatusDotColor(status),
        shape: BoxShape.circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Gender? whose = gender;
    final Color ink = whose == null
        ? AppColors.heading(dark: dark)
        : AppColors.genderAccent(whose, dark: dark);

    if (compact) {
      return Container(
        width: compactWidth,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // The person's own tint, so the pill belongs to the row rather than
          // to the state — which the dot inside it already carries.
          color: ink.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _dot(5),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  status.displayName,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ink.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _dot(6),
          const SizedBox(width: 5),
          Text(
            status.displayName,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
