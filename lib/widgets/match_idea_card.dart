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
import 'package:shadchan/utils/enums.dart';
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
    this.onPromote,
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

  /// "יאללה לקדם!" — sends one of the two cards out. Null on a proposal there
  /// is nothing to promote about (archived, or a couple already dating), which
  /// simply drops the row.
  final VoidCallback? onPromote;

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
                  onToggle: () => setState(() => _actionsOpen = !_actionsOpen),
                  onAction: widget.onQuickAction,
                  onPromote: widget.onPromote,
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
/// **"פעולות", not "עדכון סטטוס".** The bar used to open onto three status
/// buttons and nothing else, and the label said so honestly. It now opens onto
/// the whole of what the proposal screen used to be — the three status moves,
/// the card going out, a reminder, a contact, the journal — because there is no
/// proposal screen left to hold them.
///
/// **The statuses lead, and nothing below them looks like them.** What opens
/// first is the one row of same-shaped tiles: the moves this proposal can
/// actually make from where it stands. Everything under it is a different shape
/// on purpose — a wide green row for sending the card, a bar of its own for the
/// reminder, one quiet line for a related contact, and the journal itself lying
/// open at the bottom. Three more identical squares under the statuses read as
/// three more statuses, which is exactly what the old proposal page never did.
class _CardActionBar extends StatelessWidget {
  const _CardActionBar({
    required this.open,
    required this.match,
    required this.onToggle,
    required this.onAction,
    required this.onPromote,
  });

  final bool open;
  final MatchIdea match;

  final VoidCallback onToggle;
  final ValueChanged<MatchQuickAction>? onAction;
  final VoidCallback? onPromote;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ValueChanged<MatchQuickAction>? action = onAction;
    if (action == null) {
      return const SizedBox(height: 6);
    }

    final List<MatchQuickAction> statusActions =
        MatchQuickAction.statusActionsFor(match.status);

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
                        // The statuses, at the top, and the only grid on the
                        // panel.
                        _ActionRow(actions: statusActions, onTap: action),
                        const SizedBox(height: 8),
                        if (onPromote != null) ...<Widget>[
                          _PromoteRow(
                            shareLabel: match.lastShareLabel,
                            onTap: onPromote!,
                          ),
                          const SizedBox(height: 6),
                        ],
                        _ReminderRow(
                          match: match,
                          onTap: () => action(MatchQuickAction.reminder),
                        ),
                        const SizedBox(height: 6),
                        _RelatedContactsLine(
                          match: match,
                          onAdd: () => action(MatchQuickAction.contact),
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

/// The reminder, on a bar of its own.
///
/// It was one of six identical tiles labelled "הוספת תזכורת", which could say
/// only whether the button existed — never whether a reminder was already set,
/// nor for when. A proposal with a date on it is a proposal in a different
/// state, and the row says so: the bell fills, the date is spelled out, and the
/// note left with it sits underneath. Tapping opens the same picker either way,
/// and the picker offers to clear a reminder that already exists.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.match, required this.onTap});

  final MatchIdea match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final DateTime? date = match.reminderDate;
    final String note = (match.reminderNote ?? '').trim();
    final Color ink = date != null
        ? AppColors.statusChecking
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: date != null
          ? ink.withValues(alpha: dark ? 0.18 : 0.10)
          : theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: dark ? 0.30 : 0.45,
            ),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: <Widget>[
              Icon(
                date != null
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 18,
                color: ink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      date == null
                          ? 'הוספת תזכורת'
                          : 'תזכורת ל־${AppDateUtils.formatDateShort(date)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    if (note.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 1),
                      Text(
                        note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The people around the proposal who are not the couple — a mother, a friend,
/// another matchmaker — and one small way to add another.
///
/// Deliberately the quietest thing on the panel. Adding a contact is something
/// a matchmaker does to a handful of proposals, so it gets a line rather than a
/// tile; the contacts already on the proposal sit beside it, because they are
/// worth seeing without opening anything.
class _RelatedContactsLine extends StatelessWidget {
  const _RelatedContactsLine({required this.match, required this.onAdd});

  final MatchIdea match;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MatchContact> contacts = match.relatedContacts;

    return Row(
      children: <Widget>[
        InkWell(
          onTap: onAdd,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.person_add_alt_1_outlined,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  'הוספת איש קשר',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (contacts.isNotEmpty)
          Expanded(
            child: Text(
              contacts.map(_contactLabel).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  static String _contactLabel(MatchContact contact) {
    final String role = (contact.description ?? '').trim();
    return role.isEmpty ? contact.name : '${contact.name} · $role';
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

/// "יאללה לקדם!" — and, once a card has gone out, what went where.
///
/// **One row that changes its mind, rather than two controls.** Before anything
/// has been sent this is a prompt: the proposal exists and nobody has been told
/// about it, which is the single most common thing wrong with a matchmaker's
/// list. After a card goes out it becomes the answer to the question the prompt
/// was asking — "רעיון בבדיקה", and underneath it who received what. The
/// button never stops working, because a card usually goes to both sides and
/// often more than once.
class _PromoteRow extends StatelessWidget {
  const _PromoteRow({required this.shareLabel, required this.onTap});

  final String? shareLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final String? sent = shareLabel;
    final bool waiting = sent != null;
    final Color ink = waiting ? AppColors.statusChecking : kWhatsAppGreen;

    return Material(
      color: ink.withValues(alpha: dark ? 0.18 : 0.10),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: Row(
            children: <Widget>[
              FaIcon(FontAwesomeIcons.whatsapp, size: 19, color: ink),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      waiting ? 'רעיון בבדיקה' : 'יאללה לקדם!',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      sent ?? 'שליחת כרטיס לחברים',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // `chevron_right` and not `chevron_left`: Material's chevrons
              // carry `matchTextDirection`, so each one is mirrored in this
              // RTL app, and this is the one that actually draws pointing left
              // — the way the row reads and the way the card goes out.
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
