import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/ai_client.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/utils/ai_config.dart';
import 'package:shadchan/utils/chat_idea_command.dart';

/// Gemini reading a sentence written in a chat between matchmakers — only
/// when the local reading ([ChatIdeaCommand.parse]) found no two names.
///
/// **Only the sentence is sent**, never a card or anything from the
/// database; the model returns two name strings and the app resolves them
/// against real cards itself, asking whenever there is any doubt.
abstract final class AiChatCommand {
  static final Schema _schema = Schema.object(
    properties: <String, Schema>{
      'isIdeaRequest': Schema.boolean(),
      'firstPerson': Schema.string(nullable: true),
      'secondPerson': Schema.string(nullable: true),
    },
  );

  static const String _instruction =
      'You read one Hebrew sentence a matchmaker wrote in a chat. Decide '
      'whether it asks to open (or propose) a shidduch idea between two '
      'people, and if so return the two people\'s names exactly as written, '
      'without Hebrew prefix letters such as ל or ו that are not part of the '
      'name. Never invent a name. If it is not such a request, return '
      'isIdeaRequest false and null names.';

  /// The two names, or null when the sentence is not such a request or the
  /// model could not be reached.
  static Future<NamePair?> extract(String sentence) async {
    try {
      await FirebaseBootstrap.ensureReady();
      if (!FirebaseBootstrap.isReady) return null;
      final GenerateContentResponse response =
          await AiClient.model(
                systemInstruction: Content.system(_instruction),
                generationConfig: GenerationConfig(
                  responseMimeType: 'application/json',
                  responseSchema: _schema,
                  temperature: 0,
                  thinkingConfig: ThinkingConfig.withThinkingLevel(
                    AiConfig.thinkingLevel,
                  ),
                ),
              )
              .generateContent(<Content>[Content.text(sentence)])
              .timeout(const Duration(seconds: 30));
      return decode(response.text);
    } catch (error) {
      debugPrint('AiChatCommand: $error');
      return null;
    }
  }

  /// The model's answer as a pair — only when it said yes and gave two names.
  @visibleForTesting
  static NamePair? decode(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      final Object? data = jsonDecode(text);
      if (data is! Map || data['isIdeaRequest'] != true) return null;
      final Object? a = data['firstPerson'];
      final Object? b = data['secondPerson'];
      if (a is! String || b is! String) return null;
      if (a.trim().isEmpty || b.trim().isEmpty) return null;
      return (a.trim(), b.trim());
    } catch (_) {
      return null;
    }
  }
}
