import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/account_sync_engine.dart';
import 'package:shadchan/services/account_sync_ledger.dart';
import 'package:shadchan/services/device_facts.dart';

/// What support needs to answer "I don't see my database", and nothing more.
///
/// One document per account, `accountHealth/{uid}`, written by the account's
/// own devices and readable by the account and by support administrators —
/// never by anybody else. It carries the account's identity (uid, address,
/// ways in), and for each device: whether it has read the account, whether its
/// migration was verified and against which numbers, how many records it
/// holds, when it last sent and received, and the last lines of the sync log.
///
/// **No record's contents ever go in here.** The counts are numbers, the log
/// lines are collection names and error codes. The address is already the
/// account's name in Firebase Authentication; it is here so support can find
/// an account by the address its owner writes from.
abstract final class AccountHealthService {
  static const String collection = 'accountHealth';

  /// How many of the sync log's last lines travel with the report.
  static const int logLines = 25;

  /// The least time between two ordinary reports from one device.
  static const Duration minInterval = Duration(minutes: 10);

  static DateTime? _lastReport;

  @visibleForTesting
  static void resetForTest() => _lastReport = null;

  /// The device's part of the report, built from the ledger alone.
  @visibleForTesting
  static Map<String, Object?> deviceReport({
    required AccountSyncLedger ledger,
    required Map<SyncCollection, int> counts,
    required bool running,
    Object? lastError,
    DeviceFacts? facts,
  }) {
    final List<String> log = ledger.log;
    final Map<String, Object?> migration = ledger.migration;
    return <String, Object?>{
      'platform': Platform.operatingSystem,
      if (facts != null) 'os': facts.os,
      if (facts != null) 'device': facts.device,
      if (facts != null) 'appVersion': facts.appVersion,
      'initialPullDone': ledger.initialPullDone,
      'running': running,
      'migration': migration,
      'counts': <String, Object?>{
        for (final MapEntry<SyncCollection, int> e in counts.entries)
          e.key.remote: e.value,
      },
      ...ledger.stats,
      'lastError': lastError == null
          ? null
          : AccountSyncEngine.errorCode(lastError),
      'log': log.length > logLines ? log.sublist(log.length - logLines) : log,
      'reportedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Sends this device's report. [force] skips the throttle — used when
  /// something worth knowing just happened (a migration verified or failed).
  static Future<void> report({
    required AccountSyncLedger ledger,
    required Map<SyncCollection, int> counts,
    required bool running,
    Object? lastError,
    bool force = false,
  }) async {
    final DateTime now = DateTime.now();
    if (!force &&
        _lastReport != null &&
        now.difference(_lastReport!) < minInterval) {
      return;
    }
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return;
    }
    _lastReport = now;
    try {
      final DeviceFacts facts = await DeviceFacts.read();
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(user.uid)
          .set(<String, Object?>{
            'uid': user.uid,
            'email': (user.email ?? '').toLowerCase(),
            'emailVerified': user.emailVerified,
            'providers': <String>[
              for (final UserInfo info in user.providerData) info.providerId,
            ],
            'createdAt': user.metadata.creationTime?.toUtc().toIso8601String(),
            'updatedAt': FieldValue.serverTimestamp(),
            'devices': <String, Object?>{
              ledger.deviceId: deviceReport(
                ledger: ledger,
                counts: counts,
                running: running,
                lastError: lastError,
                facts: facts,
              ),
            },
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 20));
    } on Object catch (error) {
      debugPrint('ACCOUNT_HEALTH not reported: $error');
    }
  }

  /// Support's side: the report for an address or a uid, or null.
  static Future<AccountHealth?> find(String query) async {
    final String text = query.trim();
    if (text.isEmpty) {
      return null;
    }
    final CollectionReference<Map<String, dynamic>> ref = FirebaseFirestore
        .instance
        .collection(collection);
    if (text.contains('@')) {
      final QuerySnapshot<Map<String, dynamic>> found = await ref
          .where('email', isEqualTo: text.toLowerCase())
          .limit(1)
          .get();
      return found.docs.isEmpty
          ? null
          : AccountHealth.fromJson(found.docs.first.data());
    }
    final DocumentSnapshot<Map<String, dynamic>> doc = await ref
        .doc(text)
        .get();
    return doc.exists ? AccountHealth.fromJson(doc.data()!) : null;
  }
}

/// One account's report, as support reads it.
class AccountHealth {
  const AccountHealth({
    required this.uid,
    required this.email,
    required this.emailVerified,
    required this.providers,
    required this.devices,
    this.createdAt,
    this.updatedAt,
  });

  factory AccountHealth.fromJson(Map<String, dynamic> json) {
    final Object? devices = json['devices'];
    final Object? updated = json['updatedAt'];
    return AccountHealth(
      uid: '${json['uid'] ?? ''}',
      email: '${json['email'] ?? ''}',
      emailVerified: json['emailVerified'] == true,
      providers: (json['providers'] is List)
          ? (json['providers'] as List<dynamic>).whereType<String>().toList()
          : const <String>[],
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: updated is Timestamp ? updated.toDate() : null,
      devices: devices is Map
          ? <String, Map<String, Object?>>{
              for (final MapEntry<dynamic, dynamic> e in devices.entries)
                if (e.value is Map)
                  '${e.key}': Map<String, Object?>.from(e.value as Map),
            }
          : const <String, Map<String, Object?>>{},
    );
  }

  final String uid;
  final String email;
  final bool emailVerified;
  final List<String> providers;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, Map<String, Object?>> devices;
}
