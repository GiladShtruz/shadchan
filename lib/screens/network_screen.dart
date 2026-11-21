import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/models/idea_proposal.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/utils/shared_pool.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/utils/screen_perf.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/home_section.dart';

/// A photo of a shared card, fetched through the network service and cached;
/// the default avatar until it arrives (or when there is none).
class SharedPhoto extends StatelessWidget {
  const SharedPhoto({
    super.key,
    required this.ownerUid,
    required this.path,
    required this.person,
    required this.radius,
  });

  final String ownerUid;
  final String? path;
  final Person person;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String? p = path;
    final Widget fallback = PersonAvatar(person: person, radius: radius);
    if (p == null) return fallback;
    final int decode = (radius * 2 * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    return FutureBuilder<File?>(
      future: MatchmakerNetwork.photo(ownerUid, p),
      initialData: MatchmakerNetwork.photoNow(ownerUid, p),
      builder: (BuildContext context, AsyncSnapshot<File?> snap) {
        final File? file = snap.data;
        if (file == null) return fallback;
        return CircleAvatar(
          radius: radius,
          // Decoded at the size it is drawn.
          backgroundImage: ResizeImage(
            FileImage(file),
            width: decode,
            height: decode,
            policy: ResizeImagePolicy.fit,
          ),
        );
      },
    );
  }
}

/// "דרך יונתן כהן", with the holder's initial and the way to their chat —
/// so it is always clear whose card this is and whom to ask.
class SourceLine extends StatelessWidget {
  const SourceLine({super.key, required this.card, this.compact = false});

  final SharedCard card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = card.ownerName.trim().isEmpty
        ? card.ownerFirstName
        : card.ownerName.trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CircleAvatar(
          radius: compact ? 9 : 12,
          backgroundColor: AppColors.softBlue,
          child: Text(
            name.characters.first,
            style: TextStyle(
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryDark,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'דרך $name',
            overflow: TextOverflow.ellipsis,
            style:
                (compact
                        ? theme.textTheme.labelSmall
                        : theme.textTheme.labelLarge)
                    ?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        IconButton(
          tooltip: 'צ\'אט עם $name',
          visualDensity: VisualDensity.compact,
          iconSize: compact ? 16 : 20,
          onPressed: () => NetworkActions.chatWith(
            context,
            otherUid: card.ownerUid,
            otherName: card.ownerName,
            ref: ChatRef(
              kind: 'card',
              id: card.personId,
              ownerUid: card.ownerUid,
              label: card.person.fullName,
            ),
          ),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
        ),
      ],
    );
  }
}

/// The everyday words for a card: "25 · דתי לאומי · ירושלים".
String sharedSummaryOf(Person person) {
  return <String>[
    if (person.age != null) '${person.age}',
    if (person.religiousLevel != null) person.religiousLevelLabel,
    if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
  ].join(' · ');
}

/// The actions every network screen shares: offer an idea, open a chat.
abstract final class NetworkActions {
  static String _myName(BuildContext context) =>
      context.read<UserProfileProvider>().fullName ?? '';

  /// Opens the one continuing chat with [otherUid], about [ref] if given.
  static Future<void> chatWith(
    BuildContext context, {
    required String otherUid,
    required String otherName,
    ChatRef? ref,
    String? message,
  }) async {
    if (!OfflineGuard.allow(context)) return;
    final String? me = await ChatService.me();
    if (!context.mounted) return;
    if (me == null || otherUid.isEmpty || otherUid == me) {
      AppNotice.show(
        context,
        'לא הצלחנו לפתוח את הצ\'אט. צריך להיות מחובר/ת לחשבון.',
        isError: true,
      );
      return;
    }
    final String id = ChatService.directId(me, otherUid);
    if (message != null && ref != null) {
      // Sent at once: the card or idea is already in the conversation when
      // it opens. This first line also creates the chat when there was none.
      await ChatService.send(
        id,
        message,
        ref: ref,
        myName: _myName(context),
        theirName: otherName,
      );
      if (!context.mounted) return;
      await context.push(
        ChatService.routeTo(me: me, otherUid: otherUid, theirName: otherName),
      );
      return;
    }
    await context.push(
      ChatService.routeTo(me: me, otherUid: otherUid, theirName: otherName),
      extra: ref,
    );
  }

  /// "הצעת רעיון": picks a friend from this matchmaker's own database for
  /// [target] and sends the idea to the matchmaker who holds [target]. Every
  /// step goes through that matchmaker — nobody contacts the single directly.
  static Future<String?> propose(
    BuildContext context,
    SharedCard target, {
    Person? candidate,
  }) async {
    if (!OfflineGuard.allow(context)) return null;
    final PersonRepository repo = context.read<PersonRepository>();
    final Gender want = target.person.gender == Gender.male
        ? Gender.female
        : Gender.male;
    Person? chosen = candidate;
    chosen ??= await PersonPickerSheet.show(
      context,
      title: 'מי מהמאגר שלך מתאים/ה ל${target.person.firstName}?',
      filterGender: want,
      sourcePerson: target.person,
      candidatePredicate: (Person p) =>
          !p.hidden && !SharedIdeas.isPartnersPerson(p.id),
    );
    if (chosen == null || !context.mounted) return null;
    final Person mine = repo.getById(chosen.id) ?? chosen;
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final ShareEligibility eligibility = NetworkSharing.eligibilityOf(
      mine,
      accessTo: access.accessTo,
    );
    if (eligibility == ShareEligibility.awaitingConsent) {
      await _askConsent(context, mine);
      return null;
    }
    if ((mine.description ?? '').trim().isEmpty) {
      AppNotice.show(
        context,
        'כדי להציע רעיון צריך כרטיס עם טקסט ל${mine.firstName}.',
        isError: true,
      );
      return null;
    }
    final String? note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) =>
          _ProposeSheet(target: target, candidate: mine),
    );
    if (note == null || !context.mounted) return null;
    final String? id = await MatchmakerNetwork.propose(
      target: target,
      candidate: mine,
      myName: _myName(context),
      note: note,
    );
    if (!context.mounted) return null;
    if (id == null) {
      AppNotice.show(context, 'ההצעה לא נשלחה. נסו שוב.', isError: true);
      return null;
    }
    // Every idea between the two lives in their one chat.
    final String? chatId = await ChatService.openDirect(
      otherUid: target.ownerUid,
      myName: _myName(context),
      theirName: target.ownerName,
    );
    if (chatId != null) {
      final String pair = '${mine.firstName} ו${target.person.firstName}';
      await ChatService.send(
        chatId,
        note.trim().isEmpty ? 'הצעתי רעיון: $pair' : note.trim(),
        ref: ChatRef(kind: 'proposal', id: id, label: pair),
        myName: _myName(context),
        theirName: target.ownerName,
      );
    }
    if (!context.mounted) return id;
    AppNotice.show(
      context,
      'ההצעה נשלחה ל${target.ownerFirstName}. הרעיון ייפתח כשתחליטו לשאול את שני הצדדים.',
    );
    return id;
  }

  /// "דרך 3 שדכנים": whom to turn to about this card.
  static Future<void> chooseHolder(
    BuildContext context,
    SharedPoolEntry entry,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'למי לפנות לגבי ${entry.primary.person.firstName}?',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            for (final SharedCard holder in entry.holders) ...<Widget>[
              _HolderTile(card: holder),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    ),
  );

  /// Sends one of this matchmaker's own friends to one connected
  /// matchmaker — in the app's chat, even when the card is not in the shared
  /// pool — or through WhatsApp.
  static Future<void> sendCard(BuildContext context, Person person) async {
    if (!OfflineGuard.allow(context)) return;
    unawaited(MatchmakerNetwork.start());
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final ShareEligibility state = NetworkSharing.eligibilityOf(
      person,
      accessTo: access.accessTo,
    );
    await MatchmakerShares.refresh();
    if (!context.mounted) return;
    final Map<String, String> connected = MatchmakerNetwork.connectedNames;
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'שליחת הכרטיס של ${person.firstName} לשדכן/ית',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'הכרטיס יגיע בצ\'אט, לצפייה בלבד — גם אם הוא לא בשיתוף איתו/ה.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (state != ShareEligibility.ready)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    state == ShareEligibility.awaitingConsent
                        ? '${person.firstName} כיבה/כיבתה את השיתוף דרך השדכנים, '
                              'אז אפשר לשלוח רק ב־WhatsApp.'
                        : 'כדי לשלוח בצ\'אט צריך כרטיס מלא — תמונה וטקסט.',
                    textAlign: TextAlign.center,
                  ),
                )
              else if (connected.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'עוד אין שדכנים שאתם משתפים איתם — אפשר לשלוח ב־WhatsApp.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final MapEntry<String, String> c in connected.entries)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.softBlue,
                      child: Text(
                        c.value.trim().isEmpty
                            ? '?'
                            : c.value.trim().characters.first,
                      ),
                    ),
                    title: Text(c.value.isEmpty ? 'שדכן/ית' : c.value),
                    trailing: const Icon(Icons.send_rounded),
                    onTap: () => Navigator.pop(context, c.key),
                  ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('שליחה ב־WhatsApp'),
                onTap: () => Navigator.pop(context, '__whatsapp'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == '__whatsapp') {
      await ShareUtils.sharePerson(
        person,
        origin: ShareUtils.originOf(context),
      );
      return;
    }
    final String name = connected[choice] ?? '';
    final bool sent = await MatchmakerNetwork.sendCard(
      person: person,
      toUid: choice,
      myName: _myName(context),
    );
    if (!context.mounted) return;
    if (!sent) {
      AppNotice.show(context, 'הכרטיס לא נשלח. נסו שוב.', isError: true);
      return;
    }
    NetworkSharing.noteSent(person.id);
    await chatWith(
      context,
      otherUid: choice,
      otherName: name,
      ref: ChatRef(
        kind: 'card',
        id: person.id,
        ownerUid: MatchmakerNetwork.uid,
        label: person.fullName,
      ),
      message: 'שלחתי לך את הכרטיס של ${person.fullName}',
    );
  }

  static Future<void> _askConsent(BuildContext context, Person person) async {
    final bool? ask = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('${person.firstName} מנהל/ת כרטיס אישי'),
        content: Text(
          '${person.firstName} כיבה/כיבתה באזור האישי את ההצגה של הכרטיס '
          'לשדכנים שהשדכנים שלו/ה מכירים. אפשר לבקש ממנו/ה להפעיל אותה שוב.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('לבקש אישור'),
          ),
        ],
      ),
    );
    if (ask != true || !context.mounted) return;
    final String? owner = person.cardOwnerUid;
    if (owner == null) return;
    final bool sent = await context
        .read<CardAccessProvider>()
        .requestShareOnward(owner);
    if (!context.mounted) return;
    AppNotice.show(
      context,
      sent ? 'הבקשה נשלחה ל${person.firstName}' : 'לא הצלחנו לשלוח את הבקשה',
      isError: !sent,
    );
  }
}

class _ProposeSheet extends StatefulWidget {
  const _ProposeSheet({required this.target, required this.candidate});

  final SharedCard target;
  final Person candidate;

  @override
  State<_ProposeSheet> createState() => _ProposeSheetState();
}

class _ProposeSheetState extends State<_ProposeSheet> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String owner = widget.target.ownerFirstName;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'הצעת רעיון ל$owner',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _MiniPerson(
                  person: widget.candidate,
                  caption: 'מהמאגר שלך',
                  avatar: PersonAvatar(person: widget.candidate, radius: 30),
                ),
              ),
              Icon(Icons.favorite_rounded, color: AppColors.femaleAccent),
              Expanded(
                child: _MiniPerson(
                  person: widget.target.person,
                  caption: 'מהמאגר של $owner',
                  avatar: SharedPhoto(
                    ownerUid: widget.target.ownerUid,
                    path: widget.target.photoPaths.firstOrNull,
                    person: widget.target.person,
                    radius: 30,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '$owner יקבל/תקבל את הכרטיס של ${widget.candidate.firstName} — תמונות, '
            'פרטי הכרטיס, "מה מחפש/ת" ותגיות. בלי טלפון ובלי ההערות שלך. '
            'אם יאשר/תאשר, הרעיון ייפתח אצל שניכם ברגע שתחליטו לשאול את החברים, '
            'וכל אחד ימשיך מול החבר/ה שלו.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'כמה מילים ל־שדכן/ית (לא חובה)',
              hintText: 'למה חשבת עליהם?',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _note.text),
            icon: const Icon(Icons.send_rounded),
            label: Text('שליחת ההצעה ל$owner'),
          ),
        ],
      ),
    );
  }
}

class _MiniPerson extends StatelessWidget {
  const _MiniPerson({
    required this.person,
    required this.caption,
    required this.avatar,
  });

  final Person person;
  final String caption;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: <Widget>[
        avatar,
        const SizedBox(height: 6),
        Text(
          person.fullName,
          style: theme.textTheme.titleSmall?.copyWith(
            color: AppColors.genderAccent(person.gender),
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
        Text(
          sharedSummaryOf(person),
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        Text(caption, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// The cards other matchmakers share with this one — **page by page, never
/// a downloaded pool.**
///
/// With [ownerUid]: "המאגר של יונתן" — only what that one matchmaker shares
/// with this one. Without: every card shared by anybody, with a chip per
/// source ("מהמאגר של יונתן") and a search by name that runs on the server.
/// With [forPersonId]: matches for one of this matchmaker's friends among
/// what was loaded.
///
/// Thirty cards at a time ([MatchmakerNetwork.pageSize]); the next thirty
/// when the list nears its end. Photos are small, decoded at the size drawn,
/// and fetched only for the rows on screen. Nothing here keeps a listener.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key, this.forPersonId, this.ownerUid});

  static const String route = '/network';

  /// The route of one matchmaker's shared database.
  static String routeFor(String ownerUid) => '$route?owner=$ownerUid';

  final String? forPersonId;
  final String? ownerUid;

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _query = '';
  String? _source;
  PeopleFilterState? _filters;
  Timer? _debounce;

  final List<SharedCard> _cards = <SharedCard>[];
  Object? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;
  late final ScreenPerf _perf;
  VoidCallback? _releaseShares;
  VoidCallback? _releaseProposals;

  @override
  void initState() {
    super.initState();
    _source = widget.ownerUid;
    _perf = ScreenPerf(
      'network${widget.ownerUid == null ? '' : '-owner'}',
      listeners: () =>
          MatchmakerShares.listenerCount + MatchmakerNetwork.listenerCount,
    );
    _scroll.addListener(_onScroll);
    unawaited(_start());
  }

  Future<void> _start() async {
    await MatchmakerNetwork.start();
    if (!mounted) return;
    _releaseShares = MatchmakerShares.watch();
    _releaseProposals = MatchmakerNetwork.watchProposals();
    await _reload();
  }

  @override
  void dispose() {
    _perf.leave();
    _debounce?.cancel();
    _releaseShares?.call();
    _releaseProposals?.call();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || !_hasMore) return;
    if (_scroll.position.extentAfter < 600) unawaited(_loadMore());
  }

  Future<void> _reload() async {
    _generation++;
    setState(() {
      _cards.clear();
      _cursor = null;
      _hasMore = true;
      _failed = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final int generation = _generation;
    setState(() => _loading = true);
    try {
      final NetworkPage page = await MatchmakerNetwork.page(
        ownerUid: _source,
        nameQuery: _query,
        cursor: _cursor,
      );
      _perf.read();
      if (!mounted || generation != _generation) return;
      setState(() {
        _cards.addAll(page.cards);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        _perf.contentReady();
      }
    }
  }

  void _onQuery(String v) {
    _query = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_reload());
    });
  }

  List<SharedPoolEntry> _entries(PersonRepository repo) {
    final List<Person> mine = repo.getAll();
    final Set<String> myIdentities = <String>{
      for (final Person p in mine)
        if (!p.hidden && PhoneIdentity.hash(p.phone) != null)
          PhoneIdentity.hash(p.phone)!,
    };
    final Set<String> myCardOwners = <String>{
      for (final Person p in mine)
        if (!p.hidden && p.cardOwnerUid != null) p.cardOwnerUid!,
      // My own personal card, held by another matchmaker: not a stranger.
      if (MatchmakerNetwork.uid != null) MatchmakerNetwork.uid!,
    };
    List<SharedPoolEntry> entries = SharedPool.build(
      _cards,
      myIdentities: myIdentities,
      myCardOwners: myCardOwners,
    );
    final Person? source = widget.forPersonId == null
        ? null
        : repo.getById(widget.forPersonId!);
    if (source != null) {
      entries = <SharedPoolEntry>[
        for (final SharedPoolEntry e in entries)
          if (MatchSuggestionUtils.matchesBasicPreferences(
            source: source,
            candidate: e.primary.person,
          ))
            e,
      ];
    }
    return <SharedPoolEntry>[
      for (final SharedPoolEntry e in entries)
        if (_filters == null || _filters!.matches(e.primary.person)) e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    _perf.build();
    final ThemeData theme = Theme.of(context);
    final PersonRepository repo = context.watch<PersonRepository>();
    final Person? source = widget.forPersonId == null
        ? null
        : repo.getById(widget.forPersonId!);
    final String? ownerName = widget.ownerUid == null
        ? null
        : (MatchmakerShares.theirs(widget.ownerUid!)?.ownerName ?? '');
    return Scaffold(
      appBar: AppBar(
        title: Text(
          source != null
              ? 'התאמות ל${source.firstName} אצל השדכנים שלך'
              : ownerName != null
              ? 'המאגר של ${_first(ownerName)}'
              : 'כרטיסים ששיתפו איתי',
        ),
        actions: <Widget>[
          ValueListenableBuilder<int>(
            valueListenable: ChatService.unread,
            builder: (BuildContext context, int unread, _) => IconButton(
              tooltip: 'צ\'אטים',
              onPressed: () => context.push('/chats'),
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          MatchmakerShares.rows,
          MatchmakerNetwork.proposals,
        ]),
        builder: (BuildContext context, _) {
          final Map<String, String> sharing = MatchmakerShares.sharingWithMe;
          if (MatchmakerShares.loaded.value &&
              sharing.isEmpty &&
              _cards.isEmpty &&
              !_loading) {
            return _EmptyNetwork(
              title: 'עוד אף שדכן לא משתף איתך כרטיסים',
              text:
                  'כל שדכן/ית מחליט/ה מה לשתף עם כל שדכן/ית אחר/ת. זו לא רשת '
                  'ציבורית — רק שדכנים מאנשי הקשר שלך. אפשר לפתוח שיתוף מצדך '
                  'או לבקש מהם לשתף.',
              button: 'לשדכנים שאני מכיר',
              onPressed: () => context.push('/known-matchmakers'),
            );
          }
          final List<SharedPoolEntry> entries = _entries(repo);
          final List<IdeaProposal> incoming = MatchmakerNetwork.incomingPending;
          return RefreshIndicator(
            onRefresh: _reload,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      widget.ownerUid != null
                          ? '${_first(ownerName ?? '')} משתף/ת איתך '
                                '${MatchmakerShares.sharedWithMeCount(widget.ownerUid!)} כרטיסים · '
                                'צפייה בלבד, כל פנייה עוברת דרכו/ה'
                          : '${sharing.length} שדכנים משתפים איתך '
                                '${MatchmakerShares.totalSharedWithMe} כרטיסים · '
                                'צפייה בלבד, כל פנייה עוברת דרך השדכן/ית',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                if (incoming.isNotEmpty && widget.ownerUid == null)
                  SliverToBoxAdapter(
                    child: _IncomingProposals(proposals: incoming),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: _onQuery,
                            decoration: const InputDecoration(
                              hintText: 'חיפוש לפי שם',
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'סינון',
                          onPressed: () async {
                            final PeopleFilterState? next =
                                await showPeopleFiltersSheet(
                                  context,
                                  repository: repo,
                                  initial: _filters,
                                );
                            if (next != null && mounted) {
                              setState(
                                () => _filters = next.isEmpty ? null : next,
                              );
                            }
                          },
                          icon: Badge(
                            isLabelVisible: _filters != null,
                            smallSize: 8,
                            child: const Icon(Icons.tune_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.ownerUid == null && sharing.length > 1)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: const Text('כל השדכנים'),
                              selected: _source == null,
                              onSelected: (_) {
                                _source = null;
                                unawaited(_reload());
                              },
                            ),
                          ),
                          for (final MapEntry<String, String> c
                              in sharing.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: ChoiceChip(
                                label: Text(
                                  'מהמאגר של ${_first(c.value)} · '
                                  '${MatchmakerShares.sharedWithMeCount(c.key)}',
                                ),
                                selected: _source == c.key,
                                onSelected: (bool on) {
                                  _source = on ? c.key : null;
                                  unawaited(_reload());
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (_cards.isEmpty && _loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_cards.isEmpty && _failed)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyNetwork(
                      title: 'לא הצלחנו לטעון',
                      text: 'המאגרים של שדכנים אחרים דורשים חיבור לאינטרנט.',
                      button: 'ניסיון חוזר',
                      onPressed: () => unawaited(_reload()),
                    ),
                  )
                else if (entries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _query.trim().isNotEmpty || _filters != null
                              ? 'אין כרטיסים שמתאימים לחיפוש'
                              : 'עוד לא שותפו כאן כרטיסים',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    sliver: SliverList.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int i) =>
                          _PoolRow(entry: entries[i]),
                    ),
                  ),
                if (_cards.isNotEmpty && (_loading || _hasMore))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : TextButton(
                                onPressed: () => unawaited(_loadMore()),
                                child: const Text('עוד כרטיסים'),
                              ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _first(String name) {
    final String n = name.trim();
    return n.isEmpty ? 'שדכן/ית' : n.split(RegExp(r'\s+')).first;
  }
}

class _EmptyNetwork extends StatelessWidget {
  const _EmptyNetwork({
    required this.title,
    required this.text,
    required this.button,
    required this.onPressed,
  });

  final String title;
  final String text;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.diversity_3_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              text,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(button)),
          ],
        ),
      ),
    );
  }
}

class _IncomingProposals extends StatelessWidget {
  const _IncomingProposals({required this.proposals});

  final List<IdeaProposal> proposals;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: HomePaperCard(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  proposals.length == 1
                      ? 'הצעת רעיון שממתינה לתשובה שלך'
                      : '${proposals.length} הצעות רעיון ממתינות לתשובה שלך',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final IdeaProposal p in proposals)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.lightbulb_outline_rounded),
                  title: Text('${p.candidateFirstName} ו${p.targetFirstName}'),
                  subtitle: Text('מאת ${p.fromName}'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => context.push('/network/proposals/${p.id}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PoolRow extends StatelessWidget {
  const _PoolRow({required this.entry});

  final SharedPoolEntry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SharedCard card = entry.primary;
    final Person person = card.person;
    return HomePaperCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            context.push('/network/card/${card.ownerUid}/${card.personId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SharedPhoto(
                ownerUid: card.ownerUid,
                path: card.photoPaths.firstOrNull,
                person: person,
                radius: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      person.fullName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.genderAccent(person.gender),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (sharedSummaryOf(person).isNotEmpty)
                      Text(
                        sharedSummaryOf(person),
                        style: theme.textTheme.bodySmall,
                      ),
                    if (entry.heldByMany)
                      InkWell(
                        onTap: () =>
                            NetworkActions.chooseHolder(context, entry),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'מופיע אצל ${entry.holders.length} שדכנים · בחירה למי לפנות',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      )
                    else
                      SourceLine(card: card, compact: true),
                    if (entry.similar.isNotEmpty)
                      Text(
                        'ייתכן שזה אותו אדם כמו כרטיס דרך '
                        '${entry.similar.first.ownerFirstName}',
                        style: theme.textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

/// One shared card, **view only**: photos, the card's details, "מה מחפש/ת"
/// and tags. No edit, no save, no share, no number — the two things it offers
/// both go through the matchmaker who holds it: an idea, or a chat.
class SharedCardScreen extends StatelessWidget {
  const SharedCardScreen({
    super.key,
    required this.ownerUid,
    required this.personId,
    this.inSheet = false,
    this.controller,
  });

  final String ownerUid;
  final String personId;

  /// Drawn inside a sheet over a chat: the same card, no page around it.
  final bool inSheet;
  final ScrollController? controller;

  /// Opens the card over whatever is on screen — a chat stays where it was.
  static Future<void> showSheet(
    BuildContext context, {
    required String ownerUid,
    required String personId,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 1,
      builder: (BuildContext context, ScrollController controller) =>
          SharedCardScreen(
            ownerUid: ownerUid,
            personId: personId,
            inSheet: true,
            controller: controller,
          ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<List<SharedCard>>(
      valueListenable: MatchmakerNetwork.cards,
      builder: (BuildContext context, List<SharedCard> cards, _) {
        final SharedCard? card = MatchmakerNetwork.cardOf(ownerUid, personId);
        if (card == null && !MatchmakerNetwork.isGone(ownerUid, personId)) {
          // Not read this session yet: one read of this one card.
          unawaited(MatchmakerNetwork.fetchCard(ownerUid, personId));
          const Widget wait = Center(child: CircularProgressIndicator());
          return inSheet ? wait : Scaffold(appBar: AppBar(), body: wait);
        }
        if (card == null) {
          const Widget gone = Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'השדכן/ית הסיר/ה את הגישה לכרטיס.',
                textAlign: TextAlign.center,
              ),
            ),
          );
          return inSheet ? gone : Scaffold(appBar: AppBar(), body: gone);
        }
        final List<SharedPoolEntry> pool = SharedPool.build(<SharedCard>[
          ...cards,
          ...MatchmakerNetwork.sentToMe.value,
        ]);
        final SharedPoolEntry? entry = pool
            .where((SharedPoolEntry e) => e.cards.contains(card))
            .firstOrNull;
        final Person person = card.person;
        final Widget body = ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            if (card.photoPaths.isNotEmpty)
              SizedBox(
                height: 320,
                child: PageView(
                  children: <Widget>[
                    for (final String path in card.photoPaths)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ColoredBox(
                            color: theme.colorScheme.surface,
                            child: FutureBuilder<File?>(
                              future: MatchmakerNetwork.photo(ownerUid, path),
                              // Already on the phone: no spinner flash.
                              initialData: MatchmakerNetwork.photoNow(
                                ownerUid,
                                path,
                              ),
                              builder: (BuildContext context, snap) {
                                final File? f = snap.data;
                                if (f == null) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                // Decoded at the width it is drawn, not as
                                // the whole camera frame.
                                return Image.file(
                                  f,
                                  fit: BoxFit.contain,
                                  cacheWidth:
                                      (MediaQuery.sizeOf(context).width *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .round(),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              person.fullName,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.genderAccent(person.gender),
              ),
            ),
            if (sharedSummaryOf(person).isNotEmpty)
              Text(sharedSummaryOf(person), style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
            if (entry == null || !entry.heldByMany)
              SourceLine(card: card)
            else
              InkWell(
                onTap: () => NetworkActions.chooseHolder(context, entry),
                child: Text(
                  'מופיע אצל ${entry.holders.length} שדכנים · בחירה למי לפנות',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            HomePaperCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  person.description ?? '',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
            if (_lookingLines(person).isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              HomePaperCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'מה {הוא מחפש|היא מחפשת}'.forGender(person.gender),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      for (final String line in _lookingLines(person))
                        Text('· $line', style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            ],
            if (person.tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final String tag in person.tags)
                    Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (entry != null && entry.similar.isNotEmpty) ...<Widget>[
              Text(
                'ייתכן שזה אותו אדם — כרטיס דומה:',
                style: theme.textTheme.titleSmall,
              ),
              for (final SharedCard other in entry.similar)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SharedPhoto(
                    ownerUid: other.ownerUid,
                    path: other.photoPaths.firstOrNull,
                    person: other.person,
                    radius: 18,
                  ),
                  title: Text(other.person.fullName),
                  subtitle: Text(
                    'דרך ${other.ownerName.isEmpty ? other.ownerFirstName : other.ownerName} · '
                    'לא אוחדו — אין זיהוי ודאי',
                  ),
                  onTap: () => SharedCardScreen.showSheet(
                    context,
                    ownerUid: other.ownerUid,
                    personId: other.personId,
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (entry != null && entry.heldByMany) ...<Widget>[
              Text(
                'הכרטיס נמצא אצל ${entry.holders.length} שדכנים',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final SharedCard holder in entry.holders)
                _HolderTile(card: holder),
            ] else
              _HolderActions(card: card),
            const SizedBox(height: 16),
            Text(
              'צפייה בלבד. אי אפשר לערוך, לשמור או לשתף את הכרטיס הלאה, '
              'וכל פנייה ל${person.firstName} עוברת דרך ${card.ownerFirstName}.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        );
        if (inSheet) return body;
        return Scaffold(
          appBar: AppBar(title: Text(person.fullName)),
          body: body,
        );
      },
    );
  }

  static List<String> _lookingLines(Person p) {
    final List<String> lines = <String>[];
    if (p.preferredMinAge != null || p.preferredMaxAge != null) {
      lines.add(
        'גיל ${p.preferredMinAge ?? ''}–${p.preferredMaxAge ?? ''}'.trim(),
      );
    }
    if (p.preferredMinHeightCm != null || p.preferredMaxHeightCm != null) {
      lines.add(
        'גובה ${p.preferredMinHeightCm ?? ''}–${p.preferredMaxHeightCm ?? ''}',
      );
    }
    if (p.preferredReligiousLevels.isNotEmpty) {
      lines.add(
        p.preferredReligiousLevels
            .map((ReligiousLevel l) => l.displayName)
            .join(', '),
      );
    }
    if (p.preferredRegions.isNotEmpty) {
      lines.add(p.preferredRegions.map((Region r) => r.displayName).join(', '));
    }
    if (p.preferredMaritalStatuses.isNotEmpty) {
      lines.add(
        p.preferredMaritalStatuses
            .map((MaritalStatus s) => s.displayName)
            .join(', '),
      );
    }
    return lines;
  }
}

class _HolderActions extends StatelessWidget {
  const _HolderActions({required this.card});

  final SharedCard card;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: () => NetworkActions.propose(context, card),
            icon: const Icon(Icons.lightbulb_outline_rounded),
            label: Text('הצעת רעיון ל${card.ownerFirstName}'),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => NetworkActions.chatWith(
            context,
            otherUid: card.ownerUid,
            otherName: card.ownerName,
            ref: ChatRef(
              kind: 'card',
              id: card.personId,
              ownerUid: card.ownerUid,
              label: card.person.fullName,
            ),
          ),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('צ\'אט'),
        ),
      ],
    );
  }
}

class _HolderTile extends StatelessWidget {
  const _HolderTile({required this.card});

  final SharedCard card;

  @override
  Widget build(BuildContext context) {
    return HomePaperCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'אצל ${card.ownerName.isEmpty ? card.ownerFirstName : card.ownerName}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _HolderActions(card: card),
          ],
        ),
      ),
    );
  }
}

/// One idea offered between two matchmakers: both cards side by side, the
/// note, and — for the side asked — "אישור" / "דחייה".
class ProposalScreen extends StatelessWidget {
  const ProposalScreen({
    super.key,
    required this.proposalId,
    this.inSheet = false,
    this.controller,
  });

  final String proposalId;

  /// Drawn inside a sheet over a chat.
  final bool inSheet;
  final ScrollController? controller;

  static Future<void> showSheet(BuildContext context, String proposalId) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (BuildContext context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 1,
          builder: (BuildContext context, ScrollController controller) =>
              ProposalScreen(
                proposalId: proposalId,
                inSheet: true,
                controller: controller,
              ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<List<IdeaProposal>>(
      valueListenable: MatchmakerNetwork.proposals,
      builder: (BuildContext context, _, _) {
        final IdeaProposal? p = MatchmakerNetwork.proposal(proposalId);
        final String? me = MatchmakerNetwork.uid;
        if (p == null || me == null) {
          unawaited(MatchmakerNetwork.start());
          const Widget wait = Center(child: CircularProgressIndicator());
          return inSheet
              ? wait
              : Scaffold(
                  appBar: AppBar(title: const Text('הצעת רעיון')),
                  body: wait,
                );
        }
        final bool incoming = p.isIncomingFor(me);
        final Person theirs = p.theirPersonFor(me);
        final Person? mine = context.watch<PersonRepository>().getById(
          p.myPersonIdFor(me),
        );
        final String other = p.otherNameOf(me);
        final List<String> theirPhotos = p.theirPhotoPathsFor(me);
        final SharedIdeaLink? link = SharedIdeas.links[p.id];
        final Widget body = ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              incoming
                  ? '$other מציע/ה רעיון לחבר/ה שלך'
                  : 'הצעת ל$other רעיון',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _MiniPerson(
                    person: mine ?? theirs,
                    caption: 'מהמאגר שלך',
                    avatar: mine == null
                        ? const CircleAvatar(radius: 34)
                        : PersonAvatar(person: mine, radius: 34),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 26),
                  child: Icon(
                    Icons.favorite_rounded,
                    color: AppColors.femaleAccent,
                  ),
                ),
                Expanded(
                  child: _MiniPerson(
                    person: theirs,
                    caption: 'מהמאגר של $other',
                    avatar: SharedPhoto(
                      ownerUid: p.otherOf(me),
                      path: theirPhotos.firstOrNull,
                      person: theirs,
                      radius: 34,
                    ),
                  ),
                ),
              ],
            ),
            if (p.note.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              HomePaperCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text('"${p.note.trim()}" — ${p.fromName}'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            HomePaperCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'הכרטיס של ${theirs.firstName}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(theirs.description ?? ''),
                    if (theirPhotos.length > 1) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          for (final String path in theirPhotos.skip(1))
                            SharedPhoto(
                              ownerUid: p.otherOf(me),
                              path: path,
                              person: theirs,
                              radius: 26,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ..._statusArea(context, p, me, incoming, link),
            const SizedBox(height: 8),
            if (!inSheet)
              OutlinedButton.icon(
                onPressed: () => NetworkActions.chatWith(
                  context,
                  otherUid: p.otherOf(me),
                  otherName: other,
                  ref: ChatRef(
                    kind: 'proposal',
                    id: p.id,
                    label: '${p.candidateFirstName} ו${p.targetFirstName}',
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text('צ\'אט עם $other'),
              ),
          ],
        );
        if (inSheet) return body;
        return Scaffold(
          appBar: AppBar(title: const Text('הצעת רעיון')),
          body: body,
        );
      },
    );
  }

  List<Widget> _statusArea(
    BuildContext context,
    IdeaProposal p,
    String me,
    bool incoming,
    SharedIdeaLink? link,
  ) {
    switch (p.status) {
      case IdeaProposalStatus.pending:
        if (incoming) {
          return <Widget>[
            FilledButton.icon(
              onPressed: () async {
                if (!OfflineGuard.allow(context)) return;
                final bool ok = await MatchmakerNetwork.answer(
                  p,
                  approve: true,
                );
                if (!context.mounted) return;
                AppNotice.show(
                  context,
                  ok
                      ? 'אישרת — הרעיון נפתח אצל שניכם, בסטטוס "רעיון".'
                      : 'לא הצלחנו לאשר. נסו שוב.',
                  isError: !ok,
                );
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('אישור'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                if (!OfflineGuard.allow(context)) return;
                await MatchmakerNetwork.answer(p, approve: false);
              },
              child: const Text('דחייה'),
            ),
          ];
        }
        return <Widget>[
          Text('ממתין לתשובה של ${p.toName}', textAlign: TextAlign.center),
          TextButton(
            onPressed: () => MatchmakerNetwork.withdraw(p),
            child: const Text('ביטול ההצעה'),
          ),
        ];
      case IdeaProposalStatus.approved:
        return <Widget>[
          const Text(
            'סיכמתם על הרעיון. הוא ייפתח אצל שניכם ב"הרעיונות שלי" '
            'ברגע שמחליטים לשאול את החברים.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              if (!OfflineGuard.allow(context)) return;
              final bool ok = await MatchmakerNetwork.open(p);
              if (!context.mounted) return;
              AppNotice.show(
                context,
                ok
                    ? 'הרעיון נפתח אצל שניכם ב"הרעיונות שלי"'
                    : 'לא הצלחנו לפתוח. נסו שוב.',
                isError: !ok,
              );
            },
            icon: const Icon(Icons.lightbulb_outline_rounded),
            label: const Text('פותחים — שואלים את שני הצדדים'),
          ),
        ];
      case IdeaProposalStatus.opened:
        final MatchStatus? partner = p.partnerStatusFor(me);
        return <Widget>[
          Text(
            'הרעיון פתוח אצל שניכם.'
            '${partner == null ? '' : ' אצל ${p.otherNameOf(me)}: ${partner.displayName}'}',
            textAlign: TextAlign.center,
          ),
          if (link != null)
            FilledButton.tonal(
              onPressed: () => context.push('/matches/${link.matchId}'),
              child: const Text('לרעיון ב"הרעיונות שלי"'),
            ),
        ];
      case IdeaProposalStatus.declined:
        return <Widget>[
          const Text('הרעיון לא נפתח.', textAlign: TextAlign.center),
        ];
      case IdeaProposalStatus.withdrawn:
        return <Widget>[
          const Text('ההצעה בוטלה.', textAlign: TextAlign.center),
        ];
    }
  }
}

/// The route of [SharingSettingsScreen] (what I share with each matchmaker),
/// kept here so the network screens can point at it without importing it.
abstract final class SharingSettingsRoute {
  static const String path = '/network/sharing';
}
