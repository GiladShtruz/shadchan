import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/dialogs/match_journal_sheet.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/utils/contact_channel.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/dating_check_in.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/widgets/contact_channel_button.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
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
    required this.onCompletePersonCard,
    this.onPersonStatusPicked,
    this.onQuickAction,
    this.onAdvance,
    this.onSetStage,
    this.onCheckInWith,
    this.onChangeCheckInFrequency,
    this.datingSince,
    this.onActionsOpenChanged,
    this.onLongPress,
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

  /// Opens one candidate's card so a missing phone number can be added. Used
  /// in place of the messaging button for somebody who has no number at all —
  /// typically a name added straight into a proposal from outside the
  /// database.
  final void Function(Person person) onCompletePersonCard;

  /// Sets one side's availability from the chip under their name. Null leaves
  /// the chip as a plain label.
  final void Function(Person person, ProfileStatus status)?
  onPersonStatusPicked;

  /// Runs one of the proposal's own actions. Null hides the action panel.
  final ValueChanged<MatchQuickAction>? onQuickAction;

  /// "יאללה לקדם!" — takes the one step this proposal is waiting for. Null on a
  /// proposal there is nothing to advance (archived), which drops the row.
  final void Function(MatchNextStep step)? onAdvance;

  /// Sets the stage by hand, from the small menu beside the button.
  final void Function(MatchStage stage)? onSetStage;

  /// Opens a chat with one half of a couple who are out, and books the next
  /// check-in because it happened.
  final void Function(Person person)? onCheckInWith;

  /// Changes how often this couple are asked about.
  final void Function(int days)? onChangeCheckInFrequency;

  /// When this couple started going out, for the "כבר 7 ימים" line. Null unless
  /// the proposal is in "יוצאים".
  final DateTime? datingSince;

  /// Told whenever this card's action panel opens or closes.
  ///
  /// The panel's state belongs to the card — it is the card that is open — but
  /// the *screen* needs to know that at least one is, because a list with a
  /// proposal open is a list somebody is working in rather than scanning, and
  /// the filter banner over it stops earning its strip of screen. See
  /// `MatchesScreen`.
  final ValueChanged<bool>? onActionsOpenChanged;

  /// A long press on the card. The one way to delete a proposal — see
  /// `MatchesScreen._confirmDelete` for why it is a gesture and not a button.
  final VoidCallback? onLongPress;

  final bool compact;

  /// A proposal the matchmaker asked to be reminded about today: the card wears
  /// the reminder accent so it cannot be mistaken for the rest of the list.
  final bool highlighted;

  @override
  State<MatchIdeaCard> createState() => _MatchIdeaCardState();
}

class _MatchIdeaCardState extends State<MatchIdeaCard> {
  /// The action panel is closed at rest and opens in place.
  ///
  /// Six buttons per card, always open, would turn a scrollable list of
  /// proposals into a wall of controls — and most of the time the matchmaker is
  /// reading the list, not acting on it. Closed it costs one slim bar; open it
  /// is everything the proposal screen used to offer, which is why there is no
  /// proposal screen any more.
  bool _actionsOpen = false;

  MatchIdea get match => widget.match;

  @override
  void didUpdateWidget(covariant MatchIdeaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A status change closes the row: the action was taken, and leaving it open
    // invites a second one on a card that has already moved.
    if (oldWidget.match.status != widget.match.status && _actionsOpen) {
      _actionsOpen = false;
      _announceActions();
    }
  }

  @override
  void dispose() {
    // A card scrolled out of the list, or a status move that rebuilt it as a
    // different widget, must not leave the screen believing it is still open.
    if (_actionsOpen) {
      widget.onActionsOpenChanged?.call(false);
    }
    super.dispose();
  }

  /// Deferred to after the frame: this is called from `didUpdateWidget` and
  /// from a tap handler, and the listener on the other end calls `setState` on
  /// an ancestor that is mid-build in the first case.
  void _announceActions() {
    final ValueChanged<bool>? notify = widget.onActionsOpenChanged;
    if (notify == null) {
      return;
    }
    final bool open = _actionsOpen;
    WidgetsBinding.instance.addPostFrameCallback((_) => notify(open));
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
          onLongPress: widget.onLongPress,
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
                                onCompleteCard: widget.onCompletePersonCard,
                              ),
                            ),
                            _Middle(status: match.status),
                            Expanded(
                              child: _Side(
                                person: widget.male,
                                gender: Gender.male,
                                onStatusPicked: widget.onPersonStatusPicked,
                                onOpenWhatsApp: widget.onOpenPersonWhatsApp,
                                onCompleteCard: widget.onCompletePersonCard,
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
                _StatusLine(
                  match: match,
                  onSetStage: widget.onSetStage,
                  onAction: widget.onQuickAction,
                ),
                _CardActionBar(
                  open: _actionsOpen,
                  match: match,
                  male: widget.male,
                  female: widget.female,
                  datingSince: widget.datingSince,
                  onToggle: () {
                    setState(() => _actionsOpen = !_actionsOpen);
                    _announceActions();
                  },
                  onAction: widget.onQuickAction,
                  onAdvance: widget.onAdvance,
                  onCheckInWith: widget.onCheckInWith,
                  onChangeCheckInFrequency: widget.onChangeCheckInFrequency,
                ),
                SizedBox(height: widget.compact ? 8 : 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's two gender bars.
///
/// [AccentStripe] with this card's own height, and at full strength: it used
/// to be drawn here by hand at 75% opacity, which made the same bar a
/// different colour on a proposal than on the person it is about. One bar,
/// one colour, everywhere.
class _EdgeStripe extends StatelessWidget {
  const _EdgeStripe({required this.color, required this.atStart});

  final Color color;
  final bool atStart;

  /// Taller than an ordinary row: a proposal card carries two faces and their
  /// names, not one line of type.
  static const double height = 86;

  @override
  Widget build(BuildContext context) {
    return AccentStripe(color: color, atStart: atStart, height: height);
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
    required this.onCompleteCard,
  });

  final Person? person;
  final Gender gender;
  final void Function(Person person, ProfileStatus status)? onStatusPicked;
  final void Function(Person person) onOpenWhatsApp;
  final void Function(Person person) onCompleteCard;

  /// A little more presence than the 24 the faces had: large enough to know
  /// who it is at a glance, small enough that a list still reads as a list.
  static const double avatarRadius = 29;

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
                      radius: _Side.avatarRadius,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person_off_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : PersonAvatar(person: current, radius: _Side.avatarRadius),
            ),
            // Nothing to message when the record is gone.
            if (current != null)
              PositionedDirectional(
                bottom: -4,
                start: -6,
                child: _SideContactButton(
                  person: current,
                  onOpenWhatsApp: () => onOpenWhatsApp(current),
                  onCompleteCard: () => onCompleteCard(current),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _NameWithAge(fullName: name, firstName: first, age: age, ink: ring),
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
    required this.ink,
  });

  final String fullName;
  final String firstName;
  final int? age;

  /// This side's own colour: the brand blue for the boy, the palette's rose
  /// for the girl — the same pair the ring round the photo, the bar down the
  /// edge of the card and the availability under the name are drawn in, so one
  /// glance at a card says which half is which.
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // One step up from the body size, and bold: the names are what a list of
    // ideas is read by. The fallback to the first name below keeps it on one
    // line whatever the name is.
    final TextStyle style =
        theme.textTheme.bodyMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: ink,
        ) ??
        TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink);
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
    final Widget word = _AvailabilityWord(
      status: person.profileStatus,
      gender: person.gender,
    );
    if (picked == null) {
      return word;
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
                _AvailabilityWord(status: status, gender: person.gender),
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
          word,
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

/// "פנויה" / "תפוס" / "בהפסקה", drawn exactly the way המאגר שלי draws it: a dot
/// in the state's colour and the word in the person's own — blue for him,
/// rose for her. See [ProfileStatusTag]; this is that tag, so a friend's
/// status looks the same on a proposal as on their row in the database.
class _AvailabilityWord extends StatelessWidget {
  const _AvailabilityWord({required this.status, required this.gender});

  final ProfileStatus status;
  final Gender gender;

  @override
  Widget build(BuildContext context) {
    return ProfileStatusTag(status: status, gender: gender, compact: true);
  }
}

/// Where the proposal stands, at the foot of the card — and the way to change
/// it.
///
/// **The status lives on the card, bottom right, with an arrow.** It used to be
/// a quiet word at the bottom right, a reminder date at the bottom left, and
/// the ways to move the idea on inside the folded actions — so changing where
/// an idea stood meant opening a panel to find a row of tiles. Now the status
/// itself is the control: the stage as the card says it ("מחכים לתשובת
/// הבחורה"), a dot in the status's own colour, and a menu of every status the
/// idea can go to, ending with "העברה להמתנה" and "סגירת רעיון".
///
/// The reason a waiting proposal is waiting sits at the other end, in muted
/// text. The reminder date is not on the card at all any more; it lives in the
/// actions, under the two WhatsApp buttons.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.match,
    required this.onSetStage,
    required this.onAction,
  });

  final MatchIdea match;
  final void Function(MatchStage stage)? onSetStage;
  final ValueChanged<MatchQuickAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String reason = (match.waitingReason ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 2),
      child: Row(
        children: <Widget>[
          // Bottom right (the start edge, in RTL): the status, and the menu
          // behind it — where a reader's eye finishes a card that opens with
          // her face on the same side.
          Flexible(
            child: _CardStatusMenu(
              match: match,
              onSetStage: onSetStage,
              onAction: onAction,
            ),
          ),
          if (reason.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            // Bottom left: why a waiting idea is waiting, when it says.
            Expanded(
              child: Text(
                reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One entry in the status menu: a stage the idea can be set to, or one of
/// the moves that take it somewhere else.
class _StatusChoice {
  const _StatusChoice.stage(MatchStage this.stage) : action = null;
  const _StatusChoice.action(MatchQuickAction this.action) : stage = null;

  final MatchStage? stage;
  final MatchQuickAction? action;
}

/// The status word with its dot and arrow, and the list of statuses behind it.
class _CardStatusMenu extends StatelessWidget {
  const _CardStatusMenu({
    required this.match,
    required this.onSetStage,
    required this.onAction,
  });

  final MatchIdea match;
  final void Function(MatchStage stage)? onSetStage;
  final ValueChanged<MatchQuickAction>? onAction;

  /// What the card says the idea is at: the stage while it is open, the
  /// coarse state otherwise.
  static String labelOf(MatchIdea match) {
    switch (match.status) {
      case MatchStatus.idea:
      case MatchStatus.checking:
        return MatchStage.of(match).label;
      case MatchStatus.unavailable:
      case MatchStatus.dating:
      case MatchStatus.rejected:
      case MatchStatus.dated:
      case MatchStatus.married:
        return match.status.stateLabel;
    }
  }

  /// Every status the idea can be moved to from where it is, stages first and
  /// the moves that leave the stages — "העברה להמתנה", "סגירת רעיון" — last.
  List<_StatusChoice> _choices() {
    final bool staged =
        match.status == MatchStatus.idea ||
        match.status == MatchStatus.checking ||
        match.status == MatchStatus.dating;
    return <_StatusChoice>[
      if (staged && onSetStage != null)
        for (final MatchStage stage in MatchStage.values)
          if (stage.isSelectable) _StatusChoice.stage(stage),
      if (onAction != null)
        for (final MatchQuickAction action in MatchQuickAction.statusActionsFor(
          match.status,
        ))
          // "מתחילים לצאת" is already in the list as a stage.
          if (!(staged &&
              onSetStage != null &&
              action == MatchQuickAction.dating))
            _StatusChoice.action(action),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = AppColors.matchState(
      match.status,
      dark: theme.brightness == Brightness.dark,
    );
    final List<_StatusChoice> choices = _choices();
    final MatchStage current = MatchStage.of(match);

    final Widget word = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            labelOf(match),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (choices.isNotEmpty)
          Icon(Icons.arrow_drop_down_rounded, size: 22, color: color),
      ],
    );
    if (choices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: word,
      );
    }

    final bool hasStages = choices.any((_StatusChoice c) => c.stage != null);
    return PopupMenuButton<_StatusChoice>(
      tooltip: 'שינוי סטטוס הרעיון',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      onSelected: (_StatusChoice choice) {
        final MatchStage? stage = choice.stage;
        if (stage != null) {
          onSetStage?.call(stage);
        } else {
          onAction?.call(choice.action!);
        }
      },
      itemBuilder: (BuildContext context) {
        final List<PopupMenuEntry<_StatusChoice>> items =
            <PopupMenuEntry<_StatusChoice>>[];
        bool dividerPlaced = false;
        for (final _StatusChoice choice in choices) {
          if (choice.action != null && hasStages && !dividerPlaced) {
            items.add(const PopupMenuDivider());
            dividerPlaced = true;
          }
          final MatchStage? stage = choice.stage;
          final bool selected = stage != null && stage == current;
          items.add(
            PopupMenuItem<_StatusChoice>(
              value: choice,
              height: 44,
              child: Row(
                children: <Widget>[
                  if (choice.action != null) ...<Widget>[
                    Icon(
                      choice.action!.icon,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(stage?.label ?? choice.action!.label)),
                  if (selected)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
          );
        }
        return items;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: word,
      ),
    );
  }
}

/// The panel under the pair: everything a proposal can have done to it, folded
/// behind one line.
///
/// **One box, the same shape on every idea.** It is laid out the way a couple
/// who are out have always had it: the one thing the idea is waiting for at
/// the top — "יאללה לקדם" and a WhatsApp button for each side — then, inside
/// the same box, when the app will ask about it next, and the person who can
/// pass the proposal on. The status is not repeated here; it is on the card
/// itself, where it can be changed. The journal lies open under the box.
class _CardActionBar extends StatelessWidget {
  const _CardActionBar({
    required this.open,
    required this.match,
    required this.male,
    required this.female,
    required this.datingSince,
    required this.onToggle,
    required this.onAction,
    required this.onAdvance,
    required this.onCheckInWith,
    required this.onChangeCheckInFrequency,
  });

  final bool open;
  final MatchIdea match;
  final Person? male;
  final Person? female;
  final DateTime? datingSince;

  final VoidCallback onToggle;
  final ValueChanged<MatchQuickAction>? onAction;
  final void Function(MatchNextStep step)? onAdvance;
  final void Function(Person person)? onCheckInWith;
  final void Function(int days)? onChangeCheckInFrequency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ValueChanged<MatchQuickAction>? action = onAction;
    if (action == null) {
      return const SizedBox(height: 6);
    }

    final bool dating = match.status == MatchStatus.dating;
    final bool archived = match.status.isArchived;

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
                    open ? 'סגירת פעולות' : 'פעולות',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
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
                    child: Column(
                      children: <Widget>[
                        if (dating)
                          _DatingPanel(
                            match: match,
                            male: male,
                            female: female,
                            startedAt: datingSince,
                            onCheckInWith: onCheckInWith,
                            onChangeFrequency: onChangeCheckInFrequency,
                            onAddContact: () =>
                                action(MatchQuickAction.contact),
                          )
                        else
                          _AskPanel(
                            match: match,
                            male: male,
                            female: female,
                            onAsk: archived ? null : onAdvance,
                            onChangeReminder: archived
                                ? null
                                : () => action(MatchQuickAction.reminder),
                            onAddContact: () =>
                                action(MatchQuickAction.contact),
                          ),
                        const SizedBox(height: 10),
                        MatchJournalView(matchId: match.id),
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

/// "יאללה לקדם" — the one box an open idea's actions live in.
///
/// Top to bottom: the heading and its question, one WhatsApp button for each
/// side, the next reminder with "שינוי", and the person who can pass the
/// proposal on. Pressing a side's button opens their chat with the other's
/// card and records, behind the scenes, that they were asked — which is where
/// the stage lives.
///
/// A closed idea keeps only the contact row: there is nobody left to ask and
/// nothing to be reminded of.
class _AskPanel extends StatelessWidget {
  const _AskPanel({
    required this.match,
    required this.male,
    required this.female,
    required this.onAsk,
    required this.onChangeReminder,
    required this.onAddContact,
  });

  final MatchIdea match;
  final Person? male;
  final Person? female;
  final void Function(MatchNextStep step)? onAsk;
  final VoidCallback? onChangeReminder;
  final VoidCallback onAddContact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = AppColors.matchState(match.status, dark: dark);
    final void Function(MatchNextStep step)? ask = onAsk;
    final VoidCallback? changeReminder = onChangeReminder;

    return _ActionsBox(
      tint: ink,
      children: <Widget>[
        if (ask != null) ...<Widget>[
          Text(
            'יאללה לקדם',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'את מי {תרצה|תרצי} לשאול על הרעיון?'.forGender(context.userGender),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              // In RTL the first child sits on the right, under her face.
              Expanded(
                child: _CheckInButton(
                  person: female,
                  gender: Gender.female,
                  fallback: 'הבחורה',
                  onTap: (_) => ask(MatchNextStep.askFemale),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CheckInButton(
                  person: male,
                  gender: Gender.male,
                  fallback: 'הבחור',
                  onTap: (_) => ask(MatchNextStep.askMale),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (changeReminder != null) ...<Widget>[
          _ReminderSchedule(match: match, onChange: changeReminder),
          const SizedBox(height: 2),
        ],
        _ContactsLine(match: match, onAddContact: onAddContact),
      ],
    );
  }
}

/// The box every idea's actions are drawn in: a soft wash of the status's own
/// colour, rounded, with a little air inside.
class _ActionsBox extends StatelessWidget {
  const _ActionsBox({required this.tint, required this.children});

  final Color tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: dark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// "תזכורת ב־24.10" and a small "שינוי" beside it.
class _ReminderSchedule extends StatelessWidget {
  const _ReminderSchedule({required this.match, required this.onChange});

  final MatchIdea match;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? date = match.reminderDate;

    return Row(
      children: <Widget>[
        Icon(
          Icons.notifications_none_rounded,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            date == null
                ? 'אין תזכורת'
                : 'תזכורת ב־${AppDateUtils.formatDateShort(date)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        _BoxLink(label: date == null ? 'הוספה' : 'שינוי', onTap: onChange),
      ],
    );
  }
}

/// A small word-button at the end of a row inside the actions box.
class _BoxLink extends StatelessWidget {
  const _BoxLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// A couple who are out: how long it has been, one tap to each of them, when
/// the app will ask next, and who can pass things on — the same box an open
/// idea wears, in the couple's rose.
///
/// Taking one of the chats books the next check-in, at a week for the first
/// and monthly after that. The status — including the way back out of
/// "מתחילים לצאת" — is on the card.
class _DatingPanel extends StatelessWidget {
  const _DatingPanel({
    required this.match,
    required this.male,
    required this.female,
    required this.startedAt,
    required this.onCheckInWith,
    required this.onChangeFrequency,
    required this.onAddContact,
  });

  final MatchIdea match;
  final Person? male;
  final Person? female;
  final DateTime? startedAt;
  final void Function(Person person)? onCheckInWith;
  final void Function(int days)? onChangeFrequency;
  final VoidCallback onAddContact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.femaleAccentDm : AppColors.femaleAccent;
    final DateTime? since = startedAt;
    final int every = match.checkInEveryDays ?? DatingCheckIn.defaultEveryDays;

    return _ActionsBox(
      tint: ink,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.favorite_rounded, size: 20, color: ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                since == null
                    ? 'הם יוצאים 😊 בדקת איך הולך?'
                    : DatingCheckIn.headline(DatingCheckIn.daysOut(since)),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ink,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            // In RTL the first child sits on the right, matching the two
            // faces above it.
            Expanded(
              child: _CheckInButton(
                person: female,
                gender: Gender.female,
                fallback: 'הבחורה',
                onTap: onCheckInWith,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CheckInButton(
                person: male,
                gender: Gender.male,
                fallback: 'הבחור',
                onTap: onCheckInWith,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Icon(
              Icons.notifications_none_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                match.reminderDate == null
                    ? 'נזכיר לך לבדוק ${DatingCheckIn.frequencyLabel(every)}'
                    : 'תזכורת ב־'
                          '${AppDateUtils.formatDateShort(match.reminderDate!)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (onChangeFrequency != null)
              PopupMenuButton<int>(
                tooltip: 'תדירות התזכורות',
                position: PopupMenuPosition.under,
                padding: EdgeInsets.zero,
                onSelected: onChangeFrequency,
                itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
                  for (final int days in DatingCheckIn.frequencyOptions)
                    PopupMenuItem<int>(
                      value: days,
                      height: 42,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(DatingCheckIn.frequencyLabel(days)),
                          ),
                          if (days == every)
                            Icon(
                              Icons.check,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Text(
                    'שינוי',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        _ContactsLine(match: match, onAddContact: onAddContact),
      ],
    );
  }
}

/// One half of a couple, as a chat button. Absent where there is no number to
/// call, rather than drawn dead.
class _CheckInButton extends StatelessWidget {
  const _CheckInButton({
    required this.person,
    required this.gender,
    required this.fallback,
    required this.onTap,
  });

  final Person? person;

  /// Which side this is — the name is written in its own colour, blue for
  /// him and the palette's rose for her, like everywhere else in the app.
  final Gender gender;
  final String fallback;
  final void Function(Person person)? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Person? current = person;
    final bool reachable =
        current != null &&
        ContactChannels.forPerson(current) != ContactChannel.none &&
        onTap != null;
    final String name = (current?.firstName ?? '').trim().isEmpty
        ? fallback
        : current!.firstName.trim();

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: reachable ? () => onTap!(current) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 17,
                color: reachable
                    ? kWhatsAppGreen
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.genderAccent(
                      gender,
                      dark: theme.brightness == Brightness.dark,
                    ).withValues(alpha: reachable ? 1 : 0.55),
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

/// The person who can pass this proposal on — somebody who knows one of the
/// two personally — as the last row of the actions box, with "הוספה" at its
/// end.
///
/// Each contact is its name (and who they are to the idea) with a WhatsApp
/// button, because a contact is added to be *reached*, not to copy a number
/// out of.
class _ContactsLine extends StatelessWidget {
  const _ContactsLine({required this.match, required this.onAddContact});

  final MatchIdea match;
  final VoidCallback onAddContact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MatchContact> contacts = match.relatedContacts;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.person_outline_rounded,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: contacts.isEmpty
              ? Text(
                  'הוספת איש קשר שקשור להצעה',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (int i = 0; i < contacts.length; i++)
                        _ContactPill(
                          contact: contacts[i],
                          onRemove: () =>
                              _confirmRemove(context, contacts[i], i),
                        ),
                    ],
                  ),
                ),
        ),
        _BoxLink(
          label: contacts.isEmpty ? 'הוספה' : 'עוד',
          onTap: onAddContact,
        ),
      ],
    );
  }

  /// A long press on a contact takes them off this proposal, after asking.
  Future<void> _confirmRemove(
    BuildContext context,
    MatchContact contact,
    int index,
  ) async {
    final MatchRepository repository = context.read<MatchRepository>();
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'הסרת איש קשר',
      message: 'להסיר את ${contact.name} מאנשי הקשר של הרעיון?',
      confirmText: 'הסרה',
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }
    await repository.removeRelatedContact(match.id, index);
  }
}

/// A related contact: the name (and who they are to the proposal), and a
/// WhatsApp button that opens a chat with them.
class _ContactPill extends StatelessWidget {
  const _ContactPill({required this.contact, required this.onRemove});

  final MatchContact contact;

  /// A long press: take this contact off the proposal.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String role = (contact.description ?? '').trim();
    final bool reachable = contact.phone.trim().isNotEmpty;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: reachable
            ? () => WhatsAppUtils.openChatWithPhone(contact.phone)
            : null,
        onLongPress: onRemove,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  role.isEmpty ? contact.name : '${contact.name} · $role',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (reachable) ...<Widget>[
                const SizedBox(width: 6),
                const FaIcon(
                  FontAwesomeIcons.whatsapp,
                  size: 15,
                  color: kWhatsAppGreen,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One side's messaging control: a small disc sitting on the corner of their
/// photo, in the card's own surface colour so it reads as resting on the face
/// rather than punched through it.
///
/// What it *is* depends on the number behind it — WhatsApp, or SMS. With no
/// number at all there is **nothing**: the disc is not drawn, and the corner of
/// the photo is left alone.
///
/// It used to fall back to a pencil that opened the card for editing. That is a
/// different action wearing the same button in the same place — a matchmaker
/// reaching for the corner of a face expects to message that person, and on the
/// one side that cannot be messaged they got an editor instead. Editing a card
/// is a tap on the card away, and an empty corner says "no number here" more
/// clearly than any icon could.
class _SideContactButton extends StatelessWidget {
  const _SideContactButton({
    required this.person,
    required this.onOpenWhatsApp,
    required this.onCompleteCard,
  });

  final Person person;
  final VoidCallback onOpenWhatsApp;

  /// Kept for the callers that still pass it; nothing here uses it now that a
  /// person with no number gets no button. Removing it would touch four call
  /// sites for no gain.
  final VoidCallback onCompleteCard;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ContactChannel channel = ContactChannels.forPerson(person);
    if (channel == ContactChannel.none) {
      return const SizedBox.shrink();
    }

    final ({Widget icon, VoidCallback onTap}) control = switch (channel) {
      ContactChannel.whatsapp => (
        icon: const FaIcon(
          FontAwesomeIcons.whatsapp,
          size: 16,
          color: kWhatsAppGreen,
        ),
        onTap: onOpenWhatsApp,
      ),
      ContactChannel.sms => (
        icon: Icon(
          Icons.sms_outlined,
          size: 16,
          color: theme.colorScheme.primary,
        ),
        onTap: () => ContactChannels.openSms(person.phone),
      ),
      // Unreachable: handled above, before the disc is built at all.
      ContactChannel.none => (icon: const SizedBox.shrink(), onTap: () {}),
    };

    return Material(
      color: theme.colorScheme.surface,
      shape: CircleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: control.onTap,
        child: Padding(padding: const EdgeInsets.all(6), child: control.icon),
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
      padding: const EdgeInsets.fromLTRB(6, 30, 6, 0),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          // **The heart wears the proposal's status and nothing else** —
          // blue while open, brown while waiting, copper once they are out —
          // through [AppColors.matchState]. The stage inside an open idea
          // (who has been asked) never changes it.
          Icon(
            Icons.favorite,
            size: dating ? 25 : 20,
            color: AppColors.matchState(
              status,
              dark: Theme.of(context).brightness == Brightness.dark,
            ),
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
