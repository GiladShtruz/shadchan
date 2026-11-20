import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/matchmaker_share.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';

/// One matchmaker this matchmaker knows: who they are, and what each shares
/// with the other right now. Built only from what this matchmaker may
/// already know — the server's reading of their own contacts, and the share
/// rows the two are part of.
class KnownMatchmaker {
  const KnownMatchmaker({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.lastActiveAt,
    this.joinedAt,
    this.databaseCount,
    this.phoneHash,
    this.inContacts = false,
    this.mutual = false,
    this.publicFigures = false,
    this.communityUid,
    this.theyShare,
    this.iShare,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final DateTime? lastActiveAt;

  /// When they joined the community as a matchmaker — "חדש" for a week.
  final DateTime? joinedAt;
  final int? databaseCount;

  /// The directory key the server matched in this phone's contacts — how the
  /// phone finds the name and number it saved them under.
  final String? phoneHash;

  /// Saved in this matchmaker's phone (the server matched them there).
  final bool inContacts;

  /// Saved in each other's phones.
  final bool mutual;

  /// Their community figures are public (not hidden from the board).
  final bool publicFigures;

  /// Their row on `communityMembers` — the shared database's for a couple.
  final String? communityUid;

  /// What they share with this matchmaker, if anything was ever decided.
  final MatchmakerShare? theyShare;

  /// What this matchmaker shares with them.
  final MatchmakerShare? iShare;

  /// They share something with this matchmaker now.
  bool get sharesWithMe => theyShare?.isActive ?? false;

  /// This matchmaker shares something with them now.
  bool get iShareWith => iShare?.isActive ?? false;

  /// "מחוברים": at least one active share between the two, either way.
  bool get isConnected => sharesWithMe || iShareWith;

  int get sharedWithMeCount => sharesWithMe ? theyShare!.count : 0;
  int get iShareCount => iShareWith ? iShare!.count : 0;

  /// They asked this matchmaker to share.
  bool get askedMe => iShare?.isRequest ?? false;

  /// This matchmaker asked them to share.
  bool get iAsked => theyShare?.isRequest ?? false;

  /// Joined in the last week — the "חדש" mark.
  bool isNew([DateTime? now]) {
    final DateTime? at = joinedAt;
    return at != null &&
        (now ?? DateTime.now()).difference(at) < const Duration(days: 7);
  }

  String get firstName {
    final String t = name.trim();
    if (t.isEmpty) return 'שדכן/ית';
    return t.split(RegExp(r'\s+')).first;
  }

  /// "פעיל היום · 40 חברים במאגר" — what the app knows, nothing they typed.
  /// The database size is shown only once the two share something.
  String get detailsLine => <String>[
    if (lastActiveAt != null) MatchmakerFriends.activityLabel(lastActiveAt!),
    if (isConnected && databaseCount != null)
      MatchmakerFriends.databaseLabel(databaseCount!),
  ].join(' · ');
}

/// The two groups of "שדכנים שאני מכיר", in the order they are drawn.
class KnownMatchmakerGroups {
  const KnownMatchmakerGroups({
    this.connected = const <KnownMatchmaker>[],
    this.others = const <KnownMatchmaker>[],
  });

  /// משתפים איתי / מחוברים — at least one active share either way.
  final List<KnownMatchmaker> connected;

  /// עדיין לא משתפים — those who asked this matchmaker to share first.
  final List<KnownMatchmaker> others;

  int get requestCount => others.where((KnownMatchmaker m) => m.askedMe).length;

  bool get isEmpty => connected.isEmpty && others.isEmpty;

  /// Everybody, for a lookup by uid.
  Iterable<KnownMatchmaker> get all => <KnownMatchmaker>[
    ...connected,
    ...others,
  ];
}

/// "שדכנים שאני מכיר" — pure, so the grouping and the order are tested
/// without a server.
abstract final class KnownMatchmakers {
  /// Groups [helpers] (matchmakers in this matchmaker's contacts) and
  /// [shares] (the rows the two are part of).
  ///
  /// **Nobody appears who was not already known.** A matchmaker is listed
  /// because they are in this phone's contacts, or because a share row
  /// between the two exists (either shares, or one asked). A stopped share
  /// with somebody no longer in the contacts is left out.
  ///
  /// [nameOf] gives the name this matchmaker saved them under, when the
  /// phone has one. [hidden] are matchmakers this one hid from the home
  /// carousel — still listed here, never removed.
  static KnownMatchmakerGroups build({
    required String? me,
    required List<CardHelper> helpers,
    required List<MatchmakerShare> shares,
    String? Function(CardHelper helper)? nameOf,
  }) {
    final Map<String, CardHelper> byUid = <String, CardHelper>{
      for (final CardHelper h in helpers)
        if (h.uid != me) h.uid: h,
    };
    final Map<String, MatchmakerShare> theirs = <String, MatchmakerShare>{};
    final Map<String, MatchmakerShare> mine = <String, MatchmakerShare>{};
    if (me != null) {
      for (final MatchmakerShare s in shares) {
        if (s.readerUid == me && s.ownerUid != me) theirs[s.ownerUid] = s;
        if (s.ownerUid == me && s.readerUid != me) mine[s.readerUid] = s;
      }
    }
    final Set<String> uids = <String>{
      ...byUid.keys,
      for (final String u in <String>{...theirs.keys, ...mine.keys})
        if (byUid.containsKey(u) ||
            (theirs[u]?.isActive ?? false) ||
            (mine[u]?.isActive ?? false) ||
            (theirs[u]?.isRequest ?? false) ||
            (mine[u]?.isRequest ?? false))
          u,
    };
    final List<KnownMatchmaker> connected = <KnownMatchmaker>[];
    final List<KnownMatchmaker> others = <KnownMatchmaker>[];
    for (final String uid in uids) {
      final CardHelper? h = byUid[uid];
      final MatchmakerShare? t = theirs[uid];
      final MatchmakerShare? m = mine[uid];
      final String saved = h == null ? '' : (nameOf?.call(h) ?? '').trim();
      final String fromRow = (t?.ownerName.isNotEmpty ?? false)
          ? t!.ownerName
          : (m?.readerName ?? '');
      final KnownMatchmaker entry = KnownMatchmaker(
        uid: uid,
        name: saved.isNotEmpty
            ? saved
            : (h != null && h.name.trim().isNotEmpty ? h.name.trim() : fromRow),
        photoUrl: h?.photoUrl,
        lastActiveAt: h?.lastActiveAt,
        joinedAt: h?.joinedAt,
        databaseCount: h?.databaseCount,
        phoneHash: h?.phoneHash,
        inContacts: h != null,
        mutual: h?.mutual ?? false,
        publicFigures: h?.publicFigures ?? false,
        communityUid: h?.recipientUid ?? uid,
        theyShare: t,
        iShare: m,
      );
      (entry.isConnected ? connected : others).add(entry);
    }
    connected.sort(byActivity);
    others.sort((KnownMatchmaker a, KnownMatchmaker b) {
      // Those who asked this matchmaker to share lead, newest request first.
      if (a.askedMe != b.askedMe) return a.askedMe ? -1 : 1;
      if (a.askedMe && b.askedMe) {
        final DateTime? at = a.iShare?.updatedAt;
        final DateTime? bt = b.iShare?.updatedAt;
        if (at != null && bt != null && at != bt) return bt.compareTo(at);
      }
      // Saved in each other's phones next — a stronger sign they know each
      // other, never a reason to share anything unasked.
      if (a.mutual != b.mutual) return a.mutual ? -1 : 1;
      return byActivity(a, b);
    });
    return KnownMatchmakerGroups(connected: connected, others: others);
  }

  /// The home carousel "שדכנים שותפים": every matchmaker known, most recently
  /// active first (a new one — joined this week — leads), minus [hidden].
  static List<KnownMatchmaker> carousel(
    KnownMatchmakerGroups groups, {
    Set<String> hidden = const <String>{},
    DateTime? now,
  }) {
    final List<KnownMatchmaker> list = <KnownMatchmaker>[
      for (final KnownMatchmaker m in groups.all)
        if (!hidden.contains(m.uid)) m,
    ];
    list.sort((KnownMatchmaker a, KnownMatchmaker b) {
      final bool an = a.isNew(now);
      final bool bn = b.isNew(now);
      if (an != bn) return an ? -1 : 1;
      return byActivity(a, b);
    });
    return list;
  }

  /// Most recently active first; unknown activity last; then by name.
  static int byActivity(KnownMatchmaker a, KnownMatchmaker b) {
    final DateTime? at = a.lastActiveAt;
    final DateTime? bt = b.lastActiveAt;
    if (at != null && bt != null && at != bt) return bt.compareTo(at);
    if ((at == null) != (bt == null)) return at == null ? 1 : -1;
    return a.name.compareTo(b.name);
  }

  /// The short word on a row about where the two stand, or null for none.
  static String? stateLabel(KnownMatchmaker m) {
    if (m.sharesWithMe && m.iShareWith) return 'משתפים אחד עם השני';
    if (m.sharesWithMe) return 'משתף/ת איתך';
    if (m.iShareWith) return 'את/ה משתף/ת';
    if (m.askedMe) return 'מבקש/ת שתשתף/י';
    if (m.iAsked) return 'ביקשת שיתוף';
    return null;
  }
}
