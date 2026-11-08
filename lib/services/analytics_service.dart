// ignore_for_file: constant_identifier_names
import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/home_board_store.dart';

/// Product measurement — what matchmakers and singles **do**, never **about
/// whom**.
///
/// The database is full of people who never agreed to anything: friends,
/// candidates, couples. Nothing about them may reach a measurement system, so
/// the privacy rule is enforced here, in code, rather than left to each call
/// site to remember:
///
/// * **Only catalogued events.** [AnalyticsEvent] is the whole vocabulary; a
///   name that is not in it cannot be sent.
/// * **Only numbers, booleans and codes as parameters.** A string parameter
///   must look like `snake_case_ascii` (≤ 40 chars). A Hebrew name, a phone
///   number, a card text, an id with digits and dashes — none of them passes,
///   whatever a future caller hands in. Counts are reported in bands
///   ([band]) so a figure cannot single anybody out either.
/// * **The account's own uid is the user id**, never an email. Advertising
///   ids, Google Signals and ad personalisation are switched off in the
///   platform files (`AndroidManifest.xml`, `Info.plist`, `Podfile`).
/// * **Off in debug builds**, so testing never mixes with real figures, and
///   off on this account when the matchmaker turned "שליחת נתוני שימוש" off
///   in the privacy settings ([optedOut], synced with the account).
/// * **Administrators and test accounts are marked** with the user property
///   `internal_user = true`, which the console's data filter excludes.
///
/// Every call is fire-and-forget and swallows its own failures: measurement
/// must never be the reason something in the app did not happen.
abstract final class Analytics {
  static const String optOutKey = 'analytics.optOut';
  static const String _milestonesKey = 'analytics.milestones';

  /// Test seam: set to record events instead of sending them.
  @visibleForTesting
  static void Function(String name, Map<String, Object> params)? debugSink;

  static FirebaseAnalytics? get _instance {
    if (debugSink != null) {
      return null;
    }
    if (kDebugMode || !FirebaseBootstrap.isReady) {
      return null;
    }
    try {
      return FirebaseAnalytics.instance;
    } catch (_) {
      return null;
    }
  }

  static Box<dynamic>? get _settings =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// The matchmaker switched measurement off for this account.
  static bool get optedOut => _settings?.get(optOutKey) == 'true';

  static Future<void> setOptedOut(bool value) async {
    persistHomeSetting(optOutKey, value ? 'true' : 'false');
    final FirebaseAnalytics? fa = _instance;
    if (fa == null) {
      return;
    }
    try {
      await fa.setAnalyticsCollectionEnabled(!value);
      if (value) {
        // Forget this device's measurement identity as well.
        await fa.resetAnalyticsData();
      }
    } catch (error) {
      debugPrint('Analytics.setOptedOut failed: $error');
    }
  }

  /// Once Firebase is up and the account known: who this is (uid only), what
  /// kind of user, and whether they are one of us.
  static Future<void> identify({
    required String? uid,
    required String userType,
    required bool internal,
    String? buildNumber,
  }) async {
    final FirebaseAnalytics? fa = _instance;
    if (fa == null) {
      return;
    }
    try {
      await fa.setAnalyticsCollectionEnabled(!optedOut);
      await fa.setUserId(id: uid);
      await fa.setUserProperty(name: 'user_type', value: _code(userType));
      await fa.setUserProperty(
        name: 'internal_user',
        value: internal ? 'true' : 'false',
      );
      if (buildNumber != null && RegExp(r'^\d{1,8}$').hasMatch(buildNumber)) {
        await fa.setUserProperty(name: 'build_number', value: buildNumber);
      }
    } catch (error) {
      debugPrint('Analytics.identify failed: $error');
    }
  }

  /// On sign-out: nothing that follows belongs to that account.
  static Future<void> forget() async {
    final FirebaseAnalytics? fa = _instance;
    if (fa == null) {
      return;
    }
    try {
      await fa.setUserId(id: null);
      await fa.resetAnalyticsData();
    } catch (error) {
      debugPrint('Analytics.forget failed: $error');
    }
  }

  /// Logs one catalogued event. Parameters that are not numbers, booleans or
  /// short ascii codes are dropped — see the class comment.
  static void log(
    AnalyticsEvent event, [
    Map<String, Object?> params = const {},
  ]) {
    if (optedOut) {
      return;
    }
    final Map<String, Object> clean = sanitize(params);
    final void Function(String, Map<String, Object>)? sink = debugSink;
    if (sink != null) {
      sink(event.name, clean);
      return;
    }
    final FirebaseAnalytics? fa = _instance;
    if (fa == null) {
      return;
    }
    unawaited(
      fa.logEvent(name: event.name, parameters: clean).catchError((
        Object error,
      ) {
        debugPrint('Analytics.log(${event.name}) failed: $error');
      }),
    );
  }

  /// A feature was used — counted per feature, so "who uses tags at all" is
  /// a unique-user count in the console.
  static void feature(AnalyticsFeature feature) => log(
    AnalyticsEvent.feature_used,
    <String, Object?>{'feature': feature.name},
  );

  /// Logs [event] only the first time it happens on this account — the
  /// funnel steps ("first friend", "5 friends", "first idea"). Remembered in
  /// a synced setting, so a second phone does not count it again.
  static void milestone(
    AnalyticsEvent event, [
    Map<String, Object?> params = const {},
  ]) {
    final Box<dynamic>? box = _settings;
    if (box == null) {
      return;
    }
    final Object? raw = box.get(_milestonesKey);
    final Set<String> seen = raw is String && raw.isNotEmpty
        ? raw.split(',').toSet()
        : <String>{};
    if (!seen.add(event.name)) {
      return;
    }
    persistHomeSetting(_milestonesKey, seen.join(','));
    log(event, params);
  }

  /// The database-size steps of the matchmaker funnel, fired as the count
  /// crosses them.
  static void friendCountReached(int count) {
    if (count >= 1) milestone(AnalyticsEvent.first_friend_added);
    if (count >= 5) milestone(AnalyticsEvent.friends_reached_5);
    if (count >= 10) milestone(AnalyticsEvent.friends_reached_10);
    if (count >= 25) milestone(AnalyticsEvent.friends_reached_25);
  }

  /// Keeps only what cannot identify anybody.
  @visibleForTesting
  static Map<String, Object> sanitize(Map<String, Object?> params) {
    final Map<String, Object> out = <String, Object>{};
    params.forEach((String key, Object? value) {
      if (!_codePattern.hasMatch(key)) {
        return;
      }
      if (value is bool) {
        // Analytics takes no booleans; 0/1 keeps it a number.
        out[key] = value ? 1 : 0;
      } else if (value is num) {
        out[key] = value;
      } else if (value is String && _codePattern.hasMatch(value)) {
        out[key] = value;
      }
    });
    return out;
  }

  static final RegExp _codePattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

  static String _code(String value) =>
      _codePattern.hasMatch(value) ? value : 'unknown';

  /// An error's type as a code ("platformexception"), never its message —
  /// a message can carry a path, a name or a number.
  static String errorCode(Object error) {
    final String code = error.runtimeType.toString().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    final String trimmed = code.length > 40 ? code.substring(0, 40) : code;
    return _codePattern.hasMatch(trimmed) ? trimmed : 'unknown';
  }

  /// A count as a band, so a figure says how big without saying exactly.
  static String band(int count) {
    if (count <= 0) return 'n0';
    if (count < 5) return 'n1_4';
    if (count < 10) return 'n5_9';
    if (count < 25) return 'n10_24';
    if (count < 50) return 'n25_49';
    if (count < 100) return 'n50_99';
    if (count < 500) return 'n100_499';
    return 'n500_plus';
  }
}

/// The whole vocabulary. Adding an event means adding it here — and it is
/// then automatically held to the parameter rule above.
// Lower snake case on purpose: these are the names the console shows.
enum AnalyticsEvent {
  // Account
  signup_completed,
  login_completed,
  // Contacts
  contacts_permission_requested,
  contacts_permission_granted,
  contacts_permission_denied,
  contacts_permission_blocked,
  contacts_sync_completed,
  contacts_sync_failed,
  // The database
  friend_added,
  first_friend_added,
  friends_reached_5,
  friends_reached_10,
  friends_reached_25,
  // Personal card and access
  personal_card_started,
  personal_card_completed,
  personal_card_updated,
  personal_card_shared,
  access_request_sent,
  access_request_approved,
  access_request_declined,
  access_granted,
  // Ideas
  match_suggestions_opened,
  match_rejected,
  idea_created,
  first_idea_created,
  idea_status_changed,
  idea_closed,
  couple_started_dating,
  first_couple_dating,
  couple_broke_up,
  wedding_marked,
  // Reminders and notifications
  reminder_created,
  notification_opened,
  // Outside the app
  whatsapp_opened,
  // Use and health
  feature_used,
  app_error,
}

/// The features whose use is counted ([Analytics.feature]).
enum AnalyticsFeature {
  tags,
  ai_import,
  matches,
  board,
  search,
  filter,
  share_card,
  notes,
  voice_note,
  personal_area,
  reminders,
  think,
  new_ideas,
}
