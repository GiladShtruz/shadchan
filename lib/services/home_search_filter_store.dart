import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';

/// The filter set from the home search row, kept between visits and
/// launches until the matchmaker clears it ("ניקוי הסינון").
///
/// Write-through like the other home stores: [persistHomeSetting] writes in
/// the root zone, and [_pending] answers reads in the same frame.
abstract final class HomeSearchFilterStore {
  static const String _key = 'home.searchFilters';

  static String? _pending;

  /// See `LocalSettingCaches.forgetAll`.
  static void forgetCache() => _pending = null;

  /// The saved filter, or null when none is set.
  static PeopleFilterState? get filters {
    final Object? raw =
        _pending ??
        (Hive.isBoxOpen('settings')
            ? Hive.box<dynamic>('settings').get(_key)
            : null);
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    try {
      final Object? json = jsonDecode(raw);
      if (json is! Map) {
        return null;
      }
      final PeopleFilterState state = PeopleFilterState.fromJson(
        json.cast<String, Object?>(),
      );
      return state.isEmpty ? null : state;
    } catch (_) {
      return null;
    }
  }

  /// Saves [value]; null or an empty filter clears it.
  static set filters(PeopleFilterState? value) {
    final String raw = value == null || value.isEmpty
        ? ''
        : jsonEncode(value.toJson());
    _pending = raw;
    persistHomeSetting(_key, raw);
  }

  /// Forgets it — on sign-out, with the rest of the local data.
  static void reset() => filters = null;

  @visibleForTesting
  static void resetForTest() => _pending = null;
}
