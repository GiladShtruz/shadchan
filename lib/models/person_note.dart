import 'package:hive/hive.dart';

part 'person_note.g.dart';

@HiveType(typeId: 8)
class PersonNote extends HiveObject {
  PersonNote({
    required this.id,
    required this.personId,
    required this.text,
    required this.createdAt,
    required this.isAutomatic,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String personId;

  @HiveField(2)
  String text;

  @HiveField(3)
  DateTime createdAt;

  @HiveField(4)
  bool isAutomatic;
}
