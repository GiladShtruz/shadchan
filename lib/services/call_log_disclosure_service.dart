import 'package:hive/hive.dart';

/// Tracks whether the matchmaker has already seen and agreed to the
/// call-log disclosure — see [CallLogSortService].
///
/// Google Play requires "prominent disclosure" before an app first touches
/// the call log: an explanation *inside the app*, with its own accept/decline,
/// shown before the system permission dialog. The system dialog alone does not
/// satisfy that requirement, and Android only ever shows it once per install
/// anyway — so this flag is what lets the add-contacts flow show its own
/// explanation on the very first run and then get out of the way.
abstract final class CallLogDisclosureService {
  static const String _boxName = 'call_log_disclosure';
  static const String _acknowledgedKey = 'acknowledged';

  static Future<bool> wasAcknowledged() async {
    final Box<dynamic> box = await _openBox();
    return box.get(_acknowledgedKey, defaultValue: false) as bool;
  }

  static Future<void> markAcknowledged() async {
    final Box<dynamic> box = await _openBox();
    await box.put(_acknowledgedKey, true);
  }

  static Future<Box<dynamic>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<dynamic>(_boxName);
    }
    return Hive.openBox<dynamic>(_boxName);
  }
}
