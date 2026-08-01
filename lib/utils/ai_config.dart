/// Central configuration for every Gemini call the app makes.
///
/// Deliberately one file with no logic in it: swapping the model or moving the
/// processing region is a one-line change, and there is exactly one place to
/// audit when someone asks where the data goes.
abstract final class AiConfig {
  /// The Gemini model used for all import parsing — text, tables and images.
  static const String model = 'gemini-3.6-flash';

  /// The Vertex AI region requests are processed in.
  ///
  /// `global` rather than an EU region, because the 3.x Gemini models are only
  /// served from the global endpoint — europe-west4 and every other EU region
  /// stop at the 2.5 family. Pinning the region was one of the two reasons for
  /// choosing Vertex AI over the Gemini Developer API, and it was traded away
  /// for the newer model; the other reason still holds, and is why this stays
  /// on Vertex: the Google Cloud data-processing terms are a contractual
  /// commitment not to train on the content or retain it, rather than a
  /// product policy. If a future model reaches the EU regions, moving back is
  /// this one line.
  static const String vertexLocation = 'global';

  /// How long a single request may take before it is treated as failed.
  ///
  /// Deliberately far longer than any real batch. A large import legitimately
  /// takes minutes — a full chat export ran for two of them and returned 216
  /// people — and cutting that off loses work that was about to succeed. The
  /// limit exists only so a request that will never answer cannot leave the
  /// screen spinning forever with nothing to report and no way back.
  static const Duration requestTimeout = Duration(minutes: 10);

  /// Thinking is switched off for import parsing.
  ///
  /// Measured on one real batch of 25 spreadsheet rows: with the default the
  /// model spent 22,542 thinking tokens and 119 seconds; with thinking off,
  /// 37 seconds — and returned the same 78 people. Reading a name out of a
  /// cell is not a problem that rewards deliberation, and the whole cost of it
  /// lands on someone watching a progress bar.
  static const int thinkingBudget = 0;
}
