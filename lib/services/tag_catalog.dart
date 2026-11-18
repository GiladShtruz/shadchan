import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/offline_cache.dart';
import 'package:shadchan/utils/person_tags.dart';

/// The shared list of tags — what a single picks from to describe themselves
/// on their personal card, and the ready-made tags a matchmaker is offered.
///
/// **One vocabulary for both sides** is what makes a tag useful for matching:
/// a single who chose "אוהב/ת טבע" and a matchmaker who tagged a friend
/// "אוהב/ת טבע" are now saying the same word, and the automatic matches give
/// a pair that shares tags a lift.
///
/// The administrator edits the list from the console (`tagCatalog/base`): add,
/// delete, rename, reorder. Every install reads it and keeps the last answer
/// on the device ([OfflineCache], never synced to the account). Until the
/// server has answered once — or if it never has — [defaults] is the list.
abstract final class TagCatalog {
  static const String collection = 'tagCatalog';
  static const String document = 'base';
  static const String _cacheKey = 'tagCatalog.base';

  /// The most tags the list may hold, and the most a single may choose.
  static const int maxTags = 200;
  static const int maxChosen = 12;

  /// The fifty the app starts with.
  static const List<String> defaults = <String>[
    'תורני/ת',
    'דתי/ה־לאומי/ת',
    'חרד״לי/ת',
    'מסורתי/ת',
    'פתוח/ה',
    'שמרני/ת',
    'רוחני/ת',
    'משפחתי/ת',
    'קהילתי/ת',
    'לימוד תורה',
    'אקדמאי/ת',
    'סטודנט/ית',
    'קרייריסט/ית',
    'עצמאי/ת',
    'חינוך',
    'טיפול',
    'טכנולוגיה',
    'יצירתי/ת',
    'מוזיקלי/ת',
    'אמנות',
    'ספורטיבי/ת',
    'אוהב/ת טבע',
    'טיולים',
    'ספרים',
    'תרבות',
    'התנדבות',
    'שליחות',
    'חברותי/ת',
    'שקט/ה',
    'מופנם/ת',
    'מוחצן/ת',
    'קליל/ה',
    'עמוק/ה',
    'רגיש/ה',
    'מצחיק/ה',
    'ספונטני/ת',
    'מסודר/ת',
    'שאפתני/ת',
    'סקרן/ית',
    'ביתי/ת',
    'הרפתקני/ת',
    'אוהב/ת אנשים',
    'אוהב/ת ילדים',
    'משפחה גדולה',
    'עירוני/ת',
    'מושב/יישוב',
    'מרכז הארץ',
    'ירושלים',
    'צפון',
    'דרום',
  ];

  /// Bumped whenever [current] changes, for whoever draws it.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<String>? _memory;

  /// The list as it stands: the administrator's, or [defaults].
  static List<String> get current {
    final List<String>? memory = _memory;
    if (memory != null) return memory;
    final Map<String, Object?>? cached = OfflineCache.read(_cacheKey);
    final List<String>? stored = _decode(cached?['tags']);
    return _memory = stored ?? defaults;
  }

  /// Whether [tag] is one of the shared list's words.
  static bool contains(String tag) {
    final String key = PersonTags.keyOf(tag);
    return current.any((String t) => PersonTags.keyOf(t) == key);
  }

  static List<String>? _decode(Object? raw) {
    if (raw is! List) return null;
    final List<String> tags = clean(raw.whereType<String>());
    return tags.isEmpty ? null : tags;
  }

  /// Trimmed, de-duplicated (by [PersonTags.keyOf]), empty ones dropped, in
  /// order, and no longer than [maxTags].
  static List<String> clean(Iterable<String> raw) {
    final Set<String> seen = <String>{};
    final List<String> out = <String>[];
    for (final String tag in raw) {
      final String value = PersonTags.normalize(tag);
      if (value.isEmpty ||
          value.length > PersonTags.maxLength ||
          !seen.add(PersonTags.keyOf(value))) {
        continue;
      }
      out.add(value);
      if (out.length >= maxTags) break;
    }
    return out;
  }

  static void _set(List<String> tags) {
    _memory = tags;
    OfflineCache.write(_cacheKey, <String, Object?>{'tags': tags});
    revision.value++;
  }

  static DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection(collection).doc(document);

  /// Reads the administrator's list. Quiet on every failure: the last list
  /// (or [defaults]) stays.
  static Future<void> refresh() async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await _doc.get();
      final List<String>? tags = _decode(snapshot.data()?['tags']);
      if (tags != null && !listEquals(tags, current)) {
        _set(tags);
      }
    } on Object catch (error) {
      debugPrint('TagCatalog.refresh failed: $error');
    }
  }

  /// The administrator saves the list. Answers whether the server took it.
  static Future<bool> save(List<String> tags) async {
    final List<String> cleaned = clean(tags);
    if (cleaned.isEmpty) return false;
    try {
      await FirebaseBootstrap.ensureReady();
      await _doc.set(<String, Object?>{
        'tags': cleaned,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _set(cleaned);
      return true;
    } on Object catch (error) {
      debugPrint('TagCatalog.save failed: $error');
      return false;
    }
  }

  /// How the catalogue's tags are used, for the console: per tag key, how
  /// many matchmakers use it in their database and how many singles chose it
  /// on their personal card. Only an administrator can read this.
  static Future<Map<String, TagUsage>> usage() async {
    try {
      await FirebaseBootstrap.ensureReady();
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance.collection('communityTags').get();
      return <String, TagUsage>{
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs)
          doc.id: TagUsage(
            label: (doc.data()['label'] as String?) ?? doc.id,
            matchmakers: (doc.data()['users'] as num?)?.toInt() ?? 0,
            cards: (doc.data()['cards'] as num?)?.toInt() ?? 0,
          ),
      };
    } on Object catch (error) {
      debugPrint('TagCatalog.usage failed: $error');
      return const <String, TagUsage>{};
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _memory = null;
  }
}

/// One tag's use across the app.
class TagUsage {
  const TagUsage({
    required this.label,
    required this.matchmakers,
    required this.cards,
  });

  final String label;

  /// Matchmakers with the tag on at least one friend in their database.
  final int matchmakers;

  /// Singles who chose it on their own personal card.
  final int cards;

  int get total => matchmakers + cards;
}
