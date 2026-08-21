import 'package:hive/hive.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/utils/enums.dart';

part 'match_idea.g.dart';

@HiveType(typeId: 1)
class MatchIdea extends HiveObject {
  MatchIdea({
    required this.id,
    required this.personAId,
    required this.personBId,
    required this.status,
    required this.currentHandler,
    required this.createdAt,
    required this.updatedAt,
    this.handlerName,
    this.reminderDate,
    this.reminderNote,
    this.waitingReason,
    this.progress,
    this.progressOther,
    this.relatedContacts = const <MatchContact>[],
    this.lastShareLabel,
    this.lastShareAt,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String personAId;

  @HiveField(2)
  final String personBId;

  // defaultValue guards against reading records from older app versions where
  // these non-nullable fields may be absent (which would read back as null and
  // crash the type cast).
  @HiveField(3, defaultValue: MatchStatus.idea)
  MatchStatus status;

  @HiveField(4, defaultValue: CurrentHandler.me)
  CurrentHandler currentHandler;

  @HiveField(5)
  String? handlerName;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  DateTime updatedAt;

  @HiveField(8)
  DateTime? reminderDate;

  @HiveField(9)
  String? reminderNote;

  /// Why this proposal is waiting, in the matchmaker's words ("היא תפוסה").
  /// Set from the card when moving a proposal to "בהמתנה"; also marks the pause
  /// as deliberate, so it is not reopened automatically when both sides happen
  /// to be available.
  @HiveField(10)
  String? waitingReason;

  /// Where the outreach stands ("איפה זה עומד?"). Optional; null means it was
  /// never set.
  @HiveField(11)
  MatchProgress? progress;

  /// Free text used when [progress] is [MatchProgress.other].
  @HiveField(12)
  String? progressOther;

  /// Extra contacts tied to this proposal (a parent, a reference). Empty on
  /// records written before the field existed.
  @HiveField(13, defaultValue: <MatchContact>[])
  List<MatchContact> relatedContacts;

  /// What the last card sent out of this proposal was, in the words the card
  /// itself says: "הכרטיס של שרה נשלח לדוד".
  ///
  /// **This is the whole state behind "יאללה לקדם!".** The row over the status
  /// actions is a prompt while it is null and a report once it is not, which
  /// is the difference between a proposal nobody has touched and one that is
  /// out with somebody and waiting for an answer. Storing the sentence rather
  /// than an enum of ways-to-share is deliberate: what a matchmaker wants to
  /// read a week later is who got what, and that is a sentence.
  @HiveField(14)
  String? lastShareLabel;

  /// When [lastShareLabel] happened, so the row can say "לפני שבוע" rather
  /// than only what was sent.
  @HiveField(15)
  DateTime? lastShareAt;
}
