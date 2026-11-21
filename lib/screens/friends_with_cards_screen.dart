import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadchan/screens/known_matchmakers_screen.dart' show NewMark;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/card_link_dialog.dart';
import 'package:shadchan/dialogs/invite_card_friends_sheet.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';
import 'package:shadchan/utils/person_navigation.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_invite.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/personal_home_sections.dart';

/// Where a matchmaker stands with one friend's personal card.
///
/// Ordered from the furthest along: [sees] and [awaitingLink] are the friends
/// who gave access ("אישרו לי גישה"), [pending] and [requestable] the ones who
/// have not yet ("עדיין לא אישרו גישה").
enum FriendCardState {
  requestable,
  pending,

  /// Access was given and the friend is already in the database by hand: the
  /// card waits for the matchmaker's "סנכרון עם הכרטיס הקיים".
  awaitingLink,
  sees,
}

/// One friend of the matchmaker who keeps a personal card.
class FriendWithCard {
  const FriendWithCard({
    required this.ownerUid,
    required this.name,
    required this.state,
    this.phoneHash,
    this.person,
    this.cardCreatedAt,
  });
  final String ownerUid;
  final String name;
  final FriendCardState state;
  final String? phoneHash;

  /// When the friend's card was announced to this matchmaker, when known
  /// (the "cardCreated" notice).
  final DateTime? cardCreatedAt;

  /// A card made in the last week leads the home screen's three faces.
  bool isNew(DateTime now) {
    final DateTime? at = cardCreatedAt;
    return at != null && now.difference(at) < const Duration(days: 7);
  }

  /// Their record in the matchmaker's database, when there is one.
  final Person? person;

  /// Whether the friend gave this matchmaker access to the card.
  bool get approved =>
      state == FriendCardState.sees || state == FriendCardState.awaitingLink;
}

abstract final class FriendsWithCards {
  /// Every friend with a card the matchmaker can know about: the friends the
  /// server found both ways in the address books, the database records that
  /// already follow a card, and the friends whose new card was announced.
  /// A card whose owner hid it from this matchmaker is left out — to them
  /// it is no card at all.
  static List<FriendWithCard> build({
    required CardAccessProvider access,
    required PersonRepository people,
    InboxProvider? inbox,
  }) {
    final Map<String, FriendWithCard> byOwner = <String, FriendWithCard>{};
    void add(String ownerUid, String name, String? hash, Person? person) {
      if (ownerUid.isEmpty || ownerUid == access.uid) return;
      final CardAccess? row = access.accessTo(ownerUid);
      if (row?.status == CardAccessStatus.blocked) return;
      final Person? record =
          person ??
          people.findByCardOwner(ownerUid) ??
          access.awaitingLinkFor(ownerUid) ??
          (hash == null ? null : people.findByPhoneHash(hash));
      final Person? awaiting = access.awaitingLinkFor(ownerUid);
      final FriendCardState state = row?.canReadCard == true
          ? (awaiting != null
                ? FriendCardState.awaitingLink
                : FriendCardState.sees)
          : row != null &&
                (row.status == CardAccessStatus.pending || row.cardRequested)
          ? FriendCardState.pending
          : FriendCardState.requestable;
      final FriendWithCard? known = byOwner[ownerUid];
      byOwner[ownerUid] = FriendWithCard(
        ownerUid: ownerUid,
        name: record?.fullName.trim().isNotEmpty == true
            ? record!.fullName
            : (known?.name ?? name),
        state: state,
        phoneHash:
            hash ?? known?.phoneHash ?? PhoneIdentity.hash(record?.phone),
        person: record ?? known?.person,
      );
    }

    for (final CardHelper friend in access.mutualFriends) {
      add(
        friend.uid,
        ContactHashUpload.nameFor(friend.phoneHash) ?? friend.name,
        friend.phoneHash,
        null,
      );
    }
    for (final Person person in people.getAll()) {
      final String? owner = person.cardOwnerUid;
      if (owner != null && !person.hidden) {
        add(owner, person.fullName, PhoneIdentity.hash(person.phone), person);
      }
    }
    for (final MapEntry<String, CardAccess> entry
        in access.matchmakerRows.entries) {
      add(entry.key, entry.value.ownerName, entry.value.ownerPhoneHash, null);
    }
    if (inbox != null) {
      for (final InboxItem item in inbox.items) {
        final String? owner = item.ownerUid;
        final String? hash = item.ownerPhoneHash;
        if (item.kind != 'cardCreated' || owner == null || hash == null) {
          continue;
        }
        final Person? record = people.findByPhoneHash(hash);
        if (record != null) add(owner, record.fullName, hash, record);
      }
    }
    final Map<String, DateTime> created = <String, DateTime>{};
    for (final InboxItem item in inbox?.items ?? const <InboxItem>[]) {
      final String? owner = item.ownerUid;
      final DateTime? at = item.createdAt;
      if (item.kind == 'cardCreated' && owner != null && at != null) {
        final DateTime? known = created[owner];
        if (known == null || at.isAfter(known)) created[owner] = at;
      }
    }
    final List<FriendWithCard> list =
        <FriendWithCard>[
          for (final FriendWithCard f in byOwner.values)
            created[f.ownerUid] == null
                ? f
                : FriendWithCard(
                    ownerUid: f.ownerUid,
                    name: f.name,
                    state: f.state,
                    phoneHash: f.phoneHash,
                    person: f.person,
                    cardCreatedAt: created[f.ownerUid],
                  ),
        ]..sort((FriendWithCard a, FriendWithCard b) {
          final int byState = b.state.index.compareTo(a.state.index);
          return byState != 0 ? byState : a.name.compareTo(b.name);
        });
    return list;
  }
}

/// "חברים שהוסיפו כרטיס אישי" — the matchmaker's friends who keep a personal
/// card of their own, in two groups: the ones who gave access, drawn exactly
/// like any other friend in the database (one database, whoever keeps the
/// card), and the ones who have not yet, with nothing but a name, the face the
/// matchmaker already had, and "בקשת גישה". Reached from בית, from המאגר שלי
/// and from a new-card notice.
///
/// With [requestOwnerUid] (a notice about a friend whose card this
/// matchmaker cannot read yet) the access request opens by itself.
class FriendsWithCardsScreen extends StatefulWidget {
  const FriendsWithCardsScreen({
    super.key,
    this.requestOwnerUid,
    this.requestPhoneHash,
  });

  static const String route = '/card-friends';

  /// Short enough for one line in the bar.
  static const String title = 'חברים שמנהלים כרטיס אישי';

  /// The route that opens the screen straight onto [ownerUid]'s request.
  static String requestRoute(String ownerUid, {String? phoneHash}) => Uri(
    path: route,
    queryParameters: <String, String>{
      'request': ownerUid,
      if (phoneHash != null && phoneHash.isNotEmpty) 'h': phoneHash,
    },
  ).toString();

  final String? requestOwnerUid;
  final String? requestPhoneHash;

  @override
  State<FriendsWithCardsScreen> createState() => _FriendsWithCardsScreenState();
}

class _FriendsWithCardsScreenState extends State<FriendsWithCardsScreen> {
  bool _requestOpened = false;

  @override
  void initState() {
    super.initState();
    if (widget.requestOwnerUid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRequest());
    }
  }

  /// The request a notice asked for — or, when access already came, the
  /// friend's own profile; or the sync question when the card is waiting on
  /// the friend already in the database.
  Future<void> _openRequest() async {
    final String? owner = widget.requestOwnerUid;
    if (owner == null || _requestOpened || !mounted) return;
    _requestOpened = true;
    final CardAccessProvider access = context.read<CardAccessProvider>();
    await access.ensureConnected();
    if (!mounted) return;
    final FriendWithCard? friend = _find(owner);
    final Person? awaiting = access.awaitingLinkFor(owner);
    if (awaiting != null) {
      await CardLinkDialog.confirmAndLink(
        context,
        ownerUid: owner,
        person: awaiting,
      );
      return;
    }
    if (friend == null) {
      final String? hash = widget.requestPhoneHash;
      if (hash == null) return;
      final Person? record = context.read<PersonRepository>().findByPhoneHash(
        hash,
      );
      if (record == null) return;
      await _request(owner, hash, record);
      return;
    }
    switch (friend.state) {
      case FriendCardState.sees:
        final Person? person = friend.person;
        if (person != null) openPersonProfile(context, person.id);
      case FriendCardState.awaitingLink:
        break;
      case FriendCardState.pending:
        AppNotice.show(context, 'הבקשה כבר נשלחה וממתינה לאישור');
      case FriendCardState.requestable:
        final String? hash = friend.phoneHash ?? widget.requestPhoneHash;
        if (hash != null) {
          await _request(owner, hash, friend.person ?? _standIn(friend));
        }
    }
  }

  FriendWithCard? _find(String owner) {
    for (final FriendWithCard f in FriendsWithCards.build(
      access: context.read<CardAccessProvider>(),
      people: context.read<PersonRepository>(),
      inbox: _maybeRead<InboxProvider>(context),
    )) {
      if (f.ownerUid == owner) return f;
    }
    return null;
  }

  Future<void> _request(String owner, String hash, Person person) =>
      CardInviteFlow.requestAccess(
        context,
        person,
        ownerUid: owner,
        ownerPhoneHash: hash,
      );

  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final PersonRepository people = context.watch<PersonRepository>();
    final InboxProvider? inbox = maybeWatch<InboxProvider>(context);
    final List<FriendWithCard> friends = FriendsWithCards.build(
      access: access,
      people: people,
      inbox: inbox,
    );
    final DateTime now = DateTime.now();
    final List<FriendWithCard> approved = friends
        .where((FriendWithCard f) => f.approved)
        .toList();
    // A card made this week leads, newest first, then by name.
    final List<FriendWithCard> toAsk =
        friends
            .where((FriendWithCard f) => f.state == FriendCardState.requestable)
            .toList()
          ..sort((FriendWithCard a, FriendWithCard b) {
            final bool an = a.isNew(now), bn = b.isNew(now);
            if (an != bn) return an ? -1 : 1;
            if (an && bn) return b.cardCreatedAt!.compareTo(a.cardCreatedAt!);
            return a.name.compareTo(b.name);
          });
    final List<FriendWithCard> pending = friends
        .where((FriendWithCard f) => f.state == FriendCardState.pending)
        .toList();
    final ThemeData theme = Theme.of(context);

    // Two tabs — "אישרו לי גישה" first and open by default, because that is
    // the list a matchmaker works from; "בקשות גישה" holds asking (on top)
    // and waiting (quietly, at the foot).
    final int initialTab = widget.requestOwnerUid != null ? 1 : 0;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(FriendsWithCardsScreen.title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(112),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _search,
                      onChanged: (String v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'חיפוש בכל המאגר',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'ניקוי',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
                TabBar(
                  isScrollable: false,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  tabs: <Widget>[
                    _CountTab('אישרו לי גישה', approved.length),
                    _CountTab('בקשות גישה', toAsk.length),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: _query.trim().isNotEmpty
            ? _SearchResults(query: _query.trim(), friends: friends)
            : TabBarView(
                children: <Widget>[
                  _ApprovedTab(friends: approved),
                  _RequestsTab(
                    toAsk: toAsk,
                    pending: pending,
                    now: now,
                    emptyText: friends.isEmpty && !access.helpersLoaded
                        ? 'הרשימה תופיע לאחר החיבור לחשבון.'
                        : 'אין כרגע חברים חדשים לבקש מהם גישה.',
                  ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: OutlinedButton.icon(
              onPressed: () => InviteCardFriendsSheet.show(context),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
              label: Text(
                'להזמין חברים להוסיף כרטיס אישי',
                style: theme.textTheme.labelLarge,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tab's name and how many are in it.
class _CountTab extends StatelessWidget {
  const _CountTab(this.label, this.count);
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 40,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          count > 0 ? '$label · $count' : label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// "אישרו לי גישה": one large card per friend, built only as it scrolls in.
class _ApprovedTab extends StatelessWidget {
  const _ApprovedTab({required this.friends});
  final List<FriendWithCard> friends;

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) {
      return const _EmptyTab(
        'עוד אין חברים שאישרו לך גישה לכרטיס שלהם.\n'
        'בלשונית "בקשות גישה" אפשר לבקש.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: friends.length,
      // Each card draws its own photos: keep a little ahead, never everything.
      cacheExtent: 600,
      itemBuilder: (BuildContext context, int index) {
        final FriendWithCard friend = friends[index];
        return Padding(
          key: ValueKey<String>(friend.ownerUid),
          padding: const EdgeInsets.only(bottom: 14),
          child: RepaintBoundary(child: _ApprovedRow(friend: friend)),
        );
      },
    );
  }
}

/// "בקשות גישה": on top, the friends who keep a card and have not been
/// asked yet — the ones who joined this week first, each with a small "חדש"
/// — every row with "בקש גישה". At the foot, quiet and grey, those already
/// asked who have not answered: "ממתין לאישור", and nothing to press. A
/// friend who has not approved may well have chosen not to; the app does not
/// nudge them again and again, and does not crowd the matchmaker with them.
class _RequestsTab extends StatelessWidget {
  const _RequestsTab({
    required this.toAsk,
    required this.pending,
    required this.now,
    required this.emptyText,
  });
  final List<FriendWithCard> toAsk;
  final List<FriendWithCard> pending;
  final DateTime now;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (toAsk.isEmpty && pending.isEmpty) return _EmptyTab(emptyText);
    final ThemeData theme = Theme.of(context);
    final bool hasPendingHeader = pending.isNotEmpty;
    // Rows: [intro] toAsk… [pending header] pending…
    final int count =
        1 + toAsk.length + (hasPendingHeader ? 1 + pending.length : 0);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 24),
      itemCount: count,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Text(
              toAsk.isEmpty
                  ? 'אין כרגע חברים חדשים לבקש מהם גישה.'
                  : 'עם גישה, הכרטיס שלהם מתעדכן אצלך במאגר מעצמו.',
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        final int i = index - 1;
        if (i < toAsk.length) {
          final FriendWithCard friend = toAsk[i];
          return _WaitingRow(
            key: ValueKey<String>(friend.ownerUid),
            friend: friend,
            isNew: friend.isNew(now),
          );
        }
        final int k = i - toAsk.length;
        if (k == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 22, 8, 4),
            child: Text(
              'ממתינים לאישור',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.mutedInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }
        final FriendWithCard friend = pending[k - 1];
        return _PendingRow(
          key: ValueKey<String>(friend.ownerUid),
          friend: friend,
        );
      },
    );
  }
}

/// One friend already asked: grey and quiet, no button.
class _PendingRow extends StatelessWidget {
  const _PendingRow({super.key, required this.friend});
  final FriendWithCard friend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Person? person = friend.person;
    return Opacity(
      opacity: 0.6,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: ExcludeSemantics(
          child: IgnorePointer(
            child: person != null
                ? PersonAvatar(person: person, radius: 18)
                : const _InitialAvatar(radius: 18),
          ),
        ),
        title: Text(
          friend.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.mutedInk,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Text(
          'ממתין לאישור',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.mutedInk,
          ),
        ),
      ),
    );
  }
}

/// Searching from this page reaches the whole database: a friend who keeps a
/// card shows where they stand, and one who does not is offered an
/// invitation to add one.
class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query, required this.friends});
  final String query;
  final List<FriendWithCard> friends;

  @override
  Widget build(BuildContext context) {
    final PersonRepository people = context.watch<PersonRepository>();
    final String q = query.toLowerCase();
    final Map<String, FriendWithCard> byPerson = <String, FriendWithCard>{
      for (final FriendWithCard f in friends)
        if (f.person != null) f.person!.id: f,
    };
    final List<Person> hits = people
        .getAll()
        .where(
          (Person p) =>
              !p.hidden &&
              (p.fullName.toLowerCase().contains(q) ||
                  (p.phone ?? '').contains(q)),
        )
        .take(80)
        .toList();
    // Friends with a card who are not (yet) in the database are found by
    // the name the card carries.
    final List<FriendWithCard> outside = friends
        .where(
          (FriendWithCard f) =>
              f.person == null && f.name.toLowerCase().contains(q),
        )
        .toList();
    if (hits.isEmpty && outside.isEmpty) {
      return const _EmptyTab('לא נמצאו חברים בשם הזה במאגר.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      children: <Widget>[
        for (final FriendWithCard f in outside) _searchRowFor(f),
        for (final Person p in hits)
          byPerson[p.id] != null
              ? _searchRowFor(byPerson[p.id]!)
              : _InviteRow(key: ValueKey<String>(p.id), person: p),
      ],
    );
  }

  Widget _searchRowFor(FriendWithCard f) => switch (f.state) {
    FriendCardState.sees || FriendCardState.awaitingLink => Padding(
      key: ValueKey<String>('s-${f.ownerUid}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: _ApprovedRow(friend: f),
    ),
    FriendCardState.pending => _PendingRow(
      key: ValueKey<String>('s-${f.ownerUid}'),
      friend: f,
    ),
    FriendCardState.requestable => _WaitingRow(
      key: ValueKey<String>('s-${f.ownerUid}'),
      friend: f,
    ),
  };
}

/// A friend in the database who does not keep a personal card: one line and
/// an invitation to add one.
class _InviteRow extends StatelessWidget {
  const _InviteRow({super.key, required this.person});
  final Person person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: PersonAvatar(person: person, radius: 20),
      title: Text(
        person.fullName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        '{לא מנהל|לא מנהלת} כרטיס אישי'.forGender(
          person.gender == Gender.female ? Gender.female : Gender.male,
        ),
      ),
      onTap: () => openPersonProfile(context, person.id),
      trailing: TextButton(
        onPressed: () => CardInviteFlow.invite(context, person),
        child: const Text('הזמנה להוסיף כרטיס'),
      ),
    );
  }
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

/// A friend who is not in the database, as far as a request needs: the name
/// the request and its WhatsApp line speak. Never saved.
Person _standIn(FriendWithCard friend) {
  final List<String> parts = friend.name.trim().split(RegExp(r'\s+'));
  final DateTime now = DateTime.now();
  return Person(
    id: 'card-friend-${friend.ownerUid}',
    firstName: parts.isEmpty ? '' : parts.first,
    lastName: parts.length > 1 ? parts.skip(1).join(' ') : '',
    gender: Gender.unknown,
    createdAt: now,
    updatedAt: now,
  );
}

/// A friend who gave access, as the large card: a real photo with paging
/// between the photos, the name, age · city, when the card last moved, how
/// many matches the database has for them, and their open ideas (or "פתיחת
/// רעיון"). The card opens the full profile. While the card waits for the
/// matchmaker's yes on a friend kept by hand, it says so and asks.
class _ApprovedRow extends StatelessWidget {
  const _ApprovedRow({required this.friend});
  final FriendWithCard friend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Person? person = friend.person;
    if (person == null) {
      // Access came a moment ago; the card is still on its way down.
      return ListTile(
        leading: const _InitialAvatar(),
        title: Text(friend.name),
        subtitle: const Text('הכרטיס נטען…'),
      );
    }
    final bool awaiting = friend.state == FriendCardState.awaitingLink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (awaiting)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '{הוסיף|הוסיפה} כרטיס אישי · עוד לא מסונכרן עם הכרטיס הקיים'
                        .forGender(
                          person.gender == Gender.female
                              ? Gender.female
                              : Gender.male,
                        ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => CardLinkDialog.confirmAndLink(
                    context,
                    ownerUid: friend.ownerUid,
                    person: person,
                  ),
                  child: const Text('סנכרון עם הכרטיס הקיים'),
                ),
              ],
            ),
          ),
        _BigFriendCard(person: person, ownerUid: friend.ownerUid),
      ],
    );
  }
}

class _BigFriendCard extends StatefulWidget {
  const _BigFriendCard({required this.person, required this.ownerUid});
  final Person person;
  final String ownerUid;

  static const double photoHeight = 300;

  @override
  State<_BigFriendCard> createState() => _BigFriendCardState();
}

class _BigFriendCardState extends State<_BigFriendCard> {
  int _page = 0;

  /// Counted once per person and database revision: the match count walks
  /// the database, and a card scrolled past and back must not walk it again.
  static final Map<String, int> _matchCounts = <String, int>{};
  static int _countsRevision = -1;

  int _matchCount(PersonRepository people) {
    final int revision = people.revision;
    if (revision != _countsRevision) {
      _matchCounts.clear();
      _countsRevision = revision;
    }
    return _matchCounts.putIfAbsent(widget.person.id, () {
      int n = 0;
      for (final Person candidate in people.getAll()) {
        if (MatchSuggestionUtils.matchesBasicPreferences(
          source: widget.person,
          candidate: candidate,
        )) {
          n++;
        }
      }
      return n;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Person person = widget.person;
    final PersonRepository people = context.watch<PersonRepository>();
    final MatchRepository matches = context.watch<MatchRepository>();
    final List<String> photos = <String>[
      for (final String p in person.photosPaths)
        if (p.trim().isNotEmpty && PersonAvatar.hasFile(p)) p,
    ];
    final Color accent = AppColors.genderAccent(person.gender, dark: dark);
    final int open = matches
        .getByPersonId(person.id)
        .where((MatchIdea m) => !m.status.isArchived)
        .length;
    final int matchCount = _matchCount(people);
    final List<String> facts = <String>[
      if (person.age != null) 'גיל ${person.age}',
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ];
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    final double width = MediaQuery.sizeOf(context).width;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openPersonProfile(context, person.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: _BigFriendCard.photoHeight,
              child: photos.isEmpty
                  ? ColoredBox(
                      color: AppColors.genderSurface(person.gender, dark: dark),
                      child: Center(
                        child: PersonAvatar(person: person, radius: 56),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        PageView.builder(
                          itemCount: photos.length,
                          onPageChanged: (int i) => setState(() => _page = i),
                          itemBuilder: (BuildContext context, int i) => Image(
                            // Decoded at the width it is drawn.
                            image: ResizeImage(
                              FileImage(File(photos[i])),
                              width: (width * ratio).round(),
                              policy: ResizeImagePolicy.fit,
                            ),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: AppColors.genderSurface(
                                person.gender,
                                dark: dark,
                              ),
                            ),
                          ),
                        ),
                        if (photos.length > 1)
                          PositionedDirectional(
                            bottom: 10,
                            start: 0,
                            end: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                for (int i = 0; i < photos.length; i++)
                                  Container(
                                    width: i == _page ? 16 : 7,
                                    height: 7,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 2.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: i == _page ? 0.95 : 0.6,
                                      ),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            Container(height: 3, color: accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    person.fullName,
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    'עודכן לאחרונה ${AppDateUtils.timeAgoShort(person.updatedAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              openSuggestionsFor(context, person.id),
                          icon: const Icon(Icons.favorite_border, size: 18),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              matchCount == 1
                                  ? 'התאמה אחת'
                                  : '$matchCount התאמות',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: open > 0
                            ? FilledButton.tonalIcon(
                                onPressed: () =>
                                    openPersonProfile(context, person.id),
                                icon: const Icon(
                                  Icons.lightbulb_outline_rounded,
                                  size: 18,
                                ),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    open == 1
                                        ? 'רעיון פתוח אחד'
                                        : '$open רעיונות פתוחים',
                                  ),
                                ),
                              )
                            : FilledButton.tonalIcon(
                                onPressed: () =>
                                    openSuggestionsFor(context, person.id),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('פתיחת רעיון'),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A friend who keeps a card and has not given access: a name, the face the
/// matchmaker already had for them (if any), and "בקשת גישה". The row does
/// not open, and the picture is not a way into anything — nothing here can
/// be viewed, saved, shared or forwarded until the friend says yes.
class _WaitingRow extends StatelessWidget {
  const _WaitingRow({super.key, required this.friend, this.isNew = false});
  final FriendWithCard friend;

  /// Joined this week: a small "חדש" beside the name.
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final bool busy = access.isBusy('request:${friend.ownerUid}');
    final Person? person = friend.person;
    final Widget action = switch (friend.state) {
      FriendCardState.pending => Text(
        'ממתין לאישור',
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      _ =>
        busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: friend.phoneHash == null
                    ? null
                    : () => CardInviteFlow.requestAccess(
                        context,
                        person ?? _standIn(friend),
                        ownerUid: friend.ownerUid,
                        ownerPhoneHash: friend.phoneHash!,
                      ),
                child: Text('{בקש|בקשי} גישה'.forGender(context.userGender)),
              ),
    };
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
      child: Row(
        children: <Widget>[
          // Drawn, never opened: no viewer, no long press, no share.
          ExcludeSemantics(
            child: IgnorePointer(
              child: person != null
                  ? PersonAvatar(person: person, radius: 22)
                  : const _InitialAvatar(),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              friend.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (isNew) ...<Widget>[const SizedBox(width: 6), const NewMark()],
          const Spacer(),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }
}

/// A friend with no photo here: a plain flat figure of a person.
class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({this.radius = 22});
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryLight,
      child: Icon(
        Icons.person_rounded,
        size: radius * 1.3,
        color: AppColors.white,
      ),
    );
  }
}

/// "חברים שמנהלים כרטיס אישי בשדכן" — the way into [FriendsWithCardsScreen]
/// from המאגר שלי: a clear tile, not a plain row, because asking these
/// friends for access is how their cards start updating themselves in the
/// database.
class FriendsWithCardsLink extends StatelessWidget {
  const FriendsWithCardsLink({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;
    return Material(
      color: dark ? AppColors.surfaceDm : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(FriendsWithCardsScreen.route),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ink.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ink.withValues(alpha: dark ? 0.22 : 0.12),
                ),
                child: Icon(Icons.badge_outlined, size: 22, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'חברים שמנהלים כרטיס אישי בשדכן',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'בקשת גישה, והכרטיס שלהם יתעדכן אצלך מעצמו',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}
