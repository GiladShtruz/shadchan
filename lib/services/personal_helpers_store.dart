import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Hiding is reversible presentation state, independent from grants/blocks.
abstract final class PersonalHelpersStore {
  static const key = 'personalCard.hiddenHelpers';
  static final revision = ValueNotifier<int>(0);
  static Set<String>? _pending;
  static int _version = 0;
  static Set<String> get hidden => Set<String>.from(
    _pending ??
        (Hive.isBoxOpen('settings')
            ? (Hive.box<dynamic>('settings').get(key) as List?)
                  ?.whereType<String>()
                  .toSet()
            : null) ??
        <String>{},
  );
  static void hide(String uid, bool value) {
    final values = hidden;
    value ? values.add(uid) : values.remove(uid);
    _pending = values;
    final version = ++_version;
    revision.value++;
    // Like persistHomeSetting: disk I/O must outlive a widget's async zone.
    Zone.root.scheduleMicrotask(() async {
      try {
        if (Hive.isBoxOpen('settings')) {
          await Hive.box<dynamic>('settings').put(key, values.toList());
        }
      } catch (error) {
        debugPrint('Hidden helpers could not be saved: $error');
      } finally {
        if (_version == version) _pending = null;
      }
    });
  }

  static void forgetCache() {
    _version++;
    _pending = null;
  }
}
