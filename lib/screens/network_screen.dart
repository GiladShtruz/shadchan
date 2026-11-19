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
import 'package:shadchan/services/matchmaker_connections.dart';
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
    return FutureBuilder<File?>(
      future: MatchmakerNetwork.photo(ownerUid, p),
      builder: (BuildContext context, AsyncSnapshot<File?> snap) {
        final File? file = snap.data;
        if (file == null) return fallback;
        return CircleAvatar(radius: radius, backgroundImage: FileImage(file));
      },
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
  }) async {
    if (!OfflineGuard.allow(context)) return;
    final String? id = await ChatService.openDirect(
      otherUid: otherUid,
      myName: _myName(context),
      theirName: otherName,
    );
    if (!context.mounted) return;
    if (id == null) {
      AppNotice.show(
        context,
        'לא הצלחנו לפתוח את הצ\'אט. אפשר לשוחח רק עם שדכנים מחוברים.',
        isError: true,
      );
      return;
    }
    await context.push('/chats/$id', extra: ref);
  }

  /// "הצעת רעיון": picks a friend from this matchmaker's own database for
  /// [target] and sends the idea to the matchmaker who holds [target]. Every
  /// step goes through that matchmaker — nobody contacts the single directly.
  static Future<void> propose(
    BuildContext context,
    SharedCard target, {
    Person? candidate,
  }) async {
    if (!OfflineGuard.allow(context)) return;
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
    if (chosen == null || !context.mounted) return;
    final Person mine = repo.getById(chosen.id) ?? chosen;
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final ShareEligibility eligibility = NetworkSharing.eligibilityOf(
      mine,
      accessTo: access.accessTo,
    );
    if (eligibility == ShareEligibility.awaitingConsent) {
      await _askConsent(context, mine);
      return;
    }
    if ((mine.description ?? '').trim().isEmpty) {
      AppNotice.show(
        context,
        'כדי להציע רעיון צריך כרטיס עם טקסט ל${mine.firstName}.',
        isError: true,
      );
      return;
    }
    final String? note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) =>
          _ProposeSheet(target: target, candidate: mine),
    );
    if (note == null || !context.mounted) return;
    final String? id = await MatchmakerNetwork.propose(
      target: target,
      candidate: mine,
      myName: _myName(context),
      note: note,
    );
    if (!context.mounted) return;
    if (id == null) {
      AppNotice.show(context, 'ההצעה לא נשלחה. נסו שוב.', isError: true);
      return;
    }
    AppNotice.show(
      context,
      'ההצעה נשלחה ל${target.ownerFirstName}. הרעיון ייפתח אצל שניכם אם יאשר/תאשר.',
    );
  }

  static Future<void> _askConsent(BuildContext context, Person person) async {
    final bool? ask = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('${person.firstName} מנהל/ת כרטיס אישי'),
        content: Text(
          '${person.firstName} צריך/ה לאשר באזור האישי שמותר לך להציג את הכרטיס '
          'גם לשדכנים שמחוברים אליך. אפשר לבקש ממנו/ה את האישור עכשיו.',
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
            'אם יאשר/תאשר, הרעיון ייפתח אצל שניכם וכל אחד ימשיך מול החבר/ה שלו.',
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

/// "המאגר המשותף" — the cards the connected matchmakers share, each person
/// once, with search and every filter of "המאגר שלי" plus the source.
///
/// With [forPersonId]: "התאמות מהשדכנים המחוברים" for one of this matchmaker's
/// friends — the pool narrowed by the app's own matching rules.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key, this.forPersonId});

  static const String route = '/network';

  final String? forPersonId;

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _source;
  PeopleFilterState? _filters;

  @override
  void initState() {
    super.initState();
    unawaited(MatchmakerNetwork.start());
    unawaited(ChatService.start());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
    };
    List<SharedPoolEntry> entries = SharedPool.build(
      MatchmakerNetwork.cards.value,
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
    final String q = _query.trim();
    return <SharedPoolEntry>[
      for (final SharedPoolEntry e in entries)
        if ((_source == null ||
                e.holders.any((SharedCard c) => c.ownerUid == _source)) &&
            (_filters == null || _filters!.matches(e.primary.person)) &&
            (q.isEmpty ||
                e.cards.any(
                  (SharedCard c) =>
                      c.person.fullName.contains(q) ||
                      (c.person.city ?? '').contains(q) ||
                      (c.person.description ?? '').contains(q) ||
                      c.person.tags.any((String t) => t.contains(q)),
                )))
          e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository repo = context.watch<PersonRepository>();
    final Person? source = widget.forPersonId == null
        ? null
        : repo.getById(widget.forPersonId!);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          source == null
              ? 'המאגר המשותף'
              : 'התאמות ל${source.firstName} מהשדכנים המחוברים',
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
          IconButton(
            tooltip: 'שיתוף הכרטיסים שלי',
            onPressed: () => context.push(SharingSettingsRoute.path),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          MatchmakerNetwork.cards,
          MatchmakerNetwork.proposals,
          MatchmakerNetwork.loaded,
          MatchmakerConnections.connections,
        ]),
        builder: (BuildContext context, _) {
          final Map<String, String> connected =
              MatchmakerNetwork.connectedNames;
          if (connected.isEmpty) {
            return _EmptyNetwork(
              title: 'עוד אין שדכנים מחוברים',
              text:
                  'המאגר המשותף מורכב מהכרטיסים שהשדכנים שמחוברים אליך בחרו לשתף. '
                  'זו לא רשת ציבורית — רק שדכנים מאנשי הקשר שלך, שאישרו חיבור.',
              button: 'לשדכנים שאני מכיר',
              onPressed: () => context.push('/known-matchmakers'),
            );
          }
          final List<SharedPoolEntry> entries = _entries(repo);
          final Map<String, int> bySource = <String, int>{};
          for (final SharedCard c in MatchmakerNetwork.cards.value) {
            bySource[c.ownerUid] = (bySource[c.ownerUid] ?? 0) + 1;
          }
          final List<IdeaProposal> incoming = MatchmakerNetwork.incomingPending;
          return CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'כרטיסים ש־${connected.length} שדכנים מחוברים שיתפו איתך · '
                    'צפייה בלבד, כל פנייה עוברת דרך השדכן/ית',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              if (incoming.isNotEmpty)
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
                          onChanged: (String v) => setState(() => _query = v),
                          decoration: const InputDecoration(
                            hintText: 'חיפוש בשם, עיר, תגית או טקסט',
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
                          onSelected: (_) => setState(() => _source = null),
                        ),
                      ),
                      for (final MapEntry<String, String> c
                          in connected.entries)
                        if ((bySource[c.key] ?? 0) > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(
                                'מהמאגר של ${_first(c.value)} · ${bySource[c.key]}',
                              ),
                              selected: _source == c.key,
                              onSelected: (bool on) =>
                                  setState(() => _source = on ? c.key : null),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              if (!MatchmakerNetwork.loaded.value)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (MatchmakerNetwork.cards.value.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyNetwork(
                    title: 'עוד לא שותפו כרטיסים',
                    text:
                        'השדכנים המחוברים אליך עוד לא בחרו כרטיסים לשתף. '
                        'אפשר להתחיל ולשתף את שלך — זה מה שמגדיל את המאגר לכולם.',
                    button: 'שיתוף הכרטיסים שלי',
                    onPressed: () => context.push(SharingSettingsRoute.path),
                  ),
                )
              else if (entries.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('אין כרטיסים שמתאימים לחיפוש')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  sliver: SliverList.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int i) =>
                        _PoolRow(entry: entries[i]),
                  ),
                ),
            ],
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
                    const SizedBox(height: 2),
                    Text(
                      entry.sourceLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (!entry.certain)
                      Text(
                        'ייתכן שזה אותו אדם אצל כמה שדכנים',
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
  });

  final String ownerUid;
  final String personId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<List<SharedCard>>(
      valueListenable: MatchmakerNetwork.cards,
      builder: (BuildContext context, List<SharedCard> cards, _) {
        final SharedCard? card = MatchmakerNetwork.cardOf(ownerUid, personId);
        if (card == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'הכרטיס כבר לא משותף איתך.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final List<SharedPoolEntry> pool = SharedPool.build(cards);
        final SharedPoolEntry? entry = pool
            .where((SharedPoolEntry e) => e.cards.contains(card))
            .firstOrNull;
        final Person person = card.person;
        return Scaffold(
          appBar: AppBar(title: Text(person.fullName)),
          body: ListView(
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
                                builder: (BuildContext context, snap) {
                                  final File? f = snap.data;
                                  if (f == null) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }
                                  return Image.file(f, fit: BoxFit.contain);
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
              Text(
                'מהמאגר של ${card.ownerName.isEmpty ? card.ownerFirstName : card.ownerName}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
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
              if (entry != null && entry.heldByMany) ...<Widget>[
                Text(
                  entry.certain
                      ? 'הכרטיס נמצא אצל כמה שדכנים'
                      : 'ייתכן שאלה כרטיסים של אותו אדם אצל שדכנים שונים',
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
          ),
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
  const ProposalScreen({super.key, required this.proposalId});

  final String proposalId;

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
          return Scaffold(
            appBar: AppBar(title: const Text('הצעת רעיון')),
            body: const Center(child: CircularProgressIndicator()),
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
        return Scaffold(
          appBar: AppBar(title: const Text('הצעת רעיון')),
          body: ListView(
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
          ),
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
                      ? 'הרעיון נפתח אצל שניכם ב"הרעיונות שלי"'
                      : 'לא הצלחנו לאשר. נסו שוב.',
                  isError: !ok,
                );
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('אישור — לפתוח את הרעיון'),
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

/// The route of [SharingSettingsScreen], kept here so the network screens can
/// point at it without importing the settings file.
abstract final class SharingSettingsRoute {
  static const String path = '/network/sharing';
}
