import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/community_period.dart';

/// The matchmaker's own community state, on this device.
///
/// The unrelated-looking things here share one property: each of them decides
/// whether the app is allowed to *say* something, and each must survive being
/// asked the same question twice in a session.
///
/// The opt-out is kept locally as well as in Firestore. It is the setting a
/// user is most likely to change and immediately expect to see honoured, and a
/// screen that had to wait for a round trip to know whether to draw the reader
/// on the leaderboard would flash them on and off.
abstract final class CommunityProfileStore {
  static const String _hiddenKey = 'community.hiddenFromLeaderboard';
  static const String _achievementsKey = 'community.achievementsSeen';
  static const String _achievementsBaselinedKey = 'community.achievementsBase';
  static const String _bestWeekKey = 'community.bestWeek';
  static const String _bestWeekAtKey = 'community.bestWeekKey';
  static const String _pendingBulkImportKey = 'community.pendingBulkImport';
  static const String _privateKey = 'community.privateMode';
  static const String _avatarPathKey = 'community.avatarLocalPath';
  static const String _avatarUrlKey = 'community.avatarUrl';
  static const String _greetingKey = 'community.greetingCursor';
  static const String _weekSnapshotKey = 'community.weekSnapshot';
  static const String _prevWeekSnapshotKey = 'community.prevWeekSnapshot';
  static const String _communityMilestonesKey = 'community.sharedMilestones';
  static const String _communityMilestonesBaseKey =
      'community.sharedMilestonesBase';

  /// From this many friends in one import, the app says something about it.
  ///
  /// Ten is where a list stops being a few friends and starts being a database.
  /// Below it the import screen has already said everything worth saying.
  static const int bulkImportNoticeFrom = 10;

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// Written values, readable back immediately.
  ///
  /// Every write here goes through [persistHomeSetting], which deliberately
  /// runs on the root zone — a `Box.put` started inside a widget test's
  /// fake-async zone is never driven to completion, and leaves `Hive.close()`
  /// hanging in `tearDownAll` forever. The cost of that is that a value is not
  /// in the box the instant it is set, and these are read again in the same
  /// frame they are written; this map covers the gap.
  static final Map<String, Object?> _pending = <String, Object?>{};

  static Object? _read(String key) => _pending[key] ?? _box?.get(key);

  static void _write(String key, Object value) {
    _pending[key] = value;
    persistHomeSetting(key, value.toString());
  }

  // --- Hidden from the leaderboard -----------------------------------------

  /// True when the matchmaker asked to stay off the leaderboard.
  ///
  /// **False by default, and that is a deliberate change.** The app used to
  /// treat "has not been asked yet" as "no", which meant a launch dialog on
  /// every fresh install and a community board that was empty until people
  /// answered a question they had no context for. A matchmaker now appears in
  /// the community the way they appear in any other list they joined, and the
  /// one switch that takes them back out lives on "פרטיות והמאגר שלי" — see
  /// [isPrivate] for the wider one next to it.
  static bool get isHidden =>
      _read(_hiddenKey) == true || _read(_hiddenKey) == 'true';

  static void setHidden(bool hidden) => _write(_hiddenKey, hidden);

  // --- "שמור על הפרטיות שלי" -------------------------------------------------

  /// Whether this matchmaker has asked for nothing at all to be shared.
  ///
  /// **Wider than [isHidden], and the difference is the point.** Hidden keeps
  /// the *name* out of the shared collection while the counters still go up and
  /// still add to what the community did. Private stops the publish itself: no
  /// name, no counters, nothing against this uid on the server, and the row
  /// that was already there is deleted when the switch is turned on.
  ///
  /// Everything the app does for its own user carries on untouched — the
  /// personal figures, the chart, the milestones, the weekly best — because all
  /// of them are computed on the device from the device's own records. What is
  /// given up is being counted in the community totals and appearing on the
  /// leaderboard; what is kept is reading both.
  ///
  /// Off by default. Turning a privacy switch on for somebody is not a
  /// courtesy — it is deciding for them — and the community column of an app
  /// where nobody publishes is an empty room.
  static bool get isPrivate =>
      _read(_privateKey) == true || _read(_privateKey) == 'true';

  static void setPrivate(bool private) => _write(_privateKey, private);

  // --- The matchmaker's own picture on the leaderboard ----------------------

  /// Which local photo the published avatar was made from, and the URL it
  /// became.
  ///
  /// **So the picture is uploaded once, not twice a session.** Publishing runs
  /// at every app open and pause; re-uploading an unchanged photo each time
  /// would be a megabyte of somebody's data allowance a day for a picture
  /// nobody has looked at. The local path is the cheapest thing that changes
  /// exactly when the picture does — the picker writes a new file with a
  /// timestamp in its name for every photo chosen.
  static String get uploadedAvatarPath {
    final Object? raw = _read(_avatarPathKey);
    return raw is String ? raw : '';
  }

  static String get uploadedAvatarUrl {
    final Object? raw = _read(_avatarUrlKey);
    return raw is String ? raw : '';
  }

  static void rememberAvatar({required String path, required String url}) {
    _write(_avatarPathKey, path);
    _write(_avatarUrlKey, url);
  }

  // --- The line "הפעילות שלי" opens with -----------------------------------

  /// Which of the eligible opening lines to use next.
  ///
  /// **A cursor rather than a random pick**, for the same reason the ideas
  /// batches use one: randomness repeats, and a matchmaker who opens this
  /// screen three days running and reads the same sentence each time stops
  /// reading it. Walking the cursor guarantees a different one every visit for
  /// as long as there is more than one true thing to say.
  static int get greetingCursor {
    final Object? raw = _read(_greetingKey);
    if (raw is int) {
      return raw;
    }
    return raw is String ? int.tryParse(raw) ?? 0 : 0;
  }

  static void setGreetingCursor(int value) =>
      _write(_greetingKey, value.abs() % 1000);

  // --- The personal weekly best --------------------------------------------

  /// The highest weekly score this device has ever recorded, in activity
  /// points.
  ///
  /// **It is a line, not an event.** It used to raise a "שיא שבועי חדש!!!"
  /// dialog the next time the app opened, which is both an interruption and a
  /// day late; it now sits quietly inside "הפעילות שלך", where somebody looking
  /// at their own numbers will see it at the moment they are interested.
  static int get bestWeek {
    final Object? raw = _read(_bestWeekKey);
    if (raw is int) {
      return raw;
    }
    return raw is String ? int.tryParse(raw) ?? 0 : 0;
  }

  /// Which week set the standing record, so "השבוע הזה הוא השיא" can be told
  /// apart from "השיא נקבע פעם".
  static String get bestWeekKey {
    final Object? raw = _read(_bestWeekAtKey);
    return raw is String ? raw : '';
  }

  /// Records [points] as this week's total when it beats the standing best —
  /// **or whenever the standing best is this week's own figure.**
  ///
  /// That second clause is not a detail. A high-water mark that only ever goes
  /// up is right for a record set in some past week, and wrong for the week
  /// currently running: a matchmaker who reached 15 on Sunday and then deleted
  /// a record that was counted would be shown "שיא חדש השבוע! 15 נקודות"
  /// directly above a card reading 9. The record for a *finished* week cannot
  /// change; the record for the week in progress is simply this week's score,
  /// and it has to be able to come down.
  ///
  /// Nothing is announced and nothing is returned: whoever wants to say
  /// something about the record reads [bestWeek] and decides for themselves.
  static void recordWeek(int points, {String? weekKey}) {
    final String key = weekKey ?? CommunityPeriods.weekKey();
    final bool recordIsThisWeek = bestWeekKey == key;
    if (points <= bestWeek && !recordIsThisWeek) {
      return;
    }
    if (points == bestWeek && recordIsThisWeek) {
      return;
    }
    _write(_bestWeekKey, points);
    _write(_bestWeekAtKey, key);
  }

  // --- The note after a large import ----------------------------------------

  /// How many friends the last unacknowledged import brought in, or zero.
  ///
  /// It is *stored* rather than passed straight to a dialog so that the note
  /// survives the two ways the moment can be lost: the import screen navigating
  /// away before anything can be shown, and the app being killed between the
  /// save and the celebration. Whoever shows it clears it.
  static int get pendingBulkImport {
    final Object? raw = _read(_pendingBulkImportKey);
    if (raw is int) {
      return raw;
    }
    return raw is String ? int.tryParse(raw) ?? 0 : 0;
  }

  /// Records that [added] friends just arrived in one import.
  ///
  /// Below [bulkImportNoticeFrom] nothing is recorded at all: a handful of
  /// friends is an ordinary afternoon, and the app has already said so in the
  /// screen the matchmaker was looking at.
  static void noteBulkImport(int added) {
    if (added < bulkImportNoticeFrom) {
      return;
    }
    // The larger of the two, so two imports in a row before either could be
    // shown are described by the bigger of them rather than by whichever
    // happened to finish last.
    _write(
      _pendingBulkImportKey,
      added > pendingBulkImport ? added : pendingBulkImport,
    );
  }

  static void clearPendingBulkImport() => _write(_pendingBulkImportKey, 0);

  // --- Achievements ---------------------------------------------------------

  static Set<String> get seenAchievements {
    final Object? raw = _read(_achievementsKey);
    if (raw is! String || raw.isEmpty) {
      return <String>{};
    }
    return raw.split(',').where((String id) => id.isNotEmpty).toSet();
  }

  static bool hasSeen(String id) => seenAchievements.contains(id);

  static void markSeen(String id) {
    final Set<String> next = seenAchievements..add(id);
    _write(_achievementsKey, next.join(','));
  }

  /// Whether this install has already written down which milestones it had
  /// *before* the app started congratulating people at the moment they happen.
  ///
  /// Without it, a matchmaker with three hundred friends would open the update
  /// and be congratulated on two hundred — a milestone they passed months ago,
  /// announced because the app had never been asked to notice it. The baseline
  /// runs once, marks everything already reached as seen, and says nothing.
  static bool get hasBaselinedAchievements =>
      _read(_achievementsBaselinedKey) == true ||
      _read(_achievementsBaselinedKey) == 'true';

  static void markAchievementsBaselined() =>
      _write(_achievementsBaselinedKey, true);

  // --- What the community did last week -------------------------------------

  /// The community's own figures for one week, as this device last saw them.
  ///
  /// **This is how "בשבוע שעבר הגענו ל־X" is answered at all.** A member
  /// document holds one week's counters and rolls them over on the next write,
  /// so the moment a new week starts there is nothing on the server that adds
  /// up to what the community did in the week before — the figure exists only
  /// while the week is running. Rather than write a second collection of
  /// weekly summaries (a document every client would have to be trusted to
  /// update correctly, and a rules change to go with it), each device simply
  /// remembers the last community total it read, and keeps the previous week's
  /// when the key rolls over.
  ///
  /// The cost of that is honest and worth stating: the record is **the figure
  /// this phone last saw**, so a matchmaker who did not open the app after
  /// Tuesday remembers Tuesday's number as the week's. It is a target to beat,
  /// not an audited statistic, and an understated one only makes the challenge
  /// easier — never wrong in the direction that matters.
  static CommunityWeekSnapshot? get communityWeek =>
      CommunityWeekSnapshot.decode(_read(_weekSnapshotKey));

  /// The last *completed* week this device saw, or null on a device that has
  /// only ever been open in one week.
  static CommunityWeekSnapshot? get previousCommunityWeek =>
      CommunityWeekSnapshot.decode(_read(_prevWeekSnapshotKey));

  /// Records what the community has done in [weekKey] so far.
  ///
  /// Within one week the figures only ever climb — a member's counters roll
  /// forward, they do not come back — so a reading lower than one already
  /// stored is a partial answer (a scan that hit its cap, a member who deleted
  /// records) and the higher figure is kept. When the key changes, whatever was
  /// stored becomes the previous week's record in the same write.
  static void recordCommunityWeek({
    required String weekKey,
    required int friends,
    required int ideas,
    required int couples,
  }) {
    final CommunityWeekSnapshot? stored = communityWeek;
    if (stored != null && stored.weekKey != weekKey) {
      _write(_prevWeekSnapshotKey, stored.encode());
      _write(
        _weekSnapshotKey,
        CommunityWeekSnapshot(
          weekKey: weekKey,
          friends: friends,
          ideas: ideas,
          couples: couples,
        ).encode(),
      );
      return;
    }
    final CommunityWeekSnapshot next = CommunityWeekSnapshot(
      weekKey: weekKey,
      friends: stored == null || friends > stored.friends
          ? friends
          : stored.friends,
      ideas: stored == null || ideas > stored.ideas ? ideas : stored.ideas,
      couples: stored == null || couples > stored.couples
          ? couples
          : stored.couples,
    );
    _write(_weekSnapshotKey, next.encode());
  }

  // --- The community's own milestones ---------------------------------------

  /// Which shared milestones — "הקהילה הגיעה ל־1,000 רעיונות" and the like —
  /// this device has already celebrated.
  static Set<String> get seenCommunityMilestones {
    final Object? raw = _read(_communityMilestonesKey);
    if (raw is! String || raw.isEmpty) {
      return <String>{};
    }
    return raw.split(',').where((String id) => id.isNotEmpty).toSet();
  }

  static void markCommunityMilestoneSeen(String id) {
    final Set<String> next = seenCommunityMilestones..add(id);
    _write(_communityMilestonesKey, next.join(','));
  }

  /// Whether this device has written down which community milestones were
  /// already passed before it ever looked.
  ///
  /// The same reasoning as [hasBaselinedAchievements], and it matters more
  /// here: the community's all-time figures are large and mostly historic, so
  /// without a baseline every fresh install would open to a celebration of
  /// something that happened long before it was installed. The first resolved
  /// read marks everything reached as seen and says nothing; only a rung
  /// crossed *afterwards* is ever announced.
  static bool get hasBaselinedCommunityMilestones =>
      _read(_communityMilestonesBaseKey) == true ||
      _read(_communityMilestonesBaseKey) == 'true';

  static void markCommunityMilestonesBaselined() =>
      _write(_communityMilestonesBaseKey, true);
}

/// One week of community figures as a device saw them, small enough to live in
/// a single settings string.
///
/// Encoded as `weekKey|friends|ideas|couples` rather than as JSON because every
/// value in this store is written through [persistHomeSetting], which takes a
/// string — and four fields with one shape do not need a parser that can fail
/// in interesting ways.
class CommunityWeekSnapshot {
  const CommunityWeekSnapshot({
    required this.weekKey,
    required this.friends,
    required this.ideas,
    required this.couples,
  });

  final String weekKey;
  final int friends;
  final int ideas;
  final int couples;

  String encode() => '$weekKey|$friends|$ideas|$couples';

  /// Null for anything that is not a snapshot this class wrote — an empty box,
  /// a value from an older version, a half-written string.
  static CommunityWeekSnapshot? decode(Object? raw) {
    if (raw is! String) {
      return null;
    }
    final List<String> parts = raw.split('|');
    if (parts.length != 4 || parts.first.isEmpty) {
      return null;
    }
    final int? friends = int.tryParse(parts[1]);
    final int? ideas = int.tryParse(parts[2]);
    final int? couples = int.tryParse(parts[3]);
    if (friends == null || ideas == null || couples == null) {
      return null;
    }
    return CommunityWeekSnapshot(
      weekKey: parts.first,
      friends: friends,
      ideas: ideas,
      couples: couples,
    );
  }
}
