import 'dart:async';
import 'package:shadchan/utils/avatar_image.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shadchan/widgets/matchmaker_rank_badge.dart';
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
import 'package:go_router/go_router.dart';
import 'package:shadchan/screens/network_screen.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/widgets/network_onboarding.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/utils/screen_perf.dart';

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

  /// The performance log of this visit (`PERF known-matchmakers …`).
  late final CardAccessProvider _access = context.read<CardAccessProvider>();
  late final ScreenPerf _perf = ScreenPerf(
    'known-matchmakers',
    listeners: () =>
        _access.listenerCount +
        MatchmakerConnections.listenerCount +
        MatchmakerNetwork.listenerCount,
  );

  /// The grouping, kept until one of its inputs actually changed. It used to
  /// be recomputed — sorting and matching every helper against every
  /// connection — on every notification of every provider the page watched.
  KnownMatchmakerGroups? _groups;
  Object? _groupsKey;

  /// Cards each connected matchmaker shares with me, counted once per pool
  /// change rather than once per row per build.
  Map<String, int> _sharesByOwner = const <String, int>{};
  List<SharedCard>? _sharesFrom;

  @override
  void initState() {
    super.initState();
    _perf; // Starts the clock.
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _perf.leave();
    super.dispose();
  }

  Future<void> _connect() async {
    // The services are app-wide and already running (CloudSyncScheduler
    // starts them). These calls are no-ops then; they only matter when the
    // page is opened before Firebase finished starting.
    if (FirebaseBootstrap.isReady) {
      unawaited(MatchmakerConnections.start());
      unawaited(MatchmakerNetwork.start());
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
      // Never prompts, and at most once in half an hour: the whole address
      // book is read and hashed (off the UI thread), so it is not repeated
      // on every visit.
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
      identityHashCode(MatchmakerConnections.connections.value),
      identityHashCode(ContactHashUpload.contactNames.value),
      MatchmakerConnections.uid ?? access.uid,
    );
    if (key != _groupsKey || _groups == null) {
      _groupsKey = key;
      _groups = KnownMatchmakers.build(
        me: MatchmakerConnections.uid ?? access.uid,
        helpers: access.knownHelpers,
        connections: MatchmakerConnections.connections.value,
        nameOf: (CardHelper h) => ContactHashUpload.nameFor(h.phoneHash),
      );
    }
    return _groups!;
  }

  Map<String, int> _shares() {
    final List<SharedCard> pool = MatchmakerNetwork.cards.value;
    if (!identical(pool, _sharesFrom)) {
      _sharesFrom = pool;
      final Map<String, int> counts = <String, int>{};
      for (final SharedCard c in pool) {
        counts[c.ownerUid] = (counts[c.ownerUid] ?? 0) + 1;
      }
      _sharesByOwner = counts;
    }
    return _sharesByOwner;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        MatchmakerConnections.connections,
        MatchmakerConnections.loaded,
        MatchmakerConnections.busy,
        MatchmakerNetwork.cards,
        NetworkSharing.revision,
      ]),
      builder: (BuildContext context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    _perf.build();
    final ThemeData theme = Theme.of(context);
    // Only what the list needs: the helpers' revision and whether they are
    // loaded — not every notification of the provider (access rows, card
    // syncs, reports), each of which used to redraw the whole page.
    final CardAccessProvider access = context.read<CardAccessProvider>();
    context.select<CardAccessProvider, (int, bool, String?)>(
      (CardAccessProvider a) => (a.helpersRevision, a.helpersLoaded, a.uid),
    );
    final String? myPhone = context.select<UserProfileProvider, String?>(
      (UserProfileProvider p) => p.myPhone,
    );
    final KnownMatchmakerGroups groups = _groupsFor(access);
    final Map<String, int> shares = _shares();
    final bool loading =
        !access.helpersLoaded && !MatchmakerConnections.loaded.value;
    final bool noContacts =
        _permission != null && _permission != ContactsPermissionState.granted;
    if (!loading || noContacts) _perf.contentReady();

    Widget box(Widget child) => SliverToBoxAdapter(child: child);

    return Scaffold(
      appBar: AppBar(title: const Text('שדכנים שאני מכיר')),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverList.list(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text(
                    'שדכנים מאנשי הקשר שלך שמשתמשים בשדכן. חיבור הוא הדדי — '
                    'צד אחד מבקש והשני מאשר. מרגע האישור, מה שכל אחד מכם בחר '
                    'לשתף זמין לשני, ואפשר לשוחח בצ\'אט גם בלי לשתף דבר.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (NetworkSharing.mode == ShareMode.none &&
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
                        'כדי ששדכנים שמכירים אותך ימצאו אותך כאן, אפשר להוסיף '
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
          // Each group is a lazily built list: only the rows on screen are
          // laid out, painted and have their photo loaded.
          for (final (String title, Color accent, List<KnownMatchmaker> list)
              in <(String, Color, List<KnownMatchmaker>)>[
                ('מחוברים', AppColors.primaryDark, groups.connected),
                ('בקשות חיבור', AppColors.secondary, groups.requests),
                ('שדכנים מאנשי הקשר', AppColors.femaleAccent, groups.contacts),
              ])
            if (list.isNotEmpty) ...<Widget>[
              box(
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _GroupTitle(title, list.length),
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
                    child: KnownMatchmakerRow(
                      matchmaker: list[i],
                      sharesWithMe: shares[list[i].uid] ?? 0,
                    ),
                  ),
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Who sees what, in one card: how many cards I share with every matchmaker
/// I am connected with, and how many the connected matchmakers share with
/// me — so the connection is understood without reading a settings page.
class _SharingSummary extends StatelessWidget {
  const _SharingSummary();

  /// The count of my shared cards, kept until the database, the sharing
  /// choice or the access rows actually changed — it walks every friend.
  static Object? _mineKey;
  static int _mine = 0;

  @override
  Widget build(BuildContext context) {
    final PersonRepository repo = context.read<PersonRepository>();
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final int peopleRev = context.select<PersonRepository, int>(
      (PersonRepository r) => r.revision,
    );
    final int accessRev = context.select<CardAccessProvider, int>(
      (CardAccessProvider a) => a.revision,
    );
    final int connected = MatchmakerNetwork.connectedNames.length;
    final Object key = Object.hash(
      peopleRev,
      accessRev,
      NetworkSharing.revision.value,
    );
    if (key != _mineKey) {
      _mineKey = key;
      _mine = NetworkSharing.sharedNow(
        repo.getAll(),
        accessTo: access.accessTo,
      ).length;
    }
    final int mine = _mine;
    final Map<String, int> theirs = <String, int>{};
    for (final SharedCard c in MatchmakerNetwork.cards.value) {
      theirs[c.ownerUid] = (theirs[c.ownerUid] ?? 0) + 1;
    }
    final int cards = MatchmakerNetwork.cards.value.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HomePaperCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            ListTile(
              dense: true,
              leading: const Icon(Icons.ios_share_rounded),
              title: Text(
                NetworkSharing.mode == ShareMode.none
                    ? 'אני לא משתף/ת כרטיסים כרגע'
                    : 'אני משתף/ת $mine כרטיסים עם כל השדכנים המחוברים',
              ),
              trailing: TextButton(
                onPressed: () => context.push('/network/sharing'),
                child: const Text('ניהול'),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.diversity_3_outlined),
              title: Text(
                connected == 0
                    ? 'עוד אין שדכנים מחוברים'
                    : theirs.isEmpty
                    ? 'השדכנים המחוברים עוד לא שיתפו איתך כרטיסים'
                    : '${theirs.length} שדכנים משתפים איתך $cards כרטיסים',
              ),
              trailing: theirs.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () => context.push('/network'),
                      child: const Text('למאגר'),
                    ),
            ),
          ],
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

/// One row of a group, drawn as a slice of one paper card: rounded at the
/// top of the first row and the foot of the last, the group's rule under the
/// last, a hairline between the rest.
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
      foregroundImage: hasPhoto
          ? avatarImage(context, photo, diameter: radius * 2)
          : null,
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
  const KnownMatchmakerRow({
    super.key,
    required this.matchmaker,
    this.sharesWithMe = 0,
  });
  final KnownMatchmaker matchmaker;

  /// Cards this matchmaker shares with me — counted by the list, once.
  final int sharesWithMe;

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
                  if (details.isNotEmpty || state != null || sharesWithMe > 0)
                    Text(
                      <String>[
                        ?state,
                        if (details.isNotEmpty) details,
                        if (m.state == KnownMatchmakerState.connected)
                          sharesWithMe == 0
                              ? 'לא משתף/ת איתך כרטיסים'
                              : 'משתף/ת איתך $sharesWithMe כרטיסים',
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
        return IconButton(
          tooltip: 'צ\'אט',
          onPressed: () => NetworkActions.chatWith(
            context,
            otherUid: m.uid,
            otherName: m.name,
          ),
          icon: const Icon(
            Icons.chat_bubble_outline_rounded,
            color: AppColors.primaryDark,
            size: 22,
          ),
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
  int? _ideas;
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
        _ideas = (member['allIdeas'] as num?)?.toInt();
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
        MatchmakerNetwork.cards,
        NetworkSharing.revision,
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
          if ((_ideas ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(child: MatchmakerRankBadge(ideas: _ideas!)),
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
      'החיבור לבדו לא משתף אף כרטיס. כל שדכן/ית בוחר/ת אילו כרטיסים לשתף עם '
      'המחוברים אליו/ה, ואפשר לשוחח בצ\'אט ולהציע רעיונות.',
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
          // Saved in each other's phones is enough to talk — a connection is
          // what opens cards and ideas between the two.
          TextButton.icon(
            onPressed: () => NetworkActions.chatWith(
              context,
              otherUid: m.uid,
              otherName: name,
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('שליחת הודעה בצ\'אט'),
          ),
          const SizedBox(height: 4),
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
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => NetworkActions.chatWith(
                    context,
                    otherUid: m.uid,
                    otherName: name,
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('צ\'אט'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/network'),
                  icon: const Icon(Icons.diversity_3_outlined),
                  label: const Text('המאגר המשותף'),
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
