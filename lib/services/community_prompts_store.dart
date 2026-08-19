import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// What the app has already asked this matchmaker, and when it may ask again.
///
/// Two prompts live here — the invitation to the WhatsApp updates group and the
/// request for a store rating — and one thing that is only ever shown once, the
/// "מה חדש?" announcement. All three share the same problem: the app has
/// something worth saying, and saying it twice is worse than not saying it.
///
/// **Both prompts are paced by the action counter, not by the calendar.** The
/// figure is the one the home screen already shows as "כל הזמנים" — friends
/// added, ideas opened, statuses moved — so somebody who opens the app daily and
/// somebody who works in bursts are asked at the same point *in their own work*
/// rather than at the same point in the month. Time-based nagging finds the
/// people who use the app least; this finds the people it is working for.
///
/// Everything is stored in the same Hive `settings` box the rest of the app's
/// preferences use, written through [persistHomeSetting] so a prompt shown
/// during a widget test never leaves a pending write behind.
abstract final class CommunityPromptsStore {
  static const String _inGroupKey = 'community.inWhatsAppGroup';
  static const String _groupAskedAtKey = 'community.groupAskedAtActions';
  static const String _ratingAskedAtKey = 'community.ratingAskedAtActions';
  static const String _ratingAskCountKey = 'community.ratingAskCount';
  static const String _ratingDoneKey = 'community.ratingDone';
  static const String _seenAnnouncementKey = 'community.seenAnnouncementId';
  static const String _seenEngagementKey = 'community.seenEngagementId';
  static const String _congratulatedKey = 'community.congratulatedIds';
  static const String _mazelTovNotifiedKey = 'community.mazelTovNotified';
  static const String _mazelTovDeliveredKey = 'community.mazelTovDelivered';

  /// How many actions pass between two invitations to the group.
  static const int groupPromptEveryActions = 100;

  /// And between the first rating request and the one after it. Twice as far
  /// apart as the group invitation, because a rating is a bigger thing to ask.
  static const int ratingPromptEveryActions = 200;

  /// A rating is never asked more than this many times, however long the app is
  /// used. Two asks that were both ignored are an answer.
  static const int ratingMaxAsks = 2;

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// Written values, readable back immediately.
  ///
  /// Every write goes through [persistHomeSetting], which runs on the root
  /// zone — a `Box.put` started inside a widget test's fake-async zone is never
  /// driven to completion and leaves `Hive.close()` hanging in `tearDownAll`.
  /// The price is that a value is not in the box the instant it is set, and
  /// these are read again in the same frame they are written; this covers it.
  static final Map<String, Object?> _pending = <String, Object?>{};

  static Object? _read(String key) => _pending[key] ?? _box?.get(key);

  static void _write(String key, Object value) {
    _pending[key] = value;
    persistHomeSetting(key, value.toString());
  }

  static int _readInt(String key) {
    final Object? raw = _read(key);
    if (raw is int) {
      return raw;
    }
    return raw is String ? int.tryParse(raw) ?? 0 : 0;
  }

  static bool _readBool(String key) {
    final Object? raw = _read(key);
    return raw == true || raw == 'true';
  }

  // --- The WhatsApp updates group ------------------------------------------

  /// Only an explicit "אני כבר בקבוצה" stops the reminders.
  ///
  /// Tapping the invite link deliberately does **not** count. It opens WhatsApp
  /// and hands the decision to a screen this app cannot see the outcome of, so
  /// treating the tap as a join would silently drop everyone who opened the
  /// link and then changed their mind.
  static bool get isInUpdatesGroup => _readBool(_inGroupKey);

  static void markInUpdatesGroup() => _write(_inGroupKey, true);

  /// Whether the group invitation is due at [actions] total actions.
  ///
  /// The first showing is immediate — a new matchmaker should be offered the
  /// group at the start of using the app, not a hundred actions into it.
  static bool shouldOfferUpdatesGroup(int actions) {
    if (isInUpdatesGroup) {
      return false;
    }
    final int askedAt = _readInt(_groupAskedAtKey);
    if (askedAt == 0) {
      return true;
    }
    return actions - askedAt >= groupPromptEveryActions;
  }

  /// Records that the invitation was just shown, so the next one is a hundred
  /// actions away. The count is stored rather than a timestamp so a burst of
  /// work moves the next prompt and a quiet fortnight does not.
  static void markUpdatesGroupOffered(int actions) {
    // Zero would read as "never asked" and bring the prompt straight back, so
    // an offer made before the first action still counts as one.
    final int stamp = actions <= 0 ? 1 : actions;
    _write(_groupAskedAtKey, stamp);
  }

  // --- The store rating ----------------------------------------------------

  /// True once the matchmaker has been sent to the store, or has said no twice.
  static bool get isRatingSettled =>
      _readBool(_ratingDoneKey) ||
      _readInt(_ratingAskCountKey) >= ratingMaxAsks;

  /// Whether a rating may be asked for at [actions] total actions.
  ///
  /// [earned] is the caller's judgement that something good just happened — a
  /// first couple who started dating, ten ideas opened, twenty-five friends
  /// added. Without it nothing is asked at all: the point of the rule is that
  /// the request follows a success rather than arriving on a schedule.
  static bool shouldAskForRating({required int actions, required bool earned}) {
    if (isRatingSettled) {
      return false;
    }
    final int askedAt = _readInt(_ratingAskedAtKey);
    if (askedAt == 0) {
      return earned;
    }
    return actions - askedAt >= ratingPromptEveryActions;
  }

  static void markRatingAsked(int actions) {
    final int stamp = actions <= 0 ? 1 : actions;
    _write(_ratingAskedAtKey, stamp);
    _write(_ratingAskCountKey, _readInt(_ratingAskCountKey) + 1);
  }

  /// Called when the store actually opened. Nothing is ever asked again — the
  /// app cannot tell whether a review was left, and asking somebody who already
  /// went is the exact behaviour this whole file exists to avoid.
  static void markRatingDone() => _write(_ratingDoneKey, true);

  // --- "מה חדש?" -----------------------------------------------------------

  /// The id of the last announcement this device has already been shown.
  static String get seenAnnouncementId {
    final Object? raw = _read(_seenAnnouncementKey);
    return raw is String ? raw : '';
  }

  static void markAnnouncementSeen(String id) {
    if (id.isEmpty) {
      return;
    }
    _write(_seenAnnouncementKey, id);
  }

  // --- "מזל טוב! זוג חדש התארס!" -------------------------------------------

  /// The last engagement this device has already been congratulated about.
  ///
  /// One id rather than a set, because the announcement is only ever the
  /// *newest* one: a matchmaker who was away for a fortnight is told about the
  /// couple from Tuesday, not handed a backlog of four. Anything older than
  /// that has passed, which is the whole idea — see
  /// `CommunityEngagementsService.freshFor`.
  static String get seenEngagementId {
    final Object? raw = _read(_seenEngagementKey);
    return raw is String ? raw : '';
  }

  static void markEngagementSeen(String id) {
    if (id.isEmpty) {
      return;
    }
    _write(_seenEngagementKey, id);
  }

  // --- "שלחו מזל טוב" -------------------------------------------------------

  /// How many ids each of the three sets below keeps.
  ///
  /// They are append-only and they are all about things that stop mattering:
  /// an engagement stops being shown after a week, a message is deleted from
  /// the server once it is filed, and a wedding is only ever notified about
  /// once. Trimming to the newest few dozen keeps a settings value from
  /// growing without bound on a device that is used for years, and the worst
  /// case of trimming too soon is a second notification about a wedding from
  /// months ago.
  static const int _idMemory = 60;

  static Set<String> _readIds(String key) {
    final Object? raw = _read(key);
    if (raw is! String || raw.isEmpty) {
      return <String>{};
    }
    return raw.split(',').where((String id) => id.isNotEmpty).toSet();
  }

  static void _addId(String key, String id) {
    if (id.isEmpty) {
      return;
    }
    final List<String> ids = <String>[..._readIds(key)..remove(id), id];
    _write(
      key,
      (ids.length <= _idMemory ? ids : ids.sublist(ids.length - _idMemory))
          .join(','),
    );
  }

  /// Engagements this matchmaker has already sent a "מזל טוב" for, so the
  /// button turns into a thank-you rather than inviting a second one.
  static bool hasCongratulated(String engagementId) =>
      _readIds(_congratulatedKey).contains(engagementId);

  static void markCongratulated(String engagementId) =>
      _addId(_congratulatedKey, engagementId);

  /// Proposals whose congratulations have already raised a notification.
  ///
  /// **One per wedding, not one per message.** Six matchmakers wishing the same
  /// couple well is one piece of news; six notifications for it is a phone
  /// buzzing at somebody who is trying to enjoy it. The messages all land in
  /// the journal either way — this only decides how many times the app taps
  /// somebody on the shoulder about them.
  static bool hasNotifiedMazelTov(String matchId) =>
      _readIds(_mazelTovNotifiedKey).contains(matchId);

  static void markMazelTovNotified(String matchId) =>
      _addId(_mazelTovNotifiedKey, matchId);

  /// Messages already written into a journal.
  ///
  /// The belt to the server-side deletion's braces: a delete that fails leaves
  /// the message in the inbox, and without this it would be filed again on the
  /// next drain.
  static bool hasDeliveredMazelTov(String messageId) =>
      _readIds(_mazelTovDeliveredKey).contains(messageId);

  static void markMazelTovDelivered(String messageId) =>
      _addId(_mazelTovDeliveredKey, messageId);
}
