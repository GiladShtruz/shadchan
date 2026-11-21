/// What one matchmaker shares with another — one direction of
/// `matchmakerShares/{owner}_{reader}` (2026-11-20).
///
/// **One pair, one direction, one decision.** The owner decides, for this
/// reader alone: the whole database, the friends picked, everything except
/// some — or nothing. The reader may only *ask*. Two matchmakers who know each
/// other from the phone book see each other without any row at all; a row is
/// written only when something is shared, asked for, or stopped.
enum MatchmakerShareMode {
  /// The reader asked; the owner has not answered.
  requested,

  /// Every complete card the owner may share.
  all,

  /// Only the friends the owner picked for this reader.
  selected,

  /// Every complete card except the friends picked out.
  allExcept,

  /// Nothing — sharing stopped (the row stays so a stop is known).
  none;

  bool get isActive => this == all || this == selected || this == allExcept;

  static MatchmakerShareMode byName(Object? name) {
    for (final MatchmakerShareMode m in values) {
      if (m.name == name) return m;
    }
    return none;
  }
}

class MatchmakerShare {
  const MatchmakerShare({
    required this.ownerUid,
    required this.readerUid,
    required this.mode,
    this.count = 0,
    this.ownerName = '',
    this.readerName = '',
    this.updatedAt,
  });

  static String idFor(String ownerUid, String readerUid) =>
      '${ownerUid}_$readerUid';

  final String ownerUid;
  final String readerUid;
  final MatchmakerShareMode mode;

  /// How many cards the owner shares with the reader right now (the owner's
  /// phone writes it after each publish).
  final int count;
  final String ownerName;
  final String readerName;
  final DateTime? updatedAt;

  String get id => idFor(ownerUid, readerUid);
  bool get isActive => mode.isActive;
  bool get isRequest => mode == MatchmakerShareMode.requested;

  static MatchmakerShare? fromMap(Map<String, dynamic> data) {
    final Object? owner = data['ownerUid'];
    final Object? reader = data['readerUid'];
    if (owner is! String || reader is! String) return null;
    final Object? count = data['count'];
    DateTime? at;
    try {
      final Object? raw = data['updatedAt'];
      final Object? date = raw is DateTime ? raw : (raw as dynamic)?.toDate();
      at = date is DateTime ? date : null;
    } catch (_) {}
    return MatchmakerShare(
      ownerUid: owner,
      readerUid: reader,
      mode: MatchmakerShareMode.byName(data['mode']),
      count: count is num ? count.toInt() : 0,
      ownerName: ((data['ownerName'] as String?) ?? '').trim(),
      readerName: ((data['readerName'] as String?) ?? '').trim(),
      updatedAt: at,
    );
  }
}
