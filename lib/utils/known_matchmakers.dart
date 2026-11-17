import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/matchmaker_connection.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';

/// Where this matchmaker stands with one matchmaker they know.
enum KnownMatchmakerState {
  /// Both said yes.
  connected,

  /// They asked; waiting for this matchmaker.
  incoming,

  /// This matchmaker asked; waiting for them.
  outgoing,

  /// This matchmaker asked and they said "לא עכשיו" — asking again opens
  /// after [MatchmakerConnection.askAgainAfter].
  declined,

  /// Nothing between them yet.
  none,
}

/// One matchmaker on "שדכנים שאני מכיר": who they are and where the two
/// stand. Built only from what this matchmaker may already know — the
/// server's reading of their own contacts, and the rows they are part of.
class KnownMatchmaker {
  const KnownMatchmaker({
    required this.uid,
    required this.name,
    required this.state,
    this.photoUrl,
    this.lastActiveAt,
    this.databaseCount,
    this.inContacts = false,
    this.mutual = false,
    this.publicFigures = false,
    this.communityUid,
    this.connection,
  });

  final String uid;
  final String name;
  final KnownMatchmakerState state;
  final String? photoUrl;
  final DateTime? lastActiveAt;
  final int? databaseCount;

  /// Saved in this matchmaker's phone (the server matched them there).
  final bool inContacts;

  /// Saved in each other's phones.
  final bool mutual;

  /// Their community figures are public (not hidden from the board).
  final bool publicFigures;

  /// Their row on `communityMembers` — the shared database's for a couple.
  final String? communityUid;
  final MatchmakerConnection? connection;

  /// "פעיל היום · 40 חברים במאגר" — what the app knows, nothing they typed.
  String get detailsLine => <String>[
    if (lastActiveAt != null) MatchmakerFriends.activityLabel(lastActiveAt!),
    if (databaseCount != null) MatchmakerFriends.databaseLabel(databaseCount!),
  ].join(' · ');
}

/// The three groups of the screen, in the order they are drawn.
class KnownMatchmakerGroups {
  const KnownMatchmakerGroups({
    this.connected = const <KnownMatchmaker>[],
    this.requests = const <KnownMatchmaker>[],
    this.contacts = const <KnownMatchmaker>[],
  });

  /// מחוברים — first, because they are who the matchmaker already works with.
  final List<KnownMatchmaker> connected;

  /// בקשות חיבור — waiting for this matchmaker first, then their own.
  final List<KnownMatchmaker> requests;

  /// שדכנים מאנשי הקשר — everybody else in their phone who matchmakes here.
  final List<KnownMatchmaker> contacts;

  int get incomingCount => requests
      .where((KnownMatchmaker m) => m.state == KnownMatchmakerState.incoming)
      .length;

  bool get isEmpty => connected.isEmpty && requests.isEmpty && contacts.isEmpty;

  /// Everybody, for a lookup by uid.
  Iterable<KnownMatchmaker> get all => <KnownMatchmaker>[
    ...connected,
    ...requests,
    ...contacts,
  ];
}

/// "שדכנים שאני מכיר" — pure, so the grouping and the order are tested
/// without a server.
abstract final class KnownMatchmakers {
  static KnownMatchmakerState stateOf(MatchmakerConnection? c, String me) {
    if (c == null) return KnownMatchmakerState.none;
    if (c.isConnected) return KnownMatchmakerState.connected;
    if (c.isIncomingFor(me)) return KnownMatchmakerState.incoming;
    if (c.isOutgoingFor(me)) return KnownMatchmakerState.outgoing;
    if (c.isDeclinedFor(me)) return KnownMatchmakerState.declined;
    // A "לא עכשיו" this matchmaker said: free to ask them now.
    return KnownMatchmakerState.none;
  }

  /// Groups [helpers] (matchmakers in this matchmaker's contacts) and
  /// [connections] (the rows they are part of).
  ///
  /// **Nobody appears who was not already known.** A matchmaker is listed
  /// because they are in this phone's contacts, or because a row between the
  /// two exists — connected, or a request one of them sent. A "לא עכשיו"
  /// row with somebody no longer in the contacts is left out.
  ///
  /// [nameOf] gives the name this matchmaker saved them under, when the
  /// phone has one.
  static KnownMatchmakerGroups build({
    required String? me,
    required List<CardHelper> helpers,
    required List<MatchmakerConnection> connections,
    String? Function(CardHelper helper)? nameOf,
  }) {
    final Map<String, CardHelper> byUid = <String, CardHelper>{
      for (final CardHelper h in helpers)
        if (h.uid != me) h.uid: h,
    };
    final List<KnownMatchmaker> connected = <KnownMatchmaker>[];
    final List<KnownMatchmaker> requests = <KnownMatchmaker>[];
    final List<KnownMatchmaker> contacts = <KnownMatchmaker>[];
    final Set<String> placed = <String>{};

    KnownMatchmaker entry(
      String uid,
      KnownMatchmakerState state,
      MatchmakerConnection? connection,
    ) {
      final CardHelper? h = byUid[uid];
      final String saved = h == null ? '' : (nameOf?.call(h) ?? '').trim();
      final String fromRow = (connection?.names[uid] ?? '').trim();
      return KnownMatchmaker(
        uid: uid,
        name: saved.isNotEmpty
            ? saved
            : (h != null && h.name.trim().isNotEmpty ? h.name.trim() : fromRow),
        state: state,
        photoUrl: h?.photoUrl,
        lastActiveAt: h?.lastActiveAt,
        databaseCount: h?.databaseCount,
        inContacts: h != null,
        mutual: h?.mutual ?? false,
        publicFigures: h?.publicFigures ?? false,
        communityUid: h?.recipientUid ?? uid,
        connection: connection,
      );
    }

    if (me != null) {
      for (final MatchmakerConnection c in connections) {
        final String other = c.otherOf(me);
        if (other == me || placed.contains(other)) continue;
        final KnownMatchmakerState state = stateOf(c, me);
        switch (state) {
          case KnownMatchmakerState.connected:
            connected.add(entry(other, state, c));
          case KnownMatchmakerState.incoming:
          case KnownMatchmakerState.outgoing:
            requests.add(entry(other, state, c));
          case KnownMatchmakerState.declined:
          case KnownMatchmakerState.none:
            if (!byUid.containsKey(other)) continue;
            contacts.add(entry(other, state, c));
        }
        placed.add(other);
      }
    }
    for (final CardHelper h in byUid.values) {
      if (placed.add(h.uid)) {
        contacts.add(entry(h.uid, KnownMatchmakerState.none, null));
      }
    }

    connected.sort(_byActivity);
    requests.sort((KnownMatchmaker a, KnownMatchmaker b) {
      final bool ai = a.state == KnownMatchmakerState.incoming;
      final bool bi = b.state == KnownMatchmakerState.incoming;
      if (ai != bi) return ai ? -1 : 1;
      final DateTime? at = a.connection?.updatedAt;
      final DateTime? bt = b.connection?.updatedAt;
      if (at != null && bt != null && at != bt) return bt.compareTo(at);
      return a.name.compareTo(b.name);
    });
    contacts.sort((KnownMatchmaker a, KnownMatchmaker b) {
      // Saved in each other's phones first — a stronger sign they know each
      // other, never a reason to connect them unasked.
      if (a.mutual != b.mutual) return a.mutual ? -1 : 1;
      return _byActivity(a, b);
    });
    return KnownMatchmakerGroups(
      connected: connected,
      requests: requests,
      contacts: contacts,
    );
  }

  /// Most recently active first; unknown activity last; then by name.
  static int _byActivity(KnownMatchmaker a, KnownMatchmaker b) {
    final DateTime? at = a.lastActiveAt;
    final DateTime? bt = b.lastActiveAt;
    if (at != null && bt != null && at != bt) return bt.compareTo(at);
    if ((at == null) != (bt == null)) return at == null ? 1 : -1;
    return a.name.compareTo(b.name);
  }

  /// The short word on a row about where the two stand, or null for none.
  static String? stateLabel(KnownMatchmaker m) => switch (m.state) {
    KnownMatchmakerState.connected => 'מחוברים',
    KnownMatchmakerState.incoming => 'מבקש/ת להתחבר',
    KnownMatchmakerState.outgoing => 'הבקשה נשלחה',
    KnownMatchmakerState.declined => 'הבקשה לא אושרה',
    KnownMatchmakerState.none => null,
  };
}
