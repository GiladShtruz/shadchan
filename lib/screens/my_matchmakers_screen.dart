import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shadchan/services/personal_helpers_store.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/dialogs/access_permissions_dialog.dart';
import 'package:shadchan/screens/personal_privacy_screen.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/widgets/personal_home_sections.dart';

abstract final class PersonalHelperActions {
  static const hiddenKey = PersonalHelpersStore.key;
  static Set<String> get hidden => PersonalHelpersStore.hidden;
  static void hide(String uid, bool value) =>
      PersonalHelpersStore.hide(uid, value);
  static Future<void> contacts(BuildContext context) async {
    var permission = await ContactsImportService.checkPermission();
    if (permission == ContactsPermissionState.permanentlyDenied) {
      await ContactsImportService.openSettings();
      return;
    }
    if (permission != ContactsPermissionState.granted) {
      permission = await ContactsImportService.requestPermission();
    }
    if (permission == ContactsPermissionState.granted) {
      await ContactHashUpload.run(force: true);
    }
    if (context.mounted && permission != ContactsPermissionState.granted) {
      AppNotice.show(
        context,
        'אפשר להזמין חבר באופן אישי גם בלי גישה לאנשי הקשר',
      );
    }
  }
}

/// "השדכנים שלי": every friend from the owner's contacts who matchmakes
/// here, in two tabs — "אישרתי גישה" and "אפשר לתת גישה" — as compact rows,
/// so several fit on a screen and the owner can move between them quickly.
///
/// A request jumps to the head of "אפשר לתת גישה" with "ביקש גישה" on it,
/// so it is never lost under a long list. Hiding a friend only tidies the
/// list: it blocks nothing and changes no permission.
class MyMatchmakersScreen extends StatelessWidget {
  const MyMatchmakersScreen({super.key, this.approved = false, this.friendUid});
  final bool approved;
  final String? friendUid;

  @override
  Widget build(BuildContext context) {
    final access = context.watch<CardAccessProvider>();
    final cards = context.watch<PersonalCardProvider>();
    final hidden = PersonalHelpersStore.hidden;
    final friends = matchmakerFriendsOf(access);
    List<MatchmakerFriend> focused(List<MatchmakerFriend> list) {
      final i = list.indexWhere(
        (f) => f.uid == friendUid || f.helper?.uid == friendUid,
      );
      if (i <= 0) return list;
      return [list[i], ...list.take(i), ...list.skip(i + 1)];
    }

    final granted = focused(MatchmakerFriends.approved(friends));
    final grantable = focused(
      MatchmakerFriends.grantable(friends, hidden: hidden),
    );
    final hiddenCount = MatchmakerFriends.hiddenOf(friends, hidden).length;
    final theme = Theme.of(context);
    return DefaultTabController(
      key: ValueKey(approved),
      length: 2,
      initialIndex: approved ? 0 : 1,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 4, 0),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'הכרטיס שלך גלוי רק לחברים שאישרת להם גישה.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'ניהול הרשאות והזמנות',
                  icon: const Icon(Icons.tune),
                  onSelected: (value) {
                    switch (value) {
                      case 'hidden':
                        _hidden(context, access);
                      case 'privacy':
                        _privacy(context, cards.hasCard);
                      case 'invites':
                        _invitations(context, access.uid);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'hidden',
                      child: Text('חברים מוסתרים'),
                    ),
                    PopupMenuItem(
                      value: 'privacy',
                      child: Text('ניהול ופרטיות'),
                    ),
                    PopupMenuItem(
                      value: 'invites',
                      child: Text('הזמנות אישיות'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TabBar(
            tabs: [
              Tab(text: 'אישרתי גישה · ${granted.length}'),
              Tab(
                text: grantable.isEmpty
                    ? 'אפשר לתת גישה'
                    : 'אפשר לתת גישה · ${grantable.length}',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                  children: [
                    if (!access.ownerAccessLoaded)
                      const _ListNote('אישורי הגישה יופיעו לאחר החיבור לחשבון')
                    else if (granted.isEmpty)
                      const _ListNote(
                        'עדיין לא נתת גישה לחברים. אפשר להתחיל בחבר שמכיר אותך היטב.',
                      ),
                    for (final friend in granted)
                      MatchmakerFriendRow(friend: friend),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                  children: [
                    if (!access.helpersLoaded && grantable.isEmpty)
                      const _ListNote('רשימת החברים תופיע לאחר החיבור לחשבון')
                    else if (grantable.isEmpty)
                      _ListNote(
                        'מי עוד מכיר אותך מספיק טוב כדי לחשוב {עליך|עלייך}?'
                            .forGender(context.userGender),
                      ),
                    for (final friend in grantable)
                      MatchmakerFriendRow(friend: friend),
                    const SizedBox(height: 8),
                    if (hiddenCount > 0)
                      TextButton.icon(
                        onPressed: () => _hidden(context, access),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: Text('מוסתרים מהרשימה · $hiddenCount'),
                      ),
                    TextButton.icon(
                      onPressed: () => PersonalHelperActions.contacts(context),
                      icon: const Icon(Icons.contacts_outlined, size: 18),
                      label: const Text('איתור חברים מאנשי הקשר'),
                    ),
                    TextButton.icon(
                      onPressed: () => PersonalAreaService.invite(context),
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('מזמינים חבר לשדכן'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _hidden(BuildContext context, CardAccessProvider access) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('חברים מוסתרים')),
          body: _HiddenHelpers(access: access),
        ),
      ),
    );
  }

  void _privacy(BuildContext context, bool hasCard) =>
      PersonalPrivacyScreen.open(context);
  void _invitations(BuildContext context, String? uid) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('הזמנות אישיות')),
            body: uid == null
                ? const Center(child: Text('נדרש חיבור לחשבון'))
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('personalInvites')
                        .where('ownerUid', isEqualTo: uid)
                        .limit(50)
                        .snapshots(),
                    builder: (context, snapshot) => ListView(
                      children: [
                        for (final doc
                            in snapshot.data?.docs ??
                                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                          if (doc.data()['state'] == 'pending')
                            ListTile(
                              title: Text(
                                doc.data()['recipientEmail'] as String? ?? '',
                              ),
                              subtitle: const Text(
                                'ממתינה לאימייל המאומת של הנמען',
                              ),
                              trailing: TextButton(
                                onPressed: () async {
                                  try {
                                    await PersonalAreaService.call(
                                      'revokePersonalInvite',
                                      {'id': doc.id},
                                    );
                                  } catch (_) {
                                    if (context.mounted) {
                                      AppNotice.show(
                                        context,
                                        'לא ניתן לבטל כרגע',
                                      );
                                    }
                                  }
                                },
                                child: const Text('ביטול הזמנה'),
                              ),
                            ),
                      ],
                    ),
                  ),
          ),
        ),
      );
}

class _ListNote extends StatelessWidget {
  const _ListNote(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

class _HiddenHelpers extends StatelessWidget {
  const _HiddenHelpers({required this.access});
  final CardAccessProvider access;
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([access, PersonalHelpersStore.revision]),
      builder: (context, _) {
        final hidden = MatchmakerFriends.hiddenOf(
          matchmakerFriendsOf(access),
          PersonalHelpersStore.hidden,
        );
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (hidden.isEmpty) const _ListNote('אין חברים מוסתרים'),
            for (final friend in hidden)
              ListTile(
                leading: MatchmakerFace(friend: friend, radius: 20),
                title: Text(friend.name),
                trailing: TextButton(
                  onPressed: () => PersonalHelpersStore.hide(
                    MatchmakerFriends.hideKey(friend),
                    false,
                  ),
                  child: const Text('ביטול הסתרה'),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One friend, one compact row: face, full name, how big their database is
/// and how recently they were active, where the permission stands, and the
/// one action that fits.
class MatchmakerFriendRow extends StatelessWidget {
  const MatchmakerFriendRow({super.key, required this.friend});
  final MatchmakerFriend friend;

  @override
  Widget build(BuildContext context) {
    // A friend who reached the owner without the server's list (an invitation
    // link, an older grant) has no figures on the row — read them here.
    if (FirebaseBootstrap.isReady &&
        friend.databaseCount == null &&
        friend.lastActiveAt == null) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .doc('matchmakerActivity/${friend.uid}')
            .snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data();
          return _row(
            context,
            MatchmakerFriend(
              uid: friend.uid,
              name: friend.name,
              state: friend.state,
              photoUrl: friend.photoUrl,
              databaseCount: (data?['databaseCount'] as num?)?.toInt(),
              lastActiveAt: (data?['lastActiveAt'] as Timestamp?)?.toDate(),
              joinedAt: friend.joinedAt,
              row: friend.row,
              helper: friend.helper,
            ),
          );
        },
      );
    }
    return _row(context, friend);
  }

  Widget _row(BuildContext context, MatchmakerFriend f) {
    final theme = Theme.of(context);
    final access = context.watch<CardAccessProvider>();
    final busy =
        (f.row != null && access.isBusy('access:${f.row!.id}')) ||
        (f.helper != null && access.isBusy('helper:${f.helper!.uid}'));
    final requested = f.state == MatchmakerFriendState.requested;
    final details = MatchmakerFriends.detailsLine(f);
    final status = f.canReadCard
        ? MatchmakerFriends.permissionsLabel(f) +
              (f.asksForLooking ? ' · ${MatchmakerFriends.stateLabel(f)}' : '')
        : MatchmakerFriends.stateLabel(f);
    final Widget action = busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : f.canReadCard && !requested
        ? TextButton(
            onPressed: () => PersonalAccessFlow.edit(context, f),
            child: const Text('הרשאות'),
          )
        : FilledButton.tonal(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () => PersonalAccessFlow.grant(context, f),
            child: Text(requested ? 'לאשר' : 'לתת גישה'),
          );
    final hidden = MatchmakerFriends.isHidden(f, PersonalHelpersStore.hidden);
    final menu = <String, VoidCallback>{
      if (f.canReadCard)
        'שינוי הרשאות': () => PersonalAccessFlow.edit(context, f),
      if (f.canReadCard && f.row != null)
        'ביטול גישה': () => PersonalAccessFlow.revoke(context, f.row!),
      if (requested && f.row != null)
        'לא עכשיו': () => PersonalAccessFlow.decline(context, f.row!),
      if (!f.canReadCard && !requested)
        (hidden ? 'החזרה לרשימה' : 'הסתר מהרשימה'): () =>
            PersonalHelpersStore.hide(MatchmakerFriends.hideKey(f), !hidden),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => MatchmakerFriendSheet.show(context, f),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 0, 6),
        child: Row(
          children: [
            MatchmakerFace(friend: f, radius: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: requested
                          ? AppColors.secondary
                          : f.canReadCard
                          ? AppColors.primaryDark
                          : null,
                      fontWeight: requested ? FontWeight.w800 : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Large system text shrinks the button rather than the row
            // spilling past the screen.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: FittedBox(fit: BoxFit.scaleDown, child: action),
            ),
            if (menu.isNotEmpty)
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40),
                tooltip: 'עוד',
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (key) => menu[key]?.call(),
                itemBuilder: (_) => [
                  for (final key in menu.keys)
                    PopupMenuItem<String>(value: key, child: Text(key)),
                ],
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
