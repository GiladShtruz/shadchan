/// Central configuration for every Gemini call the app makes.
///
/// Deliberately one file with no logic in it: swapping the model or moving the
/// processing region is a one-line change, and there is exactly one place to
/// audit when someone asks where the data goes.
abstract final class AiConfig {
  /// The Gemini model used for all import parsing — text, tables and images.
  static const String model = 'gemini-3.5-flash-lite';

  /// The Vertex AI region requests are processed in.
  ///
  /// The app handles personal details of real people who never agreed to their
  /// data leaving the device, so requests are pinned to an EU region rather
  /// than the global endpoint. Vertex AI is used instead of the Gemini
  /// Developer API precisely because it lets us pin this and comes with the
  /// Google Cloud data-processing terms: no training on the content, no
  /// retention beyond the request.
  static const String vertexLocation = 'europe-west4';
}
