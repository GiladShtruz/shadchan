import 'package:shadchan/services/couple_workspace_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/private_looking_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/services/invite_link_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_announce_switch.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// The card owner's side of access, on the personal area: status reports to
/// answer, requests waiting, who can see the card, friends who could, and
/// anybody the card is hidden from ("מוסתרים" — stored as `blocked`).
///
/// Nothing here shows the matchmakers' own work — not their ideas, notes,
/// shares or views. The owner sees their card and who may read it; that is
/// all.
class CardAccessSections extends StatefulWidget {
  const CardAccessSections({
    super.key,
    required this.hasCard,
    this.requestsKey,
    this.management = false,
  });

  final bool hasCard;
  final bool management;

  /// Put on the "בקשות גישה" group, so a notice about a request can open the
  /// page right on it.
  final Key? requestsKey;

  @override
  State<CardAccessSections> createState() => _CardAccessSectionsState();
}

class _CardAccessSectionsState extends State<CardAccessSections> {
  ContactsPermissionState? _permission;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndScan());
  }

  Future<void> _checkAndScan() async {
    ContactsPermissionState state;
    try {
      state = await ContactHashUpload.permission();
    } catch (_) {
      state = ContactsPermissionState.denied;
    }
    if (!mounted) {
      return;
    }
    setState(() => _permission = state);
    if (state == ContactsPermissionState.granted && widget.hasCard) {
      await _scan();
    }
  }

  Future<void> _scan({bool force = false}) async {
    if (_scanning) {
      return;
    }
    setState(() => _scanning = true);
    await ContactHashUpload.run(force: force);
    if (mounted) {
      setState(() => _scanning = false);
    }
  }

  /// Contacts are needed only for this: finding friends who match, and
  /// letting the server check that a request comes from a friend.
  Future<void> _askForContacts() async {
    if (_permission == ContactsPermissionState.permanentlyDenied) {
      await ContactsImportService.openSettings();
      return;
    }
    final ContactsPermissionState state =
        await ContactsImportService.requestPermission();
    if (!mounted) {
      return;
    }
    setState(() => _permission = state);
    if (state == ContactsPermissionState.granted) {
      await _scan(force: true);
    }
  }

  void _failed() {
    AppNotice.show(context, 'לא הצלחנו לעדכן כרגע. אפשר לנסות שוב.');
  }

  /// The owner's own number, asked for once if it is missing. Every grant
  /// carries it: it is how the matchmaker's app finds the friend already in
  /// their database — and the number WhatsApp opens — so a grant without it
  /// would add the friend a second time.
  Future<bool> _ensureMyPhone() async {
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    if (profile.myPhone != null) {
      return true;
    }
    final String? phone = await MyPhoneDialog.show(context);
    if (phone == null || !mounted) {
      return false;
    }
    await profile.setMyPhone(phone);
    return true;
  }

  Future<({bool card, bool looking})?> _permissions({
    CardAccess? row,
    String? recipientName,
  }) async {
    final access = context.read<CardAccessProvider>();
    var hasLooking = false;
    try {
      final data = (await PrivateLookingService.doc(
        access.uid!,
      ).get(const GetOptions(source: Source.server))).data();
      hasLooking =
          (data?['text'] as String? ?? '').trim().isNotEmpty ||
          data?['audioPath'] != null;
    } catch (_) {
      if (mounted) {
        AppNotice.show(context, 'לא ניתן לטעון הרשאות כרגע. אפשר לנסות שוב.');
      }
      return null;
    }
    if (!mounted) return null;
    var card = row == null || row.status != CardAccessStatus.approved
        ? true
        : row.canReadCard;
    var looking = row?.canReadLooking ?? false;
    return showDialog<({bool card, bool looking})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('לתת הרשאה'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (row != null || recipientName != null)
                Text(recipientName ?? row!.matchmakerName),
              if ((row?.granteeUids.length ?? 0) == 2)
                const Text('האישור ניתן לשני בני הזוג במאגר המשותף'),
              CheckboxListTile(
                title: const Text('גישה לכרטיס'),
                value: card,
                onChanged: (v) => setState(() => card = v!),
              ),
              if (hasLooking || looking)
                CheckboxListTile(
                  title: const Text('גישה ל׳מה אני מחפש/ת׳ – לעיני השדכן בלבד'),
                  value: looking,
                  onChanged: (v) => setState(() => looking = v!),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (card: card, looking: looking)),
              child: const Text('שמירה'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPermissions(
    CardAccessProvider access,
    CardAccess row,
  ) async {
    final choice = await _permissions(row: row);
    if (choice == null) return;
    final ok = await access.setPermissions(
      row,
      card: choice.card,
      looking: choice.looking,
    );
    if (!ok && mounted) _failed();
  }

  Set<String> get _hiddenHelpers =>
      (Hive.box<dynamic>('settings').get('personalCard.hiddenHelpers') as List?)
          ?.whereType<String>()
          .toSet() ??
      <String>{};
  void _hideHelper(String uid, bool hidden) {
    final values = _hiddenHelpers;
    hidden ? values.add(uid) : values.remove(uid);
    Hive.box<dynamic>(
      'settings',
    ).put('personalCard.hiddenHelpers', values.toList());
    setState(() {});
  }

  void _openManagement() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('ניהול ופרטיות')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CardAccessSections(hasCard: widget.hasCard, management: true),
          ],
        ),
      ),
    ),
  );

  Future<void> _setStatus(
    CardAccessProvider access,
    CardAccess row,
    CardAccessStatus status,
  ) async {
    if (status == CardAccessStatus.declined &&
        row.status == CardAccessStatus.approved &&
        (row.lookingRequested || row.cardRequested)) {
      final ok = await access.setPermissions(
        row,
        card: row.canReadCard,
        looking: row.canReadLooking,
      );
      if (!ok && mounted) _failed();
      return;
    }
    if (status == CardAccessStatus.approved && !await _ensureMyPhone()) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (!mounted) return;
    final choice = status == CardAccessStatus.approved
        ? await _permissions(row: row)
        : null;
    if (!mounted || (status == CardAccessStatus.approved && choice == null)) {
      return;
    }
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final bool ok = await access.setStatus(
      row,
      choice != null && !choice.card && !choice.looking
          ? CardAccessStatus.revoked
          : status,
      cardGranted: choice?.card ?? false,
      lookingGranted: choice?.looking ?? false,
      ownerName: profile.fullName,
      ownerPhoneHash: PhoneIdentity.hash(profile.myPhone),
      ownerPhone: profile.myPhone,
    );
    if (!ok && mounted) {
      _failed();
    }
  }

  /// The matchmaker's gender as the row carries it; null when it does not.
  static Gender? _genderOf(CardAccess row) => switch (row.matchmakerGender) {
    'male' => Gender.male,
    'female' => Gender.female,
    _ => null,
  };

  /// "הסתר": never at once — a dialog says what it means first.
  ///
  /// Stored as the same `blocked` row it always was; what changed is the word
  /// and what the matchmaker sees — the card looks like no card at all to them
  /// (see `CardInviteFlow.cardVisible`), and no request can be sent.
  Future<void> _confirmBlock(CardAccessProvider access, CardAccess row) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          GenderText.resolveOrBoth(
            'להסתיר את הכרטיס {מהשדכן הזה|מהשדכנית הזו}?',
            _genderOf(row),
          ),
        ),
        content: Text(
          GenderText.resolveOrBoth(
            'מבחינת ${access.nameInContacts(row.matchmakerUid, row.matchmakerName)} '
            'ייראה כאילו אין לך כרטיס זמין ב׳שדכן׳. {אם ירצה|אם תרצה} '
            'להוסיף אותך למאגר {שלו|שלה} או לקבל פרטים, {הוא יצטרך|היא '
            'תצטרך} לפנות אליך אישית ב־WhatsApp.',
            _genderOf(row),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('הסתר'),
          ),
        ],
      ),
    );
    if (sure == true && mounted) {
      await _setStatus(access, row, CardAccessStatus.blocked);
    }
  }

  Future<void> _grant(CardAccessProvider access, CardHelper helper) async {
    if (!await _ensureMyPhone() || !mounted) {
      return;
    }
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final recipient = await CoupleWorkspaceService.call('resolveMatchmaker', {
      'uid': helper.uid,
    });
    final choice = await _permissions(
      recipientName:
          '${recipient['name']}${(recipient['members'] as List).length == 2 ? ' — האישור ניתן לשני בני הזוג' : ''}',
    );
    if (choice == null || (!choice.card && !choice.looking)) return;
    final bool ok = await access.grant(
      helper,
      cardGranted: choice.card,
      lookingGranted: choice.looking,
      expectedRecipient: recipient,
      ownerName: profile.fullName ?? '',
      ownerPhoneHash: PhoneIdentity.hash(profile.myPhone),
      ownerPhone: profile.myPhone,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      if (InviteLinkService.pending?.fromUid == helper.uid) {
        InviteLinkService.clear();
      }
      AppNotice.show(
        context,
        'הגישה לכרטיס שלך ניתנה ל${access.nameInContacts(helper.uid, helper.name)}',
      );
    } else {
      _failed();
    }
  }

  Widget _busyOr(bool busy, Widget child) {
    if (!busy) {
      return child;
    }
    return const SizedBox.square(
      dimension: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final Gender? gender = context.userGender;
    final List<CardAccess> pending = access.pendingRequests;
    final List<CardAccess> approved = access.approved;
    final List<CardAccess> blocked = access.blocked;
    final List<CardHelper> helpers = access.helpers;
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    final bool acceptsRequests = cards.acceptsRequests;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.hasCard)
          ValueListenableBuilder<int>(
            valueListenable: InviteLinkService.revision,
            builder: (context, _, _) {
              final invite = InviteLinkService.pending;
              if (invite == null || invite.fromUid == access.uid) {
                return const SizedBox.shrink();
              }
              return SettingsGroup(
                title: 'הזמנה שקיבלתי',
                children: [
                  SettingsRow(
                    icon: Icons.person_add_outlined,
                    title: invite.name,
                    trailing: TextButton(
                      onPressed: () async {
                        await _grant(
                          access,
                          CardHelper(uid: invite.fromUid, name: invite.name),
                        );
                      },
                      child: const Text('בחירת הרשאות'),
                    ),
                  ),
                ],
              );
            },
          ),
        SettingsGroup(
          title:
              'מי רואה את הכרטיס שלי · ${approved.where((r) => r.canReadCard).length}',
          children: <Widget>[
            if (!widget.management)
              TextButton(
                onPressed: _openManagement,
                child: const Text('לכל השדכנים וניהול הרשאות'),
              ),
            if (approved.isEmpty)
              SettingsRow(
                icon: Icons.lock_outline_rounded,
                title: 'רק {אתה|את}'.forGender(gender),
              )
            else
              for (final CardAccess row
                  in (widget.management ? approved : approved.take(3)))
                _AccessRow(
                  name: access.nameInContacts(
                    row.matchmakerUid,
                    row.matchmakerName,
                  ),
                  permissionsLabel:
                      'כרטיס ${row.canReadCard ? '✓' : '—'} | מה אני מחפש ${row.canReadLooking ? '✓' : '—'}',
                  busy: access.isBusy('access:${row.id}'),
                  menu: <String, VoidCallback>{
                    'שינוי הרשאות': () => _editPermissions(access, row),
                    'הסרת גישה': () =>
                        _setStatus(access, row, CardAccessStatus.revoked),
                    'הסתר': () => _confirmBlock(access, row),
                  },
                ),
          ],
        ),
        if (widget.management || pending.isNotEmpty)
          SettingsGroup(
            key: widget.requestsKey,
            title: 'בקשות גישה',
            children: <Widget>[
              // Whether matchmaker friends are told the card exists at all.
              if (widget.management) const CardAnnounceSwitch(framed: false),
              // One switch for every matchmaker. Off, nobody can ask and the
              // card looks like no card to all of them; giving a friend access
              // from "החברים שלי שמשדכים בשדכן" still works.
              if (widget.management)
                SettingsRow(
                  icon: acceptsRequests
                      ? Icons.mark_email_unread_outlined
                      : Icons.do_not_disturb_on_outlined,
                  title: 'שדכנים יכולים לבקש גישה לכרטיס',
                  subtitle: acceptsRequests
                      ? null
                      : 'כבוי: אף שדכן או שדכנית לא יכולים לשלוח בקשה, ולא יראו '
                                'שיש לך כרטיס. '
                                '{אתה יכול|את יכולה} לתת גישה לחברים בעצמך.'
                            .forGender(gender),
                  trailing: Switch(
                    value: acceptsRequests,
                    onChanged: (bool value) => cards.setAcceptsRequests(value),
                  ),
                ),
              if (widget.management && pending.isEmpty && acceptsRequests)
                const SettingsRow(
                  icon: Icons.inbox_outlined,
                  title: 'אין בקשות חדשות',
                )
              else
                for (final CardAccess row in pending)
                  _AccessRow(
                    name: access.nameInContacts(
                      row.matchmakerUid,
                      row.matchmakerName,
                    ),
                    busy: access.isBusy('access:${row.id}'),
                    menu: <String, VoidCallback>{
                      'הסתר': () => _confirmBlock(access, row),
                    },
                    actions: <Widget>[
                      FilledButton(
                        onPressed: () =>
                            _setStatus(access, row, CardAccessStatus.approved),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('לאשר'),
                      ),
                      TextButton(
                        onPressed: () =>
                            _setStatus(access, row, CardAccessStatus.declined),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('לא עכשיו'),
                      ),
                    ],
                  ),
            ],
          ),
        if (widget.hasCard)
          SettingsGroup(
            title: 'החברים שלי שמשדכים בשדכן',
            children: <Widget>[
              if (_permission == null)
                const SizedBox.shrink()
              else if (_permission != ContactsPermissionState.granted)
                SettingsRow(
                  icon: Icons.contacts_outlined,
                  title: 'גישה לאנשי הקשר',
                  subtitle:
                      'כדי למצוא חברים שמשדכים בשדכן, ולוודא שרק חברים שלך '
                      'יכולים לבקש גישה לכרטיס. נשלחים רק מספרים מוצפנים, '
                      'בלי שמות.',
                  trailing: FilledButton(
                    onPressed: _askForContacts,
                    child: Text(
                      _permission == ContactsPermissionState.permanentlyDenied
                          ? 'להגדרות'
                          : 'אישור',
                    ),
                  ),
                )
              else if (_scanning || !access.helpersLoaded)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (helpers.isEmpty)
                const SettingsRow(
                  icon: Icons.diversity_3_outlined,
                  title: 'עוד לא מצאנו חברים שלך בשדכן',
                )
              else
                for (final CardHelper helper
                    in (widget.management
                        ? helpers
                        : helpers
                              .where((h) => !_hiddenHelpers.contains(h.uid))
                              .take(3)))
                  Column(
                    children: [
                      _HelperRow(
                        name: access.nameInContacts(helper.uid, helper.name),
                        busy: access.isBusy('helper:${helper.uid}'),
                        onGrant: () => _grant(access, helper),
                      ),
                      TextButton(
                        onPressed: () => _hideHelper(
                          helper.uid,
                          !_hiddenHelpers.contains(helper.uid),
                        ),
                        child: Text(
                          _hiddenHelpers.contains(helper.uid)
                              ? 'החזרה לרשימה'
                              : 'הסתר מהרשימה',
                        ),
                      ),
                    ],
                  ),
              if (!widget.management)
                TextButton(
                  onPressed: _openManagement,
                  child: const Text('הצג עוד'),
                ),
            ],
          ),
        if (!widget.management)
          TextButton.icon(
            onPressed: _openManagement,
            icon: const Icon(Icons.tune),
            label: const Text('ניהול ופרטיות'),
          ),
        if (widget.management && blocked.isNotEmpty)
          SettingsGroup(
            title: 'מוסתרים',
            children: <Widget>[
              for (final CardAccess row in blocked)
                SettingsRow(
                  icon: Icons.visibility_off_outlined,
                  title: access.nameInContacts(
                    row.matchmakerUid,
                    row.matchmakerName,
                  ),
                  trailing: _busyOr(
                    access.isBusy('access:${row.id}'),
                    TextButton(
                      onPressed: () async {
                        if (!await access.unblock(row) && mounted) {
                          _failed();
                        }
                      },
                      child: const Text('ביטול הסתרה'),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// A friend who matchmakes in the app: their full name, and the one thing to
/// do about it. Nothing else — the heading above already says who they are.
class _HelperRow extends StatelessWidget {
  const _HelperRow({
    required this.name,
    required this.busy,
    required this.onGrant,
  });

  final String name;
  final bool busy;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              name.trim().isEmpty ? 'ללא שם' : name.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: dark ? AppColors.headingInkDm : AppColors.headingInk,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (busy)
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton.tonal(
              onPressed: onGrant,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('לתת גישה'),
            ),
        ],
      ),
    );
  }
}

/// One matchmaker on the owner's lists: an initial, their name, and what can
/// be done about them — the main answers as buttons under the name, anything
/// rarer (blocking) behind the menu. No sentence explaining the row: the
/// heading above it already says what the list is.
class _AccessRow extends StatelessWidget {
  const _AccessRow({
    required this.name,
    required this.busy,
    this.permissionsLabel,
    this.actions = const <Widget>[],
    this.menu = const <String, VoidCallback>{},
  });

  final String name;
  final String? permissionsLabel;
  final bool busy;
  final List<Widget> actions;
  final Map<String, VoidCallback> menu;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final String shown = name.trim().isEmpty ? 'ללא שם' : name.trim();
    final Color ink = dark ? AppColors.headingInkDm : AppColors.headingInk;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 17,
                backgroundColor: ink.withValues(alpha: 0.10),
                child: Text(
                  shown.characters.first,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shown,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    if (permissionsLabel != null)
                      Text(permissionsLabel!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (menu.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'פעולות',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (String label) => menu[label]?.call(),
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    for (final String label in menu.keys)
                      PopupMenuItem<String>(value: label, child: Text(label)),
                  ],
                ),
            ],
          ),
          if (actions.isNotEmpty && !busy)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 44, top: 2),
              child: Wrap(spacing: 8, runSpacing: 4, children: actions),
            ),
        ],
      ),
    );
  }
}
