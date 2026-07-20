import 'package:hive/hive.dart';

/// Per-person "soft rejected" suggestion candidates, stored in the local
/// Hive `settings` box so they survive app restarts.
///
/// Dismissing a suggested candidate only pushes them to the end of the
/// suggestions list for that source person — it does not create a rejected
/// proposal, so the pair never appears under רעיונות שנשללו.
abstract final class SuggestionDismissals {
  static const String _keyPrefix = 'suggestionDismissals.';

  static Box<dynamic> get _box => Hive.box<dynamic>('settings');

  static Set<String> dismissedFor(String personId) {
    final Object? stored = _box.get('$_keyPrefix$personId');
    if (stored is! List) {
      return <String>{};
    }
    return stored.whereType<String>().toSet();
  }

  static bool isDismissed(String personId, String candidateId) {
    return dismissedFor(personId).contains(candidateId);
  }

  static Future<void> dismiss(String personId, String candidateId) async {
    final Set<String> ids = dismissedFor(personId)..add(candidateId);
    await _box.put('$_keyPrefix$personId', ids.toList());
  }

  static Future<void> restore(String personId, String candidateId) async {
    final Set<String> ids = dismissedFor(personId)..remove(candidateId);
    if (ids.isEmpty) {
      await _box.delete('$_keyPrefix$personId');
    } else {
      await _box.put('$_keyPrefix$personId', ids.toList());
    }
  }
}
