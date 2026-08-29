import 'package:firebase_ai/firebase_ai.dart';
import 'package:shadchan/utils/ai_config.dart';

/// The one place in the app that talks to Gemini.
///
/// Every import parser goes through here rather than reaching for
/// [FirebaseAI] itself, so the backend, model and region are decided in
/// [AiConfig] alone and there is a single seam to stub in tests.
abstract final class AiClient {
  /// Builds a model for one request.
  ///
  /// Instances are cheap and [FirebaseAI] caches the underlying handle per
  /// location, so callers create one per call with the system instruction and
  /// output schema that fit their own parsing job rather than sharing a model
  /// configured for someone else's.
  ///
  /// Limited-use App Check tokens are on so that the console's replay
  /// protection can be enforced: each request then carries a fresh, single-use
  /// token instead of reusing the cached one for the hour, and a token lifted
  /// off one request buys an attacker nothing on the next. The cost is a full
  /// Play Integrity attestation per call rather than per hour, which is
  /// seconds on the first one — worth it only because an import is already a
  /// slow, deliberate action rather than something on a hot path.
  static GenerativeModel model({
    Content? systemInstruction,
    GenerationConfig? generationConfig,
  }) {
    return FirebaseAI.vertexAI(
      location: AiConfig.vertexLocation,
      useLimitedUseAppCheckTokens: true,
    ).generativeModel(
      model: AiConfig.model,
      systemInstruction: systemInstruction,
      generationConfig: generationConfig,
    );
  }

  /// A minimal round trip, used to prove the whole chain works: App Check
  /// attestation, anonymous auth, the Vertex backend and the model name.
  ///
  /// Returns the model's reply, or throws — callers decide how loud to be.
  static Future<String?> ping() async {
    final GenerateContentResponse response = await model().generateContent(
      <Content>[Content.text('Reply with exactly: OK')],
    );
    return response.text;
  }
}
