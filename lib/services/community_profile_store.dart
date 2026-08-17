import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/community_period.dart';

/// The matchmaker's own community state, on this device.
///
/// Three unrelated-looking things live here because they share one property:
/// each of them decides whether the app is allowed to *say* something, and each
/// of them must survive being asked the same question twice in a session.
///
/// The opt-out is kept locally as well as in Firestore. It is the setting a
/// user is most likely to change and immediately expect to see honoured, and a
/// screen that had to wait for a round trip to know whether to draw the reader
/// on the leaderboard would flash them on and off.
abstract final class CommunityProfileStore {
  static const String _hiddenKey = 'community.hiddenFromLeaderboard';
  static const String _consentKey = 'community.leaderboardConsentAnswered';
  static const String _bestWeekKey = 'community.bestWeek';
  static const String _bestWeekAtKey = 'community.bestWeekKey';
  static const String _recordCelebratedKey = 'community.recordCelebratedWeek';
  static const String _achievementsKey = 'community.achievementsSeen';
  static const String _pendingBulkImportKey = 'community.pendingBulkImport';

  /// An import of more than this many friends at once still counts towards
  /// every total — it was real work — but is not allowed to *set* the personal
  /// weekly record. A record nobody can ever beat is not encouragement.
  static const int bulkImportRecordLimit = 30;

  /// From this many friends in one import, the app says something about it.
  ///
  /// Lower than [bulkImportRecordLimit] and unrelated to it — the two numbers
  /// answer different questions. This one is "was that enough of a moment to be
  /// worth a word?"; the other is "was that too much to be a record?". Ten is
  /// where a list stops being a few friends and starts being a database.
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

  // --- The personal weekly record ------------------------------------------

  static int get bestWeek {
    final Object? raw = _read(_bestWeekKey);
    if (raw is int) {
      return raw;
    }
    return raw is String ? int.tryParse(raw) ?? 0 : 0;
  }

  /// Which week set the standing record, so the current week beating itself
  /// over and over is one record rather than forty.
  static String get bestWeekKey {
    final Object? raw = _read(_bestWeekAtKey);
    return raw is String ? raw : '';
  }

  /// Records [actions] as this week's total and reports whether it is a new
  /// personal best worth saying something about.
  ///
  /// Returns false when the record was merely extended inside the same week —
  /// the number is kept, but a matchmaker is congratulated once per week, not
  /// once per friend added after the moment they passed their old best.
  static bool recordWeek(int actions, {String? weekKey}) {
    final String key = weekKey ?? CommunityPeriods.weekKey();
    final int previous = bestWeek;
    if (actions <= previous) {
      return false;
    }

    final bool sameWeekAsRecord = bestWeekKey == key;
    _write(_bestWeekKey, actions);
    _write(_bestWeekAtKey, key);

    if (sameWeekAsRecord || previous == 0) {
      // Either this week already holds the record, or there was no record to
      // beat — a first week is a beginning, not an achievement.
      return false;
    }
    if (_read(_recordCelebratedKey) == key) {
      return false;
    }
    _write(_recordCelebratedKey, key);
    return true;
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
}
