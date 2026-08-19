import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';

/// What each side of a proposal was before the app marked them "תפוס".
///
/// **Because "פנוי" is a guess, and this is the answer.** When a couple starts
/// dating the app overwrites both candidates' availability, and when they stop
/// it has to put something back. Everybody who was available before goes back
/// to available and nobody notices — but somebody who was "בהפסקה" when the
/// proposal moved is quietly returned to the pool, and the matchmaker who put
/// them on a break is the last person to find out. Remembering the one value
/// that was overwritten costs a string per couple and removes the guess.
///
/// Keyed by proposal *and* person, because the same candidate can be out with
/// two people at once and each proposal must only ever undo its own doing.
///
/// Deliberately in the settings box rather than on the [Person]: it is a scrap
/// of state about an event in progress, not a fact about anybody, and it should
/// not travel in a backup or outlive the app being reinstalled.
abstract final class DatingStatusMemory {
  static const String _key = 'datingStatusBeforeBusy';

  /// The `settings` box is opened by `main.dart`, so a test that only wanted a
  /// proposal repository has not got one. Guarded exactly like
  /// `DatingCountExclusions`: with no box there is simply nothing remembered,
  /// and the release falls back to "פנוי" as it always did.
  static bool get _isReady => Hive.isBoxOpen('settings');

  static Box<dynamic> get _box => Hive.box<dynamic>('settings');

  static String _entryKey(String matchId, String personId) =>
      '$matchId|$personId';

  static Map<String, String> _all() {
    if (!_isReady) {
      return <String, String>{};
    }
    final Object? stored = _box.get(_key);
    if (stored is! Map) {
      return <String, String>{};
    }
    return <String, String>{
      for (final MapEntry<Object?, Object?> entry in stored.entries)
        if (entry.key is String && entry.value is String)
          entry.key! as String: entry.value! as String,
    };
  }

  static Future<void> _save(Map<String, String> value) async {
    if (!_isReady) {
      return;
    }
    await _box.put(_key, value);
  }

  /// Records what [personId] was before this proposal took over their status.
  ///
  /// Only the two statuses worth restoring are kept. "תפוס" is what we are
  /// about to write, and "מזל טוב" belongs to a couple who married — restoring
  /// either would be undoing the wrong thing.
  static Future<void> remember({
    required String matchId,
    required String personId,
    required ProfileStatus status,
  }) async {
    if (status != ProfileStatus.available && status != ProfileStatus.onBreak) {
      return;
    }
    final Map<String, String> all = _all()
      ..[_entryKey(matchId, personId)] = status.name;
    await _save(all);
  }

  /// What to put back, or [ProfileStatus.available] when nothing was recorded —
  /// which is every couple who started dating before this existed, and the
  /// right answer for almost all of them.
  static ProfileStatus restoreFor({
    required String matchId,
    required String personId,
  }) {
    final String? name = _all()[_entryKey(matchId, personId)];
    return switch (name) {
      'onBreak' => ProfileStatus.onBreak,
      _ => ProfileStatus.available,
    };
  }

  /// Drops what was remembered for one side of one proposal. Called once the
  /// status has been put back, and when a couple marries — there is nothing
  /// left to restore in either case.
  static Future<void> forget({
    required String matchId,
    required String personId,
  }) async {
    final Map<String, String> all = _all();
    if (all.remove(_entryKey(matchId, personId)) == null) {
      return;
    }
    await _save(all);
  }
}
