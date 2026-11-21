import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/utils/enums.dart';

enum IdeaProposalStatus {
  pending,

  /// The side asked agreed — not yet an open idea.
  approved,

  /// Opened: the friends are being asked; the idea is in both databases.
  opened,
  declined,
  withdrawn;

  static IdeaProposalStatus byName(Object? name) {
    for (final IdeaProposalStatus s in values) {
      if (s.name == name) return s;
    }
    return IdeaProposalStatus.pending;
  }
}

/// An idea one matchmaker offers another: their own candidate, for somebody
/// from the other's shared cards — `ideaProposals/{id}`.
///
/// **Everything goes through the matchmaker who holds the card.** The one
/// asked approves or declines; approved, the idea opens in both "הרעיונות
/// שלי", and each matchmaker stays responsible for their own friend.
class IdeaProposal {
  IdeaProposal({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.fromName,
    required this.toName,
    required this.status,
    required this.target,
    required this.candidate,
    required this.note,
    required this.sides,
    this.createdAt,
    this.shared,
  });

  final String id;

  /// Who offered the idea, with their own [candidate].
  final String fromUid;

  /// Who holds the [target] card, and answers.
  final String toUid;
  final String fromName;
  final String toName;
  final IdeaProposalStatus status;

  /// The card in [toUid]'s database the idea is for (a shared card's fields).
  final Map<String, dynamic> target;

  /// The offered candidate from [fromUid]'s database — the same fields a
  /// shared card carries, and nothing else.
  final Map<String, dynamic> candidate;
  final String note;

  /// Where each side's half stands, written by that side only:
  /// `{uid: {status: <MatchStatus.name>}}`.
  final Map<String, Map<String, dynamic>> sides;
  final DateTime? createdAt;

  /// **The one idea both matchmakers work on** (2026-11-21): where it stands
  /// — status and who was asked — written by whichever side moved it last.
  /// Each phone's own copy in "הרעיונות שלי" follows it, so the two never
  /// drift into two separate records that need reconciling.
  final SharedIdeaState? shared;

  String get targetPersonId => (target['personId'] as String?) ?? '';
  String get candidatePersonId => (candidate['personId'] as String?) ?? '';

  bool isIncomingFor(String uid) => toUid == uid;
  String otherOf(String uid) => uid == fromUid ? toUid : fromUid;
  String otherNameOf(String uid) => uid == fromUid ? toName : fromName;

  /// The friend in [uid]'s own database.
  String myPersonIdFor(String uid) =>
      uid == toUid ? targetPersonId : candidatePersonId;

  /// The other side's card, as it was offered.
  Map<String, dynamic> theirCardFor(String uid) =>
      uid == toUid ? candidate : target;

  /// The other side's friend as a transient [Person] (never saved as such).
  Person theirPersonFor(String uid) {
    final Map<String, dynamic> card = theirCardFor(uid);
    return SharedCard.personFrom(
      card,
      key: SharedCard.keyOf(otherOf(uid), (card['personId'] as String?) ?? id),
    );
  }

  /// Photo storage paths of the other side's card.
  List<String> theirPhotoPathsFor(String uid) => <String>[
    for (final Object? p
        in (theirCardFor(uid)['photoPaths'] as List?) ?? const <Object?>[])
      if (p is String && p.isNotEmpty) p,
  ];

  /// Where the other side's half stands, if they reported it.
  MatchStatus? partnerStatusFor(String uid) {
    final Object? raw = sides[otherOf(uid)]?['status'];
    for (final MatchStatus s in MatchStatus.values) {
      if (s.name == raw) return s;
    }
    return null;
  }

  static String _first(Map<String, dynamic> card) =>
      ((card['firstName'] as String?) ?? '').trim();

  String get candidateFirstName => _first(candidate);
  String get targetFirstName => _first(target);

  static IdeaProposal? fromMap(String id, Map<String, dynamic> data) {
    final Object? from = data['fromUid'];
    final Object? to = data['toUid'];
    final Object? target = data['target'];
    final Object? candidate = data['candidate'];
    if (from is! String ||
        to is! String ||
        target is! Map ||
        candidate is! Map) {
      return null;
    }
    final Object? sides = data['sides'];
    final Object? created = data['createdAt'];
    final SharedIdeaState? shared = SharedIdeaState.fromMap(data['idea']);
    return IdeaProposal(
      id: id,
      fromUid: from,
      toUid: to,
      fromName: (data['fromName'] as String?) ?? '',
      toName: (data['toName'] as String?) ?? '',
      status: IdeaProposalStatus.byName(data['status']),
      target: Map<String, dynamic>.from(target),
      candidate: Map<String, dynamic>.from(candidate),
      note: (data['note'] as String?) ?? '',
      sides: <String, Map<String, dynamic>>{
        if (sides is Map)
          for (final MapEntry<dynamic, dynamic> e in sides.entries)
            if (e.key is String && e.value is Map)
              e.key as String: Map<String, dynamic>.from(e.value as Map),
      },
      createdAt: created is Timestamp ? created.toDate() : null,
      shared: shared,
    );
  }
}

/// Where a shared idea stands — one record for both matchmakers
/// (`ideaProposals/{id}.idea`). The two local copies are oriented the same
/// way (the man and the woman), so "שאלתי את הבחור" means the same on both.
class SharedIdeaState {
  const SharedIdeaState({
    required this.status,
    this.askedMaleAt,
    this.askedFemaleAt,
    this.updatedBy,
    this.updatedAt,
  });

  final MatchStatus status;
  final DateTime? askedMaleAt;
  final DateTime? askedFemaleAt;
  final String? updatedBy;
  final DateTime? updatedAt;

  /// A short print of what the two sides must agree on — the status and who
  /// was asked — so a change is noticed once and never echoed back.
  String get print => printOf(status, askedMaleAt, askedFemaleAt);

  static String printOf(
    MatchStatus status,
    DateTime? askedMaleAt,
    DateTime? askedFemaleAt,
  ) =>
      '${status.name}|${askedMaleAt == null ? '' : 'm'}|'
      '${askedFemaleAt == null ? '' : 'f'}';

  Map<String, Object?> toMap(String by) => <String, Object?>{
    'status': status.name,
    'askedMaleAt': askedMaleAt == null
        ? null
        : Timestamp.fromDate(askedMaleAt!),
    'askedFemaleAt': askedFemaleAt == null
        ? null
        : Timestamp.fromDate(askedFemaleAt!),
    'updatedBy': by,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static SharedIdeaState? fromMap(Object? raw) {
    if (raw is! Map) return null;
    MatchStatus? status;
    for (final MatchStatus s in MatchStatus.values) {
      if (s.name == raw['status']) status = s;
    }
    if (status == null) return null;
    DateTime? time(Object? v) => v is Timestamp ? v.toDate() : null;
    return SharedIdeaState(
      status: status,
      askedMaleAt: time(raw['askedMaleAt']),
      askedFemaleAt: time(raw['askedFemaleAt']),
      updatedBy: raw['updatedBy'] as String?,
      updatedAt: time(raw['updatedAt']),
    );
  }
}
