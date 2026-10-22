import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Account identity stays individual; this is only the matchmaker database.
abstract final class CoupleWorkspaceService {
  static final ValueNotifier<Map<String, dynamic>?> membership = ValueNotifier(
    null,
  );
  static final ValueNotifier<int> recordsRevision = ValueNotifier(0);
  static final Map<String, Map<String, dynamic>> metadata = {};
  static String? get databaseUid => membership.value?['databaseUid'] as String?;
  static String? get workspaceId => membership.value?['operation'] as String?;
  static bool get isCouple => databaseUid != null;
  static bool get ready => !isCouple || membership.value?['state'] == 'active';
  static String? get name => membership.value?['name'] as String?;
  static List<String> get members =>
      (membership.value?['members'] as List?)?.cast<String>() ?? [];
  static Map<String, String> get names =>
      Map<String, String>.from(membership.value?['names'] as Map? ?? {});
  static String get currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  static bool sharedSetting(String key) => [
    'home.board',
    'tags.',
    'tagLibrary',
    'suggestionDismiss',
    'cardSyncRemote.',
    'deletedIdeas',
  ].any(key.startsWith);
  static List<String> sources(String id) =>
      (metadata['people/$id']?['_sources'] as List?)?.cast<String>() ?? [];
  static String? author(String collection, String id) =>
      names[(metadata['$collection/$id']?['_authorUid'] ??
          metadata['$collection/$id']?['_actorUid'])];
  static Future<void> claimPerson(String id) async {
    if (!isCouple) return;
    await FirebaseFirestore.instance
        .doc('users/$databaseUid/people/$id')
        .update({
          '_sources': FieldValue.arrayUnion([currentUid]),
          '_actorUid': currentUid,
          '_w': FieldValue.serverTimestamp(),
        });
  }

  static void remember(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) {
    metadata['$collection/$id'] = data;
    recordsRevision.value++;
  }

  static Future<Map<String, dynamic>?> refresh() async {
    final uid = currentUid;
    if (uid.isEmpty) return null;
    final data =
        (await FirebaseFirestore.instance
                .doc('memberships/$uid')
                .get(const GetOptions(source: Source.server)))
            .data();
    if (data?['operation'] != membership.value?['operation']) {
      metadata.clear();
      recordsRevision.value++;
    }
    membership.value = data;
    return data;
  }

  static Future<Map<String, dynamic>> call(
    String name, [
    Map<String, Object?> data = const {},
  ]) async {
    final response = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        )
        .call(data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Map<String, dynamic> reminder(String id) {
    final raw = Hive.box<dynamic>('settings').get('couple.reminder.$id');
    try {
      return raw is String
          ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
          : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveReminder(String id, Map<String, Object?> data) =>
      Hive.box<dynamic>('settings').put(
        'couple.reminder.$id',
        jsonEncode({
          'reminderDate': data['reminderDate'],
          'reminderNote': data['reminderNote'],
        }),
      );
  static void clear() {
    membership.value = null;
    metadata.clear();
    recordsRevision.value++;
  }
}
