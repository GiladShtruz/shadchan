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
  static const String _consentKey = 'community.leaderboardConsentAnswered';
  static const String _achievementsKey = 'community.achievementsSeen';
  static const String _achievementsBaselinedKey = 'community.achievementsBase';
  static const String _bestWeekKey = 'community.bestWeek';
  static const String _bestWeekAtKey = 'community.bestWeekKey';
  static const String _pendingBulkImportKey = 'community.pendingBulkImport';
  static const String _privateKey = 'community.privateMode';
  static const String _avatarPathKey = 'community.avatarLocalPath';
  static const String _avatarUrlKey = 'community.avatarUrl';
  static const String _greetingKey = 'community.greetingCursor';

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

  /// Whether the matchmaker has been asked, once, whether their name may
  /// appear on the leaderboard.
  ///
  /// This exists because the feature arrived in an update. Everybody using the
  /// app registered their name for a private diary, and publishing it to every
  /// other user on the strength of that is not something an opt-out after the
  /// fact repairs. Until this is true the answer is treated as "no".
  static bool get hasAnsweredLeaderboardConsent =>
      _read(_consentKey) == true || _read(_consentKey) == 'true';

  /// True when the name must be kept out of the shared collection — either
  /// because it was hidden, or because nobody has asked yet.
  ///
  /// The unasked case is the important one: a name is *not written at all*
  /// until it has been agreed to, so a matchmaker who never answers leaves
  /// nothing identifying on the server, only counters against a uid.
  static bool get isHidden =>
      !hasAnsweredLeaderboardConsent ||
      _read(_hiddenKey) == true ||
      _read(_hiddenKey) == 'true';

  /// Records the answer to the one-time question. Passing [hidden] false is
  /// what puts the name on the board.
  static void answerLeaderboardConsent({required bool hidden}) {
    _write(_consentKey, true);
    _write(_hiddenKey, hidden);
  }

  static void setHidden(bool hidden) {
    // Reaching the toggle at all means the question has been answered, however
    // it was reached.
    _write(_consentKey, true);
    _write(_hiddenKey, hidden);
  }

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
}
