import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/access_permissions_dialog.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/dialogs/person_card_viewer.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/personal_area_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/my_matchmakers_screen.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/services/personal_helpers_store.dart';
import 'package:shadchan/services/private_looking_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_status_timestamp.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';
import 'package:shadchan/widgets/person_photo_carousel.dart';
import 'package:shadchan/widgets/private_looking.dart';
import 'package:shadchan/widgets/profile_status_choices.dart';

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

/// "לאזור השדכן" — the small way across, beside the greeting, for an owner
/// who also matchmakes. The mirror of the matchmaker home's way into here.
class SwitchToMatchmakerButton extends StatelessWidget {
  const SwitchToMatchmakerButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color ink = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: ink.withValues(alpha: 0.45)),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
      label: Text('לאזור {השדכן|השדכנית}'.forGender(context.userGender)),
    );
  }
}

/// The two figures under the greeting, as two short lines rather than two
/// big statistics.
class PersonalAccessFigures extends StatelessWidget {
  const PersonalAccessFigures({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    // Hiding a friend changes the list without changing any provider.
    valueListenable: PersonalHelpersStore.revision,
    builder: (BuildContext context, _, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final List<MatchmakerFriend> friends = matchmakerFriendsOf(access);
    final int approved = access.approved.where((a) => a.canReadCard).length;
    final int others = MatchmakerFriends.grantable(
      friends,
      hidden: PersonalHelpersStore.hidden,
    ).length;
    final String approvedLine = !access.ownerAccessLoaded
        ? '—'
        : approved == 0
        ? 'עוד לא נתת גישה לחברים'
        : approved == 1
        ? 'נתת גישה לחבר אחד שלך'
        : 'נתת גישה ל־$approved חברים שלך';
    final String othersLine = !access.helpersLoaded
        ? '—'
        : others == 1
        ? 'חבר נוסף שלך משדך בשדכן'
        : '$others חברים נוספים שלך משדכים בשדכן';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _FigureLine(
          icon: Icons.lock_open_rounded,
          text: approvedLine,
          onTap: () => context.go('/me?section=approved'),
        ),
        if (!access.helpersLoaded || others > 0)
          _FigureLine(
            icon: Icons.diversity_3_outlined,
            text: othersLine,
            onTap: () => context.go('/me?section=helpers'),
          ),
      ],
    );
  }
}

class _FigureLine extends StatelessWidget {
  const _FigureLine({
    required this.icon,
    required this.text,
    required this.onTap,
  });
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
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
                  : AppColors.secondaryLight,
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
              'הכרטיס עדיין בטיוטה: תמונה אחת או כמה שורות עליך, והוא יוצג לחברים שאישרת.',
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

/// The status, compact: one line, three answers.
class PersonalStatusRow extends StatefulWidget {
  const PersonalStatusRow({super.key, required this.card});
  final Person card;

  @override
  State<PersonalStatusRow> createState() => _PersonalStatusRowState();
}

class _PersonalStatusRowState extends State<PersonalStatusRow> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ProfileStatusChoices(
          title: 'הסטטוס שלי',
          framed: false,
          compact: true,
          status: widget.card.profileStatus,
          gender: widget.card.gender,
          enabled: !_saving,
          onSelected: (ProfileStatus status) async {
            setState(() => _saving = true);
            try {
              await PersonalAreaService.updateStatus(context, status);
            } finally {
              if (mounted) setState(() => _saving = false);
            }
          },
        ),
        CardStatusTimestamp(ownerUid: context.read<CardAccessProvider>().uid),
      ],
    );
  }
}

/// "מה אני מחפש/ת" on the home page — something the owner tells the friends
/// they chose, not a setting. Empty, it invites; filled, it shows a few
/// lines and the recording, with the way to change either.
class PersonalLookingSection extends StatelessWidget {
  const PersonalLookingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final String? uid = access.uid;
    final String title = 'מה אני {מחפש|מחפשת}'.forGender(context.userGender);
    if (uid == null || !FirebaseBootstrap.isReady) {
      return _LookingBody(title: title, data: null, ready: false);
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: PrivateLookingService.doc(uid).snapshots(),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
          ) => _LookingBody(
            title: title,
            data: snapshot.hasData
                ? (snapshot.data!.data() ?? <String, dynamic>{})
                : null,
            ready: snapshot.hasData,
          ),
    );
  }
}

class _LookingBody extends StatelessWidget {
  const _LookingBody({
    required this.title,
    required this.data,
    required this.ready,
  });
  final String title;
  final Map<String, dynamic>? data;
  final bool ready;

  Future<void> _open(BuildContext context, LookingEditorStart start) =>
      openPrivateLookingEditor(
        context,
        data: data,
        start: start,
        onSaved: () => PersonalAreaService.offerUpdate(context),
      );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String text = (data?['text'] as String? ?? '').trim();
    final String? audio = data?['audioPath'] as String?;
    final bool empty = text.isEmpty && audio == null;
    final Gender? gender = context.userGender;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PersonalSectionTitle(
          title,
          trailing: empty
              ? null
              : TextButton(
                  onPressed: ready
                      ? () => _open(context, LookingEditorStart.edit)
                      : null,
                  child: const Text('עריכה'),
                ),
        ),
        if (empty)
          Text(
            'רוצה לעזור לחברים לחשוב על התאמות מדויקות יותר? {ספר|ספרי} להם מה חשוב לך.'
                .forGender(gender),
            style: theme.textTheme.bodyMedium,
          )
        else ...<Widget>[
          if (text.isNotEmpty)
            Text(
              text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          if (audio != null)
            PrivateAudioPlayer(
              key: ValueKey<String>(audio),
              path: audio,
              shareable: true,
            ),
        ],
        if (empty) ...<Widget>[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: ready
                    ? () => _open(context, LookingEditorStart.edit)
                    : null,
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('כתיבה'),
              ),
              OutlinedButton.icon(
                onPressed: ready
                    ? () => _open(context, LookingEditorStart.record)
                    : null,
                icon: const Icon(Icons.mic_none_rounded, size: 18),
                label: const Text('הקלטה'),
              ),
              TextButton.icon(
                onPressed: ready
                    ? () => _open(context, LookingEditorStart.import)
                    : null,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('ייבוא מ־WhatsApp'),
              ),
            ],
          ),
          Text(
            'כבר יש לך הקלטה ב־WhatsApp? אפשר להעביר אותה לכאן בקלות.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(lookingOwnerNotice, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ],
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

/// "החברים שלי שמשדכים בשדכן": a horizontal strip of faces with a short
/// status under each, newest friends first, requests before everybody.
class PersonalMatchmakersStrip extends StatelessWidget {
  const PersonalMatchmakersStrip({super.key});

  static const int shown = 6;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    // Hiding a friend changes the list without changing any provider.
    valueListenable: PersonalHelpersStore.revision,
    builder: (BuildContext context, _, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final ThemeData theme = Theme.of(context);
    final Set<String> hidden = PersonalHelpersStore.hidden;
    final List<MatchmakerFriend> all = matchmakerFriendsOf(access);
    final List<MatchmakerFriend> visible = MatchmakerFriends.sorted(
      all.where(
        (MatchmakerFriend f) =>
            f.canReadCard ||
            f.state == MatchmakerFriendState.requested ||
            !MatchmakerFriends.isHidden(f, hidden),
      ),
    );

    Widget body;
    if (!access.helpersLoaded && visible.isEmpty) {
      body = Text(
        'רשימת החברים תופיע לאחר החיבור לחשבון',
        style: theme.textTheme.bodyMedium,
      );
    } else if (visible.isEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'מי עוד מכיר אותך מספיק טוב כדי לחשוב {עליך|עלייך}?'.forGender(
              context.userGender,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          Wrap(
            spacing: 6,
            children: <Widget>[
              TextButton.icon(
                onPressed: () => PersonalAreaService.invite(context),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('מזמינים חבר לשדכן'),
              ),
              TextButton.icon(
                onPressed: () => PersonalHelperActions.contacts(context),
                icon: const Icon(Icons.contacts_outlined, size: 18),
                label: const Text('איתור חברים מאנשי הקשר'),
              ),
            ],
          ),
        ],
      );
    } else {
      final double scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      body = SizedBox(
        height: 112 * scale.clamp(1.0, 1.6),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: visible.length.clamp(0, shown),
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (BuildContext context, int index) =>
              _StripFace(friend: visible[index]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PersonalSectionTitle('החברים שלי שמשדכים בשדכן'),
        body,
        if (visible.isNotEmpty || access.helpersLoaded)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => context.go('/me?section=helpers'),
              child: Text(
                visible.length > shown
                    ? 'לכל ${visible.length} השדכנים'
                    : 'לכל השדכנים',
              ),
            ),
          ),
      ],
    );
  }
}

class _StripFace extends StatelessWidget {
  const _StripFace({required this.friend});
  final MatchmakerFriend friend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool requested = friend.state == MatchmakerFriendState.requested;
    final Color statusInk = requested
        ? AppColors.secondary
        : friend.canReadCard
        ? AppColors.primaryDark
        : theme.colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 84,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => MatchmakerFriendSheet.show(context, friend),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 2),
            MatchmakerFace(friend: friend, radius: 26),
            const SizedBox(height: 4),
            Text(
              friend.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.textTheme.titleMedium?.color,
              ),
            ),
            Text(
              MatchmakerFriends.stateLabel(friend),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: statusInk),
            ),
          ],
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

/// "מי רואה את הכרטיס שלי": the count said as what it means, a few faces,
/// and the way to change it.
class PersonalWhoSees extends StatelessWidget {
  const PersonalWhoSees({super.key});

  @override
  Widget build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    if (!access.ownerAccessLoaded) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final Gender? gender = context.userGender;
    final List<MatchmakerFriend> approved = MatchmakerFriends.approved(
      matchmakerFriendsOf(access),
    );
    final int count = approved.length;
    final String line = count == 0
        ? 'כרגע רק {אתה רואה|את רואה} את הכרטיס'.forGender(gender)
        : count == 1
        ? 'חבר אחד יכול לחשוב {עליך|עלייך}'.forGender(gender)
        : '$count חברים יכולים לחשוב {עליך|עלייך}'.forGender(gender);
    const double face = 16;
    final List<MatchmakerFriend> faces = approved.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PersonalSectionTitle('מי רואה את הכרטיס שלי'),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go('/me?section=approved'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: <Widget>[
                if (faces.isNotEmpty) ...<Widget>[
                  SizedBox(
                    width: face * 2 + (faces.length - 1) * face * 1.2,
                    height: face * 2,
                    child: Stack(
                      children: <Widget>[
                        for (int i = 0; i < faces.length; i++)
                          PositionedDirectional(
                            start: i * face * 1.2,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.scaffoldBackgroundColor,
                                  width: 2,
                                ),
                              ),
                              child: MatchmakerFace(
                                friend: faces[i],
                                radius: face - 2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    line,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'ניהול גישה',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One line of "מה חדש אצלי".
class _NewsLine {
  const _NewsLine({
    required this.key,
    required this.icon,
    required this.text,
    required this.onTap,
    this.action,
  });
  final String key;
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final Widget? action;
}

/// "מה חדש אצלי" — drawn only when there is something that asks the owner
/// to act: a friend who just joined, a request, a card worth refreshing, a
/// missing number. Two or three short lines; with nothing new, nothing at
/// all. Nothing about what matchmakers do with the card is ever here.
class PersonalWhatsNew extends StatelessWidget {
  const PersonalWhatsNew({super.key});

  static const int limit = 3;

  @override
  Widget build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final PersonalAreaProvider? data = maybeWatch<PersonalAreaProvider>(
      context,
    );
    final InboxProvider? inbox = maybeWatch<InboxProvider>(context);
    final List<_NewsLine> lines = <_NewsLine>[];
    for (final MatchmakerFriend f in matchmakerFriendsOf(access)) {
      if (f.state != MatchmakerFriendState.requested) continue;
      final String asked = f.row?.matchmakerGender == 'female'
          ? 'ביקשה'
          : 'ביקש';
      lines.add(
        _NewsLine(
          key: 'request:${f.uid}',
          icon: Icons.mark_email_unread_outlined,
          text: f.asksForCard
              ? '${f.name} $asked גישה לכרטיס שלך'
              : '${f.name} $asked גישה ל״מה אני מחפש/ת״',
          onTap: () => MatchmakerFriendSheet.show(context, f),
        ),
      );
    }
    if (inbox != null) {
      for (final InboxItem item in inbox.items) {
        if (item.read || item.kind != 'friendJoined') continue;
        lines.add(
          _NewsLine(
            key: 'inbox:${item.id}',
            icon: Icons.waving_hand_outlined,
            text: item.title,
            onTap: () {
              unawaited(inbox.markRead(item));
              context.go(
                item.route.isEmpty ? '/me?section=helpers' : item.route,
              );
            },
          ),
        );
      }
    }
    final Person? card = cards.card;
    if (cards.hasCard && card != null && data != null) {
      DateTime last = data.date('reviewedAt') ?? card.updatedAt;
      DateTime edited = card.updatedAt;
      final DateTime? remote = data.date('editedAt');
      if (remote != null && remote.isAfter(edited)) edited = remote;
      if (edited.isAfter(last)) last = edited;
      if (PersonalAreaProvider.reviewDue(last)) {
        lines.add(
          _NewsLine(
            key: 'review',
            icon: Icons.auto_awesome_outlined,
            text: 'הגיע הזמן לרענן את הכרטיס — הכול עדיין רלוונטי?',
            onTap: () => PersonalAreaService.editCard(context),
            action: TextButton(
              onPressed: () async {
                try {
                  await PersonalAreaService.call('confirmPersonalCardCurrent');
                } catch (_) {
                  if (context.mounted) {
                    AppNotice.show(context, 'האישור לא נשמר. כדאי לנסות שוב.');
                  }
                }
              },
              child: const Text('הכול מעודכן'),
            ),
          ),
        );
      }
    }
    if (profile.myPhone == null && !cards.isDeleted) {
      lines.add(
        _NewsLine(
          key: 'phone',
          icon: Icons.phone_outlined,
          text: 'הוספת המספר שלי — בלעדיו חברים שמשדכים לא ימצאו את הכרטיס',
          onTap: () async {
            final String? phone = await MyPhoneDialog.show(context);
            if (phone != null) await profile.setMyPhone(phone);
          },
        ),
      );
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The gap above lives here, so an empty section leaves none behind.
        const SizedBox(height: 18),
        const PersonalSectionTitle('מה חדש אצלי'),
        for (final _NewsLine line in lines.take(limit))
          InkWell(
            key: ValueKey<String>(line.key),
            borderRadius: BorderRadius.circular(10),
            onTap: line.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: <Widget>[
                  Icon(line.icon, size: 18, color: AppColors.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(line.text, style: theme.textTheme.bodyMedium),
                  ),
                  ?line.action,
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The community, small: how many singles keep a card here, and one true
/// figure turning over beside it. Only numbers the server counted; never
/// anybody's identity.
class PersonalCommunityLine extends StatefulWidget {
  const PersonalCommunityLine({super.key});

  @override
  State<PersonalCommunityLine> createState() => _PersonalCommunityLineState();
}

class _PersonalCommunityLineState extends State<PersonalCommunityLine> {
  Timer? _timer;
  int _index = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The month key the server writes beside its monthly figure.
  static String monthKey([DateTime? at]) {
    final DateTime now = at ?? DateTime.now();
    return 'M${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// The rotating lines: only figures that belong to the current period and
  /// are above zero.
  static List<String> linesFor(Map<String, dynamic> stats) {
    final List<String> out = <String>[];
    void add(String key, String Function(num) text) {
      final Object? value = stats[key];
      if (value is num && value > 0) out.add(text(value));
    }

    if (stats['monthKey'] == monthKey()) {
      add(
        'newSinglesMonth',
        (num v) => v == 1 ? 'אחד הצטרף החודש' : '$v הצטרפו החודש',
      );
    }
    if (stats['weekKey'] == CommunityPeriods.weekKey()) {
      add(
        'newSinglesWeek',
        (num v) => v == 1 ? 'אחד הצטרף השבוע' : '$v הצטרפו השבוע',
      );
      add('newMatchmakersWeek', (num v) => '$v שדכנים חדשים הצטרפו השבוע');
      add('activeMatchmakers', (num v) => '$v שדכנים פעילים השבוע');
      add('couplesWeek', (num v) => '$v זוגות התחילו לצאת השבוע');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final PersonalAreaProvider? data = maybeWatch<PersonalAreaProvider>(
      context,
    );
    final Object? singles = data?.stats['singles'];
    if (singles is! num || singles <= 0) {
      _timer?.cancel();
      _timer = null;
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final List<String> lines = linesFor(data!.stats);
    final bool animate =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    if (lines.length > 1 && animate) {
      _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) setState(() => _index++);
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
    final String? current = lines.isEmpty ? null : lines[_index % lines.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.favorite_border_rounded,
              size: 18,
              color: AppColors.femaleAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$singles רווקים ורווקות מנהלים כרטיס אישי בשדכן',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        if (current != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 26, top: 2),
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: animate ? 300 : 0),
              child: Text(
                current,
                key: ValueKey<String>(current),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Builder(
            builder: (BuildContext anchor) => TextButton.icon(
              onPressed: () async {
                try {
                  await PersonalAreaService.invite(anchor);
                } on Object {
                  // Nothing to share to is not worth a message.
                }
              },
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('לשתף עם חבר'),
            ),
          ),
        ),
      ],
    );
  }
}
