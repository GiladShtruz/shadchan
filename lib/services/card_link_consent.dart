import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

/// **A friend the matchmaker already keeps by hand is never taken over by
/// their personal card without being asked.**
///
/// When a friend who is already in the database (typed in, imported from the
/// contacts) writes a personal card and the matchmaker gets access to it, the
/// card would otherwise land on that record silently: its details and its
/// filter rewritten by somebody else. So the link waits for a "yes" — given
/// either up front, when the matchmaker asks for access from that friend's own
/// profile (the request dialog explains it), or afterwards, from the notice or
/// from "חברים שהוסיפו כרטיס אישי". After the yes there is one record,
/// followed by the card, with every note, tag, idea, reminder and line of
/// history the matchmaker had kept on it.
///
/// Stored per card owner (`settings` key [key], a JSON list of uids). It is
/// the matchmaker's decision about their own database, so it travels with the
/// account like every other synced setting.
abstract final class CardLinkConsent {
  static const String key = 'cardLink.confirmed';

  /// Written this frame and not yet on disk.
  static Set<String>? _pending;

  static Set<String> _read() {
    final Set<String>? pending = _pending;
    if (pending != null) {
      return pending;
    }
    if (!Hive.isBoxOpen('settings')) {
      return <String>{};
    }
    final Object? raw = Hive.box<dynamic>('settings').get(key);
    if (raw is! String) {
      return <String>{};
    }
    try {
      final Object? json = jsonDecode(raw);
      return json is List ? json.whereType<String>().toSet() : <String>{};
    } on FormatException {
      return <String>{};
    }
  }

  static bool isConfirmed(String ownerUid) => _read().contains(ownerUid);

  static void confirm(String ownerUid) {
    final Set<String> all = _read()..add(ownerUid);
    _write(all);
  }

  /// Taken back — the request it was given with was never sent.
  static void withdraw(String ownerUid) {
    final Set<String> all = _read();
    if (all.remove(ownerUid)) {
      _write(all);
    }
  }

  static void _write(Set<String> all) {
    _pending = all;
    final String value = jsonEncode(all.toList()..sort());
    // Written from the root zone, like every home setting: a Hive write
    // started inside a widget test's fake-async zone never completes.
    Zone.root.scheduleMicrotask(() async {
      try {
        if (Hive.isBoxOpen('settings')) {
          await Hive.box<dynamic>('settings').put(key, value);
        }
      } catch (_) {
        // The cache below still answers for this session.
        return;
      }
      if (identical(_pending, all)) _pending = null;
    });
  }

  /// For a sign-out or an account change.
  static void forgetCache() => _pending = null;
}
