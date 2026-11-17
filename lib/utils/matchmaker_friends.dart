import 'package:shadchan/models/card_access.dart';

/// Where one matchmaker friend stands with the owner's card.
enum MatchmakerFriendState {
  /// They can read the card now.
  seesCard,

  /// They asked — for the card, or for "מה אני מחפש/ת" — and are waiting.
  requested,

  /// A friend who matchmakes here and has no access yet.
  canGrant,
}

/// One friend from the owner's contacts who matchmakes in the app, with
/// everything the personal area draws about them in one place: the server's
/// list of matchmakers in the owner's address book merged with the access
/// rows the owner and the matchmakers have written.
class MatchmakerFriend {
  const MatchmakerFriend({
    required this.uid,
    required this.name,
    required this.state,
    this.photoUrl,
    this.databaseCount,
    this.lastActiveAt,
    this.joinedAt,
    this.row,
    this.helper,
  });

  /// The uid the access row is keyed on — a couple's shared database when the
  /// friend matchmakes as a couple.
  final String uid;
  final String name;
  final MatchmakerFriendState state;
  final String? photoUrl;
  final int? databaseCount;
  final DateTime? lastActiveAt;
  final DateTime? joinedAt;

  /// The access row, when there is one.
  final CardAccess? row;

  /// The server's entry for them, when the owner's contacts produced one.
  final CardHelper? helper;

  bool get canReadCard => row?.canReadCard ?? false;
  bool get canReadLooking => row?.canReadLooking ?? false;

  /// Asked for "מה אני מחפש/ת" while already seeing the card.
  bool get asksForLooking =>
      row != null && row!.lookingRequested && !row!.canReadLooking;

  /// Asked for the card itself.
  bool get asksForCard =>
      row != null &&
      !row!.canReadCard &&
      (row!.status == CardAccessStatus.pending || row!.cardRequested);
}

abstract final class MatchmakerFriends {
  /// Every matchmaker friend of the owner, blocked ones left out.
  ///
  /// [known] is the server's list of matchmakers in the owner's contacts;
  /// [rows] are the owner's access rows. A friend appears once however many
  /// of the two mention them — a couple's two members fold into the row
  /// written for their shared database.
  static List<MatchmakerFriend> build({
    required List<CardHelper> known,
    required List<CardAccess> rows,
    String Function(String uid, String fallback)? nameOf,
  }) {
    final List<MatchmakerFriend> out = <MatchmakerFriend>[];
    final Set<String> claimed = <String>{};
    String named(String uid, String fallback) =>
        nameOf == null ? fallback : nameOf(uid, fallback);

    for (final CardAccess row in rows) {
      final Set<String> ids = <String>{row.matchmakerUid, ...row.granteeUids};
      CardHelper? helper;
      for (final CardHelper h in known) {
        if (ids.contains(h.uid) || h.recipientUid == row.matchmakerUid) {
          helper ??= h;
          claimed.add(h.uid);
        }
      }
      claimed.addAll(ids);
      if (row.status == CardAccessStatus.blocked) {
        continue;
      }
      final bool requested =
          (!row.canReadCard &&
              (row.status == CardAccessStatus.pending || row.cardRequested)) ||
          (row.lookingRequested && !row.canReadLooking);
      final MatchmakerFriendState state = row.canReadCard
          ? (requested
                ? MatchmakerFriendState.requested
                : MatchmakerFriendState.seesCard)
          : requested
          ? MatchmakerFriendState.requested
          : MatchmakerFriendState.canGrant;
      final String fallback = row.matchmakerName.trim().isNotEmpty
          ? row.matchmakerName
          : (helper?.name ?? '');
      out.add(
        MatchmakerFriend(
          uid: row.matchmakerUid,
          name: row.granteeUids.length == 2
              ? fallback
              : named(helper?.uid ?? row.matchmakerUid, fallback),
          state: state,
          photoUrl: helper?.photoUrl,
          databaseCount: helper?.databaseCount,
          lastActiveAt: helper?.lastActiveAt,
          joinedAt: helper?.joinedAt,
          row: row,
          helper: helper,
        ),
      );
    }
    for (final CardHelper helper in known) {
      if (claimed.contains(helper.uid) ||
          (helper.recipientUid != null &&
              claimed.contains(helper.recipientUid))) {
        continue;
      }
      claimed.add(helper.uid);
      out.add(
        MatchmakerFriend(
          uid: helper.recipientUid ?? helper.uid,
          name: helper.granteeUids.length == 2
              ? helper.name
              : named(helper.uid, helper.name),
          state: MatchmakerFriendState.canGrant,
          photoUrl: helper.photoUrl,
          databaseCount: helper.databaseCount,
          lastActiveAt: helper.lastActiveAt,
          joinedAt: helper.joinedAt,
          helper: helper,
        ),
      );
    }
    return out;
  }

  /// Requests first — a request must never be lost under a long list — then
  /// the friends who joined most recently, then by name.
  static List<MatchmakerFriend> sorted(Iterable<MatchmakerFriend> friends) {
    final List<MatchmakerFriend> list = friends.toList();
    int rank(MatchmakerFriend f) =>
        f.state == MatchmakerFriendState.requested ? 0 : 1;
    list.sort((MatchmakerFriend a, MatchmakerFriend b) {
      final int byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final DateTime? aj = a.joinedAt, bj = b.joinedAt;
      if (aj != null || bj != null) {
        if (aj == null) return 1;
        if (bj == null) return -1;
        final int byJoin = bj.compareTo(aj);
        if (byJoin != 0) return byJoin;
      }
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// "אפשר לתת גישה": everybody who cannot read the card yet, requests
  /// first. [hidden] clears friends the owner put away — never a request.
  static List<MatchmakerFriend> grantable(
    Iterable<MatchmakerFriend> friends, {
    Set<String> hidden = const <String>{},
  }) => sorted(
    friends.where(
      (MatchmakerFriend f) =>
          !f.canReadCard &&
          (f.state == MatchmakerFriendState.requested || !isHidden(f, hidden)),
    ),
  );

  /// "אישרתי גישה": everybody who reads the card.
  static List<MatchmakerFriend> approved(Iterable<MatchmakerFriend> friends) =>
      sorted(friends.where((MatchmakerFriend f) => f.canReadCard));

  /// The friends the owner put away from the list.
  static List<MatchmakerFriend> hiddenOf(
    Iterable<MatchmakerFriend> friends,
    Set<String> hidden,
  ) => sorted(
    friends.where(
      (MatchmakerFriend f) =>
          !f.canReadCard &&
          f.state != MatchmakerFriendState.requested &&
          isHidden(f, hidden),
    ),
  );

  static bool isHidden(MatchmakerFriend f, Set<String> hidden) =>
      hidden.contains(f.uid) ||
      (f.helper != null && hidden.contains(f.helper!.uid));

  /// The uid "הסתר מהרשימה" stores for [f].
  static String hideKey(MatchmakerFriend f) => f.helper?.uid ?? f.uid;

  /// "פעיל היום" / "לפני 3 ימים" / "לפני שבוע" — how recently, said the way a
  /// person would, never a timestamp.
  static String activityLabel(DateTime at, [DateTime? now]) {
    final DateTime today = now ?? DateTime.now();
    final DateTime a = DateTime(at.year, at.month, at.day);
    final DateTime b = DateTime(today.year, today.month, today.day);
    final int days = b.difference(a).inDays;
    if (days <= 0) return 'פעיל היום';
    if (days == 1) return 'פעיל אתמול';
    if (days == 2) return 'לפני יומיים';
    if (days < 7) return 'לפני $days ימים';
    if (days < 14) return 'לפני שבוע';
    if (days < 30) return 'לפני ${days ~/ 7} שבועות';
    if (days < 60) return 'לפני חודש';
    if (days < 365) return 'לפני ${days ~/ 30} חודשים';
    return 'לפני יותר משנה';
  }

  /// Recently active matchmakers count back this far; older is not "recent".
  static const Duration recentWindow = Duration(days: 30);

  /// "השדכנים שלי שהיו פעילים לאחרונה": friends active in [recentWindow],
  /// most recent first, at most [limit]. A friend put away from the list is
  /// left out — unless they are asking for something.
  static List<MatchmakerFriend> recentlyActive(
    Iterable<MatchmakerFriend> friends, {
    Set<String> hidden = const <String>{},
    int limit = 3,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    final List<MatchmakerFriend> list =
        friends
            .where(
              (MatchmakerFriend f) =>
                  f.lastActiveAt != null &&
                  at.difference(f.lastActiveAt!) < recentWindow &&
                  (f.canReadCard ||
                      f.state == MatchmakerFriendState.requested ||
                      !isHidden(f, hidden)),
            )
            .toList()
          ..sort(
            (MatchmakerFriend a, MatchmakerFriend b) =>
                b.lastActiveAt!.compareTo(a.lastActiveAt!),
          );
    return list.take(limit).toList();
  }

  /// "פעיל לפני 20 דקות" / "פעילה לפני 3 שעות" today, "פעיל אתמול" /
  /// "פעיל לפני 4 ימים" before — said the way a person would.
  static String recentActivityLabel(
    DateTime at, {
    DateTime? now,
    bool female = false,
  }) {
    final String active = female ? 'פעילה' : 'פעיל';
    final DateTime today = now ?? DateTime.now();
    final DateTime a = DateTime(at.year, at.month, at.day);
    final DateTime b = DateTime(today.year, today.month, today.day);
    final int days = b.difference(a).inDays;
    if (days <= 0) {
      final Duration ago = today.difference(at);
      final int minutes = ago.inMinutes;
      if (minutes < 1) return '$active ממש עכשיו';
      if (minutes == 1) return '$active לפני דקה';
      if (minutes < 60) return '$active לפני $minutes דקות';
      final int hours = ago.inHours;
      if (hours == 1) return '$active לפני שעה';
      if (hours == 2) return '$active לפני שעתיים';
      return '$active לפני $hours שעות';
    }
    if (days == 1) return '$active אתמול';
    if (days == 2) return '$active לפני יומיים';
    return '$active לפני $days ימים';
  }

  /// "12 חברים במאגר".
  static String databaseLabel(int count) =>
      count == 1 ? 'חבר אחד במאגר' : '$count חברים במאגר';

  /// The short line beside a friend's name.
  static String stateLabel(MatchmakerFriend f) {
    if (f.state == MatchmakerFriendState.requested) {
      // A couple's shared database asks as both of them, and approving gives
      // both of them access — said plainly, never left to be guessed.
      final bool pair = (f.row?.granteeUids.length ?? 0) == 2;
      final String asked = pair
          ? 'מבקשים יחד'
          : f.row?.matchmakerGender == 'female'
          ? 'ביקשה'
          : 'ביקש';
      return f.asksForCard ? '$asked גישה' : '$asked גישה ל״מה אני מחפש/ת״';
    }
    return f.canReadCard ? 'רואה את הכרטיס' : 'אפשר לתת גישה';
  }

  /// "12 אנשים במאגר · פעיל היום" — what the app already knows about a
  /// friend's activity, nothing they had to fill in.
  static String detailsLine(MatchmakerFriend f, [DateTime? now]) => <String>[
    if (f.databaseCount != null)
      f.databaseCount == 1 ? 'אדם אחד במאגר' : '${f.databaseCount} אנשים במאגר',
    if (f.lastActiveAt != null) activityLabel(f.lastActiveAt!, now),
  ].join(' · ');

  /// "כרטיס ✓ | מה אני מחפש ✓", as granted.
  static String permissionsLabel(MatchmakerFriend f) =>
      'כרטיס ${f.canReadCard ? '✓' : '—'} | מה אני מחפש ${f.canReadLooking ? '✓' : '—'}';
}
