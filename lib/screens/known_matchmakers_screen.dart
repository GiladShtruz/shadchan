import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/matchmaker_connection.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/matchmaker_connections.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_navigation.dart';
import 'package:shadchan/utils/known_matchmakers.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The groups of "שדכנים שאני מכיר", read from the two live sources.
KnownMatchmakerGroups _groups(BuildContext context, {bool listen = true}) {
  final CardAccessProvider access = listen
      ? context.watch<CardAccessProvider>()
      : context.read<CardAccessProvider>();
  return KnownMatchmakers.build(
    me: MatchmakerConnections.uid ?? access.uid,
    helpers: access.knownHelpers,
    connections: MatchmakerConnections.connections.value,
    nameOf: (CardHelper h) => ContactHashUpload.nameFor(h.phoneHash),
  );
}

/// "שדכנים שאני מכיר" — matchmakers among this matchmaker's own contacts who
/// use the app, and the connections between them.
///
/// **Contacts are the layer of trust.** The list is the server's reading of
/// this phone's address book: nobody appears who is not already saved here,
/// except somebody this matchmaker is connected with or who asked to connect.
/// No phone number is drawn anywhere — the only number involved is the one
/// already in the matchmaker's own phone.
///
/// **Three groups, in this order:** מחוברים (who they already work with),
/// בקשות חיבור (waiting for them first, then their own), and שדכנים מאנשי
/// הקשר (everybody else, those saved in each other's phones first). Each row
/// is one compact line: face, name, last activity and database size.
class KnownMatchmakersScreen extends StatefulWidget {
  const KnownMatchmakersScreen({super.key});

  static const String route = '/known-matchmakers';
  static String profileRoute(String uid) => '$route/$uid';

  @override
  State<KnownMatchmakersScreen> createState() => _KnownMatchmakersScreenState();
}

class _KnownMatchmakersScreenState extends State<KnownMatchmakersScreen> {
  ContactsPermissionState? _permission;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    if (FirebaseBootstrap.isReady) {
      unawaited(MatchmakerConnections.start());
      unawaited(context.read<CardAccessProvider>().ensureConnected());
    }
    ContactsPermissionState state;
    try {
      state = await ContactHashUpload.permission();
    } catch (_) {
      state = ContactsPermissionState.denied;
    }
    if (!mounted) return;
    setState(() => _permission = state);
    if (state == ContactsPermissionState.granted) {
      // Never prompts: refreshes an address book this phone may already read,
      // at most once a day unless something changed.
      unawaited(ContactHashUpload.run());
    }
  }

  Future<void> _askForContacts() async {
    if (_permission == ContactsPermissionState.permanentlyDenied) {
      await ContactsImportService.openSettings();
      return;
    }
    final ContactsPermissionState state =
        await ContactsImportService.requestPermission();
    if (!mounted) return;
    setState(() => _permission = state);
    if (state == ContactsPermissionState.granted) {
      setState(() => _scanning = true);
      await ContactHashUpload.run(force: true);
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        MatchmakerConnections.connections,
        MatchmakerConnections.loaded,
        MatchmakerConnections.busy,
      ]),
      builder: (BuildContext context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final KnownMatchmakerGroups groups = _groups(context);
    final bool loading =
        !access.helpersLoaded && !MatchmakerConnections.loaded.value;
    final bool noContacts =
        _permission != null && _permission != ContactsPermissionState.granted;

    return Scaffold(
      appBar: AppBar(title: const Text('שדכנים שאני מכיר')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              'שדכנים מאנשי הקשר שלך שמשתמשים בשדכן. חיבור הוא הדדי — '
              'צד אחד מבקש והשני מאשר — ולא משתף כרטיסים או מידע מהמאגר.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (noContacts)
            _Notice(
              text:
                  'כדי למצוא שדכנים שאת/ה מכיר/ה, צריך גישה לאנשי הקשר. '
                  'רק אנשים ששמורים אצלך בטלפון יופיעו כאן.',
              action: _permission == ContactsPermissionState.permanentlyDenied
                  ? 'פתיחת הגדרות הטלפון'
                  : 'לאפשר גישה לאנשי קשר',
              onAction: _askForContacts,
            ),
          if (profile.myPhone == null)
            _Notice(
              text:
                  'כדי ששדכנים שמכירים אותך ימצאו אותך כאן, אפשר להוסיף את '
                  'המספר שלך. הוא לא מוצג לאף אחד.',
              action: 'הוספת המספר שלי',
              onAction: () async {
                final String? phone = await MyPhoneDialog.show(
                  context,
                  purpose: MyPhonePurpose.matchmaker,
                );
                if (phone != null) await profile.setMyPhone(phone);
              },
            ),
          if (_scanning || (loading && !noContacts))
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
              child: Text(
                noContacts
                    ? 'הרשימה תופיע אחרי שתאפשר/י גישה לאנשי הקשר.'
                    : 'עוד לא מצאנו שדכנים מאנשי הקשר שלך בשדכן. '
                          'כשמישהו מהם יצטרף, נעדכן אותך.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (groups.connected.isNotEmpty) ...<Widget>[
            _GroupTitle('מחוברים', groups.connected.length),
            _GroupCard(
              accent: AppColors.primaryDark,
              children: <Widget>[
                for (final KnownMatchmaker m in groups.connected)
                  KnownMatchmakerRow(matchmaker: m),
              ],
            ),
          ],
          if (groups.requests.isNotEmpty) ...<Widget>[
            _GroupTitle('בקשות חיבור', groups.requests.length),
            _GroupCard(
              accent: AppColors.secondary,
              children: <Widget>[
                for (final KnownMatchmaker m in groups.requests)
                  KnownMatchmakerRow(matchmaker: m),
              ],
            ),
          ],
          if (groups.contacts.isNotEmpty) ...<Widget>[
            _GroupTitle('שדכנים מאנשי הקשר', groups.contacts.length),
            _GroupCard(
              accent: AppColors.femaleAccent,
              children: <Widget>[
                for (final KnownMatchmaker m in groups.contacts)
                  KnownMatchmakerRow(matchmaker: m),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    required this.action,
    required this.onAction,
  });
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HomePaperCard(
        stripe: AppColors.secondary,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(text, style: theme.textTheme.bodyMedium),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: onAction, child: Text(action)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text, this.count);
  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 16, 4, 6),
      child: Text(
        '$text · $count',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.accent, required this.children});
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Color line = Theme.of(context).colorScheme.outlineVariant;
    return HomePaperCard(
      stripe: accent,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Divider(height: 1, indent: 64, endIndent: 12, color: line),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A matchmaker's face: their published photo, else an initial.
class KnownMatchmakerFace extends StatelessWidget {
  const KnownMatchmakerFace({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 22,
  });
  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String? photo = photoUrl?.trim();
    final bool hasPhoto = photo != null && photo.isNotEmpty;
    final String initial = name.trim().isEmpty
        ? ''
        : name.trim().characters.first;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.softBlue,
      foregroundImage: hasPhoto ? NetworkImage(photo) : null,
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w900,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}

/// One compact row: face, name, last activity and database size, and the
/// one thing to do about them. The whole row opens the basic profile.
class KnownMatchmakerRow extends StatelessWidget {
  const KnownMatchmakerRow({super.key, required this.matchmaker});
  final KnownMatchmaker matchmaker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KnownMatchmaker m = matchmaker;
    final String details = m.detailsLine;
    final String? state = KnownMatchmakers.stateLabel(m);
    final String name = m.name.isEmpty ? 'שדכן/ית' : m.name;
    return InkWell(
      onTap: () => AppNavigation.open(
        context,
        KnownMatchmakersScreen.profileRoute(m.uid),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
        child: Row(
          children: <Widget>[
            KnownMatchmakerFace(name: name, photoUrl: m.photoUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (details.isNotEmpty || state != null)
                    Text(
                      <String>[
                        ?state,
                        if (details.isNotEmpty) details,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _RowAction(matchmaker: m),
          ],
        ),
      ),
    );
  }
}

/// The one action a row offers: "להתחבר" to a contact, "אישור" to a request.
class _RowAction extends StatelessWidget {
  const _RowAction({required this.matchmaker});
  final KnownMatchmaker matchmaker;

  @override
  Widget build(BuildContext context) {
    final KnownMatchmaker m = matchmaker;
    if (MatchmakerConnections.isBusy(m.uid)) {
      return const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final ButtonStyle style = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 14),
    );
    switch (m.state) {
      case KnownMatchmakerState.none:
        return FilledButton.tonal(
          style: style,
          onPressed: () => KnownMatchmakerActions.connect(context, m),
          child: const Text('להתחבר'),
        );
      case KnownMatchmakerState.incoming:
        return FilledButton(
          style: style,
          onPressed: () => KnownMatchmakerActions.approve(context, m),
          child: const Text('אישור'),
        );
      case KnownMatchmakerState.connected:
        return const Icon(
          Icons.handshake_outlined,
          color: AppColors.primaryDark,
          size: 22,
        );
      case KnownMatchmakerState.outgoing:
      case KnownMatchmakerState.declined:
        return Icon(
          Icons.chevron_left_rounded,
          color: Theme.of(context).colorScheme.outline,
          textDirection: TextDirection.ltr,
        );
    }
  }
}

/// Every action on a connection, shared by the row and the profile: guarded
/// offline, and answered with a notice only when it failed or did something
/// worth saying.
abstract final class KnownMatchmakerActions {
  static String _myName(BuildContext context) =>
      context.read<UserProfileProvider>().communityDisplayName ?? '';

  static Future<void> connect(BuildContext context, KnownMatchmaker m) async {
    if (!OfflineGuard.allow(context)) return;
    if (MatchmakerConnections.uid == null) {
      await MatchmakerConnections.start();
    }
    if (!context.mounted) return;
    final bool ok = await MatchmakerConnections.request(
      otherUid: m.uid,
      myName: _myName(context),
      theirName: m.name,
    );
    if (!context.mounted) return;
    AppNotice.show(
      context,
      ok
          ? (m.state == KnownMatchmakerState.incoming
                ? 'אתם מחוברים עכשיו'
                : 'הבקשה נשלחה ל${m.name}')
          : 'לא הצלחנו לשלוח את הבקשה כרגע. אפשר לנסות שוב.',
      isError: !ok,
    );
  }

  static Future<void> approve(BuildContext context, KnownMatchmaker m) async {
    final MatchmakerConnection? c = m.connection;
    if (c == null || !OfflineGuard.allow(context)) return;
    final bool ok = await MatchmakerConnections.approve(
      c,
      myName: _myName(context),
    );
    if (!context.mounted) return;
    AppNotice.show(
      context,
      ok ? 'אתם מחוברים עכשיו' : 'לא הצלחנו לאשר כרגע. אפשר לנסות שוב.',
      isError: !ok,
    );
  }

  static Future<void> decline(BuildContext context, KnownMatchmaker m) async {
    final MatchmakerConnection? c = m.connection;
    if (c == null || !OfflineGuard.allow(context)) return;
    final bool ok = await MatchmakerConnections.decline(c);
    if (!ok && context.mounted) {
      AppNotice.show(
        context,
        'לא הצלחנו לעדכן כרגע. אפשר לנסות שוב.',
        isError: true,
      );
    }
  }

  static Future<void> withdraw(BuildContext context, KnownMatchmaker m) async {
    final MatchmakerConnection? c = m.connection;
    if (c == null || !OfflineGuard.allow(context)) return;
    final bool ok = await MatchmakerConnections.remove(c);
    if (!ok && context.mounted) {
      AppNotice.show(
        context,
        'לא הצלחנו לבטל כרגע. אפשר לנסות שוב.',
        isError: true,
      );
    }
  }

  static Future<void> disconnect(
    BuildContext context,
    KnownMatchmaker m,
  ) async {
    final MatchmakerConnection? c = m.connection;
    if (c == null || !OfflineGuard.allow(context)) return;
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: const Text('לנתק את החיבור?'),
        content: Text('החיבור עם ${m.name} יוסר. אפשר יהיה להתחבר שוב בכל עת.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('ניתוק'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final bool ok = await MatchmakerConnections.remove(c);
    if (!context.mounted) return;
    AppNotice.show(
      context,
      ok ? 'החיבור הוסר' : 'לא הצלחנו לנתק כרגע. אפשר לנסות שוב.',
      isError: !ok,
    );
  }
}

/// A matchmaker's basic profile, from "שדכנים שאני מכיר" or a notice.
///
/// **Basic on purpose.** Name, photo, last activity, how many friends are in
/// their database and — only when they show their figures in the community
/// anyway — how many of their couples went out and married. Nothing from
/// their database, and no phone number: the only way to reach them here is
/// to connect.
///
/// Opened for somebody who is neither in this phone's contacts nor part of a
/// row with this matchmaker, it says so and shows nothing about them.
class KnownMatchmakerProfileScreen extends StatefulWidget {
  const KnownMatchmakerProfileScreen({super.key, required this.uid});
  final String uid;

  @override
  State<KnownMatchmakerProfileScreen> createState() =>
      _KnownMatchmakerProfileScreenState();
}

class _KnownMatchmakerProfileScreenState
    extends State<KnownMatchmakerProfileScreen> {
  /// What the server adds to the row: activity for somebody not in the
  /// contacts, and the community figures when they are public.
  int? _databaseCount;
  DateTime? _lastActiveAt;
  String? _photoUrl;
  int? _couples;
  int? _weddings;
  bool _extrasRead = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !FirebaseBootstrap.isReady) return;
      unawaited(MatchmakerConnections.start());
      unawaited(context.read<CardAccessProvider>().ensureConnected());
    });
  }

  Future<void> _readExtras(KnownMatchmaker m) async {
    if (_extrasRead || !FirebaseBootstrap.isReady) return;
    _extrasRead = true;
    final FirebaseFirestore db = FirebaseFirestore.instance;
    if (m.lastActiveAt == null && m.databaseCount == null) {
      try {
        final Map<String, dynamic>? data =
            (await db.doc('matchmakerActivity/${m.uid}').get()).data();
        _databaseCount = (data?['databaseCount'] as num?)?.toInt();
        _lastActiveAt = (data?['lastActiveAt'] as Timestamp?)?.toDate();
      } catch (_) {
        // Not readable: the row's own figures (or none) are what is shown.
      }
    }
    try {
      final Map<String, dynamic>? member =
          (await db.doc('communityMembers/${m.communityUid ?? m.uid}').get())
              .data();
      // Public figures only: a matchmaker hidden from the board shows none.
      if (member != null && member['hidden'] == false) {
        _couples = (member['allCouples'] as num?)?.toInt();
        _weddings = (member['allEngagements'] as num?)?.toInt();
        final Object? photo = member['photoUrl'];
        if (photo is String && photo.trim().isNotEmpty) _photoUrl = photo;
      }
    } catch (_) {
      // The profile stands without them.
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        MatchmakerConnections.connections,
        MatchmakerConnections.loaded,
        MatchmakerConnections.busy,
      ]),
      builder: (BuildContext context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    KnownMatchmaker? m;
    for (final KnownMatchmaker k in _groups(context).all) {
      if (k.uid == widget.uid) m = k;
    }
    final bool settled =
        access.helpersLoaded && MatchmakerConnections.loaded.value;

    if (m == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: settled || !FirebaseBootstrap.isReady
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'השדכן/ית לא נמצא/ת באנשי הקשר שלך.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    unawaited(_readExtras(m));
    final KnownMatchmaker k = m;
    final String name = k.name.isEmpty ? 'שדכן/ית' : k.name;
    final DateTime? lastActive = k.lastActiveAt ?? _lastActiveAt;
    final int? database = k.databaseCount ?? _databaseCount;
    final String? photo = k.photoUrl ?? _photoUrl;

    return Scaffold(
      appBar: AppBar(
        actions: <Widget>[
          if (k.state == KnownMatchmakerState.connected)
            PopupMenuButton<String>(
              tooltip: 'עוד',
              onSelected: (_) => KnownMatchmakerActions.disconnect(context, k),
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'disconnect',
                      child: Text('ניתוק החיבור'),
                    ),
                  ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Center(
            child: KnownMatchmakerFace(name: name, photoUrl: photo, radius: 46),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          if (k.mutual)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'שמורים זה אצל זה באנשי הקשר',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          _Facts(
            facts: <(IconData, String)>[
              if (lastActive != null)
                (
                  Icons.schedule_rounded,
                  MatchmakerFriends.activityLabel(lastActive),
                ),
              if (database != null)
                (
                  Icons.groups_2_outlined,
                  MatchmakerFriends.databaseLabel(database),
                ),
              if ((_couples ?? 0) > 0)
                (
                  Icons.favorite_border_rounded,
                  _couples == 1
                      ? 'זוג אחד התחיל לצאת'
                      : '$_couples זוגות התחילו לצאת',
                ),
              if ((_weddings ?? 0) > 0)
                (
                  Icons.celebration_outlined,
                  _weddings == 1 ? 'חתונה אחת' : '$_weddings חתונות',
                ),
            ],
          ),
          const SizedBox(height: 20),
          _ConnectPanel(matchmaker: k),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.facts});
  final List<(IconData, String)> facts;

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return HomePaperCard(
      stripe: AppColors.primaryDark,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (IconData icon, String text) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 20, color: AppColors.primaryDark),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The main action, by where the two stand.
class _ConnectPanel extends StatelessWidget {
  const _ConnectPanel({required this.matchmaker});
  final KnownMatchmaker matchmaker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KnownMatchmaker m = matchmaker;
    final String name = m.name.isEmpty ? 'השדכן/ית' : m.name;
    final bool busy = MatchmakerConnections.isBusy(m.uid);
    final Widget note = Text(
      'החיבור לא משתף כרטיסים או מידע מהמאגר — הוא רק יוצר קשר ביניכם בתוך שדכן.',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall,
    );
    final Widget spinner = const Center(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: CircularProgressIndicator(),
      ),
    );
    final List<Widget> children;
    switch (m.state) {
      case KnownMatchmakerState.none:
        children = <Widget>[
          if (busy)
            spinner
          else
            FilledButton.icon(
              onPressed: () => KnownMatchmakerActions.connect(context, m),
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('להתחבר'),
            ),
          const SizedBox(height: 8),
          Text(
            '$name יקבל/תקבל בקשה ויוכל/תוכל לאשר.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          note,
        ];
      case KnownMatchmakerState.incoming:
        children = <Widget>[
          Text(
            '$name מבקש/ת להתחבר אליך',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (busy)
            spinner
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: () => KnownMatchmakerActions.approve(context, m),
                    child: const Text('אישור החיבור'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => KnownMatchmakerActions.decline(context, m),
                    child: const Text('לא עכשיו'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          note,
        ];
      case KnownMatchmakerState.outgoing:
        children = <Widget>[
          Text(
            'הבקשה נשלחה · ממתינה לאישור',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (busy)
            spinner
          else
            TextButton(
              onPressed: () => KnownMatchmakerActions.withdraw(context, m),
              child: const Text('ביטול הבקשה'),
            ),
        ];
      case KnownMatchmakerState.declined:
        final bool canAsk =
            m.connection?.canAskAgain(MatchmakerConnections.uid ?? '') ?? false;
        children = <Widget>[
          Text(
            'הבקשה לא אושרה',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (canAsk && !busy)
            FilledButton.tonal(
              onPressed: () => KnownMatchmakerActions.connect(context, m),
              child: const Text('לבקש שוב'),
            )
          else if (busy)
            spinner
          else
            Text(
              'אפשר יהיה לבקש שוב בהמשך.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
        ];
      case KnownMatchmakerState.connected:
        children = <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.handshake_outlined,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 8),
              Text(
                'אתם מחוברים בשדכן',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          note,
        ];
    }
    return HomePaperCard(
      stripe: AppColors.secondary,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
