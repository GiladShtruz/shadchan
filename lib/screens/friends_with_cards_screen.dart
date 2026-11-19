import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/card_link_dialog.dart';
import 'package:shadchan/dialogs/invite_card_friends_sheet.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/person_navigation.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_invite.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';
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
    // Two lists, never one: the friends still to ask — a card made this week
    // leading, newest first — and the requests already sent and waiting for
    // the friend's yes.
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
    return Scaffold(
      appBar: AppBar(title: const Text(FriendsWithCardsScreen.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Text(
              'עם גישה, הכרטיס שלהם מתעדכן אצלך במאגר מעצמו.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: OutlinedButton.icon(
              onPressed: () => InviteCardFriendsSheet.show(context),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
              label: const Text('להזמין חברים להוסיף כרטיס אישי'),
            ),
          ),
          if (friends.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                access.helpersLoaded
                    ? 'עוד לא מצאנו חברים שלך שהוסיפו כרטיס אישי.'
                    : 'הרשימה תופיע לאחר החיבור לחשבון.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (toAsk.isNotEmpty) ...<Widget>[
            const _GroupTitle('בקשות גישה חדשות'),
            for (final FriendWithCard friend in toAsk)
              friend.isNew(now)
                  ? _NewCardRow(friend: friend)
                  : _WaitingRow(friend: friend),
          ],
          if (pending.isNotEmpty) ...<Widget>[
            const _GroupTitle('ממתינים לאישור שלי'),
            for (final FriendWithCard friend in pending)
              _WaitingRow(friend: friend),
          ],
          if (approved.isNotEmpty) ...<Widget>[
            const _GroupTitle('אישרו לי גישה'),
            for (final FriendWithCard friend in approved)
              _ApprovedRow(friend: friend),
          ],
        ],
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

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 18, 8, 6),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// A friend who gave access: the same row as any friend in המאגר שלי, the
/// whole card and every photo one tap away. While the card waits for the
/// matchmaker's yes on a friend kept by hand, the row says so and asks.
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
        leading: _InitialAvatar(name: friend.name),
        title: Text(friend.name),
        subtitle: const Text('הכרטיס נטען…'),
      );
    }
    final bool awaiting = friend.state == FriendCardState.awaitingLink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PersonListCard(
          person: person,
          heroEnabled: false,
          onTap: () => openPersonProfile(context, person.id),
          onToggleFavorite: () =>
              context.read<PersonRepository>().toggleFavorite(person.id),
          onOpenWhatsApp: () => WhatsAppUtils.openChat(person),
          keepWhatsAppSlot: true,
        ),
        if (awaiting)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
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
      ],
    );
  }
}

/// A friend who keeps a card and has not given access: a name, the face the
/// matchmaker already had for them (if any), and "בקשת גישה". The row does
/// not open, and the picture is not a way into anything — nothing here can
/// be viewed, saved, shared or forwarded until the friend says yes.
class _WaitingRow extends StatelessWidget {
  const _WaitingRow({required this.friend});
  final FriendWithCard friend;

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
                child: const Text('בקשת גישה'),
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
                  : _InitialAvatar(name: friend.name),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              friend.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          action,
        ],
      ),
    );
  }
}

/// A friend whose card was made in the last week, and who has not been asked
/// yet: drawn ahead of everything, on a warm wash, as one sentence —
/// "חדש! משה הוסיף כרטיס לשדכן · בקש גישה".
class _NewCardRow extends StatelessWidget {
  const _NewCardRow({required this.friend});
  final FriendWithCard friend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color warm = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final bool busy = access.isBusy('request:${friend.ownerUid}');
    final Person? person = friend.person;
    final String first = friend.name.trim().split(RegExp(r'\s+')).first;
    final String added = switch (person?.gender) {
      Gender.female => 'הוסיפה',
      Gender.male => 'הוסיף',
      _ => 'הוסיף/ה',
    };
    final VoidCallback? ask = friend.phoneHash == null || busy
        ? null
        : () => CardInviteFlow.requestAccess(
            context,
            person ?? _standIn(friend),
            ownerUid: friend.ownerUid,
            ownerPhoneHash: friend.phoneHash!,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Material(
        color: warm.withValues(alpha: dark ? 0.16 : 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: warm.withValues(alpha: 0.45)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: ask,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 12, 10),
            child: Row(
              children: <Widget>[
                ExcludeSemantics(
                  child: person != null
                      ? PersonAvatar(person: person, radius: 22)
                      : _InitialAvatar(name: friend.name),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: 'חדש! ',
                          style: TextStyle(
                            color: warm,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        TextSpan(text: '$first $added כרטיס לשדכן · '),
                        TextSpan(
                          text: '{בקש|בקשי} גישה'.forGender(context.userGender),
                          style: TextStyle(
                            color: dark
                                ? AppColors.primaryDarkDm
                                : AppColors.primaryDark,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
                if (busy) ...<Widget>[
                  const SizedBox(width: 8),
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String trimmed = name.trim();
    return CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.softBlue,
      child: Text(
        trimmed.isEmpty ? '' : trimmed.characters.first,
        style: theme.textTheme.titleMedium?.copyWith(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w900,
        ),
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
