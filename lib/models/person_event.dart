import 'package:hive/hive.dart';

part 'person_event.g.dart';

/// The kinds of meaningful events recorded on a person's history timeline.
/// Used both for phrasing and for the filters on the full history screen
/// (הכל / הצעות / יצאו / שלילות / הערות).
@HiveType(typeId: 13)
enum PersonEventType {
  @HiveField(0)
  proposalOpened,

  @HiveField(1)
  dated,

  @HiveField(2)
  rejected,

  @HiveField(3)
  statusChanged,

  @HiveField(4)
  note,

  @HiveField(5)
  cardChanged,

  @HiveField(6)
  reminderSet,
}

/// A single entry in a person's history log. This is the dedicated event store
/// behind the profile's "היסטוריה אחרונה" feed and the full history screen —
/// separate from [PersonNote], which holds the matchmaker's personal notes.
@HiveType(typeId: 12)
class PersonEvent extends HiveObject {
  PersonEvent({
    required this.id,
    required this.personId,
    required this.type,
    required this.text,
    required this.createdAt,
    this.relatedPersonId,
    this.relatedMatchId,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String personId;

  @HiveField(2)
  final PersonEventType type;

  @HiveField(3)
  String text;

  @HiveField(4)
  DateTime createdAt;

  /// The other side of a proposal-related event, when relevant.
  @HiveField(5)
  String? relatedPersonId;

  /// The proposal this event came from, when relevant.
  @HiveField(6)
  String? relatedMatchId;
}
