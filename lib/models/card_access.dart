/// Where one matchmaker stands with one card owner's card.
enum CardAccessStatus {
  pending,
  approved,
  declined,
  blocked,
  revoked;

  static CardAccessStatus? byName(Object? name) {
    for (final CardAccessStatus status in CardAccessStatus.values) {
      if (status.name == name) {
        return status;
      }
    }
    return null;
  }
}

/// One `cardAccess/{ownerUid}_{matchmakerUid}` document.
class CardAccess {
  const CardAccess({
    required this.ownerUid,
    required this.matchmakerUid,
    required this.status,
    required this.requestedBy,
    this.ownerName = '',
    this.matchmakerName = '',
    this.matchmakerGender,
    this.ownerPhoneHash,
    this.ownerPhone,
  });

  final String ownerUid;
  final String matchmakerUid;
  final CardAccessStatus status;

  /// `matchmaker` when the matchmaker asked; `owner` when the owner gave
  /// access unasked.
  final String requestedBy;
  final String ownerName;
  final String matchmakerName;

  /// `male` / `female`, written by the matchmaker when asking, so the owner's
  /// screens can say "השדכן" or "השדכנית". Null on older rows and on a grant
  /// the owner made unasked — those fall back to wording that fits both.
  final String? matchmakerGender;

  /// Lets the matchmaker's device find the friend already in its database.
  final String? ownerPhoneHash;

  /// The owner's own number, written by the owner when approving — so a
  /// matchmaker who does not have it saved can still send a mazel tov.
  final String? ownerPhone;

  String get id => '${ownerUid}_$matchmakerUid';

  static CardAccess? fromMap(Map<String, dynamic> data) {
    final Object? owner = data['ownerUid'];
    final Object? matchmaker = data['matchmakerUid'];
    final CardAccessStatus? status = CardAccessStatus.byName(data['status']);
    if (owner is! String || matchmaker is! String || status == null) {
      return null;
    }
    return CardAccess(
      ownerUid: owner,
      matchmakerUid: matchmaker,
      status: status,
      requestedBy: (data['requestedBy'] as String?) ?? 'matchmaker',
      ownerName: (data['ownerName'] as String?) ?? '',
      matchmakerName: (data['matchmakerName'] as String?) ?? '',
      matchmakerGender: data['matchmakerGender'] as String?,
      ownerPhoneHash: data['ownerPhoneHash'] as String?,
      ownerPhone: data['ownerPhone'] as String?,
    );
  }
}

/// A matchmaker among the owner's contacts, as the server found them.
class CardHelper {
  const CardHelper({required this.uid, required this.name, this.phoneHash});

  final String uid;

  /// The name the matchmaker gave themselves — shown only when the owner's
  /// own contacts have no name for [phoneHash].
  final String name;

  /// The directory key the server matched in the owner's contacts: how the
  /// owner's phone finds the name *they* saved this friend under.
  final String? phoneHash;
}

/// "Yitzchak marked you 'busy' — is that right?", waiting for the owner.
class StatusReport {
  const StatusReport({
    required this.id,
    required this.ownerUid,
    required this.matchmakerUid,
    required this.matchmakerName,
    required this.status,
  });

  final String id;
  final String ownerUid;
  final String matchmakerUid;
  final String matchmakerName;
  final String status;
}
