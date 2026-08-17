import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/utils/community_goal.dart';
import 'package:shadchan/utils/community_period.dart';

/// One matchmaker's own counters, as this device believes them.
class CommunityMemberCounts {
  const CommunityMemberCounts({
    required this.day,
    required this.week,
    required this.month,
    required this.allTime,
    required this.ideas,
    required this.couples,
    required this.weekCouples,
    int? weekForRecord,
  }) : weekForRecord = weekForRecord ?? week;

  final int day;
  final int week;
  final int month;
  final int allTime;
  final int ideas;
  final int couples;

  /// [week] with any oversized import taken back out, for the personal weekly
  /// record and for nothing else.
  ///
  /// **Deliberately not published.** [CommunityService.publish] writes its
  /// fields one by one and this is not among them: the record is a private
  /// figure on this device, and a second, smaller week count sitting in a
  /// collection every user reads would be a second answer to "how much did
  /// they do this week" with no way to tell which one the leaderboard meant.
  final int weekForRecord;

  /// Couples who started dating inside the current week, which is the figure
  /// the three-a-week threshold is measured against.
  final int weekCouples;

  int forPeriod(CommunityPeriod period) {
    switch (period) {
      case CommunityPeriod.day:
        return day;
      case CommunityPeriod.week:
        return week;
      case CommunityPeriod.month:
        return month;
      case CommunityPeriod.allTime:
        return allTime;
    }
  }
}

/// What the community did in one window.
class CommunityTotals {
  const CommunityTotals({
    required this.actions,
    required this.activeMatchmakers,
    required this.ideas,
    required this.couples,
  });

  static const CommunityTotals empty = CommunityTotals(
    actions: 0,
    activeMatchmakers: 0,
    ideas: 0,
    couples: 0,
  );

  final int actions;

  /// A matchmaker who did at least one thing in this window. The definition is
  /// deliberately that low — the figure is there to say "you are not alone in
  /// here", not to rank anybody.
  final int activeMatchmakers;

  final int ideas;

  /// Couples who started dating. Withheld from the UI entirely until the
  /// community reliably produces some — see [CommunityService.couplesThreshold].
  final int couples;
}

/// One row of the leaderboard.
class CommunityRankEntry {
  const CommunityRankEntry({
    required this.uid,
    required this.name,
    required this.actions,
  });

  final String uid;
  final String name;
  final int actions;
}

/// The whole leaderboard for one window: the top ten, and where the reader
/// stands.
class CommunityLeaderboard {
  const CommunityLeaderboard({
    required this.top,
    required this.myRank,
    required this.myActions,
  });

  static const CommunityLeaderboard empty = CommunityLeaderboard(
    top: <CommunityRankEntry>[],
    myRank: null,
    myActions: 0,
  );

  final List<CommunityRankEntry> top;

  /// 1-based, or null when the reader has hidden themselves or has not done
  /// anything in this window.
  final int? myRank;

  final int myActions;
}

/// The community's shared numbers.
///
/// **Written for the read budget, not for the shape of the data.** Three
/// choices carry that, and none of them are obvious from the outside:
///
/// 1. **One document per matchmaker**, holding every window at once with a key
///    beside each count (`weekKey` + `weekActions`). A document per action, or
///    per period, would be tidier — and a leaderboard cannot sort by a field
///    that does not exist, so the count has to be *stored*. Rolling the keys
///    over on write costs nothing; not storing them would cost a client-side
///    scan of the whole collection.
///
/// 2. **Community totals come from aggregate queries**, never from reading the
///    members. `sum()` and `count()` are billed at roughly one read per
///    thousand documents matched, so the whole community area costs about four
///    reads however many matchmakers there are. Summing it client-side would
///    have cost one read *per matchmaker*, per refresh, per screen.
///
/// 3. **Nothing here refreshes on a rebuild.** Every read goes through a
///    process-level cache with a deadline ([_freshFor]); the home taster and
///    the activity screen share it, so opening the screen after glancing at the
///    home block costs nothing at all.
///
/// Writes are twice a session — app open and app pause, the same two moments
/// the cloud backup uses — never per action.
abstract final class CommunityService {
  static const String membersCollection = 'communityMembers';
  static const String goalsCollection = 'communityGoals';

  /// How many rows the leaderboard shows. Ten, and then the reader's own line
  /// separately: a list of four hundred names is not a community, it is a
  /// phone book.
  static const int leaderboardSize = 10;

  /// Couples are not shown as a community figure until the community actually
  /// produces them at this rate — a "0 זוגות" line every week for a year is a
  /// worse advertisement for the app than no line at all.
  static const int couplesThreshold = 3;

  /// Long enough that moving between the home screen and the activity screen
  /// never costs a second round of reads; short enough that a matchmaker who
  /// adds twenty friends sees the community figure move within the session.
  static const Duration _freshFor = Duration(minutes: 10);

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Future<User?> _account() async {
    if (!FirebaseBootstrap.isReady) {
      return null;
    }
    return FirebaseAuth.instance.currentUser;
  }

  // --- Publishing this device's own counts ---------------------------------

  /// Writes this matchmaker's counters, rolling any window that has turned over.
  ///
  /// Idempotent and safe to call from both lifecycle moments: the counts are
  /// recomputed from the local ledgers each time rather than incremented, so a
  /// double call writes the same numbers twice instead of doubling them.
  ///
  /// The finished week's total is added to that week's goal document on the way
  /// past — that is the only record of what the community actually did in a
  /// week once the per-member counters have rolled, and it is what next week's
  /// target is calculated from.
  static Future<void> publish({
    required CommunityMemberCounts counts,
    required String name,
    required bool hidden,
  }) async {
    final User? user = await _account();
    if (user == null) {
      return;
    }

    final String dayKey = CommunityPeriods.dayKey();
    final String weekKey = CommunityPeriods.weekKey();
    final String monthKey = CommunityPeriods.monthKey();

    try {
      final DocumentReference<Map<String, dynamic>> doc = _db
          .collection(membersCollection)
          .doc(user.uid);

      final DocumentSnapshot<Map<String, dynamic>> before = await doc.get();
      final Map<String, dynamic> old = before.data() ?? <String, dynamic>{};
      final String? oldWeekKey = old['weekKey'] as String?;
      final int oldWeekActions = (old['weekActions'] as num?)?.toInt() ?? 0;

      await doc.set(<String, Object?>{
        // A hidden matchmaker's name is not stored, not merely not shown. The
        // difference matters: this collection is readable by every installed
        // copy of the app, so "we keep it but hide it" would be a promise the
        // database itself contradicts. What is left against the uid is a row of
        // numbers.
        'name': hidden ? '' : name.trim(),
        'hidden': hidden,
        'dayKey': dayKey,
        'dayActions': counts.day,
        'weekKey': weekKey,
        'weekActions': counts.week,
        'monthKey': monthKey,
        'monthActions': counts.month,
        'allActions': counts.allTime,
        'ideas': counts.ideas,
        'couples': counts.couples,
        'weekCouples': counts.weekCouples,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // The week just turned over on this device. Bank what it did, once.
      if (oldWeekKey != null && oldWeekKey != weekKey && oldWeekActions > 0) {
        await _db.collection(goalsCollection).doc(oldWeekKey).set(
          <String, Object?>{'actual': FieldValue.increment(oldWeekActions)},
          SetOptions(merge: true),
        );
      }
    } catch (_) {
      // A community figure is never worth an error in front of somebody who
      // came here to do matchmaking.
    }
  }

  /// Reads back this account's stored `hidden` flag — the one field the app
  /// cannot recompute locally after a reinstall. One document, once.
  static Future<bool?> fetchHidden() async {
    final User? user = await _account();
    if (user == null) {
      return null;
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await _db
          .collection(membersCollection)
          .doc(user.uid)
          .get();
      final Object? hidden = doc.data()?['hidden'];
      return hidden is bool ? hidden : null;
    } catch (_) {
      return null;
    }
  }

  /// Flips the leaderboard opt-out without rewriting the counters.
  ///
  /// Hiding erases the stored name in the same write rather than waiting for
  /// the next publish — somebody who has just asked to disappear should not
  /// still be in the collection by name until they next close the app.
  static Future<void> setHidden(bool hidden, {String name = ''}) async {
    final User? user = await _account();
    if (user == null) {
      return;
    }
    try {
      await _db.collection(membersCollection).doc(user.uid).set(
        <String, Object?>{'hidden': hidden, 'name': hidden ? '' : name.trim()},
        SetOptions(merge: true),
      );
    } catch (_) {
      // Left to the next publish, which writes both fields too.
    }
  }

  /// Removes this account from the community entirely.
  ///
  /// The counters go with the name: what is being asked for is erasure, and a
  /// row of numbers keyed to a uid is still a record of a person. The app
  /// carries on working — the numbers are all derived locally — and the next
  /// publish simply recreates the row, which is why the caller hides the
  /// matchmaker first.
  static Future<bool> deleteMyData() async {
    final User? user = await _account();
    if (user == null) {
      return false;
    }
    try {
      await _db.collection(membersCollection).doc(user.uid).delete();
      invalidate();
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Reading the community ------------------------------------------------

  static final Map<String, _Cached<CommunityTotals>> _totalsCache =
      <String, _Cached<CommunityTotals>>{};
  static final Map<String, _Cached<CommunityLeaderboard>> _boardCache =
      <String, _Cached<CommunityLeaderboard>>{};
  static _Cached<({int target, int actual})>? _goalCache;

  /// Drops every cached figure, so the next read goes to the network. Called
  /// after publishing this device's own counts, which is the one moment the
  /// numbers are known to have moved.
  static void invalidate() {
    _totalsCache.clear();
    _boardCache.clear();
    _goalCache = null;
  }

  /// One window's community figures, in a single aggregate round trip.
  static Future<CommunityTotals> totals(CommunityPeriod period) async {
    final String cacheKey = period.name;
    final _Cached<CommunityTotals>? cached = _totalsCache[cacheKey];
    if (cached != null && cached.isFresh) {
      return cached.value;
    }
    if (await _account() == null) {
      return CommunityTotals.empty;
    }

    try {
      Query<Map<String, dynamic>> query = _db.collection(membersCollection);
      final String? keyField = period.keyField;
      if (keyField != null) {
        query = query.where(
          keyField,
          isEqualTo: CommunityPeriods.keyFor(period),
        );
      }

      // One request for all four numbers. `count()` here is "members whose
      // counter belongs to this window", which for a window with a key is the
      // same as "members who were active in it" — a member is only written
      // with the current key when they have just done something.
      final AggregateQuerySnapshot snapshot = await query
          .aggregate(
            sum(period.actionsField),
            count(),
            sum('ideas'),
            sum(period == CommunityPeriod.week ? 'weekCouples' : 'couples'),
          )
          .get();

      final CommunityTotals result = CommunityTotals(
        actions: snapshot.getSum(period.actionsField)?.round() ?? 0,
        activeMatchmakers: snapshot.count ?? 0,
        ideas: snapshot.getSum('ideas')?.round() ?? 0,
        couples:
            snapshot
                .getSum(
                  period == CommunityPeriod.week ? 'weekCouples' : 'couples',
                )
                ?.round() ??
            0,
      );
      _totalsCache[cacheKey] = _Cached<CommunityTotals>(result);
      return result;
    } catch (_) {
      return cached?.value ?? CommunityTotals.empty;
    }
  }

  /// The top ten for one window, plus the reader's own place in it.
  ///
  /// Eleven reads at most: ten rows, and one aggregate `count()` for the rank —
  /// "how many people are above me" is a counting question, and answering it by
  /// downloading everybody above you is how a leaderboard becomes the most
  /// expensive screen in an app.
  ///
  /// **Nobody appears on a board for a window they did nothing in.** The period
  /// key alone does not guarantee that: a member is written with the current
  /// key at every publish, and publishing happens on app open, so somebody who
  /// opened the app this morning and did nothing sits in today's collection
  /// with `dayActions: 0`. In a small community that is enough to reach the top
  /// ten, and a leaderboard whose tenth place did no matchmaking is not a
  /// leaderboard.
  static Future<CommunityLeaderboard> leaderboard(
    CommunityPeriod period, {
    required bool includeMe,
    required int myActions,
  }) async {
    final String cacheKey = '${period.name}:$includeMe:$myActions';
    final _Cached<CommunityLeaderboard>? cached = _boardCache[cacheKey];
    if (cached != null && cached.isFresh) {
      return cached.value;
    }
    final User? user = await _account();
    if (user == null) {
      return CommunityLeaderboard.empty;
    }

    try {
      Query<Map<String, dynamic>> base = _db
          .collection(membersCollection)
          .where('hidden', isEqualTo: false);
      final String? keyField = period.keyField;
      if (keyField != null) {
        base = base.where(keyField, isEqualTo: CommunityPeriods.keyFor(period));
      }

      final QuerySnapshot<Map<String, dynamic>> top = await base
          .where(period.actionsField, isGreaterThan: 0)
          .orderBy(period.actionsField, descending: true)
          .limit(leaderboardSize)
          .get();

      final List<CommunityRankEntry> rows = <CommunityRankEntry>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in top.docs)
          CommunityRankEntry(
            uid: doc.id,
            name: (doc.data()['name'] as String?)?.trim().isNotEmpty ?? false
                ? (doc.data()['name'] as String).trim()
                : 'שדכן',
            actions: (doc.data()[period.actionsField] as num?)?.toInt() ?? 0,
          ),
      ];

      int? rank;
      if (includeMe && myActions > 0) {
        final int index = rows.indexWhere(
          (CommunityRankEntry row) => row.uid == user.uid,
        );
        if (index >= 0) {
          rank = index + 1;
        } else {
          // The `> 0` filter is deliberately not repeated here. This branch only
          // runs when `myActions > 0`, so `> myActions` is already the tighter
          // of the two bounds — and one range filter per field keeps the query
          // inside exactly the composite indexes the board above already uses.
          final AggregateQuerySnapshot above = await base
              .where(period.actionsField, isGreaterThan: myActions)
              .count()
              .get();
          rank = (above.count ?? 0) + 1;
        }
      }

      final CommunityLeaderboard result = CommunityLeaderboard(
        top: rows,
        myRank: rank,
        myActions: myActions,
      );
      _boardCache[cacheKey] = _Cached<CommunityLeaderboard>(result);
      return result;
    } catch (_) {
      return cached?.value ?? CommunityLeaderboard.empty;
    }
  }

  /// This week's shared target and how far the community has come.
  ///
  /// The target is written by whichever client first finds it missing, inside a
  /// transaction so a hundred phones opening on a Sunday morning still produce
  /// one number. Its inputs are the previous weeks' goal documents, which is
  /// where each finished week's actual total was banked on rollover.
  static Future<({int target, int actual})> weeklyGoal() async {
    final _Cached<({int target, int actual})>? cached = _goalCache;
    if (cached != null && cached.isFresh) {
      return cached.value;
    }
    if (await _account() == null) {
      return (target: CommunityGoal.firstTarget, actual: 0);
    }

    try {
      final String weekKey = CommunityPeriods.weekKey();
      final DocumentReference<Map<String, dynamic>> doc = _db
          .collection(goalsCollection)
          .doc(weekKey);
      DocumentSnapshot<Map<String, dynamic>> snapshot = await doc.get();

      if (!snapshot.exists || snapshot.data()?['target'] == null) {
        final int target = await _computeTarget();
        await _db.runTransaction((Transaction tx) async {
          final DocumentSnapshot<Map<String, dynamic>> fresh = await tx.get(
            doc,
          );
          if (fresh.exists && fresh.data()?['target'] != null) {
            return;
          }
          tx.set(doc, <String, Object?>{
            'target': target,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        });
        snapshot = await doc.get();
      }

      // The live figure comes from the members, not from the goal document —
      // `actual` there is only ever written on rollover, after the week is over.
      final CommunityTotals week = await totals(CommunityPeriod.week);
      final ({int target, int actual}) result = (
        target:
            (snapshot.data()?['target'] as num?)?.toInt() ??
            CommunityGoal.firstTarget,
        actual: week.actions,
      );
      _goalCache = _Cached<({int target, int actual})>(result);
      return result;
    } catch (_) {
      return cached?.value ?? (target: CommunityGoal.firstTarget, actual: 0);
    }
  }

  /// Reads the last five goal documents and applies [CommunityGoal.nextTarget].
  /// Five small documents, once a week, on one client.
  static Future<int> _computeTarget() async {
    final List<String> keys = <String>[
      for (int week = 1; week <= CommunityGoal.smoothingWeeks + 1; week++)
        CommunityPeriods.weekKey(
          CommunityPeriods.now().subtract(Duration(days: 7 * week)),
        ),
    ];

    final List<DocumentSnapshot<Map<String, dynamic>>> docs =
        await Future.wait<DocumentSnapshot<Map<String, dynamic>>>(
          <Future<DocumentSnapshot<Map<String, dynamic>>>>[
            for (final String key in keys)
              _db.collection(goalsCollection).doc(key).get(),
          ],
        );

    int intOf(DocumentSnapshot<Map<String, dynamic>> doc, String field) =>
        (doc.data()?[field] as num?)?.toInt() ?? 0;

    final List<int> actuals = <int>[
      for (final DocumentSnapshot<Map<String, dynamic>> doc in docs)
        intOf(doc, 'actual'),
    ];

    return CommunityGoal.nextTarget(
      lastTarget: intOf(docs.first, 'target'),
      lastActual: actuals.first,
      recentActuals: actuals,
    );
  }
}

/// A value with a deadline on it.
class _Cached<T> {
  _Cached(this.value) : at = DateTime.now();

  final T value;
  final DateTime at;

  bool get isFresh =>
      DateTime.now().difference(at) < CommunityService._freshFor;
}
