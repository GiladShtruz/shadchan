import 'package:package_info_plus/package_info_plus.dart';

/// The app's own version, read from the platform once and remembered.
///
/// It used to be a `const String` in the settings footer, which is the kind of
/// thing that is right on the day it is written and wrong for every release
/// after it — the footer still said 1.0.0 seventeen versions later. There is
/// exactly one true answer to "which build is this", it lives in the bundle,
/// and this is the one place that asks for it.
abstract final class AppVersion {
  static String _value = '';
  static Future<String>? _pending;

  /// The version if it has already been read, otherwise empty.
  ///
  /// Empty means "not known yet", never "no version": show nothing rather than
  /// a placeholder, because a wrong version number in a bug report costs more
  /// than a missing one.
  static String get value => _value;

  /// Reads the version, caching both the answer and the request.
  ///
  /// Safe to call from `build` — the second caller onwards gets the same future
  /// rather than a fresh platform round trip.
  static Future<String> read() => _pending ??= _read();

  static Future<String> _read() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      _value = info.version;
    } on Object {
      // A platform channel that cannot answer is not worth failing over.
    }
    return _value;
  }
}
