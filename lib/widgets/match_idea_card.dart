import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
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
    required this.onOpenPersonWhatsApp,
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

  /// Opens one candidate's WhatsApp. The card does not decide what that
  /// means — the choice between chatting and sending a card names both people,
  /// and both people belong to the screen, not to this widget.
  final void Function(Person person) onOpenPersonWhatsApp;

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
                    // A thin gender stripe on each edge of the card. The
                    // WhatsApp shortcut is back to one per side — on the face
                    // itself, so there is never a question of whose chat a tap
                    // opens.
                    _EdgeStripe(
                      color: AppColors.genderAccent(Gender.female, dark: dark),
                      atStart: true,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                        child: Row(
                          // Top-aligned so both photos stay level whatever the
                          // names under them come to.
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // In RTL the first child sits on the right.
                            Expanded(
                              child: _Side(
                                person: widget.female,
                                gender: Gender.female,
                                onStatusPicked: widget.onPersonStatusPicked,
                                onOpenWhatsApp: widget.onOpenPersonWhatsApp,
                              ),
                            ),
                            _Middle(status: match.status),
                            Expanded(
                              child: _Side(
                                person: widget.male,
                                gender: Gender.male,
                                onStatusPicked: widget.onPersonStatusPicked,
                                onOpenWhatsApp: widget.onOpenPersonWhatsApp,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _EdgeStripe(
                      color: AppColors.genderAccent(Gender.male, dark: dark),
                      atStart: false,
                    ),
                  ],
                ),
                _CardActionBar(
                  open: _actionsOpen,
                  dating: dating,
                  // An archived proposal has no status left worth setting, but
                  // there is still every reason to message the people in it —
                  // which is why the chat button does not live inside the part
                  // that disappears.
                  showStatusToggle:
                      widget.onQuickAction != null && !match.status.isArchived,
                  onToggle: () => setState(() => _actionsOpen = !_actionsOpen),
                  onAction: widget.onQuickAction,
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

/// One person inside the card: photo in a gender-coloured ring with their own
/// WhatsApp button on it, then name, age and their availability, changeable in
/// place.
///
/// **The chat button is a badge on the face, not a row of its own.** It has to
/// belong unmistakably to *this* side — that is the entire reason the card
/// stopped having one shared button — and a card in a scrolling list has no
/// vertical room to spare. Sitting on the corner of the photo it costs nothing
/// and points at exactly one person.
class _Side extends StatelessWidget {
  const _Side({
    required this.person,
    required this.gender,
    required this.onStatusPicked,
    required this.onOpenWhatsApp,
  });

  final Person? person;
  final Gender gender;
  final void Function(Person person, ProfileStatus status)? onStatusPicked;
  final void Function(Person person) onOpenWhatsApp;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ring = AppColors.genderAccent(gender, dark: dark);
    final Person? current = person;

    final String name = current?.fullName.trim().isNotEmpty == true
        ? current!.fullName.trim()
        : 'אדם נמחק';
    final String first = (current?.firstName ?? '').trim();
    final int? age = current?.age;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Stack(
          clipBehavior: Clip.none,
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
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person_off_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : PersonAvatar(person: current, radius: 24),
            ),
            // Nothing to message when the record is gone.
            if (current != null)
              PositionedDirectional(
                bottom: -4,
                start: -6,
                child: _SideWhatsAppButton(
                  onTap: () => onOpenWhatsApp(current),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _NameWithAge(fullName: name, firstName: first, age: age),
        if (current != null) ...<Widget>[
          const SizedBox(height: 4),
          _StatusPicker(person: current, onStatusPicked: onStatusPicked),
        ],
      ],
    );
  }
}

/// A person's name and age on exactly one line, whatever the name is.
///
/// A proposal card is one of a scrolling list, and a card that is taller than
/// the one above it because somebody has two given names makes the whole list
/// read as unsteady. So the line never wraps, and it gives things up in a fixed
/// order:
///
/// 1. the full name with the age, when it fits;
/// 2. the **first name** with the age, when the full name does not — dropping a
///    surname whole is far more readable than "אלישבע-מרים כהן־שט…, 26";
/// 3. as much of the first name as fits, ellipsized, with the age still there.
///
/// The age never gives way, because it is the one thing on the card a
/// matchmaker scans for and the one thing a truncated name cannot imply.
class _NameWithAge extends StatelessWidget {
  const _NameWithAge({
    required this.fullName,
    required this.firstName,
    required this.age,
  });

  final String fullName;
  final String firstName;
  final int? age;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle style =
        theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700) ??
        const TextStyle(fontWeight: FontWeight.w700);
    final String suffix = age == null ? '' : ', $age';

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.maxWidth;
        final TextScaler scaler = MediaQuery.textScalerOf(context);

        double widthOf(String text) {
          final TextPainter painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final double width = painter.width;
          painter.dispose();
          return width;
        }

        // The full name is preferred; the first name alone is the fallback, and
        // only when it is genuinely shorter (a one-word name is both).
        String name = fullName;
        if (available.isFinite &&
            firstName.isNotEmpty &&
            firstName.length < fullName.length &&
            widthOf('$fullName$suffix') > available) {
          name = firstName;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Flexible, so this is the part that gives; the age beside it is
            // not, so it cannot be squeezed out.
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
            if (suffix.isNotEmpty)
              Text(suffix, maxLines: 1, softWrap: false, style: style),
          ],
        );
      },
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

/// The bar under the pair: the proposal's own status actions, folded behind one
/// line.
///
/// **No chat button here.** It used to carry one, opening a sheet that asked
/// which of the two people was meant — a question the card had already made the
/// reader ask by putting a single icon under two faces. Each side owns its own
/// button now, on its own photo, and this bar is left doing the one thing that
/// belongs to the proposal rather than to a person.
///
/// **"עדכון סטטוס", not "פעולות מהירות".** The row behind it does exactly one
/// thing — move the proposal from one status to another — and a label that
/// says so is the difference between a control people use and a drawer people
/// open once to find out what is in it.
///
/// Closed, it is a single line and the card grows by about the height of a
/// chip. Open, it is the same actions the proposal screen offers, weighted the
/// same way: "מתחילים לצאת" filled and leading, unmistakably a button rather
/// than a badge saying where the couple already are.
class _CardActionBar extends StatelessWidget {
  const _CardActionBar({
    required this.open,
    required this.dating,
    required this.showStatusToggle,
    required this.onToggle,
    required this.onAction,
  });

  final bool open;

  /// A couple who are already out are not offered "מתחילים לצאת" again.
  final bool dating;

  /// False for an archived proposal, which has no status left worth setting.
  final bool showStatusToggle;

  final VoidCallback onToggle;
  final ValueChanged<MatchQuickAction>? onAction;

  List<MatchQuickAction> get _actions => dating
      ? <MatchQuickAction>[MatchQuickAction.close]
      : MatchQuickAction.values;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ValueChanged<MatchQuickAction>? action = onAction;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: showStatusToggle
                    ? InkWell(
                        onTap: onToggle,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                open ? 'סגירת עדכון סטטוס' : 'עדכון סטטוס',
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
                      )
                    : const SizedBox(height: 34),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open && showStatusToggle && action != null
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: <Widget>[
                        for (final MatchQuickAction quickAction in _actions)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: _QuickActionButton(
                                action: quickAction,
                                onTap: () => action(quickAction),
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

/// One side's WhatsApp control: a small disc sitting on the corner of their
/// photo, in the card's own surface colour so it reads as resting on the face
/// rather than punched through it.
class _SideWhatsAppButton extends StatelessWidget {
  const _SideWhatsAppButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      shape: CircleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: FaIcon(
            FontAwesomeIcons.whatsapp,
            size: 16,
            color: Color(0xFF25D366),
          ),
        ),
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
