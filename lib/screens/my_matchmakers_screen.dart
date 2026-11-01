import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shadchan/services/personal_helpers_store.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_access_sections.dart';
import 'package:shadchan/widgets/home_section.dart';

abstract final class PersonalHelperActions {
  static const hiddenKey = PersonalHelpersStore.key;
  static Set<String> get hidden => PersonalHelpersStore.hidden;
  static void hide(String uid, bool value) =>
      PersonalHelpersStore.hide(uid, value);
  static Future<void> grant(BuildContext context, CardHelper helper) async {
    final cards = context.read<PersonalCardProvider>();
    if (!cards.hasCard) {
      AppNotice.show(context, 'יש להשלים כרטיס פעיל לפני מתן גישה');
      return;
    }
    final access = context.read<CardAccessProvider>();
    final profile = context.read<UserProfileProvider>();
    if (profile.myPhone == null) {
      final phone = await MyPhoneDialog.show(context);
      if (phone == null || !context.mounted) return;
      await profile.setMyPhone(phone);
    }
    if (!context.mounted) return;
    final ok = await access.grant(
      helper,
      ownerName: profile.fullName ?? '',
      ownerPhoneHash: PhoneIdentity.hash(profile.myPhone),
      ownerPhone: profile.myPhone,
      cardGranted: true,
      lookingGranted: access.approved.any(
        (row) =>
            row.matchmakerUid == (helper.recipientUid ?? helper.uid) &&
            row.canReadLooking,
      ),
      expectedRecipient: {
        'uid': helper.recipientUid ?? helper.uid,
        'members': helper.granteeUids.isEmpty
            ? [helper.uid]
            : helper.granteeUids,
      },
    );
    if (context.mounted) {
      AppNotice.show(
        context,
        ok ? 'הגישה לכרטיס ניתנה ❤️' : 'הגישה לא נשמרה. כדאי לרענן ולנסות שוב.',
      );
    }
  }

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

class MyMatchmakersScreen extends StatelessWidget {
  const MyMatchmakersScreen({super.key, this.approved = false, this.friendUid});
  final bool approved;
  final String? friendUid;
  @override
  Widget build(BuildContext context) {
    final access = context.watch<CardAccessProvider>();
    final cards = context.watch<PersonalCardProvider>();
    final granted = access.approved.where((a) => a.canReadCard).toList();
    final helpers =
        access.helpers
            .where((h) => !PersonalHelperActions.hidden.contains(h.uid))
            .toList()
          ..sort(
            (a, b) => a.uid == friendUid
                ? -1
                : b.uid == friendUid
                ? 1
                : a.name.compareTo(b.name),
          );
    return DefaultTabController(
      key: ValueKey(approved),
      length: 2,
      initialIndex: approved ? 1 : 0,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ככל {שתיתן|שתיתני} גישה ליותר חברים שמכירים אותך, כך יהיו יותר אנשים שיוכלו לחשוב {עליך|עלייך} ❤️'
                      .forGender(context.userGender),
                ),
                const SizedBox(height: 10),
                const Text('🔒 הכרטיס שלך גלוי רק לחברים שאישרת להם גישה.'),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => _hidden(context, access),
                      child: const Text('חברים מוסתרים'),
                    ),
                    TextButton(
                      onPressed: () => _privacy(context, cards.hasCard),
                      child: const Text('הרשאות ותוכן לשדכנים'),
                    ),
                    TextButton(
                      onPressed: () => _invitations(context, access.uid),
                      child: const Text('הזמנות אישיות'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'חברים שאפשר לאשר'),
              Tab(text: 'חברים שאישרתי'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final row in access.pendingRequests)
                      HomePaperCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('${row.matchmakerName} ביקשו גישה'),
                            if (row.granteeUids.length == 2)
                              const Text('הבקשה מתייחסת לשני בני הזוג'),
                            if (row.lookingRequested)
                              TextButton(
                                onPressed: () =>
                                    _privacy(context, cards.hasCard),
                                child: const Text('בחירת הרשאות למידע הפרטי'),
                              ),
                            if (row.status == CardAccessStatus.pending ||
                                row.cardRequested)
                              FilledButton(
                                onPressed: access.isBusy('access:${row.id}')
                                    ? null
                                    : () async {
                                        final ok = await access.setStatus(
                                          row,
                                          CardAccessStatus.approved,
                                          cardGranted: true,
                                          lookingGranted: row.canReadLooking,
                                        );
                                        if (!ok && context.mounted) {
                                          AppNotice.show(
                                            context,
                                            'האישור לא נשמר',
                                          );
                                        }
                                      },
                                child: const Text('לתת גישה לכרטיס'),
                              ),
                            TextButton(
                              onPressed: () => access.setPermissions(
                                row,
                                card: row.canReadCard,
                                looking: row.canReadLooking,
                              ),
                              child: const Text('לא עכשיו'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (helpers.isEmpty)
                      const Text('מי עוד מכיר אותך מספיק טוב כדי לחשוב עליך?'),
                    for (final helper in helpers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PersonalHelperCard(helper: helper),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => PersonalHelperActions.contacts(context),
                      icon: const Icon(Icons.contacts_outlined),
                      label: const Text('איתור חברים בקשר הדדי'),
                    ),
                    FilledButton(
                      onPressed: () => PersonalAreaService.invite(context),
                      child: const Text('מזמינים חבר לשדכן'),
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (granted.isEmpty)
                      const Text(
                        'עדיין לא נתת גישה לחברים. אפשר להתחיל בחבר שמכיר אותך היטב.',
                      ),
                    for (final row in granted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _GrantedCard(row: row),
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
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('הרשאות ופרטיות')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                CardAccessSections(hasCard: hasCard, management: true),
              ],
            ),
          ),
        ),
      );
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

class _HiddenHelpers extends StatefulWidget {
  const _HiddenHelpers({required this.access});
  final CardAccessProvider access;
  @override
  State<_HiddenHelpers> createState() => _HiddenHelpersState();
}

class _HiddenHelpersState extends State<_HiddenHelpers> {
  @override
  Widget build(BuildContext context) {
    final hidden = widget.access.helpers
        .where((h) => PersonalHelperActions.hidden.contains(h.uid))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hidden.isEmpty) const Text('אין חברים מוסתרים'),
        for (final helper in hidden)
          ListTile(
            title: Text(helper.name),
            trailing: TextButton(
              onPressed: () =>
                  setState(() => PersonalHelperActions.hide(helper.uid, false)),
              child: const Text('ביטול הסתרה'),
            ),
          ),
      ],
    );
  }
}

class PersonalHelperCard extends StatelessWidget {
  const PersonalHelperCard({
    super.key,
    required this.helper,
    this.compact = false,
  });
  final CardHelper helper;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final access = context.watch<CardAccessProvider>();
    final photo = helper.photoUrl?.trim();
    final hasPhoto = photo != null && photo.isNotEmpty;
    return HomePaperCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundImage: hasPhoto ? NetworkImage(photo) : null,
                child: !hasPhoto ? const Icon(Icons.person_outline) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  helper.granteeUids.length == 2
                      ? helper.name
                      : access.nameInContacts(helper.uid, helper.name),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (helper.granteeUids.length == 2)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('הגישה ניתנת לשני בני הזוג'),
            ),
          if (!compact) ...[
            const SizedBox(height: 10),
            Text(
              helper.databaseCount == null
                  ? 'גודל המאגר טרם פורסם'
                  : '${helper.databaseCount} חברים במאגר',
            ),
            Text(
              helper.lastActiveAt == null
                  ? 'מועד הפעילות אינו זמין'
                  : 'פעילות אחרונה: ${AppDateUtils.timeAgoShort(helper.lastActiveAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: access.isBusy('helper:${helper.uid}')
                ? null
                : () => PersonalHelperActions.grant(context, helper),
            child: const Text('לתת גישה'),
          ),
          TextButton(
            onPressed: () => PersonalHelperActions.hide(helper.uid, true),
            child: const Text('הסתרה'),
          ),
        ],
      ),
    );
  }
}

class _GrantedCard extends StatelessWidget {
  const _GrantedCard({required this.row});
  final CardAccess row;
  @override
  Widget build(BuildContext context) {
    final access = context.watch<CardAccessProvider>();
    Widget card(Map<String, dynamic> data) => HomePaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundImage:
                  data['hidden'] == false &&
                      data['photoUrl'] is String &&
                      (data['photoUrl'] as String).trim().isNotEmpty
                  ? NetworkImage(data['photoUrl'] as String)
                  : null,
              child:
                  data['hidden'] == false &&
                      data['photoUrl'] is String &&
                      (data['photoUrl'] as String).trim().isNotEmpty
                  ? null
                  : const Icon(Icons.person_outline),
            ),
            title: Text(row.matchmakerName),
            subtitle: row.invited ? const Text('הזמנה אישית') : null,
          ),
          Text(
            data['databaseCount'] is num
                ? '${data['databaseCount']} חברים במאגר'
                : 'גודל המאגר טרם פורסם',
          ),
          Text(
            data['lastActiveAt'] is Timestamp
                ? 'פעילות אחרונה: ${AppDateUtils.timeAgoShort((data['lastActiveAt'] as Timestamp).toDate())}'
                : 'מועד הפעילות אינו זמין',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(
            onPressed: access.isBusy('access:${row.id}')
                ? null
                : () async {
                    final ok = await access.setStatus(
                      row,
                      CardAccessStatus.revoked,
                    );
                    if (context.mounted) {
                      AppNotice.show(
                        context,
                        ok
                            ? 'הגישה לכרטיס ולמידע הפרטי בוטלה'
                            : 'ביטול הגישה לא נשמר. יש לנסות שוב.',
                      );
                    }
                  },
            child: const Text('ביטול גישה'),
          ),
        ],
      ),
    );
    if (!FirebaseBootstrap.isReady) return card({});
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .doc('matchmakerActivity/${row.matchmakerUid}')
          .snapshots(),
      builder: (_, snap) =>
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .doc('communityMembers/${row.matchmakerUid}')
                .snapshots(),
            builder: (_, photo) => card({
              ...snap.data?.data() ?? <String, dynamic>{},
              'photoUrl': photo.data?.data()?['photoUrl'],
              'hidden': photo.data?.data()?['hidden'],
            }),
          ),
    );
  }
}
