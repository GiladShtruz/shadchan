import 'package:firebase_ai/firebase_ai.dart';
import 'package:shadchan/services/telemetry.dart';
import 'package:shadchan/utils/ai_config.dart';

/// Which part of the app made an AI request.
enum AiFeature {
  /// One pasted card read into the add-friend form.
  card(AppFeature.ai_card),

  /// A batch import: Excel, a WhatsApp export, pasted text, a photo.
  import(AppFeature.ai_import),

  /// "פתח רעיון בין … ל…" read in a chat.
  chat(AppFeature.ai_chat);

  const AiFeature(this.monitored);

  final AppFeature monitored;
}

/// One AI request, recorded for the monitoring (`Telemetry.aiCall`): the
/// feature, the model, the provider's own token counts, how long it took,
/// whether it worked and how many tries it took. **Never the text** — only
/// the metadata. The server prices it with the pricing version in force.
abstract final class AiUsage {
  /// After a request that answered.
  static void record(
    GenerateContentResponse response,
    AiFeature feature, {
    required int latencyMs,
    int tries = 1,
  }) {
    final UsageMetadata? usage = response.usageMetadata;
    Telemetry.aiCall(
      feature: feature.monitored,
      model: AiConfig.model,
      inputTokens: usage?.promptTokenCount ?? 0,
      // Thinking is billed as output.
      outputTokens:
          (usage?.candidatesTokenCount ?? 0) + (usage?.thoughtsTokenCount ?? 0),
      latencyMs: latencyMs,
      ok: true,
      tries: tries,
    );
  }

  /// After a request that failed (timed out, refused, unavailable).
  static void failure(
    AiFeature feature,
    Object error, {
    required int latencyMs,
    int tries = 1,
  }) {
    Telemetry.aiCall(
      feature: feature.monitored,
      model: AiConfig.model,
      inputTokens: 0,
      outputTokens: 0,
      latencyMs: latencyMs,
      ok: false,
      tries: tries,
      error: error,
    );
  }
}
