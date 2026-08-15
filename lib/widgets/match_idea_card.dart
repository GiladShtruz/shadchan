import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';

/// One proposal, as a single shared card rather than two separate squares. The
/// two sides are told apart only by the ring around each photo — stone blue for
/// him, muted rose for her — so the card itself stays calm.
class MatchIdeaCard extends StatefulWidget {
  const MatchIdeaCard({
    super.key,
    required this.match,
    required this.male,
    required this.female,
    required this.onTap,
    required this.onOpenWhatsApp,
    this.onPersonStatusPicked,
    this.onQuickAction,
    this.showStatusTag = false,
    this.compact = false,
    this.highlighted = false,
  });

  final MatchIdea match;
  final Person? male;
  final Person? female;
  final VoidCallback onTap;
  final ValueChanged<Person> onOpenWhatsApp;

  /// Sets one side's availability from the chip under their name. Null leaves
  /// the chip as a plain label.
  final void Function(Person person, ProfileStatus status)?
  onPersonStatusPicked;

  /// Runs one of the proposal's own actions. Null hides the quick-action row.
  final ValueChanged<MatchQuickAction>? onQuickAction;

  final bool showStatusTag;
  final bool compact;

  /// A proposal the matchmaker asked to be reminded about today: the card wears
  /// the reminder accent so it cannot be mistaken for the rest of the list.
  final bool highlighted;

  @override
  State<MatchIdeaCard> createState() => _MatchIdeaCardState();
}

class _MatchIdeaCardState extends State<MatchIdeaCard> {
  /// The action row is closed at rest and opens in place.
  ///
  /// Three buttons per card, always open, would turn a scrollable list of
  /// proposals into a wall of controls — and most of the time the matchmaker is
  /// reading the list, not acting on it. Closed it costs one slim bar; open it
  /// is exactly the same three actions the proposal screen offers.
  bool _actionsOpen = false;

  MatchIdea get match => widget.match;

  @override
  void didUpdateWidget(covariant MatchIdeaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A status change closes the row: the action was taken, and leaving it open
    // invites a second one on a card that has already moved.
    if (oldWidget.match.status != widget.match.status) {
      _actionsOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = theme.colorScheme.secondary;
    final bool dating = match.status == MatchStatus.dating;
    final Color datingAccent = dark
        ? AppColors.femaleAccentDm
        : AppColors.femaleAccent;
    final bool highlighted = widget.highlighted;
    final Color regularSurface = highlighted
        ? Color.alphaBlend(
            accent.withValues(alpha: dark ? 0.16 : 0.07),
            theme.colorScheme.surface,
          )
        : theme.colorScheme.surface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: dating ? Colors.transparent : regularSurface,
        borderRadius: BorderRadius.circular(16),
        elevation: dating
            ? 4
            : highlighted
            ? 2
            : 0,
        shadowColor: (dating ? datingAccent : accent).withValues(alpha: 0.38),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: dating
                  ? LinearGradient(
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                      colors: <Color>[
                        Color.alphaBlend(
                          AppColors.softRose.withValues(
                            alpha: dark ? 0.18 : 0.72,
                          ),
                          theme.colorScheme.surface,
                        ),
                        Color.alphaBlend(
                          AppColors.softYellow.withValues(
                            alpha: dark ? 0.10 : 0.42,
                          ),
                          theme.colorScheme.surface,
                        ),
                      ],
                    )
                  : null,
              border: Border.all(
                color: dating
                    ? datingAccent.withValues(alpha: 0.72)
                    : highlighted
                    ? accent.withValues(alpha: 0.65)
                    : theme.colorScheme.outlineVariant,
                width: dating
                    ? 1.8
                    : highlighted
                    ? 1.6
                    : 1,
              ),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    // A thin gender stripe on each edge of the card, and — now
                    // that the status chip has taken its old place under the
                    // name — the WhatsApp shortcut right beside it. Each side's
                    // chat sits at that side's own edge, which is where a thumb
                    // reaches it without covering the card.
                    _EdgeStripe(
                      color: AppColors.genderAccent(Gender.female, dark: dark),
                      atStart: true,
                    ),
                    _EdgeWhatsApp(
                      person: widget.female,
                      onOpenWhatsApp: widget.onOpenWhatsApp,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
                        child: Row(
                          // Top-aligned so both photos stay level even when one
                          // name wraps onto a second line.
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // In RTL the first child sits on the right.
                            Expanded(
                              child: _Side(
                                person: widget.female,
                                gender: Gender.female,
                                onStatusPicked: widget.onPersonStatusPicked,
                              ),
                            ),
                            _Middle(status: match.status),
                            Expanded(
                              child: _Side(
                                person: widget.male,
                                gender: Gender.male,
                                onStatusPicked: widget.onPersonStatusPicked,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _EdgeWhatsApp(
                      person: widget.male,
                      onOpenWhatsApp: widget.onOpenWhatsApp,
                    ),
                    _EdgeStripe(
                      color: AppColors.genderAccent(Gender.male, dark: dark),
                      atStart: false,
                    ),
                  ],
                ),
                if (widget.onQuickAction != null && !match.status.isArchived)
                  _QuickActionsBar(
                    open: _actionsOpen,
                    dating: dating,
                    onToggle: () =>
                        setState(() => _actionsOpen = !_actionsOpen),
                    onAction: widget.onQuickAction!,
                  ),
                _Footer(
                  match: match,
                  showStatusTag: widget.showStatusTag,
                  compact: widget.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeStripe extends StatelessWidget {
  const _EdgeStripe({required this.color, required this.atStart});

  final Color color;
  final bool atStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 72,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.75),
        borderRadius: BorderRadiusDirectional.horizontal(
          end: atStart ? const Radius.circular(12) : Radius.zero,
          start: atStart ? Radius.zero : const Radius.circular(12),
        ),
      ),
    );
  }
}

/// One person inside the card: photo in a gender-coloured ring, name, age and —
/// where the WhatsApp icon used to sit — their own availability, changeable in
/// place.
///
/// The swap is the point. WhatsApp was the most prominent control on a card
/// about a *proposal*, while the thing that actually decides whether the
/// proposal can move — is she free, is he on a break — was not on the card at
/// all. Now the status is a tap under the name, and the chat is at the edge.
class _Side extends StatelessWidget {
  const _Side({
    required this.person,
    required this.gender,
    required this.onStatusPicked,
  });

  final Person? person;
  final Gender gender;
  final void Function(Person person, ProfileStatus status)? onStatusPicked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ring = AppColors.genderAccent(gender, dark: dark);
    final Person? current = person;

    final String name = current?.fullName.trim().isNotEmpty == true
        ? current!.fullName.trim()
        : 'אדם נמחק';
    final int? age = current?.age;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 2),
          ),
          child: current == null
              ? CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.person_off_outlined,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : PersonAvatar(person: current, radius: 24),
        ),
        const SizedBox(height: 8),
        Text(
          age != null ? '$name, $age' : name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (current != null) ...<Widget>[
          const SizedBox(height: 4),
          _StatusPicker(person: current, onStatusPicked: onStatusPicked),
        ],
      ],
    );
  }
}

/// The availability chip under a name, and the menu behind it.
class _StatusPicker extends StatelessWidget {
  const _StatusPicker({required this.person, required this.onStatusPicked});

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
    final Widget tag = ProfileStatusTag(status: person.profileStatus);
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          tag,
          Icon(
            Icons.arrow_drop_down_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// The WhatsApp shortcut at the card's own edge, next to that side's stripe.
class _EdgeWhatsApp extends StatelessWidget {
  const _EdgeWhatsApp({required this.person, required this.onOpenWhatsApp});

  final Person? person;
  final ValueChanged<Person> onOpenWhatsApp;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Person? current = person;
    final bool hasPhone =
        current != null && PhoneUtils.toWhatsAppNumber(current.phone) != null;

    return SizedBox(
      width: 34,
      child: IconButton(
        tooltip: 'וואטסאפ',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        onPressed: hasPhone ? () => onOpenWhatsApp(current) : null,
        icon: FaIcon(
          FontAwesomeIcons.whatsapp,
          size: 20,
          color: hasPhone
              ? const Color(0xFF25D366)
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

/// The proposal's own actions, folded into one slim bar under the pair.
///
/// Closed, it is a single line — the card grows by about the height of a chip.
/// Open, it is the same three actions the proposal screen offers, in the same
/// order and with the same weighting: "מתחילים לצאת" filled and leading,
/// because it is the one worth encouraging, and unmistakably a button rather
/// than a badge saying where the couple already are.
class _QuickActionsBar extends StatelessWidget {
  const _QuickActionsBar({
    required this.open,
    required this.dating,
    required this.onToggle,
    required this.onAction,
  });

  final bool open;

  /// A couple who are already out are not offered "מתחילים לצאת" again.
  final bool dating;

  final VoidCallback onToggle;
  final ValueChanged<MatchQuickAction> onAction;

  List<MatchQuickAction> get _actions => dating
      ? <MatchQuickAction>[MatchQuickAction.close]
      : MatchQuickAction.values;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    open ? 'סגירת הפעולות' : 'פעולות מהירות',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: <Widget>[
                        for (final MatchQuickAction action in _actions)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: _QuickActionButton(
                                action: action,
                                onTap: () => onAction(action),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.action, required this.onTap});

  final MatchQuickAction action;
  final VoidCallback onTap;

  Color get _ink {
    switch (action) {
      case MatchQuickAction.waiting:
        return AppColors.statusChecking;
      case MatchQuickAction.dating:
        return AppColors.statusDating;
      case MatchQuickAction.close:
        return AppColors.statusRejected;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool lead = action == MatchQuickAction.dating;
    final Color ink = _ink;

    return Material(
      color: lead ? ink : ink.withValues(alpha: dark ? 0.18 : 0.09),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      elevation: lead ? 2 : 0,
      shadowColor: ink.withValues(alpha: 0.5),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(action.icon, size: 17, color: lead ? Colors.white : ink),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  action.label,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: lead ? Colors.white : ink,
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

/// The column between the two people: just the heart. The last-updated date,
/// reminders and status controls now live on the proposal-detail screen.
class _Middle extends StatelessWidget {
  const _Middle({required this.status});

  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    final bool dating = status == MatchStatus.dating;
    return Padding(
      // The top padding lands the heart level with the middle of the photos.
      padding: const EdgeInsets.fromLTRB(6, 24, 6, 0),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          Icon(
            Icons.favorite,
            size: dating ? 25 : 20,
            color: AppColors.statusColor(status.name),
          ),
          if (dating) ...<Widget>[
            const Positioned(
              top: -9,
              right: -7,
              child: Icon(
                Icons.auto_awesome,
                size: 11,
                color: AppColors.secondary,
              ),
            ),
            const Positioned(
              bottom: -8,
              left: -6,
              child: Icon(
                Icons.auto_awesome,
                size: 9,
                color: AppColors.femaleAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.match,
    required this.showStatusTag,
    required this.compact,
  });

  final MatchIdea match;
  final bool showStatusTag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? waitingReason = match.waitingReason?.trim();

    final bool hasWaitingReason =
        waitingReason != null && waitingReason.isNotEmpty;
    final bool dating = match.status == MatchStatus.dating;
    // Reminders no longer surface on the card — they live on the detail screen.
    if (!showStatusTag && !hasWaitingReason && !dating) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, compact ? 10 : 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showStatusTag || dating)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: dating
                  ? const _DatingTag()
                  : _StatusTag(status: match.status),
            ),
          if (hasWaitingReason) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              waitingReason,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DatingTag extends StatelessWidget {
  const _DatingTag();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = AppColors.statusDating;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.softGreen.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        '✨ יוצאים יחד ✨',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});

  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = AppColors.statusColor(status.name);
    final bool celebrate = status == MatchStatus.married;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: celebrate ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        celebrate ? '🎉 ${status.displayName}' : status.displayName,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
