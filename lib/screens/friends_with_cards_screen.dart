import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_navigation.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/widgets/card_invite.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/personal_home_sections.dart';

/// Where a matchmaker stands with one friend's personal card.
enum FriendCardState { sees, pending, requestable }

/// One friend of the matchmaker who keeps a personal card.
class FriendWithCard {
  const FriendWithCard({
    required this.ownerUid,
    required this.name,
    required this.state,
    this.phoneHash,
    this.person,
  });
  final String ownerUid;
  final String name;
  final FriendCardState state;
  final String? phoneHash;

  /// Their record in the matchmaker's database, when there is one.
  final Person? person;
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
          (hash == null ? null : people.findByPhoneHash(hash));
      final FriendCardState state = row?.canReadCard == true
          ? FriendCardState.sees
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
    final List<FriendWithCard> list = byOwner.values.toList()
      ..sort((FriendWithCard a, FriendWithCard b) {
        final int byState = b.state.index.compareTo(a.state.index);
        return byState != 0 ? byState : a.name.compareTo(b.name);
      });
    return list;
  }
}

/// "חברים שלי שהוסיפו כרטיס אישי" — the matchmaker's friends who keep a card
/// of their own, and asking each of them for access. Reached from בית and
/// from המאגר שלי alike.
class FriendsWithCardsScreen extends StatelessWidget {
  const FriendsWithCardsScreen({super.key});

  static const String route = '/card-friends';

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
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('חברים שלי שהוסיפו כרטיס אישי')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              'חברים שמנהלים כרטיס אישי בשדכן. עם גישה, הכרטיס שלהם מתעדכן אצלך במאגר מעצמו.',
              style: theme.textTheme.bodySmall,
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
          for (final FriendWithCard friend in friends)
            _FriendRow(friend: friend),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend});
  final FriendWithCard friend;

  Person _personFor() {
    final Person? person = friend.person;
    if (person != null) return person;
    final List<String> parts = friend.name.trim().split(RegExp(r'\s+'));
    final DateTime now = DateTime.now();
    // Never saved: only the name the request and its WhatsApp line speak.
    return Person(
      id: 'card-friend-${friend.ownerUid}',
      firstName: parts.isEmpty ? '' : parts.first,
      lastName: parts.length > 1 ? parts.skip(1).join(' ') : '',
      gender: Gender.unknown,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final bool busy = access.isBusy('request:${friend.ownerUid}');
    final Person? person = friend.person;
    final String status = switch (friend.state) {
      FriendCardState.sees => 'יש לך גישה לכרטיס',
      FriendCardState.pending => 'הבקשה נשלחה · ממתינה לאישור',
      FriendCardState.requestable => 'אפשר לבקש גישה',
    };
    final Widget action = switch (friend.state) {
      FriendCardState.sees =>
        person == null
            ? const SizedBox.shrink()
            : TextButton(
                onPressed: () => openPersonProfile(context, person.id),
                child: const Text('לכרטיס'),
              ),
      FriendCardState.pending => const SizedBox.shrink(),
      FriendCardState.requestable =>
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
                        _personFor(),
                        ownerUid: friend.ownerUid,
                        ownerPhoneHash: friend.phoneHash!,
                      ),
                child: const Text('בקשת גישה'),
              ),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: person == null
          ? null
          : () => openPersonProfile(context, person.id),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
        child: Row(
          children: <Widget>[
            if (person != null)
              PersonAvatar(person: person, radius: 21)
            else
              CircleAvatar(
                radius: 21,
                backgroundColor: AppColors.softBlue,
                child: Text(
                  friend.name.trim().isEmpty
                      ? ''
                      : friend.name.trim().characters.first,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    friend.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            action,
          ],
        ),
      ),
    );
  }
}

/// The way into [FriendsWithCardsScreen], one quiet row — the same on בית
/// and on המאגר שלי.
class FriendsWithCardsLink extends StatelessWidget {
  const FriendsWithCardsLink({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final int count =
        FriendsWithCards.build(
              access: access,
              people: context.watch<PersonRepository>(),
              inbox: maybeWatch<InboxProvider>(context),
            )
            .where((FriendWithCard f) => f.state == FriendCardState.requestable)
            .length;
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push(FriendsWithCardsScreen.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(Icons.badge_outlined, size: 20, color: ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'חברים שלי שהוסיפו כרטיס אישי',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            Icon(Icons.chevron_right_rounded, color: ink),
          ],
        ),
      ),
    );
  }
}
