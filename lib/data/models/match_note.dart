import 'package:hive/hive.dart';

part 'match_note.g.dart';

@HiveType(typeId: 2)
class MatchNote extends HiveObject {
  MatchNote({
    required this.id,
    required this.matchId,
    required this.text,
    required this.createdAt,
    required this.isAutomatic,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String matchId;

  @HiveField(2)
  String text;

  @HiveField(3)
  DateTime createdAt;

  @HiveField(4)
  bool isAutomatic;
}
