import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/matchmaker_share.dart';
import 'package:shadchan/services/analytics_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/utils/screen_perf.dart';

/// Who shares what with whom, between this matchmaker and the matchmakers
/// they know — the rows of `matchmakerShares` this account is part of.
///
/// **Metadata only, and never a listener per matchmaker.** The rows are a
/// few dozen small documents (two uids, a mode, a count, two names); they are
/// read once when Firebase is up, again on app resume, and live only while a
/// screen that shows them is open ([watch] — reference counted, released when
/// the last screen closes). No card and no database is ever read here; the
/// cards themselves are read page by page, only when a matchmaker's database
/// is actually opened (`NetworkCards`).
///
/// Replaces the mutual `MatchmakerConnections` model (deleted 2026-11-20, no
/// migration): there is no "connection request" any more. Matchmakers who
/// know each other from the phone book see each other; a share is decided by
/// its owner, for one reader at a time.
abstract final class MatchmakerShares {
  static const String collection = 'matchmakerShares';

  /// Synced: the matchmakers already counted as "found among my contacts".
  static const String _seenKey = 'knownMatchmakers.seen';

  /// Device-only: when this phone last read the rows.
  static const String _syncedKey = 'network.sharesSyncedAt';

  /// An unforced [refresh] (app resume, the home carousel) reads every row
  /// this account is in — at most this often. A screen that shows the rows
  /// holds the live listener ([watch]); pull-to-refresh forces a read; a new
  /// request arrives as a push. It was 20 seconds, which on a busy day was a
  /// full read on nearly every return to the app (2026-11-22).
  static const Duration unforcedEvery = Duration(minutes: 5);

  /// Every row this account is part of, whatever its mode.
  static final ValueNotifier<List<MatchmakerShare>> rows =
      ValueNotifier<List<MatchmakerShare>>(const <MatchmakerShare>[]);

  /// Whether the server answered at least once.
  static final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);

  /// Uids with an action in flight, so a button cannot be pressed twice.
  static final ValueNotifier<Set<String>> busy = ValueNotifier<Set<String>>(
    const <String>{},
  );

  static String? _uid;
  static String? get uid => _uid;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static int _watchers = 0;
  static String? _print;
  static DateTime? _lastRead;

  /// Firestore listeners held here right now (for the performance log).
  static int get listenerCount => _sub == null ? 0 : 1;

  /// Connects once Firebase and a durable account are up, and reads once.
  static Future<void>? _startFuture;

  static Future<void> start() {
    if (_uid != null || !FirebaseBootstrap.isReady) return Future<void>.value();
    return _startFuture ??= _start().whenComplete(() => _startFuture = null);
  }

  static Future<void> _start() async {
    try {
      final String? uid = await PersonalCardService.durableUid();
      if (uid == null) return;
      _uid = uid;
      await refresh(force: true);
    } catch (error) {
      _log(error);
    }
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _watchers = 0;
    _uid = null;
    _print = null;
    _lastRead = null;
    rows.value = const <MatchmakerShare>[];
    loaded.value = false;
    busy.value = const <String>{};
  }

  /// One read of the rows. Skipped when they were read in the last 20s
  /// (resume after resume) unless [force]; skipped altogether while a screen
  /// holds the live listener, which already has them.
  static Future<void> refresh({bool force = false}) async {
    final String? me = _uid;
    if (me == null || _sub != null) return;
    final DateTime now = DateTime.now();
    if (!force &&
        _lastRead != null &&
        now.difference(_lastRead!) < unforcedEvery) {
      return;
    }
    _lastRead = now;
    try {
      ScreenPerf.noteQuery();
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection(collection)
          .where('uids', arrayContains: me)
          .get();
      if (_uid != me) return;
      _apply(snap);
      persistHomeSetting(_syncedKey, now.toIso8601String());
    } catch (error) {
      _log(error);
    }
  }

  /// Holds a live listener while a screen that shows the rows is open.
  /// Returns the release; the listener closes with the last screen.
  static VoidCallback watch() {
    _watchers++;
    final String? me = _uid;
    if (_sub == null && me != null) {
      ScreenPerf.noteQuery();
      _sub = FirebaseFirestore.instance
          .collection(collection)
          .where('uids', arrayContains: me)
          .snapshots()
          .listen((QuerySnapshot<Map<String, dynamic>> snap) {
            if (_uid == me) _apply(snap);
          }, onError: _log);
    }
    bool released = false;
    return () {
      if (released) return;
      released = true;
      _watchers = (_watchers - 1).clamp(0, 1 << 20);
      if (_watchers == 0) {
        unawaited(_sub?.cancel());
        _sub = null;
      }
    };
  }

  static void _apply(QuerySnapshot<Map<String, dynamic>> snap) {
    loaded.value = true;
    // The same rows again (a metadata-only snapshot, a second read): nothing
    // is replaced, so nobody downstream redraws for nothing.
    final String print = snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              '${d.id}:${d.data()}',
        )
        .join(';');
    if (print == _print) return;
    _print = print;
    rows.value = <MatchmakerShare>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs)
        ?MatchmakerShare.fromMap(d.data()),
    ];
  }

  // --- Reading the rows -----------------------------------------------------

  /// What this matchmaker shares with [readerUid] (or asked of them: null).
  static MatchmakerShare? mine(String readerUid) {
    final String? me = _uid;
    for (final MatchmakerShare s in rows.value) {
      if (s.ownerUid == me && s.readerUid == readerUid) return s;
    }
    return null;
  }

  /// What [ownerUid] shares with this matchmaker.
  static MatchmakerShare? theirs(String ownerUid) {
    final String? me = _uid;
    for (final MatchmakerShare s in rows.value) {
      if (s.ownerUid == ownerUid && s.readerUid == me) return s;
    }
    return null;
  }

  /// [ownerUid] shares something with this matchmaker right now.
  static bool sharesWithMe(String ownerUid) =>
      theirs(ownerUid)?.isActive ?? false;

  /// This matchmaker shares something with [readerUid] right now.
  static bool iShareWith(String readerUid) =>
      mine(readerUid)?.isActive ?? false;

  /// "מחוברים": at least one active share between the two, either way.
  static bool isConnected(String other) =>
      sharesWithMe(other) || iShareWith(other);

  /// How many cards [ownerUid] shares with this matchmaker.
  static int sharedWithMeCount(String ownerUid) {
    final MatchmakerShare? s = theirs(ownerUid);
    return s != null && s.isActive ? s.count : 0;
  }

  /// How many cards this matchmaker shares with [readerUid].
  static int iShareCount(String readerUid) {
    final MatchmakerShare? s = mine(readerUid);
    return s != null && s.isActive ? s.count : 0;
  }

  /// Everybody who shares with this matchmaker now, by uid → their name.
  static Map<String, String> get sharingWithMe => <String, String>{
    for (final MatchmakerShare s in rows.value)
      if (s.readerUid == _uid && s.isActive) s.ownerUid: s.ownerName,
  };

  /// Every matchmaker with an active share either way, uid → name.
  static Map<String, String> get connectedNames {
    final String? me = _uid;
    final Map<String, String> out = <String, String>{};
    for (final MatchmakerShare s in rows.value) {
      if (!s.isActive) continue;
      if (s.readerUid == me) out[s.ownerUid] = s.ownerName;
      if (s.ownerUid == me) out.putIfAbsent(s.readerUid, () => s.readerName);
    }
    return out;
  }

  /// Total cards shared with this matchmaker, by everybody.
  static int get totalSharedWithMe => <int>[
    for (final MatchmakerShare s in rows.value)
      if (s.readerUid == _uid && s.isActive) s.count,
  ].fold(0, (int a, int b) => a + b);

  /// Matchmakers asking this one to share, newest first.
  static List<MatchmakerShare> get requestsToMe =>
      <MatchmakerShare>[
        for (final MatchmakerShare s in rows.value)
          if (s.ownerUid == _uid && s.isRequest) s,
      ]..sort(
        (MatchmakerShare a, MatchmakerShare b) =>
            (b.updatedAt ?? DateTime(2000)).compareTo(
              a.updatedAt ?? DateTime(2000),
            ),
      );

  /// This matchmaker asked [ownerUid] to share and is waiting.
  static bool askedOf(String ownerUid) => theirs(ownerUid)?.isRequest ?? false;

  /// [readerUid] asked this matchmaker to share.
  static bool askedBy(String readerUid) => mine(readerUid)?.isRequest ?? false;

  static bool isBusy(String other) => busy.value.contains(other);

  // --- Writing --------------------------------------------------------------

  /// Writes what this matchmaker shares with [readerUid] — the decision is
  /// the owner's alone and needs nobody's approval. [count] is the number of
  /// cards it opens (refined after the next publish).
  static Future<bool> setMine({
    required String readerUid,
    required MatchmakerShareMode mode,
    required int count,
    required String myName,
    required String theirName,
  }) async {
    final String? me = _uid;
    if (me == null ||
        readerUid == me ||
        mode == MatchmakerShareMode.requested) {
      return false;
    }
    final MatchmakerShare? before = mine(readerUid);
    return _run(readerUid, () async {
      final DocumentReference<Map<String, dynamic>> ref = FirebaseFirestore
          .instance
          .collection(collection)
          .doc(MatchmakerShare.idFor(me, readerUid));
      final Map<String, Object?> data = <String, Object?>{
        'ownerUid': me,
        'readerUid': readerUid,
        'uids': <String>[me, readerUid],
        'mode': mode.name,
        'count': mode.isActive ? count : 0,
        'ownerName': _short(myName),
        'readerName': _short(theirName),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (before == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await ref.set(data);
      } else {
        await ref.update(data);
      }
      _local(
        MatchmakerShare(
          ownerUid: me,
          readerUid: readerUid,
          mode: mode,
          count: mode.isActive ? count : 0,
          ownerName: _short(myName),
          readerName: _short(theirName),
          updatedAt: DateTime.now(),
        ),
      );
      if (mode.isActive && !(before?.isActive ?? false)) {
        Analytics.log(AnalyticsEvent.connection_request_approved);
      }
    });
  }

  /// Updates only the card count of an active share (after a publish) —
  /// quietly, and only when it moved.
  static Future<void> updateCount(String readerUid, int count) async {
    final String? me = _uid;
    final MatchmakerShare? row = mine(readerUid);
    if (me == null || row == null || !row.isActive || row.count == count) {
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(row.id)
          .update(<String, Object?>{
            'count': count,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _local(
        MatchmakerShare(
          ownerUid: row.ownerUid,
          readerUid: row.readerUid,
          mode: row.mode,
          count: count,
          ownerName: row.ownerName,
          readerName: row.readerName,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _log(error);
    }
  }

  /// Asks [ownerUid] to share with this matchmaker — "בקש/י שיתוף".
  static Future<bool> request({
    required String ownerUid,
    required String myName,
    required String theirName,
  }) async {
    final String? me = _uid;
    if (me == null || ownerUid == me) return false;
    final MatchmakerShare? before = theirs(ownerUid);
    if (before != null && (before.isActive || before.isRequest)) return true;
    return _run(ownerUid, () async {
      final DocumentReference<Map<String, dynamic>> ref = FirebaseFirestore
          .instance
          .collection(collection)
          .doc(MatchmakerShare.idFor(ownerUid, me));
      if (before == null) {
        await ref.set(<String, Object?>{
          'ownerUid': ownerUid,
          'readerUid': me,
          'uids': <String>[ownerUid, me],
          'mode': 'requested',
          'count': 0,
          'ownerName': _short(theirName),
          'readerName': _short(myName),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await ref.update(<String, Object?>{
          'mode': 'requested',
          'readerName': _short(myName),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      _local(
        MatchmakerShare(
          ownerUid: ownerUid,
          readerUid: me,
          mode: MatchmakerShareMode.requested,
          ownerName: _short(theirName),
          readerName: _short(myName),
          updatedAt: DateTime.now(),
        ),
      );
      Analytics.log(AnalyticsEvent.connection_request_sent, <String, Object?>{
        'again': before != null,
      });
    });
  }

  static void _local(MatchmakerShare row) {
    rows.value = <MatchmakerShare>[
      for (final MatchmakerShare s in rows.value)
        if (s.id != row.id) s,
      row,
    ];
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

  static Future<bool> _run(String other, Future<void> Function() action) async {
    if (isBusy(other)) return false;
    busy.value = <String>{...busy.value, other};
    try {
      await action();
      return true;
    } catch (error) {
      _log(error);
      return false;
    } finally {
      busy.value = <String>{...busy.value}..remove(other);
    }
  }

  static String _short(String name) {
    final String t = name.trim();
    return t.length > 80 ? t.substring(0, 80) : t;
  }

  static void _log(Object error) => debugPrint('MatchmakerShares: $error');

  /// Test seam: rows as if the server had sent them.
  @visibleForTesting
  static void debugSet(String uid, List<MatchmakerShare> list) {
    _uid = uid;
    rows.value = list;
    loaded.value = true;
  }
}
