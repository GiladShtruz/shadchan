import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/network_screen.dart';
import 'package:shadchan/screens/sharing_settings_screen.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_navigation.dart';
import 'package:shadchan/utils/avatar_image.dart';
import 'package:shadchan/utils/known_matchmakers.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/utils/screen_perf.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/matchmaker_rank_badge.dart';
import 'package:shadchan/widgets/network_onboarding.dart';

/// The groups of "שדכנים שאני מכיר" from the helpers and the share rows.
KnownMatchmakerGroups knownMatchmakerGroups(CardAccessProvider access) =>
    KnownMatchmakers.build(
      me: MatchmakerShares.uid ?? access.uid,
      helpers: access.knownHelpers,
      shares: MatchmakerShares.rows.value,
      nameOf: (CardHelper h) => ContactHashUpload.nameFor(h.phoneHash),
    );

/// "שדכנים שאני מכיר" — matchmakers among this matchmaker's own contacts who
/// use the app, and what each shares with the other.
///
/// **Contacts are the layer of trust, and there is no friend request.** A
/// matchmaker saved in this phone who matchmakes here is simply listed. What
/// is decided is a *share*, by its owner, for one matchmaker at a time
/// (`SharingSettingsScreen`). "מחוברים" are two who share something either
/// way.
///
/// **Light on purpose.** The first view is the helpers the server already
/// computed (face, name, activity) and the share rows (a few small
/// documents) — no card, no database. Twenty rows at first, more on demand,
/// each built lazily. The share rows are live only while the page is open
/// (one listener, closed on leaving).
class KnownMatchmakersScreen extends StatefulWidget {
  const KnownMatchmakersScreen({super.key});

  static const String route = '/known-matchmakers';
  static String profileRoute(String uid) => '$route/$uid';

  /// Rows drawn at first, and added on each "עוד".
  static const int pageSize = 20;

  @override
  State<KnownMatchmakersScreen> createState() => _KnownMatchmakersScreenState();
}

class _KnownMatchmakersScreenState extends State<KnownMatchmakersScreen> {
  ContactsPermissionState? _permission;
  bool _scanning = false;
  int _shownOthers = KnownMatchmakersScreen.pageSize;
  VoidCallback? _release;

  late final CardAccessProvider _access = context.read<CardAccessProvider>();
  late final ScreenPerf _perf = ScreenPerf(
    'known-matchmakers',
    listeners: () =>
        _access.listenerCount +
        MatchmakerShares.listenerCount +
        MatchmakerNetwork.listenerCount,
  );

  KnownMatchmakerGroups? _groups;
  Object? _groupsKey;

  @override
  void initState() {
    super.initState();
    _perf; // Starts the clock.
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _release?.call();
    _perf.leave();
    super.dispose();
  }

  Future<void> _connect() async {
    if (FirebaseBootstrap.isReady) {
      await MatchmakerNetwork.start();
      if (!mounted) return;
      _release = MatchmakerShares.watch();
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
      // Never prompts, and at most once in half an hour.
      _perf.read();
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
      _perf.read();
      await ContactHashUpload.run(force: true);
      if (mounted) setState(() => _scanning = false);
    }
  }

  KnownMatchmakerGroups _groupsFor(CardAccessProvider access) {
    final Object key = Object.hash(
      access.helpersRevision,
      identityHashCode(MatchmakerShares.rows.value),
      identityHashCode(ContactHashUpload.contactNames.value),
      MatchmakerShares.uid ?? access.uid,
    );
    if (key != _groupsKey || _groups == null) {
      _groupsKey = key;
      _groups = knownMatchmakerGroups(access);
    }
    return _groups!;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        MatchmakerShares.rows,
        MatchmakerShares.loaded,
        MatchmakerShares.busy,
      ]),
      builder: (BuildContext context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    _perf.build();
    final ThemeData theme = Theme.of(context);
    final CardAccessProvider access = context.read<CardAccessProvider>();
    context.select<CardAccessProvider, (int, bool, String?)>(
      (CardAccessProvider a) => (a.helpersRevision, a.helpersLoaded, a.uid),
    );
    final String? myPhone = context.select<UserProfileProvider, String?>(
      (UserProfileProvider p) => p.myPhone,
    );
    final KnownMatchmakerGroups groups = _groupsFor(access);
    final bool loading =
        !access.helpersLoaded && !MatchmakerShares.loaded.value;
    final bool noContacts =
        _permission != null && _permission != ContactsPermissionState.granted;
    if (!loading || noContacts) _perf.contentReady();
    final List<KnownMatchmaker> others = groups.others
        .take(_shownOthers)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('שדכנים שאני מכיר'),
        actions: <Widget>[
          IconButton(
            tooltip: 'מה אני משתף/ת עם כל שדכן',
            onPressed: () => context.push(SharingSettingsRoute.path),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverList.list(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text(
                    'שדכנים מאנשי הקשר שלך שמשתמשים בשדכן. עם כל אחד מחליטים '
                    'בנפרד מה לשתף — כל המאגר, אנשים נבחרים או כלום — ואפשר '
                    'לדבר בצ\'אט או ב־WhatsApp גם בלי לשתף.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (!NetworkSharing.sharesAnything &&
                    !NetworkSharing.onboardingDone)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: NetworkOnboardingCard(),
                  ),
                const _SharingSummary(),
                if (noContacts)
                  _Notice(
                    text:
                        'כדי למצוא שדכנים שאת/ה מכיר/ה, צריך גישה לאנשי הקשר. '
                        'רק אנשים ששמורים אצלך בטלפון יופיעו כאן.',
                    action:
                        _permission == ContactsPermissionState.permanentlyDenied
                        ? 'פתיחת הגדרות הטלפון'
                        : 'לאפשר גישה לאנשי קשר',
                    onAction: _askForContacts,
                  ),
                if (myPhone == null)
                  _Notice(
                    text:
                        'כדי ששדכנים שמכירים אותך ימצאו אותך כאן, צריך להוסיף '
                        'את המספר שלך. הוא לא מוצג לאף אחד.',
                    action: 'הוספת המספר שלי',
                    onAction: () async {
                      final UserProfileProvider profile = context
                          .read<UserProfileProvider>();
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
              ],
            ),
          ),
          if (groups.connected.isNotEmpty)
            ..._group(
              'משתפים איתי / מחוברים',
              AppColors.primary,
              groups.connected,
              groups.connected.length,
            ),
          if (groups.others.isNotEmpty)
            ..._group(
              groups.requestCount > 0
                  ? 'עדיין לא משתפים · ${groups.requestCount} ביקשו ממך שיתוף'
                  : 'עדיין לא משתפים',
              AppColors.rose,
              others,
              groups.others.length,
            ),
          if (groups.others.length > _shownOthers)
            SliverToBoxAdapter(
              child: Center(
                child: TextButton(
                  onPressed: () => setState(
                    () => _shownOthers += KnownMatchmakersScreen.pageSize,
                  ),
                  child: Text(
                    'עוד ${groups.others.length - _shownOthers} שדכנים',
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _group(
    String title,
    Color accent,
    List<KnownMatchmaker> list,
    int total,
  ) => <Widget>[
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _GroupTitle(title, total),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList.builder(
        itemCount: list.length,
        itemBuilder: (BuildContext context, int i) => _GroupRow(
          accent: accent,
          first: i == 0,
          last: i == list.length - 1,
          child: KnownMatchmakerRow(matchmaker: list[i]),
        ),
      ),
    ),
  ];
}

/// Who sees what, in one line: how many matchmakers I share with, and how
/// many share with me and how much.
class _SharingSummary extends StatelessWidget {
  const _SharingSummary();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int mine = NetworkSharing.readers.length;
    final int theirs = MatchmakerShares.sharingWithMe.length;
    if (mine == 0 && theirs == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HomePaperCard(
        stripe: AppColors.teal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        onTap: theirs > 0 ? () => context.push(NetworkScreen.route) : null,
        child: Text(
          <String>[
            if (mine > 0) 'את/ה משתף/ת עם $mine שדכנים',
            if (theirs > 0)
              '$theirs שדכנים משתפים איתך '
                  '${MatchmakerShares.totalSharedWithMe} כרטיסים',
          ].join(' · '),
          style: theme.textTheme.bodyMedium,
        ),
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

/// One row of a group, drawn as a slice of one white card.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.accent,
    required this.first,
    required this.last,
    required this.child,
  });
  final Color accent;
  final bool first;
  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    const Radius r = Radius.circular(20);
    return Material(
      color: dark
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.vertical(
        top: first ? r : Radius.zero,
        bottom: last ? r : Radius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (first) const SizedBox(height: 4),
          if (!first)
            Divider(
              height: 1,
              indent: 64,
              endIndent: 12,
              color: theme.colorScheme.outlineVariant,
            ),
          child,
          if (last) ...<Widget>[
            const SizedBox(height: 4),
            AccentUnderline(color: accent),
          ],
        ],
      ),
    );
  }
}

/// A matchmaker's face: their published photo, else a plain flat figure of a
/// person — never a first letter.
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
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryLight,
      foregroundImage: hasPhoto
          ? avatarImage(context, photo, diameter: radius * 2)
          : null,
      child: Icon(
        Icons.person_rounded,
        size: radius * 1.3,
        color: AppColors.white,
      ),
    );
  }
}

/// One compact row: face, name, last activity, what each shares with the
/// other, and the one thing to do. The whole row opens the profile.
class KnownMatchmakerRow extends StatelessWidget {
  const KnownMatchmakerRow({super.key, required this.matchmaker});
  final KnownMatchmaker matchmaker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KnownMatchmaker m = matchmaker;
    final String name = m.name.isEmpty ? 'שדכן/ית' : m.name;
    final List<String> lines = <String>[
      if (m.detailsLine.isNotEmpty) m.detailsLine,
      if (m.isConnected)
        'משתף/ת איתך ${m.sharedWithMeCount} · את/ה ${m.iShareCount}'
      else if (KnownMatchmakers.stateLabel(m) != null)
        KnownMatchmakers.stateLabel(m)!,
    ];
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
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (m.isNew()) ...<Widget>[
                        const SizedBox(width: 6),
                        const NewMark(),
                      ],
                    ],
                  ),
                  for (final String line in lines)
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            KnownMatchmakerAction(matchmaker: m, compact: true),
          ],
        ),
      ),
    );
  }
}

/// The small "חדש" mark of a matchmaker who joined this week.
class NewMark extends StatelessWidget {
  const NewMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.rose,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'חדש',
        style: TextStyle(
          color: AppColors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// **The one main action for a matchmaker, everywhere it is drawn** (row,
/// home carousel, profile):
///
///  - they share with me → "למאגר" (and "X כרטיסים");
///  - only I share with them → "צ'אט";
///  - nothing yet → "שיתוף מאגר" — straight to choosing what to share with
///    them (never a vague "connect"). Always one line: scaled down, never
///    wrapped.
class KnownMatchmakerAction extends StatelessWidget {
  const KnownMatchmakerAction({
    super.key,
    required this.matchmaker,
    this.compact = false,
    this.expand = false,
  });

  final KnownMatchmaker matchmaker;
  final bool compact;

  /// Fills the width it is given (the carousel's card).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final KnownMatchmaker m = matchmaker;
    if (MatchmakerShares.isBusy(m.uid)) {
      return const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final ButtonStyle style = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      minimumSize: expand ? const Size.fromHeight(36) : null,
    );
    final Widget button;
    if (m.sharesWithMe) {
      button = FilledButton(
        style: style,
        onPressed: () => KnownMatchmakerActions.openDatabase(context, m),
        child: const Text('למאגר'),
      );
    } else if (m.iShareWith) {
      button = FilledButton.tonal(
        style: style,
        onPressed: () => KnownMatchmakerActions.chat(context, m),
        child: const Text('צ\'אט'),
      );
    } else {
      button = FilledButton.tonal(
        style: style,
        onPressed: () => KnownMatchmakerActions.openSharing(context, m),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            m.askedMe ? 'לשתף בחזרה' : 'שיתוף מאגר',
            maxLines: 1,
            softWrap: false,
          ),
        ),
      );
    }
    if (!m.sharesWithMe || compact) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        button,
        const SizedBox(height: 2),
        Text(
          '${m.sharedWithMeCount} כרטיסים',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

/// Every action on another matchmaker: guarded offline, and answered with a
/// notice only when it failed or did something worth saying.
abstract final class KnownMatchmakerActions {
  static String _myName(BuildContext context) =>
      context.read<UserProfileProvider>().fullName ?? '';

  /// Their database: only what they share with me, page by page.
  static Future<void> openDatabase(BuildContext context, KnownMatchmaker m) =>
      context.push(NetworkScreen.routeFor(m.uid));

  /// What I share with them — straight into the choice.
  static Future<void> openSharing(BuildContext context, KnownMatchmaker m) {
    if (!OfflineGuard.allow(context)) return Future<void>.value();
    return context.push(SharingSettingsScreen.routeFor(m.uid, m.name));
  }

  static Future<void> chat(BuildContext context, KnownMatchmaker m) =>
      NetworkActions.chatWith(context, otherUid: m.uid, otherName: m.name);

  /// WhatsApp to the number this phone saved them under.
  static Future<void> whatsapp(BuildContext context, KnownMatchmaker m) async {
    final String? phone = ContactHashUpload.phoneFor(m.phoneHash);
    final bool ok = await WhatsAppUtils.openChatWithPhone(phone);
    if (!ok && context.mounted) {
      AppNotice.show(
        context,
        'לא מצאנו מספר שמור. אפשר לכתוב בצ\'אט שבאפליקציה.',
        isError: true,
      );
    }
  }

  static bool hasWhatsApp(KnownMatchmaker m) =>
      ContactHashUpload.phoneFor(m.phoneHash) != null;

  /// "בקש/י שיתוף" — they decide what, if anything.
  static Future<void> requestShare(
    BuildContext context,
    KnownMatchmaker m,
  ) async {
    if (!OfflineGuard.allow(context)) return;
    final bool ok = await MatchmakerShares.request(
      ownerUid: m.uid,
      myName: _myName(context),
      theirName: m.name,
    );
    if (!context.mounted) return;
    AppNotice.show(
      context,
      ok
          ? 'הבקשה נשלחה ל${m.firstName}. ${m.firstName} יחליט/תחליט מה לשתף.'
          : 'הבקשה לא נשלחה. נסו שוב.',
      isError: !ok,
    );
  }
}

/// A matchmaker's profile — light, and only what may be known:
///
///  - before anything is shared: photo, name, rank, last activity;
///  - once the two share something: also the database size, the cards shared
///    each way, couples who went out and weddings (public figures only).
///
/// And the share with them, managed in place: כל המאגר | אנשים נבחרים | כל
/// המאגר חוץ מ… — plus chat and WhatsApp.
class KnownMatchmakerProfileScreen extends StatefulWidget {
  const KnownMatchmakerProfileScreen({super.key, required this.uid});
  final String uid;

  @override
  State<KnownMatchmakerProfileScreen> createState() =>
      _KnownMatchmakerProfileScreenState();
}

class _KnownMatchmakerProfileScreenState
    extends State<KnownMatchmakerProfileScreen> {
  int? _databaseCount;
  DateTime? _lastActiveAt;
  String? _photoUrl;
  int? _couples;
  int? _weddings;
  int? _ideas;
  bool _extrasRead = false;
  VoidCallback? _release;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !FirebaseBootstrap.isReady) return;
      await MatchmakerNetwork.start();
      if (!mounted) return;
      _release = MatchmakerShares.watch();
      unawaited(context.read<CardAccessProvider>().ensureConnected());
    });
  }

  @override
  void dispose() {
    _release?.call();
    super.dispose();
  }

  Future<void> _readExtras(KnownMatchmaker m) async {
    if (_extrasRead || !FirebaseBootstrap.isReady) return;
    _extrasRead = true;
    final FirebaseFirestore db = FirebaseFirestore.instance;
    if (m.lastActiveAt == null && m.databaseCount == null) {
      try {
        ScreenPerf.noteQuery();
        final Map<String, dynamic>? data =
            (await db.doc('matchmakerActivity/${m.uid}').get()).data();
        _databaseCount = (data?['databaseCount'] as num?)?.toInt();
        _lastActiveAt = (data?['lastActiveAt'] as Timestamp?)?.toDate();
      } catch (_) {}
    }
    try {
      ScreenPerf.noteQuery();
      final Map<String, dynamic>? member =
          (await db.doc('communityMembers/${m.communityUid ?? m.uid}').get())
              .data();
      // Public figures only: a matchmaker hidden from the board shows none.
      if (member != null && member['hidden'] == false) {
        _couples = (member['allCouples'] as num?)?.toInt();
        _weddings = (member['allEngagements'] as num?)?.toInt();
        _ideas = (member['allIdeas'] as num?)?.toInt();
        final Object? photo = member['photoUrl'];
        if (photo is String && photo.trim().isNotEmpty) _photoUrl = photo;
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        MatchmakerShares.rows,
        MatchmakerShares.loaded,
        MatchmakerShares.busy,
        NetworkSharing.revision,
      ]),
      builder: (BuildContext context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    KnownMatchmaker? m;
    for (final KnownMatchmaker k in knownMatchmakerGroups(access).all) {
      if (k.uid == widget.uid) m = k;
    }
    final bool settled = access.helpersLoaded && MatchmakerShares.loaded.value;

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
    final ShareChoice mine = NetworkSharing.choiceFor(k.uid);

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Center(
            child: KnownMatchmakerFace(name: name, photoUrl: photo, radius: 46),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (k.isNew()) ...<Widget>[
                const SizedBox(width: 8),
                const NewMark(),
              ],
            ],
          ),
          if ((_ideas ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(child: MatchmakerRankBadge(ideas: _ideas!)),
            ),
          const SizedBox(height: 16),
          _Facts(
            facts: <(IconData, String)>[
              if (lastActive != null)
                (
                  Icons.schedule_rounded,
                  MatchmakerFriends.activityLabel(lastActive),
                ),
              if (k.isConnected) ...<(IconData, String)>[
                if (database != null)
                  (
                    Icons.groups_2_outlined,
                    MatchmakerFriends.databaseLabel(database),
                  ),
                (
                  Icons.call_received_rounded,
                  k.sharesWithMe
                      ? 'משתף/ת איתך ${k.sharedWithMeCount} כרטיסים'
                      : 'לא משתף/ת איתך כרטיסים',
                ),
                (
                  Icons.call_made_rounded,
                  k.iShareWith
                      ? 'את/ה משתף/ת ${k.iShareCount} כרטיסים'
                      : 'את/ה לא משתף/ת כרטיסים',
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
            ],
          ),
          const SizedBox(height: 16),
          // The main thing to do, then the ways to talk.
          if (k.sharesWithMe)
            FilledButton.icon(
              onPressed: () => KnownMatchmakerActions.openDatabase(context, k),
              icon: const Icon(Icons.style_outlined),
              label: Text('למאגר של ${k.firstName} · ${k.sharedWithMeCount}'),
            )
          else if (k.iAsked)
            Text(
              'ביקשת מ${k.firstName} לשתף. ${k.firstName} יחליט/תחליט מה.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            )
          else
            OutlinedButton.icon(
              onPressed: () => KnownMatchmakerActions.requestShare(context, k),
              icon: const Icon(Icons.forward_to_inbox_outlined),
              label: Text('בקשת שיתוף מ${k.firstName}'),
            ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => KnownMatchmakerActions.chat(context, k),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('צ\'אט'),
                ),
              ),
              if (KnownMatchmakerActions.hasWhatsApp(k)) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        KnownMatchmakerActions.whatsapp(context, k),
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          HomePaperCard(
            stripe: AppColors.copper,
            onTap: () => KnownMatchmakerActions.openSharing(context, k),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'מה אני משתף/ת עם ${k.firstName}',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        k.askedMe && !mine.isOn
                            ? '${k.firstName} ביקש/ה שתשתף/י · בחירה'
                            : switch (mine.mode) {
                                ShareMode.none => 'כלום — לבחירה',
                                ShareMode.all => 'כל המאגר',
                                ShareMode.selected =>
                                  'אנשים נבחרים (${mine.selected.length})',
                                ShareMode.allExcept =>
                                  'כל המאגר חוץ מ־${mine.excluded.length}',
                              },
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left_rounded),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'השיתוף נקבע בנפרד לכל שדכן/ית, ואפשר לשנות או להפסיק אותו בכל רגע. '
            'רעיונות שכבר נפתחו נשארים.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
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
      stripe: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (IconData icon, String text) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
