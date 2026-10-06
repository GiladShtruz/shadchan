import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/person_tags.dart';

/// The matchmaker's own tags: every tag they have created, most recently used
/// first — including one created and not yet put on anybody, so it is there
/// the next time a friend is added.
///
/// Stored in the `settings` box. The tags on people are the other half of the
/// truth, so [personal] also brings back any tag that is on a friend but not
/// in the stored list (a restored backup, an older build) — the list can be
/// lost without losing anything that is in use.
abstract final class TagLibrary {
  static const String _key = 'tags.library';

  /// Writes land in Hive a microtask later (see [persistHomeSetting]); this is
  /// what makes a tag created this frame readable in the same frame.
  static List<String>? _pending;

  /// See `LocalSettingCaches.forgetAll`.
  static void forgetCache() => _pending = null;

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  static List<String> _stored() {
    final List<String>? pending = _pending;
    if (pending != null) {
      return pending;
    }
    final Object? raw = _box?.get(_key);
    if (raw is! String || raw.isEmpty) {
      return <String>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return <String>[
          for (final Object? item in decoded)
            if (item is String && item.trim().isNotEmpty) item,
        ];
      }
    } on FormatException {
      // A damaged list is rebuilt from the tags in use.
    }
    return <String>[];
  }

  static void _save(List<String> tags) {
    _pending = tags;
    persistHomeSetting(_key, jsonEncode(tags));
  }

  /// Every tag of this matchmaker's, recently used first, then any tag that is
  /// only on people, by how many carry it.
  static List<String> personal(Iterable<Person> people) {
    final List<String> result = <String>[];
    final Set<String> seen = <String>{};
    for (final String tag in _stored()) {
      if (seen.add(PersonTags.keyOf(tag))) {
        result.add(tag);
      }
    }
    final Map<String, int> counts = <String, int>{};
    final Map<String, String> labels = <String, String>{};
    for (final Person person in people) {
      for (final String tag in person.tags) {
        final String key = PersonTags.keyOf(tag);
        if (seen.contains(key)) {
          continue;
        }
        counts[key] = (counts[key] ?? 0) + 1;
        labels.putIfAbsent(key, () => tag);
      }
    }
    final List<String> extra = counts.keys.toList()
      ..sort((String a, String b) => counts[b]!.compareTo(counts[a]!));
    result.addAll(extra.map((String key) => labels[key]!));
    return result;
  }

  /// Every distinct tag on at least one of [people] — what the people filter
  /// offers.
  static List<String> inUse(Iterable<Person> people) {
    final Map<String, String> byKey = <String, String>{};
    for (final Person person in people) {
      for (final String tag in person.tags) {
        byKey.putIfAbsent(PersonTags.keyOf(tag), () => tag);
      }
    }
    final List<String> tags = byKey.values.toList()..sort();
    return tags;
  }

  /// Puts [tag] at the front of the list — created, or simply used again.
  static void remember(String tag) {
    final String value = PersonTags.normalize(tag);
    if (value.isEmpty) {
      return;
    }
    final List<String> tags =
        _stored().where((String t) => !PersonTags.sameTag(t, value)).toList()
          ..insert(0, value);
    _save(tags.take(300).toList());
  }

  /// Removes [tag] from the list. Friends who carry it keep it.
  static void forget(String tag) {
    _save(_stored().where((String t) => !PersonTags.sameTag(t, tag)).toList());
  }

  /// Test seam.
  static void resetForTest() => _pending = null;
}
