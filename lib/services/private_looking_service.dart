import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/voice_note_store.dart';

/// Never part of Person, card exports, notes, backups or matching telemetry.
abstract final class PrivateLookingService {
  static const maxDurationMs = 600000;
  static const maxBytes = 30 * 1024 * 1024;
  static DocumentReference<Map<String, dynamic>> doc(String uid) =>
      FirebaseFirestore.instance.collection('privateLooking').doc(uid);

  static Future<({String name, int durationMs})> importAudio(
    String source,
  ) async {
    if (!VoiceNoteStore.isAudioPath(source) ||
        await File(source).length() > maxBytes) {
      throw const FormatException('יש לבחור הקלטת קול עד 30 מגה־בייט');
    }
    final player = AudioPlayer();
    try {
      Duration? duration;
      try {
        duration = await player.setFilePath(source);
      } catch (_) {
        /* The server decodes and, when needed, converts WhatsApp's container. */
      }
      if (duration != null &&
          (duration.inMilliseconds <= 0 ||
              duration.inMilliseconds > maxDurationMs)) {
        throw const FormatException('אפשר לצרף הקלטה אחת באורך של עד 10 דקות');
      }
      final name = await VoiceNoteStore.importFile(source);
      if (name == null) throw const FormatException('לא ניתן לקרוא את ההקלטה');
      return (name: name, durationMs: duration?.inMilliseconds ?? 0);
    } finally {
      await player.dispose();
    }
  }

  static Future<void> save({
    required String text,
    String? newAudio,
    String? audioPath,
    int? durationMs,
  }) async {
    final uid = await PersonalCardService.durableUid();
    if (uid == null) throw StateError('נדרשת התחברות');
    if (newAudio != null) {
      final file = await VoiceNoteStore.fileFor(newAudio);
      audioPath = 'privateLooking/$uid/$newAudio';
      final ref = FirebaseStorage.instance.ref(audioPath);
      var uploaded = false;
      try {
        uploaded = (await ref.getMetadata()).size == await file.length();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
      if (!uploaded) {
        await ref.putFile(
          file,
          SettableMetadata(contentType: _contentType(newAudio)),
        );
      }
    }
    await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('savePrivateLooking')
        .call({'text': text.trim(), 'audioPath': audioPath});
  }

  static String _contentType(String name) {
    if (name.endsWith('.mp3')) return 'audio/mpeg';
    if (name.endsWith('.wav')) return 'audio/wav';
    if (name.endsWith('.opus') ||
        name.endsWith('.ogg') ||
        name.endsWith('.oga')) {
      return 'audio/ogg';
    }
    if (name.endsWith('.amr')) return 'audio/amr';
    return 'audio/mp4';
  }
}
