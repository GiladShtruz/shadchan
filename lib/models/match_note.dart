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
    this.mazelTovFrom,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String matchId;

  @HiveField(2)
  String text;

  @HiveField(3)
  DateTime createdAt;

  @HiveField(4, defaultValue: false)
  bool isAutomatic;

  /// The name of the matchmaker who sent this line as a "מזל טוב", or null for
  /// every ordinary journal entry.
  ///
  /// **One nullable field rather than a flag and a name.** A congratulation
  /// always comes from somebody — an anonymous one would be a line of text with
  /// nobody behind it, which is not what arrives here — so "is this a מזל טוב"
  /// and "who from" are the same question, and storing them apart would allow a
  /// state that cannot exist.
  ///
  /// Set only by [MatchRepository.addMazelTov], which is the only path from the
  /// shared inbox into a matchmaker's own journal. Everything else in the app
  /// that writes a note leaves it null, and the journal draws those exactly as
  /// it always has.
  @HiveField(5)
  String? mazelTovFrom;
}
