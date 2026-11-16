import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/widgets/area_switch_button.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/dialogs/access_permissions_dialog.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/dialogs/person_card_viewer.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_area_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/services/personal_helpers_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/utils/personal_next_step.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';
import 'package:shadchan/widgets/person_photo_carousel.dart';

/// The personal home is drawn from three shapes only: the one central card
/// (the owner's own), compact rows of action, and horizontal strips of
/// people. Everything else sits on the page's cream under a plain heading —
/// a page of white boxes reads as a settings screen, which is exactly what
/// this page must not feel like.

/// Reads [T] when an ancestor provides it, else null — the inbox is not in
/// every tree that draws the personal home (tests, a cold start).
T? maybeWatch<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

/// The merged list of the owner's matchmaker friends.
List<MatchmakerFriend> matchmakerFriendsOf(CardAccessProvider access) =>
    MatchmakerFriends.build(
      known: access.knownHelpers,
      rows: access.ownerRows.isEmpty && access.approved.isNotEmpty
          // A provider that only reports [approved] (older seams, tests).
          ? access.approved
          : access.ownerRows,
      nameOf: access.nameInContacts,
    );

/// A plain section heading on the page's own paper.
class PersonalSectionTitle extends StatelessWidget {
  const PersonalSectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// "למעבר לאזור השדכן" — the small way across, beside the greeting, for an
/// owner who also matchmakes. The mirror of the matchmaker home's "למעבר לאזור
/// האישי", and drawn by the same [AreaSwitchButton].
class SwitchToMatchmakerButton extends StatelessWidget {
  const SwitchToMatchmakerButton({super.key, required this.onTap});
  final VoidCallback onTap;

  static const String labelTemplate = 'למעבר לאזור {השדכן|השדכנית}';

  @override
  Widget build(BuildContext context) => AreaSwitchButton(
    label: labelTemplate.forGender(context.userGender),
    onTap: onTap,
  );
}

/// "הכרטיס שלי" — the one central card of the page: the main photo (up to
/// four, swipeable, a tap opens the card in full), the name and facts, a few
/// lines of the text, and the way to the whole card.
class PersonalMyCard extends StatelessWidget {
  const PersonalMyCard({super.key, required this.card, required this.active});

  final Person card;

  /// False while the card is still a draft nobody can see.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = AppColors.genderAccent(card.gender, dark: dark);
    final List<String> photos = card.photosPaths
        .where((String path) => File(path).existsSync())
        .take(4)
        .toList();
    final String description = (card.description ?? '').trim();
    final List<String> facts = <String>[
      if (card.age != null) 'גיל ${card.age}',
      if (card.religiousLevelLabel.isNotEmpty) card.religiousLevelLabel,
      if ((card.city ?? '').trim().isNotEmpty) card.city!.trim(),
    ];

    return HomePaperCard(
      stripe: accent,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'הכרטיס שלי',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'עריכת הכרטיס',
                visualDensity: VisualDensity.compact,
                onPressed: () => PersonalAreaService.editCard(context),
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
            ],
          ),
          if (photos.isNotEmpty) ...<Widget>[
            PersonPhotoCarousel(
              photosPaths: photos,
              height: 240,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(16),
              backgroundColor: dark
                  ? theme.colorScheme.surfaceContainerHighest
                  : AppColors.cardCream,
              onTapIndex: (int index) =>
                  PersonCardViewer.openOwnCard(context, initialIndex: index),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: <Widget>[
              if (photos.isEmpty) ...<Widget>[
                GestureDetector(
                  onTap: () => PersonCardViewer.openOwnCard(context),
                  child: PersonAvatar(person: card, radius: 28),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      card.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    if (facts.isNotEmpty)
                      Text(
                        facts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              ProfileStatusTag(
                status: card.profileStatus,
                gender: card.gender,
                compact: true,
              ),
            ],
          ),
          if (description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ],
          if (!active) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              PersonalCardCodec.draftHint(card) ?? '',
              style: theme.textTheme.bodySmall,
            ),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => PersonCardViewer.openOwnCard(context),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('צפייה בכרטיס המלא'),
            ),
          ),
        ],
      ),
    );
  }
}

/// No card, or a deleted one: the central card's place, saying what to do.
class PersonalCardPrompt extends StatelessWidget {
  const PersonalCardPrompt({
    super.key,
    required this.deleted,
    required this.onAction,
    this.busy = false,
  });
  final bool deleted;
  final bool busy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return HomePaperCard(
      stripe: AppColors.secondary,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            deleted ? 'הכרטיס שלך נמחק' : 'עוד אין לך כרטיס אישי',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            deleted
                ? 'הוא שמור, ואפשר להחזיר אותו בכל עת — בסטטוס "פנוי".'
                : 'כרטיס אחד, שרק {אתה מעדכן|את מעדכנת}, והחברים שמשדכים רואים תמיד את הגרסה העדכנית.'
                      .forGender(context.userGender),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.icon(
                    onPressed: onAction,
                    icon: Icon(
                      deleted ? Icons.restore_rounded : Icons.add_rounded,
                    ),
                    label: Text(
                      deleted ? 'שחזור הכרטיס שלי' : 'יצירת הכרטיס שלי',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A matchmaker friend's face: their published photo, else an initial.
class MatchmakerFace extends StatelessWidget {
  const MatchmakerFace({super.key, required this.friend, this.radius = 24});
  final MatchmakerFriend friend;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? photo = friend.photoUrl?.trim();
    final bool hasPhoto = photo != null && photo.isNotEmpty;
    final String initial = friend.name.trim().isEmpty
        ? ''
        : friend.name.trim().characters.first;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.softBlue,
      foregroundImage: hasPhoto ? NetworkImage(photo) : null,
      child: Text(
        initial,
        style: theme.textTheme.titleMedium?.copyWith(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// One friend, tapped in the strip: who they are and the one or two things
/// to do about them.
abstract final class MatchmakerFriendSheet {
  static Future<void> show(BuildContext context, MatchmakerFriend friend) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  MatchmakerFace(friend: friend, radius: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          friend.name,
                          style: Theme.of(sheet).textTheme.titleMedium,
                        ),
                        Text(
                          MatchmakerFriends.detailsLine(friend),
                          style: Theme.of(sheet).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...MatchmakerFriendActions.buttons(
                context,
                friend,
                close: () => Navigator.of(sheet).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What can be done about one friend, wherever they are drawn.
abstract final class MatchmakerFriendActions {
  static List<Widget> buttons(
    BuildContext context,
    MatchmakerFriend friend, {
    required VoidCallback close,
  }) {
    void run(Future<void> Function() action) {
      close();
      unawaited(action());
    }

    final bool hidden = MatchmakerFriends.isHidden(
      friend,
      PersonalHelpersStore.hidden,
    );
    return <Widget>[
      if (friend.state == MatchmakerFriendState.requested) ...<Widget>[
        FilledButton(
          onPressed: () => run(() => PersonalAccessFlow.grant(context, friend)),
          child: const Text('לאשר'),
        ),
        TextButton(
          onPressed: () =>
              run(() => PersonalAccessFlow.decline(context, friend.row!)),
          child: const Text('לא עכשיו'),
        ),
      ] else if (friend.canReadCard) ...<Widget>[
        Text(
          MatchmakerFriends.permissionsLabel(friend),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => run(() => PersonalAccessFlow.edit(context, friend)),
          child: const Text('שינוי הרשאות'),
        ),
        TextButton(
          onPressed: () =>
              run(() => PersonalAccessFlow.revoke(context, friend.row!)),
          child: const Text('ביטול גישה'),
        ),
      ] else ...<Widget>[
        FilledButton(
          onPressed: () => run(() => PersonalAccessFlow.grant(context, friend)),
          child: const Text('לתת גישה'),
        ),
        TextButton(
          onPressed: () {
            close();
            PersonalHelpersStore.hide(
              MatchmakerFriends.hideKey(friend),
              !hidden,
            );
          },
          child: Text(hidden ? 'החזרה לרשימה' : 'הסתר מהרשימה'),
        ),
      ],
    ];
  }
}

/// The two ways out of the personal home: the card in full, and every
/// matchmaker friend. Two equal tiles, side by side.
class PersonalShortcuts extends StatelessWidget {
  const PersonalShortcuts({
    super.key,
    required this.onCard,
    required this.onMatchmakers,
  });

  final VoidCallback onCard;
  final VoidCallback onMatchmakers;

  static const String cardLabel = 'לכרטיס האישי שלי';
  static const String matchmakersLabel = 'השדכנים שלי';

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _ShortcutTile(
              icon: Icons.badge_outlined,
              label: cardLabel,
              accent: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
              onTap: onCard,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ShortcutTile(
              icon: Icons.handshake_outlined,
              label: matchmakersLabel,
              accent: dark ? AppColors.primaryDarkDm : AppColors.primaryDark,
              onTap: onMatchmakers,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Material(
      color: dark
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: dark ? 0 : 2,
      shadowColor: AppColors.onSurface.withValues(alpha: 0.20),
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.textTheme.titleMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AccentUnderline(color: accent),
          ],
        ),
      ),
    );
  }
}

/// "השדכנים שלי שהיו פעילים לאחרונה": a few friends, most recently active
/// first — face, name, when they were last active and how big their
/// database is. A tap opens that friend; the foot leads to all of them.
///
/// Drawn only when somebody was active in the last month: an empty box here
/// would be a list of nobody.
class PersonalRecentMatchmakers extends StatelessWidget {
  const PersonalRecentMatchmakers({super.key, required this.onSeeAll});

  final VoidCallback onSeeAll;

  static const String title = 'השדכנים שלי שהיו פעילים לאחרונה';
  static const String seeAllLabel = 'לכל השדכנים שלי';
  static const int shown = 3;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    // Hiding a friend changes the list without changing any provider.
    valueListenable: PersonalHelpersStore.revision,
    builder: (BuildContext context, _, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final List<MatchmakerFriend> recent = MatchmakerFriends.recentlyActive(
      matchmakerFriendsOf(access),
      hidden: PersonalHelpersStore.hidden,
      limit: shown,
    );
    if (recent.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PersonalSectionTitle(title),
          for (final MatchmakerFriend friend in recent)
            _RecentMatchmakerRow(friend: friend),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onSeeAll,
              child: const Text(seeAllLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentMatchmakerRow extends StatelessWidget {
  const _RecentMatchmakerRow({required this.friend});
  final MatchmakerFriend friend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String line = <String>[
      MatchmakerFriends.recentActivityLabel(
        friend.lastActiveAt!,
        female: friend.row?.matchmakerGender == 'female',
      ),
      if (friend.databaseCount != null)
        MatchmakerFriends.databaseLabel(friend.databaseCount!),
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => MatchmakerFriendSheet.show(context, friend),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            MatchmakerFace(friend: friend, radius: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    friend.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.textTheme.titleMedium?.color,
                    ),
                  ),
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// "מה כדאי לעשות עכשיו": exactly one short step, chosen by
/// [PersonalNextStep.pick], whose button goes straight to where it is done.
class PersonalNextAction extends StatelessWidget {
  const PersonalNextAction({
    super.key,
    required this.card,
    required this.live,
    required this.onMatchmakers,
  });

  final Person card;
  final bool live;

  /// Opens "השדכנים שלי" — where several friends are given access.
  final VoidCallback onMatchmakers;

  static const String title = 'מה כדאי לעשות עכשיו';

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: PersonalHelpersStore.revision,
    builder: (BuildContext context, _, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final PersonalAreaProvider? data = maybeWatch<PersonalAreaProvider>(
      context,
    );
    DateTime touched = card.updatedAt;
    final DateTime? remote = data?.date('editedAt');
    if (remote != null && remote.isAfter(touched)) touched = remote;
    DateTime reviewed = data?.date('reviewedAt') ?? touched;
    if (touched.isAfter(reviewed)) reviewed = touched;

    final PersonalNextStep step = PersonalNextStep.pick(
      card: card,
      live: live,
      friends: matchmakerFriendsOf(access),
      hidden: PersonalHelpersStore.hidden,
      hasPhone: profile.myPhone != null,
      friendsLoaded: access.helpersLoaded && access.ownerAccessLoaded,
      lastTouched: touched,
      reviewDue: PersonalAreaProvider.reviewDue(reviewed),
      gender: context.userGender,
      draftHint: PersonalCardCodec.draftHint(card),
    );

    Future<void> run() async {
      switch (step.kind) {
        case PersonalNextStepKind.request:
          await MatchmakerFriendSheet.show(context, step.friend!);
        case PersonalNextStepKind.grant:
          if (step.friend != null) {
            await PersonalAccessFlow.grant(context, step.friend!);
          } else {
            onMatchmakers();
          }
        case PersonalNextStepKind.addPhone:
          final String? phone = await MyPhoneDialog.show(context);
          if (phone != null) await profile.setMyPhone(phone);
        case PersonalNextStepKind.finishCard ||
            PersonalNextStepKind.review ||
            PersonalNextStepKind.refresh:
          await PersonalAreaService.editCard(context);
        case PersonalNextStepKind.invite:
          try {
            await PersonalAreaService.invite(context);
          } on Object {
            // Nothing to share to is not worth a message.
          }
      }
    }

    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    final IconData icon = switch (step.kind) {
      PersonalNextStepKind.request => Icons.mark_email_unread_outlined,
      PersonalNextStepKind.grant => Icons.lock_open_rounded,
      PersonalNextStepKind.addPhone => Icons.phone_outlined,
      PersonalNextStepKind.finishCard => Icons.edit_note_rounded,
      PersonalNextStepKind.review => Icons.auto_awesome_outlined,
      PersonalNextStepKind.refresh => Icons.add_a_photo_outlined,
      PersonalNextStepKind.invite => Icons.person_add_alt_1_outlined,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PersonalSectionTitle(title),
        HomePaperCard(
          key: ValueKey<PersonalNextStepKind>(step.kind),
          stripe: accent,
          onTap: run,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 22, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: run,
                  child: Text(step.action),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One figure about the community — a different one on each visit, never a
/// board of numbers. Only figures the server counted, only for the period
/// they belong to, only above zero; nothing at all until there is one.
class PersonalCommunityFigure extends StatelessWidget {
  const PersonalCommunityFigure({super.key, required this.visit});

  /// Which figure this visit shows, turned over by the caller on every
  /// arrival at the home.
  final int visit;

  /// The month key the server writes beside its monthly figure.
  static String monthKey([DateTime? at]) {
    final DateTime now = at ?? DateTime.now();
    return 'M${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// Every figure worth saying today. Never "how many cards were updated" —
  /// a count of other people's housekeeping says nothing to anybody.
  static List<String> linesFor(Map<String, dynamic> stats, [DateTime? now]) {
    final List<String> out = <String>[];
    void add(String key, String Function(num) text) {
      final Object? value = stats[key];
      if (value is num && value > 0) out.add(text(value));
    }

    add('singles', (num v) => '$v רווקים ורווקות מנהלים כרטיס אישי בשדכן');
    if (stats['weekKey'] == CommunityPeriods.weekKey(now)) {
      add(
        'newSinglesWeek',
        (num v) => v == 1
            ? 'עוד רווק או רווקה הצטרפו השבוע'
            : '$v רווקים ורווקות הצטרפו השבוע',
      );
      add('activeMatchmakers', (num v) => '$v שדכנים היו פעילים השבוע');
      add(
        'newMatchmakersWeek',
        (num v) => v == 1
            ? 'שדכן חדש הצטרף לקהילה השבוע'
            : '$v שדכנים חדשים הצטרפו לקהילה השבוע',
      );
      add(
        'couplesWeek',
        (num v) =>
            v == 1 ? 'זוג אחד התחיל לצאת השבוע' : '$v זוגות התחילו לצאת השבוע',
      );
      add(
        'engagementsWeek',
        (num v) => v == 1
            ? 'מזל טוב! זוג מהקהילה התארס השבוע 🎉'
            : 'מזל טוב! $v זוגות מהקהילה התארסו השבוע 🎉',
      );
    }
    if (stats['monthKey'] == monthKey(now)) {
      add(
        'newSinglesMonth',
        (num v) => v == 1
            ? 'עוד רווק או רווקה הצטרפו החודש'
            : '$v רווקים ורווקות הצטרפו החודש',
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final PersonalAreaProvider? data = maybeWatch<PersonalAreaProvider>(
      context,
    );
    final List<String> lines = data == null
        ? const <String>[]
        : linesFor(data.stats);
    if (lines.isEmpty) return const SizedBox.shrink();
    final String line = lines[visit % lines.length];
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.favorite_border_rounded,
            size: 18,
            color: AppColors.femaleAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                line,
                key: ValueKey<String>(line),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
