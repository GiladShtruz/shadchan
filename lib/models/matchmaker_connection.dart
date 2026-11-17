/// Where two matchmakers who know each other stand ("שדכנים שאני מכיר").
///
/// **A connection shares nothing.** It is two uids, who asked whom, and the
/// name each side goes by — no card, no friend and no figure of either
/// database. Later features may build on it; this is only the row.
enum MatchmakerConnectionStatus { pending, approved, declined }

/// One `matchmakerConnections/{a}_{b}` document, read from [me]'s side.
class MatchmakerConnection {
  const MatchmakerConnection({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.status,
    this.names = const <String, String>{},
    this.createdAt,
    this.updatedAt,
  });

  /// `{a}_{b}`, the two uids sorted — the same document whoever asks.
  static String idFor(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  final String id;

  /// Who asked.
  final String fromUid;

  /// Who was asked.
  final String toUid;
  final MatchmakerConnectionStatus status;

  /// The name each side goes by, as they published it themselves.
  final Map<String, String> names;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  List<String> get uids => <String>[fromUid, toUid]..sort();

  /// The other matchmaker, from [me]'s side.
  String otherOf(String me) => fromUid == me ? toUid : fromUid;

  bool get isConnected => status == MatchmakerConnectionStatus.approved;

  /// Waiting for [me] to answer.
  bool isIncomingFor(String me) =>
      status == MatchmakerConnectionStatus.pending && toUid == me;

  /// [me] asked and is waiting.
  bool isOutgoingFor(String me) =>
      status == MatchmakerConnectionStatus.pending && fromUid == me;

  /// [me] asked and the other side said "לא עכשיו".
  bool isDeclinedFor(String me) =>
      status == MatchmakerConnectionStatus.declined && fromUid == me;

  /// How long a matchmaker who was declined waits before asking again —
  /// the same thirty days `firestore.rules` holds them to.
  static const Duration askAgainAfter = Duration(days: 30);

  /// Whether [me] may ask now: nothing between them, a "לא עכשיו" [me]
  /// said themselves, or one said to [me] more than [askAgainAfter] ago.
  bool canAskAgain(String me, [DateTime? now]) {
    if (status != MatchmakerConnectionStatus.declined) return false;
    if (toUid == me) return true;
    final DateTime? at = updatedAt;
    return at != null && (now ?? DateTime.now()).difference(at) > askAgainAfter;
  }

  static MatchmakerConnection? fromMap(String id, Map<String, dynamic> data) {
    final Object? from = data['fromUid'];
    final Object? to = data['toUid'];
    if (from is! String || to is! String) return null;
    final MatchmakerConnectionStatus? status = switch (data['status']) {
      'pending' => MatchmakerConnectionStatus.pending,
      'approved' => MatchmakerConnectionStatus.approved,
      'declined' => MatchmakerConnectionStatus.declined,
      _ => null,
    };
    if (status == null) return null;
    final Object? rawNames = data['names'];
    return MatchmakerConnection(
      id: id,
      fromUid: from,
      toUid: to,
      status: status,
      names: <String, String>{
        if (rawNames is Map)
          for (final MapEntry<Object?, Object?> e in rawNames.entries)
            if (e.key is String && e.value is String)
              e.key! as String: (e.value! as String).trim(),
      },
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    try {
      // A Firestore Timestamp, without importing Firestore into a model.
      final Object? date = (value as dynamic)?.toDate();
      return date is DateTime ? date : null;
    } catch (_) {
      return null;
    }
  }
}
