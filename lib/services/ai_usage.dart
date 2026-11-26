import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';

/// Which part of the app made an AI request — the admin dashboard's
/// breakdown. A code, never anything the user typed.
enum AiFeature {
  /// One pasted card read into the add-friend form.
  card,

  /// A batch import: Excel, a WhatsApp export, pasted text, a photo.
  import,

  /// "פתח רעיון בין … ל…" read in a chat.
  chat,
}

/// **What the AI costs, per account.** Every Gemini answer carries how many
/// tokens it read and wrote; this adds them to `aiUsage/{uid}` — totals, the
/// month, and the feature — with Firestore increments, so two phones of one
/// account never overwrite each other and nothing has to be read first.
///
/// Only counts leave the device: never the text, never a name. The support
/// console reads the collection (administrators only) and turns the tokens
/// into money with the prices kept in `adminConfig/pricing`.
///
/// Never throws and never delays the import: it is fire-and-forget after the
/// answer is already in hand.
abstract final class AiUsage {
  static const String collection = 'aiUsage';

  /// Test seam: what would have been written.
  @visibleForTesting
  static void Function(Map<String, Object?> increments)? debugSink;

  /// The month key the counters are filed under, e.g. `2026-11`.
  static String monthKey(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}';

  /// The increments one answer adds, by field path.
  static Map<String, Object?> incrementsFor(
    AiFeature feature, {
    required int input,
    required int output,
    DateTime? at,
  }) {
    final String month = monthKey(at ?? DateTime.now());
    return <String, Object?>{
      'calls': 1,
      'inputTokens': input,
      'outputTokens': output,
      'months.$month.calls': 1,
      'months.$month.inputTokens': input,
      'months.$month.outputTokens': output,
      'features.${feature.name}.calls': 1,
      'features.${feature.name}.inputTokens': input,
      'features.${feature.name}.outputTokens': output,
    };
  }

  /// Records one answer. Call it right after `generateContent` returns.
  static void record(GenerateContentResponse response, AiFeature feature) {
    final UsageMetadata? usage = response.usageMetadata;
    final Map<String, Object?> increments = incrementsFor(
      feature,
      input: usage?.promptTokenCount ?? 0,
      // Thinking is billed as output.
      output:
          (usage?.candidatesTokenCount ?? 0) + (usage?.thoughtsTokenCount ?? 0),
    );
    final void Function(Map<String, Object?>)? sink = debugSink;
    if (sink != null) {
      sink(increments);
      return;
    }
    _write(increments);
  }

  static Future<void> _write(Map<String, Object?> increments) async {
    try {
      if (!FirebaseBootstrap.isReady) return;
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final Map<String, Object?> data = <String, Object?>{
        for (final MapEntry<String, Object?> e in increments.entries)
          e.key: FieldValue.increment(e.value! as int),
        'lastAt': FieldValue.serverTimestamp(),
      };
      // `update` understands dotted paths as nested fields; a first write has
      // nothing to update, so it falls back to a merge of the same values.
      final DocumentReference<Map<String, dynamic>> doc = FirebaseFirestore
          .instance
          .collection(collection)
          .doc(user.uid);
      try {
        await doc.update(data);
      } on FirebaseException catch (error) {
        if (error.code != 'not-found') rethrow;
        await doc.set(_nested(increments), SetOptions(merge: true));
      }
    } catch (error) {
      debugPrint('AiUsage: $error');
    }
  }

  /// Dotted paths as nested maps, for the very first write.
  static Map<String, Object?> _nested(Map<String, Object?> increments) {
    final Map<String, Object?> root = <String, Object?>{
      'lastAt': FieldValue.serverTimestamp(),
    };
    for (final MapEntry<String, Object?> e in increments.entries) {
      final List<String> parts = e.key.split('.');
      Map<String, Object?> node = root;
      for (final String part in parts.sublist(0, parts.length - 1)) {
        node = (node[part] ??= <String, Object?>{}) as Map<String, Object?>;
      }
      node[parts.last] = FieldValue.increment(e.value! as int);
    }
    return root;
  }
}
