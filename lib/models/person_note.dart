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
    this.audioFile,
    this.audioDurationMs,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String personId;

  @HiveField(2)
  String text;

  @HiveField(3)
  DateTime createdAt;

  @HiveField(4, defaultValue: false)
  bool isAutomatic;

  /// A voice note: the recording's file name inside `voice_notes/` in the
  /// app's own documents — a name, not a path, because iOS moves the app's
  /// container on every update. Null for a written note. The recording stays
  /// on this device: the cloud backup carries the note's text and date, not
  /// the audio. See `VoiceNoteStore`.
  @HiveField(5)
  String? audioFile;

  /// How long the recording is, when it was known at the time it was saved.
  @HiveField(6)
  int? audioDurationMs;

  bool get isVoice => (audioFile ?? '').isNotEmpty;
}
