import 'package:hive/hive.dart';
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
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String personAId;

  @HiveField(2)
  final String personBId;

  @HiveField(3)
  MatchStatus status;

  @HiveField(4)
  CurrentHandler currentHandler;

  @HiveField(5)
  String? handlerName;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  DateTime updatedAt;
}
