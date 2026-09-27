import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/utils/person_tags.dart';

/// "השראה מהקהילה" — tag words other matchmakers use, and nothing else.
///
/// **What leaves the phone is a list of words.** `tagUsage/{uid}` holds the
/// general tags this matchmaker has put on at least one friend — never which
/// friend, never how many, and never a tag [PersonTags.isCommunityShareable]
/// reads as a personal circle (an institution, a unit, a named place). Only
/// the owner can read that document. A Cloud Function counts, per word, how
/// many different matchmakers use it, into `communityTags/{key}`; the rules
/// let the app read a word only once three or more do. Nobody can see who
/// uses a word, or on whom.
///
/// Skipped entirely without a durable account, and in private mode.
abstract final class CommunityTagsService {
  static const String _printKey = 'tags.publishedPrint';

  /// How many different matchmakers must use a word before it is shown.
  static const int minimumUsers = 3;

  static Box<dynamic>? get _settings =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// The shareable tags in use across [people], as they would be published.
  @visibleForTesting
  static List<String> shareableTagsOf(Iterable<Person> people) {
    final List<Person> all = people.toList();
    final Set<String> places = <String>{
      for (final Person person in all)
        if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    };
    final Map<String, String> byKey = <String, String>{};
    for (final Person person in all) {
      for (final String tag in person.tags) {
        if (PersonTags.isCommunityShareable(tag, knownPlaces: places)) {
          byKey.putIfAbsent(
            PersonTags.keyOf(tag),
            () => PersonTags.normalize(tag),
          );
        }
      }
    }
    final List<String> tags = byKey.values.toList()..sort();
    return tags.take(200).toList();
  }

  /// Publishes this matchmaker's shareable tags when they changed since the
  /// last publish. Never starts Firebase; quiet on every failure.
  static Future<void> publishFrom(Iterable<Person> people) async {
    if (!FirebaseBootstrap.isReady || CommunityProfileStore.isPrivate) {
      return;
    }
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return;
    }
    final List<String> tags = shareableTagsOf(people);
    final String print = '${user.uid}:${tags.join('|')}';
    if (_settings?.get(_printKey) == print) {
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('tagUsage').doc(user.uid).set(
        <String, Object>{
          'tags': tags,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      await _settings?.put(_printKey, print);
    } catch (error) {
      debugPrint('CommunityTagsService.publish failed: $error');
    }
  }

  static List<String>? _cache;
  static DateTime? _cachedAt;

  /// Words at least [minimumUsers] matchmakers use, most used first. Cached
  /// for half an hour; an empty list when offline or signed out.
  static Future<List<String>> inspiration() async {
    final DateTime now = DateTime.now();
    if (_cache != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < const Duration(minutes: 30)) {
      return _cache!;
    }
    if (!FirebaseBootstrap.isReady) {
      return const <String>[];
    }
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const <String>[];
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('communityTags')
              .where('users', isGreaterThanOrEqualTo: minimumUsers)
              .orderBy('users', descending: true)
              .limit(80)
              .get();
      final List<({String label, int users})> found =
          <({String label, int users})>[
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in snapshot.docs)
              if (doc.data()['label'] case final String label)
                // Checked again here: the server's filter and this one are two
                // chances to keep a personal circle out of somebody's screen.
                if (PersonTags.isCommunityShareable(label))
                  (
                    label: label,
                    users: (doc.data()['users'] as num?)?.toInt() ?? 0,
                  ),
          ];
      // Most used first. The query already asks for that order; sorting here
      // too keeps it true whatever the server hands back.
      found.sort(
        (({String label, int users}) a, ({String label, int users}) b) =>
            b.users.compareTo(a.users),
      );
      final Set<String> seen = <String>{};
      final List<String> words = <String>[
        for (final ({String label, int users}) item in found)
          if (seen.add(PersonTags.keyOf(item.label))) item.label,
      ];
      _cache = words;
      _cachedAt = now;
      return words;
    } catch (error) {
      debugPrint('CommunityTagsService.inspiration failed: $error');
      return const <String>[];
    }
  }
}
