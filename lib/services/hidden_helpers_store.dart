import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// A display preference, not a block or an access decision. It only hides
/// matchmakers from the owner's optional "friends who matchmake" suggestion
/// list, never from existing grants, requests, or Firestore permissions.
abstract final class HiddenHelpersStore {
  static const String key = 'personalArea.hiddenHelpers';

  static Set<String> read(Box<dynamic> settings) {
    final Object? raw = settings.get(key);
    if (raw is! String) return <String>{};
    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is! List) return <String>{};
      return parsed
          .whereType<String>()
          .where((String uid) => uid.trim().isNotEmpty)
          .toSet();
    } on FormatException {
      return <String>{};
    }
  }

  static void setHidden(Box<dynamic> settings, String uid, bool hide) {
    if (uid.trim().isEmpty) return;
    final Set<String> ids = read(settings);
    if (hide) {
      ids.add(uid);
    } else {
      ids.remove(uid);
    }
    // The regular account settings sync carries the preference between the
    // owner's devices. Unlike a block, this never writes to cardAccess.
    persistHomeSetting(key, jsonEncode(ids.toList()..sort()));
  }
}
