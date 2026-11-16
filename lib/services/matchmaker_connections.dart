import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/matchmaker_connection.dart';
import 'package:shadchan/services/analytics_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/personal_card_service.dart';

/// Connections between matchmakers who already know each other, live —
/// "שדכנים שאני מכיר".
///
/// **Contacts are the layer of trust.** Who can be asked is the server's
/// reading of this matchmaker's own address book (the `helpers` list that
/// `CardAccessProvider` follows); the rules refuse a request to anybody not
/// saved in this phone. Nothing here opens a directory of strangers.
///
/// **A connection shares nothing.** Approving one writes a status on a row
/// with two uids and two names — no card, no friend and no figure of either
/// database moves because of it.
///
/// Static and notifier-based rather than a `Provider`, so no screen or test
/// harness has to construct it: nothing listens until `CloudSyncScheduler`
/// starts it once Firebase and a durable account are up, and a sign-out stops
/// it before anything is cleared. Every action returns false on failure and
/// changes nothing locally — the listener is the only thing that ever moves
/// the list.
abstract final class MatchmakerConnections {
  static const String collection = 'matchmakerConnections';

  /// Synced: the matchmakers already counted as "found among my contacts",
  /// so a second phone does not count them again.
  static const String _seenKey = 'knownMatchmakers.seen';

  /// Every row this account is part of, whatever its status.
  static final ValueNotifier<List<MatchmakerConnection>> connections =
      ValueNotifier<List<MatchmakerConnection>>(const <MatchmakerConnection>[]);

  /// Whether the server answered at least once — before that, an empty list
  /// means "not known yet", never "nobody".
  static final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);

  /// Uids with an action in flight, so a button cannot be pressed twice.
  static final ValueNotifier<Set<String>> busy = ValueNotifier<Set<String>>(
    const <String>{},
  );

  static String? _uid;
  static bool _starting = false;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// This account's uid once connected.
  static String? get uid => _uid;

  /// The row with [otherUid], if there is one.
  static MatchmakerConnection? withUid(String otherUid) {
    final String? me = _uid;
    if (me == null) return null;
    for (final MatchmakerConnection c in connections.value) {
      if (c.otherOf(me) == otherUid) return c;
    }
    return null;
  }

  static bool isBusy(String otherUid) => busy.value.contains(otherUid);

  /// Connects, once Firebase is up and a durable account is signed in.
  static Future<void> start() async {
    if (_uid != null || _starting || !FirebaseBootstrap.isReady) return;
    _starting = true;
    try {
      final String? uid = await PersonalCardService.durableUid();
      if (uid == null) return;
      _uid = uid;
      _sub = FirebaseFirestore.instance
          .collection(collection)
          .where('uids', arrayContains: uid)
          .snapshots(includeMetadataChanges: true)
          .listen((QuerySnapshot<Map<String, dynamic>> snap) {
            if (_uid != uid) return;
            connections.value = <MatchmakerConnection>[
              for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                  in snap.docs)
                ?MatchmakerConnection.fromMap(doc.id, doc.data()),
            ];
            if (!snap.metadata.isFromCache || snap.docs.isNotEmpty) {
              loaded.value = true;
            }
          }, onError: _log);
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    } finally {
      _starting = false;
    }
  }

  /// Disconnects and forgets, for a sign-out.
  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _uid = null;
    connections.value = const <MatchmakerConnection>[];
    loaded.value = false;
    busy.value = const <String>{};
  }

  /// Asks [otherUid] to connect. When they already asked this account, this
  /// approves their request instead — two people pressing "להתחבר" at each
  /// other have agreed.
  static Future<bool> request({
    required String otherUid,
    required String myName,
    required String theirName,
  }) async {
    final String? me = _uid;
    if (me == null || otherUid == me) return false;
    final MatchmakerConnection? existing = withUid(otherUid);
    if (existing != null && existing.isIncomingFor(me)) {
      return approve(existing, myName: myName);
    }
    if (existing != null &&
        existing.status != MatchmakerConnectionStatus.declined) {
      return existing.isConnected || existing.isOutgoingFor(me);
    }
    return _run(otherUid, () async {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(MatchmakerConnection.idFor(me, otherUid))
          .set(<String, Object?>{
            'uids': <String>[me, otherUid]..sort(),
            'fromUid': me,
            'toUid': otherUid,
            'status': 'pending',
            'names': <String, String>{
              me: _short(myName),
              otherUid: _short(theirName),
            },
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      Analytics.log(AnalyticsEvent.connection_request_sent, <String, Object?>{
        'again': existing != null,
      });
    });
  }

  /// Approves a request waiting for this account.
  static Future<bool> approve(
    MatchmakerConnection connection, {
    String? myName,
  }) {
    final String? me = _uid;
    if (me == null || !connection.isIncomingFor(me)) {
      return Future<bool>.value(false);
    }
    final String other = connection.otherOf(me);
    return _run(other, () async {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(connection.id)
          .update(<String, Object?>{
            'status': 'approved',
            if (myName != null && myName.trim().isNotEmpty)
              'names.$me': _short(myName),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      Analytics.log(AnalyticsEvent.connection_request_approved);
    });
  }

  /// "לא עכשיו" to a request waiting for this account. The other side is
  /// told nothing; their own screen says the request was not approved.
  static Future<bool> decline(MatchmakerConnection connection) {
    final String? me = _uid;
    if (me == null || !connection.isIncomingFor(me)) {
      return Future<bool>.value(false);
    }
    final String other = connection.otherOf(me);
    return _run(other, () async {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(connection.id)
          .update(<String, Object?>{
            'status': 'declined',
            'updatedAt': FieldValue.serverTimestamp(),
          });
      Analytics.log(AnalyticsEvent.connection_request_declined);
    });
  }

  /// Leaves a connection, or withdraws this account's own request.
  static Future<bool> remove(MatchmakerConnection connection) {
    final String? me = _uid;
    if (me == null) return Future<bool>.value(false);
    return _run(connection.otherOf(me), () async {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(connection.id)
          .delete();
    });
  }

  /// Counts the matchmakers found among this account's contacts that were
  /// not counted before — `matchmaker_contact_found`, as a band, never who.
  static void noteContactsFound(Iterable<String> uids) {
    if (!Hive.isBoxOpen('settings')) return;
    final Object? raw = Hive.box<dynamic>('settings').get(_seenKey);
    final Set<String> seen = raw is String && raw.isNotEmpty
        ? raw.split(',').toSet()
        : <String>{};
    final Set<String> fresh = uids
        .where((String u) => u.isNotEmpty && !u.contains(','))
        .toSet()
        .difference(seen);
    if (fresh.isEmpty) return;
    persistHomeSetting(_seenKey, <String>{...seen, ...fresh}.join(','));
    Analytics.log(AnalyticsEvent.matchmaker_contact_found, <String, Object?>{
      'count': Analytics.band(fresh.length),
      'first_time': seen.isEmpty,
    });
  }

  static Future<bool> _run(
    String otherUid,
    Future<void> Function() action,
  ) async {
    if (isBusy(otherUid)) return false;
    busy.value = <String>{...busy.value, otherUid};
    try {
      await action();
      return true;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return false;
    } finally {
      busy.value = <String>{...busy.value}..remove(otherUid);
    }
  }

  static String _short(String name) {
    final String trimmed = name.trim();
    return trimmed.length > 80 ? trimmed.substring(0, 80) : trimmed;
  }

  static void _log(Object error, [StackTrace? stackTrace]) {
    debugPrint('MatchmakerConnections: $error');
  }

  /// Test seam: a list as if the server had sent it.
  @visibleForTesting
  static void debugSet(String uid, List<MatchmakerConnection> rows) {
    _uid = uid;
    connections.value = rows;
    loaded.value = true;
  }
}
