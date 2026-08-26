import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/models/community_profile.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/community_period.dart';

/// One matchmaker's own figures, as this device believes them.
///
/// Every window carries the whole breakdown rather than only its score, because
/// the two are shown in different places and recomputing one from the other is
/// impossible in the direction that matters: 55 points could be 55 friends or
/// one engagement and one couple.
class CommunityMemberCounts {
  const CommunityMemberCounts({
    required this.day,
    required this.week,
    required this.month,
    required this.allTime,
  });

  static const CommunityMemberCounts empty = CommunityMemberCounts(
    day: ActivityBreakdown.empty,
    week: ActivityBreakdown.empty,
    month: ActivityBreakdown.empty,
    allTime: ActivityBreakdown.empty,
  );

  final ActivityBreakdown day;
  final ActivityBreakdown week;
  final ActivityBreakdown month;
  final ActivityBreakdown allTime;

  ActivityBreakdown forPeriod(CommunityPeriod period) {
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

  int pointsFor(CommunityPeriod period) => forPeriod(period).points;
}

/// What the community did in one window.
class CommunityTotals {
  const CommunityTotals({
    required this.points,
    required this.activeMatchmakers,
    required this.friends,
    required this.ideas,
    required this.couples,
    required this.engagements,
    this.resolved = true,
  });

  /// "We do not know", not "the community did nothing".
  ///
  /// **The difference is the whole reason this class carries a flag.** A read
  /// that never left the device — no account yet, Firebase still starting, no
  /// network — used to come back as a row of zeroes indistinguishable from a
  /// real answer, and every caller cached it and stopped asking. That is how a
  /// live community of matchmakers showed up as "0" and stayed there for the
  /// rest of the session. Anything built from this constant is a placeholder to
  /// be asked again, and callers must never store it as an answer.
  static const CommunityTotals empty = CommunityTotals(
    points: 0,
    activeMatchmakers: 0,
    friends: 0,
    ideas: 0,
    couples: 0,
    engagements: 0,
    resolved: false,
  );

  /// True when these figures actually came back from the server — including a
  /// genuine, hard-won zero.
  final bool resolved;

  /// The community's weighted activity points.
  final int points;

  /// A matchmaker who scored at least one point in this window. The definition
  /// is deliberately that low — the figure is there to say "you are not alone
  /// in here", not to rank anybody.
  final int activeMatchmakers;

  final int friends;
  final int ideas;
  final int couples;
  final int engagements;

  /// Whether there is anything here worth drawing at all.
  bool get isEmpty => points == 0 && activeMatchmakers == 0;
}

/// One row of the leaderboard.
class CommunityRankEntry {
  const CommunityRankEntry({
    required this.uid,
    required this.name,
    required this.points,
    this.photoUrl = '',
  });

  final String uid;
  final String name;
  final int points;

  /// The matchmaker's own picture, or empty.
  ///
  /// **Their own face, never a candidate's**, published under exactly the same
  /// consent as their name: a matchmaker who is hidden, private, or has not
  /// answered the leaderboard question has no photo here and never gets one.
  final String photoUrl;
}

/// The whole leaderboard for one window: the top ten, and where the reader
/// stands.
class CommunityLeaderboard {
  const CommunityLeaderboard({
    required this.top,
    required this.myRank,
    required this.myPoints,
    required this.activeMatchmakers,
    this.resolved = true,
  });

  /// The same "we do not know" [CommunityTotals.empty] is — see there.
  static const CommunityLeaderboard empty = CommunityLeaderboard(
    top: <CommunityRankEntry>[],
    myRank: null,
    myPoints: 0,
    activeMatchmakers: 0,
    resolved: false,
  );

  /// True when this board actually came back from the server.
  final bool resolved;

  final List<CommunityRankEntry> top;

  /// 1-based, or null when the reader has hidden themselves or has not done
  /// anything in this window.
  final int? myRank;

  final int myPoints;

  /// How many matchmakers were active in this window — the "מתוך Y" the
  /// reader's own line is read against. Out of the same figure the community
  /// area shows, so the two can never disagree.
  final int activeMatchmakers;
}

/// The community's shared numbers.
///
/// **Written for the read budget, not for the shape of the data.** Three
/// choices carry that, and none of them are obvious from the outside:
///
/// 1. **One document per matchmaker**, holding every window at once with a key
///    beside each count (`weekKey` + `weekActions` + `weekFriends` + …). A
///    document per action, or per period, would be tidier — and a leaderboard
///    cannot sort by a field that does not exist, so the score has to be
///    *stored*. Rolling the keys over on write costs nothing; not storing them
///    would cost a client-side scan of the whole collection.
///
/// 2. **Community totals come from aggregate queries**, never from reading the
///    members. `sum()` and `count()` are billed at roughly one read per
///    thousand documents matched, so the whole community area costs a handful
///    of reads however many matchmakers there are. Summing it client-side would
///    have cost one read *per matchmaker*, per refresh, per screen.
///
/// 3. **Nothing here refreshes on a rebuild.** Every read goes through a
///    process-level cache with a deadline ([_freshFor]); the home block and the
///    activity screen share it, so opening the screen after glancing at the
///    home block costs nothing at all.
///
/// Writes are twice a session — app open and app pause, the same two moments
/// the cloud backup uses — never per action.
abstract final class CommunityService {
  static const String membersCollection = 'communityMembers';

  /// How many rows the leaderboard shows. Ten, and then the reader's own line
  /// separately: a list of four hundred names is not a community, it is a
  /// phone book.
  static const int leaderboardSize = 10;

  /// Long enough that moving between the home screen and the activity screen
  /// never costs a second round of reads; short enough that a matchmaker who
  /// adds twenty friends sees the community figure move within the session.
  ///
  /// Three minutes rather than the ten it was: the activity screen forces a
  /// read of its own on every open, so this window now only has to cover the
  /// home block being rebuilt, and a community figure that is a quarter of an
  /// hour old on the landing page reads as a broken feature.
  static const Duration _freshFor = Duration(minutes: 3);

  /// How many member documents the fallback scan will read in one go.
  ///
  /// A ceiling rather than a page: past this the aggregate query is the only
  /// sensible way to do it, and if it is failing at that size the answer is to
  /// deploy the index, not to download the collection. Until the community is
  /// that large this is simply the whole of it.
  static const int _scanLimit = 400;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// The account every read and write here goes through, or null.
  ///
  /// **An anonymous user is not an account.** Every device has one from the
  /// first launch — it is what App Check and the AI quota hang off — so
  /// accepting it here is what used to put matchmakers who had never signed in
  /// into the community totals and onto the leaderboard, under a uid that dies
  /// with the install and a name they were never asked for. The community is
  /// for people who connected an account; this one check is what makes that
  /// true of the publish, the totals and the board at once.
  ///
  /// **It waits for the session to be restored, and that is the fix for a
  /// publish that silently never happened.** `Firebase.initializeApp`
  /// completing does not mean `currentUser` is populated: the persisted session
  /// is read back asynchronously, and for the first second or so of every
  /// launch `currentUser` is null on a device that is perfectly well signed in.
  /// The app's own publish runs one frame after the first — see
  /// `CloudSyncScheduler` — so it landed inside that window nearly every time,
  /// read null here, and returned without writing anything. What was left was
  /// the publish at app pause, which is a moment the OS is entitled to freeze
  /// the process in. The net effect is a device whose figures reach the shared
  /// collection rarely, and a community total that looks like it contains
  /// nobody but the reader.
  ///
  /// So a null `currentUser` is not taken as "signed out" until auth says so.
  /// The wait is bounded and shared: one subscription per launch, whatever
  /// asks.
  static Future<User?> _account() async {
    if (!FirebaseBootstrap.isReady) {
      return null;
    }
    final User? user = FirebaseAuth.instance.currentUser ?? await _restored();
    return user == null || user.isAnonymous ? null : user;
  }

  /// The first answer `authStateChanges` gives in this process, remembered.
  ///
  /// `first` on that stream resolves as soon as auth has read whatever it has
  /// on disk — immediately for a genuinely signed-out install, and after the
  /// restore for a signed-in one. The timeout is there for the case where auth
  /// never answers at all (no Play Services, a broken keystore): a community
  /// figure is not worth hanging a publish on for ever.
  static Future<User?>? _restoring;

  static Future<User?> _restored() {
    return _restoring ??= FirebaseAuth.instance
        .authStateChanges()
        .first
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => FirebaseAuth.instance.currentUser,
        )
        .catchError((Object _) => FirebaseAuth.instance.currentUser);
  }

  /// Test seam: forgets the remembered auth resolution.
  @visibleForTesting
  static void resetAccountWait() => _restoring = null;

  // --- Publishing this device's own counts ---------------------------------

  /// Writes this matchmaker's figures, rolling any window that has turned over.
  ///
  /// Idempotent and safe to call from both lifecycle moments: everything is
  /// recomputed from the local ledgers each time rather than incremented, so a
  /// double call writes the same numbers twice instead of doubling them.
  ///
  /// Answers whether the shared collection actually changed — false for a row
  /// identical to the last one that landed, for a device with no account, and
  /// for a write the server refused. The caller uses it to decide whether every
  /// cached community figure is now out of date; saying "yes" when nothing was
  /// written costs every screen on the page a round of reads for no news.
  static Future<bool> publish({
    required CommunityMemberCounts counts,
    required String name,
    required bool hidden,
    String photoUrl = '',
    String about = '',
    List<MatchmakerShare> shares = const <MatchmakerShare>[],
    String benefit = '',
    String contactPhone = '',
  }) async {
    final User? user = await _account();
    if (user == null) {
      return false;
    }

    final Map<String, Object?> row = <String, Object?>{
      // A hidden matchmaker's name is not stored, not merely not shown. The
      // difference matters: this collection is readable by every installed
      // copy of the app, so "we keep it but hide it" would be a promise the
      // database itself contradicts. What is left against the uid is a row
      // of numbers.
      'name': hidden ? '' : name.trim(),
      // A face travels further than a name, so it follows the same rule and
      // is cleared by the same write. See [uploadAvatar].
      'photoUrl': hidden ? '' : photoUrl.trim(),
      // The public page — see [CommunityProfile]. Every one of these is
      // something a matchmaker deliberately typed into their own profile, and
      // every one of them is governed by exactly the rule the name is: hiding
      // does not stop showing them, it stops storing them. A phone number in
      // particular is not "kept but not displayed" in a collection every
      // installed copy of the app can read.
      'about': hidden ? '' : _clip(about, CommunityProfile.maxAboutLength),
      'shares': hidden
          ? const <String>[]
          : <String>[
              for (final MatchmakerShare share in shares) share.encode(),
            ],
      'benefit': hidden
          ? ''
          : _clip(benefit, CommunityProfile.maxBenefitLength),
      'contactPhone': hidden ? '' : _clip(contactPhone, 24),
      'hidden': hidden,
      for (final CommunityPeriod period in CommunityPeriod.values) ...{
        if (period.keyField case final String key)
          key: CommunityPeriods.keyFor(period),
        ..._fieldsFor(period, counts.forPeriod(period)),
      },
    };

    // Nothing moved since the last successful publish, so there is nothing to
    // say. The row is rebuilt from the local ledgers every time rather than
    // incremented, which is what makes this comparison sound: an identical map
    // means an identical document, and writing it again would change nothing
    // but `updatedAt` — a field nothing in the app reads.
    //
    // The period keys are part of the fingerprint, so a window rolling over at
    // midnight publishes exactly as it always did.
    final String fingerprint = '${user.uid}|${_fingerprintOf(row)}';
    if (CommunityProfileStore.publishedFingerprint == fingerprint) {
      return false;
    }

    try {
      await _write(user.uid, row);
      // Remembered only after the server took it. A write that failed must be
      // retried by the next publish, not skipped because we already decided it
      // had happened.
      CommunityProfileStore.rememberPublished(fingerprint);
      return true;
    } on FirebaseException catch (error) {
      // **A refusal here is usually not a permission problem — it is an old
      // document.** `noStrayFields` in the security rules is a whitelist, and
      // `set(merge: true)` leaves whatever is already on the document inside
      // `request.resource.data`. So an account whose row still carries a field
      // this app stopped writing — top-level `ideas` and `couples` from before
      // the counters were split per window — has every publish rejected, for
      // ever, silently. Their figures freeze at whatever they were on the day
      // the rules tightened, and no amount of using the app can unfreeze them.
      //
      // The repair is to name the strays and delete them in the same write.
      // It costs one extra read and it runs once per account, because after it
      // the document matches the whitelist and the ordinary path works again.
      if (error.code == 'permission-denied' &&
          await _repairAndWrite(user.uid, row)) {
        CommunityProfileStore.rememberPublished(fingerprint);
        return true;
      }
    } catch (_) {
      // A community figure is never worth an error in front of somebody who
      // came here to do matchmaking.
    }
    return false;
  }

  static Future<void> _write(String uid, Map<String, Object?> row) {
    return _db.collection(membersCollection).doc(uid).set(<String, Object?>{
      ...row,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Every field this app writes to a member document.
  ///
  /// The same list the security rules whitelist, and it has to stay the same
  /// list: anything here that the rules do not allow is a write that fails, and
  /// anything the rules allow that is missing here is a field [_repairAndWrite]
  /// would wrongly delete.
  static Set<String> get _knownFields => <String>{
    'name',
    'photoUrl',
    'about',
    'shares',
    'benefit',
    'contactPhone',
    'hidden',
    'updatedAt',
    for (final CommunityPeriod period in CommunityPeriod.values) ...<String>{
      ?period.keyField,
      period.actionsField,
      period.friendsField,
      period.ideasField,
      period.couplesField,
      period.engagementsField,
    },
  };

  /// Reads the stored document, deletes anything the rules do not recognise,
  /// and writes the row again. Answers whether the second write landed.
  static Future<bool> _repairAndWrite(
    String uid,
    Map<String, Object?> row,
  ) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await _db
          .collection(membersCollection)
          .doc(uid)
          .get();
      final Map<String, dynamic> stored = doc.data() ?? <String, dynamic>{};
      final Set<String> known = _knownFields;
      final List<String> strays = <String>[
        for (final String key in stored.keys)
          if (!known.contains(key)) key,
      ];
      if (strays.isEmpty) {
        // Nothing to clean, so the refusal was a real one — a signed-out
        // account, App Check, a rule this write genuinely does not satisfy.
        // Retrying it would only fail again.
        return false;
      }
      await _write(uid, <String, Object?>{
        ...row,
        for (final String key in strays) key: FieldValue.delete(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The row as one comparable string, keys sorted.
  ///
  /// Sorted because the map is built by a loop over an enum inside a literal,
  /// and a reordering there would otherwise look like a change to every
  /// account in the app at once.
  static String _fingerprintOf(Map<String, Object?> row) {
    final List<String> keys = row.keys.toList()..sort();
    return <String>[
      for (final String key in keys) '$key=${row[key]}',
    ].join('|');
  }

  /// [value] trimmed and cut to [limit].
  ///
  /// The security rules refuse anything longer, and a refusal here is silent —
  /// so a matchmaker who pasted a paragraph would have every publish rejected
  /// for ever and never be told why. Cutting is the only failure mode that
  /// leaves the rest of their figures working.
  static String _clip(String value, int limit) {
    final String trimmed = value.trim();
    return trimmed.length <= limit ? trimmed : trimmed.substring(0, limit);
  }

  static Map<String, Object?> _fieldsFor(
    CommunityPeriod period,
    ActivityBreakdown breakdown,
  ) {
    return <String, Object?>{
      period.actionsField: breakdown.points,
      period.friendsField: breakdown.friends,
      period.ideasField: breakdown.ideas,
      period.couplesField: breakdown.couples,
      period.engagementsField: breakdown.engagements,
    };
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

  /// One matchmaker's public page, or null.
  ///
  /// **One document read, and it is not cached.** A profile is opened
  /// deliberately, one at a time, by somebody who tapped a name — which is both
  /// rare enough that a read costs nothing worth counting and exactly the
  /// moment stale data would be noticed. Null covers every way this can fail:
  /// no account, no network, a row that has been deleted, and a matchmaker who
  /// hid themselves between the board being drawn and the name being tapped.
  static Future<CommunityProfile?> profile(String uid) async {
    if (uid.trim().isEmpty || await _account() == null) {
      return null;
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await _db
          .collection(membersCollection)
          .doc(uid.trim())
          .get();
      final Map<String, dynamic>? data = doc.data();
      if (data == null || data['hidden'] == true) {
        return null;
      }
      return CommunityProfile.fromDocument(doc.id, data);
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
        <String, Object?>{
          'hidden': hidden,
          'name': hidden ? '' : name.trim(),
          // Hiding takes the picture and the whole public page down in the
          // same write for the same reason it erases the name: "we keep it but
          // do not show it" is a promise this collection cannot make, because
          // every installed copy of the app can read it. What is left against
          // the uid is a row of numbers.
          if (hidden) ...<String, Object?>{
            'photoUrl': '',
            'about': '',
            'shares': <String>[],
            'benefit': '',
            'contactPhone': '',
          },
        },
        SetOptions(merge: true),
      );
      if (hidden) {
        await _deleteAvatar(user.uid);
      }
    } catch (_) {
      // Left to the next publish, which writes both fields too.
    } finally {
      // This row no longer matches the one [publish] last fingerprinted —
      // whether the write above landed or not. Forgetting it is what stops the
      // next publish from deciding there is nothing to send, which on the
      // failure path is the difference between "retried in a moment" and
      // "silently never".
      CommunityProfileStore.forgetPublished();
    }
  }

  /// Puts this matchmaker's own picture where the leaderboard can draw it, and
  /// answers with the URL.
  ///
  /// **Uploaded once per picture, not once per launch.** The last uploaded
  /// path and URL are remembered locally ([CommunityProfileStore]); an
  /// unchanged photo is answered from that memory without touching the
  /// network, which matters because publishing happens twice a session.
  ///
  /// Returns an empty string — and takes down whatever is already there — for
  /// a matchmaker who is hidden, has no photo, or whose photo file has gone.
  /// Never throws: a picture is the least important thing on this screen.
  static Future<String> uploadAvatar({
    required String? localPath,
    required bool hidden,
  }) async {
    final User? user = await _account();
    if (user == null) {
      return '';
    }

    final String path = (localPath ?? '').trim();
    if (hidden || path.isEmpty || !File(path).existsSync()) {
      if (CommunityProfileStore.uploadedAvatarUrl.isNotEmpty) {
        await _deleteAvatar(user.uid);
        CommunityProfileStore.rememberAvatar(path: '', url: '');
      }
      return '';
    }

    if (CommunityProfileStore.uploadedAvatarPath == path &&
        CommunityProfileStore.uploadedAvatarUrl.isNotEmpty) {
      return CommunityProfileStore.uploadedAvatarUrl;
    }

    try {
      final Reference ref = _avatarRef(user.uid);
      await ref.putFile(
        File(path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final String url = await ref.getDownloadURL();
      CommunityProfileStore.rememberAvatar(path: path, url: url);
      return url;
    } catch (_) {
      // The row simply keeps the default avatar. Nothing else is affected.
      return CommunityProfileStore.uploadedAvatarUrl;
    }
  }

  static Reference _avatarRef(String uid) =>
      FirebaseStorage.instance.ref('$membersCollection/$uid/avatar.jpg');

  static Future<void> _deleteAvatar(String uid) async {
    try {
      await _avatarRef(uid).delete();
    } catch (_) {
      // Already gone, or never there.
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
      // The row is gone, so the next publish must write a whole one rather
      // than recognise its own fingerprint and send nothing.
      CommunityProfileStore.forgetPublished();
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

  /// The windows whose aggregate query has been shown to work in this process.
  ///
  /// **What stops the fallback scan from becoming the normal path.** A missing
  /// composite index and a genuinely quiet window are indistinguishable from
  /// the client — both come back as zero — so [totals] checks a zero against a
  /// direct read before believing it. The trouble is that "quiet" is the
  /// ordinary state of `day` every morning: without this, every matchmaker who
  /// opened the app before anybody had done anything paid a 400-document scan,
  /// again every three minutes, for the true answer zero.
  ///
  /// So the check is asked once per window per launch rather than every time.
  /// A window is trusted the moment its aggregate returns something, or the
  /// moment a scan agrees that it returns nothing; after that a zero is taken
  /// at face value and costs the two aggregate reads it should.
  ///
  /// Deliberately *not* cleared by [invalidate]: whether the index exists is a
  /// property of the project, not of the figures, and it cannot change while
  /// the app is running.
  static final Set<String> _aggregatesTrusted = <String>{};

  /// Drops every cached figure, so the next read goes to the network. Called
  /// after publishing this device's own counts, which is the one moment the
  /// numbers are known to have moved.
  static void invalidate() {
    _totalsCache.clear();
    _boardCache.clear();
  }

  /// Test seam: forgets that the aggregate queries were ever shown to work.
  @visibleForTesting
  static void resetAggregateTrust() => _aggregatesTrusted.clear();

  /// One window's community figures.
  ///
  /// **Two aggregate round trips rather than one, because Firestore allows at
  /// most five aggregations in a query and this needs six.** Both are still
  /// billed at roughly one read per thousand documents matched, so the split
  /// costs about one extra read and nothing else.
  ///
  /// The `> 0` filter is what makes "שדכנים פעילים" mean what it says. A member
  /// is written with the current period key at every publish, and publishing
  /// happens on app open, so without it everybody who merely *opened* the app
  /// today would be counted as active — which is the same trap the leaderboard
  /// fell into before it got the same filter.
  static Future<CommunityTotals> totals(
    CommunityPeriod period, {
    bool forceRefresh = false,
  }) async {
    final String cacheKey = period.name;
    final _Cached<CommunityTotals>? cached = _totalsCache[cacheKey];
    if (!forceRefresh && cached != null && cached.isFresh) {
      return cached.value;
    }
    if (await _account() == null) {
      return CommunityTotals.empty;
    }

    // **The window can live under more than one key.** A member document
    // carries one key per window, and the month's key changed shape without a
    // migration — see [CommunityPeriods.legacyKeysFor]. Reading only the
    // current one is what made "החודש" a figure from a single matchmaker while
    // "כל הזמנים", which has no key filter at all, showed the whole community.
    // Each key is a disjoint set of documents, so the windows simply add up.
    final List<CommunityTotals> parts = <CommunityTotals>[];
    bool anyResolved = false;
    for (final String? key in _keysFor(period)) {
      final CommunityTotals part = await _totalsForKey(
        period,
        key,
        cacheKey: cacheKey,
      );
      if (part.resolved) {
        anyResolved = true;
        parts.add(part);
      }
    }
    if (!anyResolved) {
      return cached?.value ?? CommunityTotals.empty;
    }
    final CommunityTotals merged = _sum(parts);
    _totalsCache[cacheKey] = _Cached<CommunityTotals>(merged);
    return merged;
  }

  /// Every key whose documents belong to [period] right now: the one this build
  /// writes, then anything an older build wrote for the same window. A single
  /// `null` for all-time, which has no key filter.
  static List<String?> _keysFor(CommunityPeriod period) {
    if (period.keyField == null) {
      return const <String?>[null];
    }
    return <String?>[
      CommunityPeriods.keyFor(period),
      ...CommunityPeriods.legacyKeysFor(period),
    ];
  }

  static CommunityTotals _sum(List<CommunityTotals> parts) {
    int points = 0;
    int active = 0;
    int friends = 0;
    int ideas = 0;
    int couples = 0;
    int engagements = 0;
    for (final CommunityTotals part in parts) {
      points += part.points;
      active += part.activeMatchmakers;
      friends += part.friends;
      ideas += part.ideas;
      couples += part.couples;
      engagements += part.engagements;
    }
    return CommunityTotals(
      points: points,
      activeMatchmakers: active,
      friends: friends,
      ideas: ideas,
      couples: couples,
      engagements: engagements,
    );
  }

  /// One window under one key. Unresolved when neither the aggregate nor the
  /// scan could answer.
  static Future<CommunityTotals> _totalsForKey(
    CommunityPeriod period,
    String? key, {
    required String cacheKey,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _db.collection(membersCollection);
      if (period.keyField case final String keyField) {
        query = query.where(keyField, isEqualTo: key);
      }
      query = query.where(period.actionsField, isGreaterThan: 0);

      final List<AggregateQuerySnapshot> snapshots =
          await Future.wait<AggregateQuerySnapshot>(
            <Future<AggregateQuerySnapshot>>[
              query
                  .aggregate(
                    sum(period.actionsField),
                    count(),
                    sum(period.friendsField),
                    sum(period.ideasField),
                  )
                  .get(),
              query
                  .aggregate(
                    sum(period.couplesField),
                    sum(period.engagementsField),
                  )
                  .get(),
            ],
          );

      final CommunityTotals result = CommunityTotals(
        points: snapshots[0].getSum(period.actionsField)?.round() ?? 0,
        activeMatchmakers: snapshots[0].count ?? 0,
        friends: snapshots[0].getSum(period.friendsField)?.round() ?? 0,
        ideas: snapshots[0].getSum(period.ideasField)?.round() ?? 0,
        couples: snapshots[1].getSum(period.couplesField)?.round() ?? 0,
        engagements: snapshots[1].getSum(period.engagementsField)?.round() ?? 0,
      );
      if (!result.isEmpty) {
        // The query works in this project, whatever it answers next time.
        _aggregatesTrusted.add(cacheKey);
        return result;
      }
      // Aggregates said nothing. That is *usually* the truth — but it is also
      // exactly what a missing composite index looks like from here, so the
      // zero is checked against a direct read before it is believed. Once.
      if (_aggregatesTrusted.contains(cacheKey)) {
        return result;
      }
    } catch (_) {
      // And so is a failure. Both roads lead to the scan below.
    }

    final CommunityTotals scanned = await _totalsByScan(period, key);
    if (scanned.resolved && scanned.isEmpty) {
      // The scan agreed there is nothing here, so the aggregate was telling
      // the truth and need not be second-guessed again this launch. A scan
      // that found figures the aggregate missed says the opposite — the index
      // is missing — so the window stays untrusted and keeps scanning.
      _aggregatesTrusted.add(cacheKey);
    }
    return scanned;
  }

  /// The community's figures added up on this device, one member at a time.
  ///
  /// **The fallback, and the reason "פעילות הקהילה" can no longer sit on 0 when
  /// it should not.** The aggregate query above is the right way to do this —
  /// a handful of reads however large the community grows — but it depends on a
  /// composite index existing in the project, and when one does not the query
  /// fails in a way that is indistinguishable from a quiet week: an empty
  /// answer. Every matchmaker in the app then sees a live community reported as
  /// zero, and nothing on the device can tell them otherwise.
  ///
  /// So a zero is not taken at face value. This reads the member documents for
  /// the window directly — one equality filter, which needs no composite index
  /// at all — and adds them up in Dart. It costs one read per member and is
  /// capped at [_scanLimit], which is why it is the second choice and not the
  /// first; the three-minute cache means it runs at most a few times an hour.
  ///
  /// The `> 0` test the aggregate does in the query is done here in the loop,
  /// so "שדכנים פעילים" keeps meaning "did at least one thing" rather than
  /// "opened the app".
  static Future<CommunityTotals> _totalsByScan(
    CommunityPeriod period,
    String? key,
  ) async {
    if (await _account() == null) {
      return CommunityTotals.empty;
    }
    try {
      Query<Map<String, dynamic>> query = _db.collection(membersCollection);
      if (period.keyField case final String keyField) {
        query = query.where(keyField, isEqualTo: key);
      }
      // One more than the cap, so a community that has outgrown the scan can
      // be recognised rather than quietly half-counted. See below.
      final QuerySnapshot<Map<String, dynamic>> snapshot = await query
          .limit(_scanLimit + 1)
          .get();
      if (snapshot.docs.length > _scanLimit) {
        // There are more members in this window than this fallback can read,
        // so anything it added up would be a fraction of the community
        // presented as the whole of it. "פעילות הקהילה" is a real figure or it
        // is nothing; [CommunityTotals.empty] is the unresolved placeholder,
        // so the card says it could not load rather than showing a fraction.
        return CommunityTotals.empty;
      }

      int points = 0;
      int active = 0;
      int friends = 0;
      int ideas = 0;
      int couples = 0;
      int engagements = 0;
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final Map<String, dynamic> data = doc.data();
        int read(String field) => (data[field] as num?)?.toInt() ?? 0;
        final int memberPoints = read(period.actionsField);
        if (memberPoints <= 0) {
          continue;
        }
        active++;
        points += memberPoints;
        friends += read(period.friendsField);
        ideas += read(period.ideasField);
        couples += read(period.couplesField);
        engagements += read(period.engagementsField);
      }

      return CommunityTotals(
        points: points,
        activeMatchmakers: active,
        friends: friends,
        ideas: ideas,
        couples: couples,
        engagements: engagements,
      );
    } catch (_) {
      return CommunityTotals.empty;
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
    required int myPoints,
    bool forceRefresh = false,
  }) async {
    final String cacheKey = '${period.name}:$includeMe:$myPoints';
    final _Cached<CommunityLeaderboard>? cached = _boardCache[cacheKey];
    if (!forceRefresh && cached != null && cached.isFresh) {
      return cached.value;
    }
    final User? user = await _account();
    if (user == null) {
      return CommunityLeaderboard.empty;
    }

    try {
      Query<Map<String, dynamic>> baseFor(String? key) {
        Query<Map<String, dynamic>> base = _db
            .collection(membersCollection)
            .where('hidden', isEqualTo: false);
        if (period.keyField case final String keyField) {
          base = base.where(keyField, isEqualTo: key);
        }
        return base;
      }

      // The same union the totals read — see [_keysFor]. Ten rows per key,
      // merged and re-sorted here: the keys partition the collection, so the
      // top ten of the union is inside the ten best of each part.
      final List<String?> keys = _keysFor(period);
      final List<CommunityRankEntry> rows = <CommunityRankEntry>[];
      for (final String? key in keys) {
        final QuerySnapshot<Map<String, dynamic>> top = await baseFor(key)
            .where(period.actionsField, isGreaterThan: 0)
            .orderBy(period.actionsField, descending: true)
            .limit(leaderboardSize)
            .get();
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in top.docs) {
          rows.add(
            CommunityRankEntry(
              uid: doc.id,
              name: (doc.data()['name'] as String?)?.trim().isNotEmpty ?? false
                  ? (doc.data()['name'] as String).trim()
                  : 'שדכן',
              points: (doc.data()[period.actionsField] as num?)?.toInt() ?? 0,
              photoUrl: ((doc.data()['photoUrl'] as String?) ?? '').trim(),
            ),
          );
        }
      }
      rows.sort(
        (CommunityRankEntry a, CommunityRankEntry b) =>
            b.points.compareTo(a.points),
      );
      if (rows.length > leaderboardSize) {
        rows.removeRange(leaderboardSize, rows.length);
      }

      int? rank;
      if (includeMe && myPoints > 0) {
        final int index = rows.indexWhere(
          (CommunityRankEntry row) => row.uid == user.uid,
        );
        if (index >= 0) {
          rank = index + 1;
        } else {
          // The `> 0` filter is deliberately not repeated here. This branch only
          // runs when `myPoints > 0`, so `> myPoints` is already the tighter of
          // the two bounds — and one range filter per field keeps the query
          // inside exactly the composite indexes the board above already uses.
          int above = 0;
          for (final String? key in keys) {
            final AggregateQuerySnapshot part = await baseFor(
              key,
            ).where(period.actionsField, isGreaterThan: myPoints).count().get();
            above += part.count ?? 0;
          }
          rank = above + 1;
        }
      }

      // Cached, and usually already in hand: the community area above the board
      // asked for the same window a moment ago.
      final CommunityTotals window = await totals(
        period,
        forceRefresh: forceRefresh,
      );

      final CommunityLeaderboard result = CommunityLeaderboard(
        top: rows,
        myRank: rank,
        myPoints: myPoints,
        activeMatchmakers: window.activeMatchmakers,
      );
      _boardCache[cacheKey] = _Cached<CommunityLeaderboard>(result);
      return result;
    } catch (_) {
      return cached?.value ?? CommunityLeaderboard.empty;
    }
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
