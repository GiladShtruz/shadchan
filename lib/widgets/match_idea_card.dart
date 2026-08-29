import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/dialogs/match_journal_sheet.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/contact_channel.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/dating_check_in.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/widgets/contact_channel_button.dart';
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
                _StatusLine(match: match),
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
                  onSetStage: widget.onSetStage,
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
    required this.onCompleteCard,
  });

  final Person? person;
  final Gender gender;
  final void Function(Person person, ProfileStatus status)? onStatusPicked;
  final void Function(Person person) onOpenWhatsApp;
  final void Function(Person person) onCompleteCard;

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
                child: _SideContactButton(
                  person: current,
                  onOpenWhatsApp: () => onOpenWhatsApp(current),
                  onCompleteCard: () => onCompleteCard(current),
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

/// Where the proposal stands — said once, quietly, inside the card.
///
/// **Small, because the card already says most of it.** This was a full-width
/// band with the status emoji in it, drawn across every card in the list, and
/// on a screen of proposals it was the loudest thing on every one of them: a
/// row of coloured bars with the two faces underneath. The status still has to
/// be readable at a glance — that is why it exists at all — but "readable at a
/// glance" is a dot and a word, not a banner.
///
/// The reason a waiting proposal is waiting rides on the same line, in muted
/// text, because it is the sentence that finishes the word beside it.
///
/// One coarse word rather than the stored status: see [MatchStatus.stateLabel].
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.match});

  final MatchIdea match;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = AppColors.statusColor(match.status.name);
    final String reason = (match.waitingReason ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  match.status.stateLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (reason.isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
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

/// The panel under the pair: everything a proposal can have done to it, folded
/// behind one line.
///
/// **The promotion is the first thing under the fold, and the loudest.** It
/// used to open onto a row of three status tiles — "העברה להמתנה", "מתחילים
/// לצאת", "סגירת רעיון" — which are the three ways an idea *ends*, offered
/// before the one thing it is actually waiting for. Somebody who opens the
/// actions of an open proposal is nearly always there to move it on, so that
/// is what meets the eye: one wide row naming the exact next step, with the
/// stage beside it.
///
/// **A couple who are out get a different panel entirely.** Asking him, asking
/// her and sending the card are finished business the moment the two of them
/// are meeting; see [_DatingPanel].
///
/// Under the promotion, in descending order of how often it is wanted: the
/// status moves as one row of same-shaped tiles, then one quiet line carrying
/// the reminder and the related contact, then the journal lying open. Nothing
/// below the promotion is shaped like it, so nothing below it competes with it.
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
    required this.onSetStage,
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
  final void Function(MatchStage stage)? onSetStage;
  final void Function(Person person)? onCheckInWith;
  final void Function(int days)? onChangeCheckInFrequency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ValueChanged<MatchQuickAction>? action = onAction;
    if (action == null) {
      return const SizedBox(height: 6);
    }

    final List<MatchQuickAction> statusActions =
        MatchQuickAction.statusActionsFor(match.status);
    final MatchNextStep? next = MatchStages.nextStep(match);
    final bool dating = match.status == MatchStatus.dating;

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
                    child: Column(
                      children: <Widget>[
                        // 1. The one thing this proposal is waiting for.
                        if (dating)
                          _DatingPanel(
                            match: match,
                            male: male,
                            female: female,
                            startedAt: datingSince,
                            onCheckInWith: onCheckInWith,
                            onChangeFrequency: onChangeCheckInFrequency,
                            onSetStage: onSetStage,
                          )
                        else if (next != null && onAdvance != null) ...<Widget>[
                          _PromoteRow(
                            match: match,
                            step: next,
                            male: male,
                            female: female,
                            onTap: () => onAdvance!(next),
                            onOther: MatchStages.otherFirstStep(match) == null
                                ? null
                                : () => onAdvance!(
                                    MatchStages.otherFirstStep(match)!,
                                  ),
                            onSetStage: onSetStage,
                          ),
                        ],
                        if (dating || (next != null && onAdvance != null))
                          const SizedBox(height: 10),

                        // 2. The status moves, and the only grid on the panel.
                        _ActionRow(actions: statusActions, onTap: action),
                        const SizedBox(height: 8),

                        // 3. The two small things, on one line: when to come
                        // back to this, and who else is around it.
                        _SecondaryActionsLine(
                          match: match,
                          onReminder: () => action(MatchQuickAction.reminder),
                          onAddContact: () => action(MatchQuickAction.contact),
                        ),
                        const SizedBox(height: 8),
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

/// "יאללה לקדם" — the exact next step, and the stage it comes from.
///
/// **One button that changes its mind, rather than a prompt that never
/// changes.** The row used to say "יאללה לקדם!" for the life of the proposal
/// and open a sheet asking who to message — a question the app can answer, and
/// one it had to ask again every single time because nothing was written down
/// about who had already been told. Now the proposal carries the two dates
/// behind [MatchStage], so the button names the side whose turn it is, sends
/// them the other one's card, and moves the stage on by itself.
///
/// **The stage sits beside the button, and it is editable.** Most matchmaking
/// happens on a phone call the app never sees; a stage that could only be
/// advanced through this button would be wrong on half the list. The little
/// menu is how it gets put right.
///
/// **And a proposal nothing has happened to for a week says so, here.** Not by
/// moving up the list — the order stays chronological, because a list that
/// rearranges itself is a list nobody can keep their place in — but by wearing
/// the sentence in the one place somebody is already looking when they decide
/// what to do next.
///
/// **Quiet paper, not a green slab.** This was a block of mint filling the top
/// of every open panel, with the stage chip, an alternative side and a line
/// about what was last sent all stacked inside the same tinted area — the
/// loudest thing on a screen full of cards, and busy enough that the one
/// button in it had to compete with three other controls painted on the same
/// colour. It is the card's own surface now with a thin green edge, the green
/// kept to a small square behind the icon and to the words on the button
/// itself. Everything that is *not* the action moved below a hairline into one
/// quiet footer line, so the panel opens on a single unmistakable next step
/// with its context underneath rather than around it.
class _PromoteRow extends StatelessWidget {
  const _PromoteRow({
    required this.match,
    required this.step,
    required this.male,
    required this.female,
    required this.onTap,
    required this.onOther,
    required this.onSetStage,
  });

  final MatchIdea match;
  final MatchNextStep step;
  final Person? male;
  final Person? female;
  final VoidCallback onTap;

  /// "לפנות דווקא אל הבחורה" — only on a brand-new idea, where there is still a
  /// choice of which side to start with.
  final VoidCallback? onOther;

  final void Function(MatchStage stage)? onSetStage;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool bothAsked = step == MatchNextStep.startDating;
    final Color ink = bothAsked ? AppColors.statusDating : kWhatsAppGreen;
    final String? nudge = MatchStaleness.nudge(match);
    final String? sent = match.lastShareLabel;
    final bool hasFooter =
        onSetStage != null ||
        onOther != null ||
        (sent != null && sent.trim().isNotEmpty);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink.withValues(alpha: dark ? 0.45 : 0.30)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            // Nothing to press once both sides have been asked: the row is a
            // statement of where the proposal stands, and what happens next is
            // one of the three status tiles under it.
            onTap: bothAsked ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
              child: Row(
                children: <Widget>[
                  // The colour lives here and on the row's own words, and
                  // nowhere else on the panel.
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: dark ? 0.22 : 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: bothAsked
                        ? Icon(Icons.done_all_rounded, size: 18, color: ink)
                        : FaIcon(
                            FontAwesomeIcons.whatsapp,
                            size: 18,
                            color: ink,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          MatchStages.buttonLabel(
                            step,
                            male: male,
                            female: female,
                          ),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        // **Only the nudge gets a second line.** What the
                        // button does was written under it on every open
                        // proposal in the list — a caption explaining a button
                        // whose own words already say it. That a proposal has
                        // not been touched in a week is the one thing here
                        // that cannot be read off the row itself.
                        if (nudge != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            nudge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.statusChecking,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // `chevron_right` and not `chevron_left`: Material's chevrons
                  // carry `matchTextDirection`, so each one is mirrored in this
                  // RTL app, and this is the one that actually draws pointing
                  // left — the way the row reads and the way the card goes out.
                  if (!bothAsked)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (hasFooter) ...<Widget>[
            Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
              // A `Wrap` and not a `Row`: the stage can be five words long and
              // the alternative side is four more, which is wider than a 320px
              // card at any text scale. Side by side while they fit, stacked
              // when they do not — never clipped, and never overflowing.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: <Widget>[
                  if (onSetStage != null)
                    _StageMenu(
                      current: MatchStage.of(match),
                      onSelected: onSetStage!,
                    ),
                  if (onOther != null)
                    TextButton(
                      onPressed: onOther,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('לפנות קודם לבחורה'),
                    ),
                  // What already went out, once something has — on the same
                  // quiet line as the rest of the context rather than as a
                  // paragraph of its own under the button. A card sent last
                  // week does not answer the question of what to do next, but
                  // it is the context for it.
                  if (sent != null && sent.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 0),
                      child: Text(
                        sent,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The proposal's status, as a chip that opens the list of statuses.
///
/// **It says "סטטוס" before it says the status.** The chip used to be the bare
/// words — "שאלתי את הבחור" — sitting in a footer under a button, which reads
/// as a caption on the button rather than as the one field on the panel that
/// can be set. Naming it is what turns it into a control, and the arrow beside
/// it is then a promise the reader can act on.
///
/// **The list goes backwards as well as forwards.** Every status is offered
/// whatever the proposal is on now, which is the whole point: a "מתחילים לצאת"
/// tapped by mistake has to be undoable, and it has to be undoable from the
/// same place it was set. Still small and grey, because a correction is not an
/// action — the button above it is what moves a proposal in the ordinary
/// course of things.
class _StageMenu extends StatelessWidget {
  const _StageMenu({required this.current, required this.onSelected});

  final MatchStage current;
  final void Function(MatchStage stage) onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return PopupMenuButton<MatchStage>(
      tooltip: 'עדכון סטטוס הרעיון',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<MatchStage>>[
        PopupMenuItem<MatchStage>(
          enabled: false,
          height: 34,
          child: Text(
            'עדכון סטטוס',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final MatchStage stage in MatchStage.values)
          if (stage.isSelectable)
            PopupMenuItem<MatchStage>(
              value: stage,
              height: 42,
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(stage.label)),
                  if (stage == current)
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // "סטטוס: מחכים לתשובת הבחורה" is a long chip on a narrow card at
            // a large system font. It wraps rather than being cut: the whole
            // point of the word "סטטוס" in front is that the control names
            // itself, and half a name is worse than none.
            Flexible(
              child: Text(
                'סטטוס: ${current.label}',
                maxLines: 2,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// A couple who are out: how long it has been, and one tap to each of them.
///
/// **The proposal machinery is gone from this card.** "לשאול את הבחור",
/// "לשלוח כרטיס", "מתחילים לצאת" are all things that have already happened, and
/// leaving them on a couple who are meeting turns the best news on the screen
/// into another row of admin. What replaces them is the only open question:
/// they have been out for a while — have you asked how it is going?
///
/// The two chats are the action, and taking one books the next check-in, at a
/// week for the first and monthly after that. Changing the status is still
/// possible and deliberately quiet: it is on the tile row below, where every
/// other status move lives.
class _DatingPanel extends StatelessWidget {
  const _DatingPanel({
    required this.match,
    required this.male,
    required this.female,
    required this.startedAt,
    required this.onCheckInWith,
    required this.onChangeFrequency,
    required this.onSetStage,
  });

  final MatchIdea match;
  final Person? male;
  final Person? female;
  final DateTime? startedAt;
  final void Function(Person person)? onCheckInWith;
  final void Function(int days)? onChangeFrequency;

  /// The way back out of "מתחילים לצאת".
  ///
  /// **A couple who are out had no undo at all.** The status chip lives in the
  /// promotion row's footer, and this panel replaces that row entirely — so a
  /// proposal marked as dating by a mis-tap was stuck there, with both
  /// candidates marked "תפוס" and the card offering nothing but a wedding or a
  /// closure. It is the same menu it is everywhere else, at the foot of the
  /// panel where it stays out of the way of the good news.
  final void Function(MatchStage stage)? onSetStage;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.femaleAccentDm : AppColors.femaleAccent;
    final DateTime? since = startedAt;
    final int every = match.checkInEveryDays ?? DatingCheckIn.defaultEveryDays;

    return Material(
      color: ink.withValues(alpha: dark ? 0.16 : 0.10),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.favorite_rounded, size: 18, color: ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    since == null
                        ? 'הם יוצאים 😊 בדקת איך הולך?'
                        : DatingCheckIn.headline(DatingCheckIn.daysOut(since)),
                    style: theme.textTheme.labelLarge?.copyWith(
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
                    fallback: 'הבחורה',
                    onTap: onCheckInWith,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CheckInButton(
                    person: male,
                    fallback: 'הבחור',
                    onTap: onCheckInWith,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(
                  Icons.notifications_none_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    match.reminderDate == null
                        ? 'נזכיר לך לבדוק ${DatingCheckIn.frequencyLabel(every)}'
                        : 'התזכורת הבאה: '
                              '${AppDateUtils.formatDateShort(match.reminderDate!)}'
                              ' · ${DatingCheckIn.frequencyLabel(every)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onChangeFrequency != null)
                  PopupMenuButton<int>(
                    tooltip: 'תדירות התזכורות',
                    position: PopupMenuPosition.under,
                    padding: EdgeInsets.zero,
                    onSelected: onChangeFrequency,
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<int>>[
                          for (final int days in DatingCheckIn.frequencyOptions)
                            PopupMenuItem<int>(
                              value: days,
                              height: 42,
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      DatingCheckIn.frequencyLabel(days),
                                    ),
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
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        'שינוי',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (onSetStage != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _StageMenu(
                  current: MatchStage.of(match),
                  onSelected: onSetStage!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One half of a couple, as a chat button. Absent where there is no number to
/// call, rather than drawn dead.
class _CheckInButton extends StatelessWidget {
  const _CheckInButton({
    required this.person,
    required this.fallback,
    required this.onTap,
  });

  final Person? person;
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 15,
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
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: reachable
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
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

/// The two small things, on one line: when to come back to this proposal, and
/// who else is around it.
///
/// **Both used to be rows of their own, and neither deserved one.** The
/// reminder was a full-width bar with an icon and two lines of text, drawn on
/// every open proposal whether or not one was set — the loudest thing on the
/// panel after the promotion, for a feature most proposals never use. Adding a
/// contact had a line to itself directly under it. Together they were two more
/// bands between the button and the journal.
///
/// So: a chip that says "🔔 תזכורת 24.9" when there is one and "הוספת תזכורת"
/// when there is not, and beside it the contact link at the size a secondary
/// action should be. The contacts already on the proposal ride underneath,
/// because they are worth seeing without opening anything.
class _SecondaryActionsLine extends StatelessWidget {
  const _SecondaryActionsLine({
    required this.match,
    required this.onReminder,
    required this.onAddContact,
  });

  final MatchIdea match;
  final VoidCallback onReminder;
  final VoidCallback onAddContact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? date = match.reminderDate;
    final String note = (match.reminderNote ?? '').trim();
    final List<MatchContact> contacts = match.relatedContacts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // **A `Wrap`, so neither pill is ever cut.** Side by side in a `Row`
        // the second one took whatever the first left, which on any ordinary
        // phone was not enough: "הוספת איש קשר שקשור לרעיון" was ellipsized to
        // "הוספת איש קשר שקשור…" on every open proposal in the list. Stacked
        // when they do not fit, side by side when they do, and each of them
        // always shows its whole label.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            _MiniAction(
              icon: date != null
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              label: date == null
                  ? 'הוספת תזכורת'
                  : 'תזכורת ${AppDateUtils.formatDateShort(date)}',
              tint: date != null
                  ? AppColors.statusChecking
                  : theme.colorScheme.onSurfaceVariant,
              onTap: onReminder,
            ),
            _MiniAction(
              icon: Icons.person_add_alt_1_outlined,
              label: 'הוספת איש קשר שקשור לרעיון',
              tint: theme.colorScheme.onSurfaceVariant,
              onTap: onAddContact,
            ),
          ],
        ),
        if (note.isNotEmpty || contacts.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            <String>[
              if (note.isNotEmpty) note,
              if (contacts.isNotEmpty) contacts.map(_contactLabel).join(' · '),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  static String _contactLabel(MatchContact contact) {
    final String role = (contact.description ?? '').trim();
    return role.isEmpty ? contact.name : '${contact.name} · $role';
  }
}

/// A small pill: an icon, a word, and nothing drawn around it but a thin edge.
class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 5),
              // **It wraps rather than being cut.** "הוספת איש קשר שקשור
              // לרעיון" is wider than the inside of a proposal card on an
              // ordinary phone, so clamping it to one line meant it was
              // ellipsized to "הוספת איש קשר שקשור…" every time. Two lines
              // cost a few pixels once; a label nobody can finish reading
              // costs the action.
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: tint,
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.actions, required this.onTap});

  final List<MatchQuickAction> actions;
  final ValueChanged<MatchQuickAction> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final MatchQuickAction action in actions)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _QuickActionButton(
                action: action,
                onTap: () => onTap(action),
              ),
            ),
          ),
      ],
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

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.action, required this.onTap});

  final MatchQuickAction action;
  final VoidCallback onTap;

  /// One hue per action. The status moves keep the traffic-light reading they
  /// have always had — amber waits, green goes, red stops — and the tools are
  /// deliberately outside that language: they change nothing about where the
  /// proposal stands, so colouring them like a status would be a lie about
  /// what pressing them does.
  Color _ink(ThemeData theme) {
    switch (action) {
      case MatchQuickAction.waiting:
        return AppColors.statusChecking;
      case MatchQuickAction.dating:
      case MatchQuickAction.married:
        return AppColors.statusDating;
      case MatchQuickAction.close:
        return AppColors.statusRejected;
      case MatchQuickAction.reopen:
        return AppColors.statusIdea;
      case MatchQuickAction.reminder:
      case MatchQuickAction.contact:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = _ink(theme);

    // Every tile in a row is drawn identically; only the hue moves. Filling
    // "מתחילים לצאת" made it look like the status the proposal was already in,
    // and `_StatusBanner` is the one place that says where it actually is.
    return Material(
      color: ink.withValues(alpha: dark ? 0.18 : 0.09),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(action.icon, size: 17, color: ink),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  action.label,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ink,
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
