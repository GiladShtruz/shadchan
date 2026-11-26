import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// The five things that earn activity points.
enum ScoreEventType {
  /// A friend added from the matchmaker's own contacts — 1.
  friend,

  /// A single's personal card the matchmaker was given access to. Worth 2 in
  /// all for that friend: 2 on its own, or 1 on top of an earlier [friend].
  card,

  /// An idea opened — 1, once per pair.
  idea,

  /// A couple who started going out — 5, once per pair.
  dating,

  /// A couple who got engaged / married — 50, once per pair.
  engaged;

  static ScoreEventType? byName(Object? name) {
    for (final ScoreEventType type in values) {
      if (type.name == name) return type;
    }
    return null;
  }
}

/// What every scoring event is worth, and the one date the rules changed.
abstract final class ScoreRules {
  static const int friend = 1;

  /// A personal card's base worth for its friend, in total.
  static const int card = 2;
  static const int idea = 1;
  static const int dating = 5;
  static const int engaged = 50;

  /// **Before this day every friend added counted**, whichever way they came
  /// in — that is what the app said at the time, and a matchmaker's score is
  /// not taken away by an update. From this day on only a friend added from
  /// the contacts earns the friend point. Fixed rather than "the first launch
  /// of this version", so every phone of an account backfills the past with
  /// the same events and nothing is counted twice.
  static final DateTime newRulesSince = DateTime(2026, 11, 26);

  /// The `source` the contacts import stamps on a friend
  /// (`ContactsImportService.stageSingleCandidate`, and older versions).
  static bool isFromContacts(Person person) =>
      person.source == 'סריקה' || person.source == 'אנשי קשר';

  static int pointsOf(ScoreEventType type) => switch (type) {
    ScoreEventType.friend => friend,
    ScoreEventType.card => card,
    ScoreEventType.idea => idea,
    ScoreEventType.dating => dating,
    ScoreEventType.engaged => engaged,
  };
}

/// One scoring event: what happened, to whom, when, and what it was worth.
///
/// The id is **deterministic** — `type:key` — which is the whole of the
/// de-duplication: the same friend, the same card, the same pair can only ever
/// be written once, on any phone of the account, however many times the event
/// is "done" again (re-added, re-approved, moved back and forth).
@immutable
class ScoreEvent {
  const ScoreEvent({
    required this.id,
    required this.type,
    required this.points,
    required this.at,
    required this.recordedAt,
    this.personId,
    this.personKey,
    this.cardOwnerUid,
    this.matchId,
    this.aId,
    this.bId,
    this.aKey,
    this.bKey,
    this.legacy = false,
  });

  final String id;
  final ScoreEventType type;

  /// What this event added to the matchmaker's total. A card that follows a
  /// contacts friend is 1, a card on its own 2.
  final int points;

  /// When it happened — the window it counts in.
  final DateTime at;

  /// When this device first wrote it down.
  final DateTime recordedAt;

  // friend / card
  final String? personId;
  final String? personKey;
  final String? cardOwnerUid;

  // idea / dating / engaged
  final String? matchId;
  final String? aId;
  final String? bId;
  final String? aKey;
  final String? bKey;

  /// Backfilled from records made before [ScoreRules.newRulesSince].
  final bool legacy;

  bool get isPair =>
      type == ScoreEventType.idea ||
      type == ScoreEventType.dating ||
      type == ScoreEventType.engaged;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    't': type.name,
    'p': points,
    'at': at.toIso8601String(),
    'r': recordedAt.toIso8601String(),
    if (personId != null) 'pid': personId,
    if (personKey != null) 'k': personKey,
    if (cardOwnerUid != null) 'u': cardOwnerUid,
    if (matchId != null) 'm': matchId,
    if (aId != null) 'a': aId,
    if (bId != null) 'b': bId,
    if (aKey != null) 'ka': aKey,
    if (bKey != null) 'kb': bKey,
    if (legacy) 'l': true,
  };

  static ScoreEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final ScoreEventType? type = ScoreEventType.byName(raw['t']);
    final Object? id = raw['id'];
    final DateTime? at = raw['at'] is String
        ? DateTime.tryParse(raw['at'] as String)
        : null;
    if (type == null || id is! String || at == null) return null;
    final Object? points = raw['p'];
    String? s(String key) => raw[key] is String ? raw[key] as String : null;
    return ScoreEvent(
      id: id,
      type: type,
      points: points is int ? points : ScoreRules.pointsOf(type),
      at: at,
      recordedAt: DateTime.tryParse(s('r') ?? '') ?? at,
      personId: s('pid'),
      personKey: s('k'),
      cardOwnerUid: s('u'),
      matchId: s('m'),
      aId: s('a'),
      bId: s('b'),
      aKey: s('ka'),
      bKey: s('kb'),
      legacy: raw['l'] == true,
    );
  }
}

/// **The one source of every activity figure in the app.**
///
/// The total on the profile, the community board, "שדכני השבוע", the weekly
/// summary, the activity chart and the small figure on each friend's card are
/// all sums over these events — never a counter that is incremented and can
/// drift. Each event is a `settings` entry `score.e.<id>`, so it travels with
/// the account to `users/{uid}/settings` like every synced setting (shared by
/// a couple, see `CoupleWorkspaceService.sharedSetting`) and can be read back,
/// recounted and checked.
///
/// Events are written two ways, both idempotent:
/// * [reconcile] reads the records — friends, ideas, the status ledger — and
///   writes whatever event they show that is not written yet. It is also the
///   migration: the first run on an existing database fills the past in.
/// * [recordCard] is called the moment a personal card is linked, so its two
///   points are dated today rather than the day the friend was first typed.
///
/// Nothing is ever taken away again, with one exception: a couple marked
/// "יוצאים" or "חתונה" by mistake and taken back within
/// [DatingHistory.mistakeWindow], or removed by hand from "זוגות שיצאו", has
/// that event retracted — that is a correction, not a second event.
abstract final class ScoreLedger {
  static const String prefix = 'score.e.';

  static Map<String, ScoreEvent>? _cache;
  static Map<String, ScoreEvent>? _transient;
  static int _cacheBoxLength = -1;
  static Box<dynamic>? _cacheBox;

  /// Written or deleted this session and maybe not on disk yet.
  static final Map<String, ScoreEvent> _pendingPut = <String, ScoreEvent>{};
  static final Set<String> _pendingDelete = <String>{};

  /// Bumped on every change, so anything memoised over the events knows.
  static int revision = 0;

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// Every event this account holds, by id.
  static Map<String, ScoreEvent> _all() {
    final Box<dynamic>? box = _box;
    if (box == null) {
      // No settings box (some tests): nothing persists. Each [reconcile]
      // starts from the records alone; what it found is kept for the reads
      // that follow it ([events], [pointsFor]) until the next one.
      return _transient ??= <String, ScoreEvent>{};
    }
    if (_cache == null ||
        !identical(_cacheBox, box) ||
        _cacheBoxLength != box.length) {
      final Map<String, ScoreEvent> loaded = <String, ScoreEvent>{};
      for (final Object? key in box.keys) {
        if (key is! String || !key.startsWith(prefix)) continue;
        final Object? raw = box.get(key);
        try {
          final ScoreEvent? event = ScoreEvent.fromJson(
            raw is String ? jsonDecode(raw) : raw,
          );
          if (event != null) loaded[event.id] = event;
        } on FormatException {
          continue;
        }
      }
      loaded.addAll(_pendingPut);
      _pendingDelete.forEach(loaded.remove);
      _cache = loaded;
      _cacheBox = box;
      _cacheBoxLength = box.length;
      _index = null;
    }
    return _cache!;
  }

  /// All events, in no order.
  static List<ScoreEvent> get events => _all().values.toList(growable: false);

  /// The cache is dropped when the account changes `settings` (another phone
  /// wrote an event) — see `LocalSettingCaches`.
  static void forgetCache() {
    _cache = null;
    _transient = null;
    _index = null;
    _memoKey = null;
    revision++;
  }

  @visibleForTesting
  static void resetForTest() {
    _cache = null;
    _transient = null;
    _cacheBox = null;
    _cacheBoxLength = -1;
    _pendingPut.clear();
    _pendingDelete.clear();
    _index = null;
    _memoKey = null;
    revision++;
  }

  static void _put(ScoreEvent event) {
    final Map<String, ScoreEvent> all = _all();
    all[event.id] = event;
    _pendingDelete.remove(event.id);
    revision++;
    _index = null;
    final Box<dynamic>? box = _box;
    if (box == null) {
      // Nothing to write to; held for this call chain only.
      return;
    }
    _pendingPut[event.id] = event;
    final String value = jsonEncode(event.toJson());
    // Root zone, like every setting written from a build: a Hive write
    // started in a widget test's fake-async zone never completes.
    Zone.root.scheduleMicrotask(() async {
      try {
        if (Hive.isBoxOpen('settings')) {
          await Hive.box<dynamic>('settings').put('$prefix${event.id}', value);
        }
      } catch (_) {
        return;
      }
      _pendingPut.remove(event.id);
    });
  }

  static void _remove(String id) {
    final Map<String, ScoreEvent> all = _all();
    if (all.remove(id) == null) return;
    _pendingPut.remove(id);
    revision++;
    _index = null;
    if (_box == null) return;
    _pendingDelete.add(id);
    Zone.root.scheduleMicrotask(() async {
      try {
        if (Hive.isBoxOpen('settings')) {
          await Hive.box<dynamic>('settings').delete('$prefix$id');
        }
      } catch (_) {
        return;
      }
      _pendingDelete.remove(id);
    });
  }

  // --- Who is who ------------------------------------------------------------

  /// The one key a friend is known by across a deletion and a re-add: their
  /// phone (hashed), else the card they keep, else the record's own id.
  static String keyOf(Person person) {
    final String? phone = PhoneIdentity.hash(person.phone);
    if (phone != null) return 'p:$phone';
    final String? uid = person.cardOwnerUid;
    if (uid != null && uid.isNotEmpty) return 'u:$uid';
    return 'id:${person.id}';
  }

  /// Every key a friend's events may have been written under.
  static Set<String> keysOf(Person person) => <String>{
    'id:${person.id}',
    keyOf(person),
    if ((person.cardOwnerUid ?? '').isNotEmpty) 'u:${person.cardOwnerUid}',
  };

  static String _keyForId(String id, Map<String, Person> byId) {
    final Person? person = byId[id];
    return person == null ? 'id:$id' : keyOf(person);
  }

  static String _nameKey(Person person) => person.fullName
      .toLowerCase()
      .replaceAll(RegExp(r'''[\s'"־–—.,()\-]+'''), ' ')
      .trim();

  static String _dayKey(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';

  static String _pairOf(String a, String b) {
    final List<String> pair = <String>[a, b]..sort();
    return pair.join('|');
  }

  // --- Writing ---------------------------------------------------------------

  static bool _cardCoversKey(Map<String, ScoreEvent> all, String key) {
    for (final ScoreEvent e in all.values) {
      if (e.type == ScoreEventType.card && e.personKey == key) return true;
    }
    return false;
  }

  /// A friend who came in from the contacts (or before the rules changed).
  static void _friend(
    Person person,
    Map<String, ScoreEvent> all,
    DateTime now,
  ) {
    final String key = keyOf(person);
    final bool legacy = person.createdAt.isBefore(ScoreRules.newRulesSince);
    // A friend from before the change with no phone is known, as the old
    // count knew them, by name and day — so the same person typed twice on
    // one day was one friend then and stays one friend now.
    final String id = legacy && key.startsWith('id:')
        ? 'friend:n:${_nameKey(person)}:${_dayKey(person.createdAt)}'
        : 'friend:$key';
    if (all.containsKey(id)) return;
    // A friend whose card already gave them their base points earns no
    // friend point on top — a card is worth 2 in all, never 3.
    if ((person.cardOwnerUid ?? '').isNotEmpty &&
        all.containsKey('card:${person.cardOwnerUid}')) {
      return;
    }
    if (_cardCoversKey(all, key)) return;
    _put(
      ScoreEvent(
        id: id,
        type: ScoreEventType.friend,
        points: ScoreRules.friend,
        at: person.createdAt,
        recordedAt: now,
        personId: person.id,
        personKey: key,
        legacy: legacy,
      ),
    );
  }

  static bool _earnsFriendPoint(Person person) =>
      ScoreRules.isFromContacts(person) ||
      person.createdAt.isBefore(ScoreRules.newRulesSince);

  static void _card(
    Person person,
    Map<String, ScoreEvent> all,
    DateTime at,
    DateTime now,
  ) {
    final String? uid = person.cardOwnerUid;
    if (uid == null || uid.isEmpty) return;
    final String id = 'card:$uid';
    if (all.containsKey(id)) return;
    // A friend from the contacts already holds their 1; the card adds the
    // second. Written first if the friend event is not down yet.
    if (_earnsFriendPoint(person)) _friend(person, all, now);
    final String key = keyOf(person);
    final bool hadFriend = all.values.any(
      (ScoreEvent e) =>
          e.type == ScoreEventType.friend &&
          (e.personKey == key || e.personId == person.id),
    );
    _put(
      ScoreEvent(
        id: id,
        type: ScoreEventType.card,
        points: hadFriend
            ? ScoreRules.card - ScoreRules.friend
            : ScoreRules.card,
        at: at,
        recordedAt: now,
        personId: person.id,
        personKey: key,
        cardOwnerUid: uid,
        legacy: at.isBefore(ScoreRules.newRulesSince),
      ),
    );
  }

  /// A personal card was just linked to [person] (access approved). Dated
  /// now — the moment the matchmaker earned it.
  static void recordCard(Person person, {DateTime? at}) {
    final DateTime now = DateTime.now();
    _card(person, _all(), at ?? now, now);
  }

  static void _pair(
    ScoreEventType type,
    MatchIdea match,
    DateTime at,
    Map<String, Person> byId,
    Map<String, ScoreEvent> all,
    DateTime now,
  ) {
    final String aKey = _keyForId(match.personAId, byId);
    final String bKey = _keyForId(match.personBId, byId);
    final String id = '${type.name}:${_pairOf(aKey, bKey)}';
    if (all.containsKey(id)) return;
    _put(
      ScoreEvent(
        id: id,
        type: type,
        points: ScoreRules.pointsOf(type),
        at: at,
        recordedAt: now,
        matchId: match.id,
        aId: match.personAId,
        bId: match.personBId,
        aKey: aKey,
        bKey: bKey,
        legacy: at.isBefore(ScoreRules.newRulesSince),
      ),
    );
  }

  // --- Reconciling with the records -----------------------------------------

  static String? _memoKey;
  static List<ScoreEvent>? _memo;

  /// Brings the ledger up to date with the records and returns every event.
  ///
  /// Add-only and idempotent: it is safe to call from a build, as often as
  /// the screens like, on every phone. Memoised on everything that can change
  /// the answer.
  static List<ScoreEvent> reconcile({
    required List<Person> people,
    required List<MatchIdea> matches,
    required List<MatchStatusEvent> statusEvents,
    Set<String> excludedFromDating = const <String>{},
    List<DatingCoupleRecord>? datingCouples,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    String key() {
      int latest = 0;
      for (final Person p in people) {
        final int t = p.updatedAt.millisecondsSinceEpoch;
        if (t > latest) latest = t;
      }
      for (final MatchIdea m in matches) {
        final int t = m.updatedAt.millisecondsSinceEpoch;
        if (t > latest) latest = t;
      }
      return '${identityHashCode(_box)}|${_box?.length}|$revision|'
          '${people.length}|${matches.length}|${statusEvents.length}|'
          '${excludedFromDating.length}|$latest|'
          '${at.year}-${at.month}-${at.day}-${at.hour}';
    }

    final String before = key();
    if (_box != null && _memoKey == before && _memo != null) return _memo!;

    if (_box == null) {
      _transient = <String, ScoreEvent>{};
      _index = null;
    }
    final Map<String, ScoreEvent> all = _all();
    final Map<String, Person> byId = <String, Person>{
      for (final Person p in people) p.id: p,
    };

    // 1. Cards first: a friend who keeps one gets their 2 from it.
    for (final Person person in people) {
      if (person.hidden || (person.cardOwnerUid ?? '').isEmpty) continue;
      // A card linked before the rules changed is dated with the friend;
      // one this device somehow missed linking today is dated today.
      final DateTime cardAt =
          person.createdAt.isBefore(ScoreRules.newRulesSince)
          ? person.createdAt
          : at;
      _card(person, all, cardAt, at);
    }

    // 2. Friends: from the contacts, or anybody before the rules changed.
    for (final Person person in people) {
      if (person.hidden || !_earnsFriendPoint(person)) continue;
      _friend(person, all, at);
    }

    // 3. Ideas.
    for (final MatchIdea match in matches) {
      _pair(ScoreEventType.idea, match, match.createdAt, byId, all, at);
    }

    // 4. Couples who went out — the same history every couple figure reads.
    final List<DatingCoupleRecord> dating =
        datingCouples ??
        DatingHistory.all(
          matches: matches,
          statusEvents: statusEvents,
          excludedMatchIds: excludedFromDating,
          now: at,
        );
    final Set<String> datingNow = <String>{};
    for (final DatingCoupleRecord record in dating) {
      datingNow.add(record.match.id);
      _pair(
        ScoreEventType.dating,
        record.match,
        record.startedAt,
        byId,
        all,
        at,
      );
    }

    // 5. Engagements / weddings.
    final Map<String, DateTime> engagedAt = engagementDates(
      matches,
      statusEvents,
    );
    final Map<String, MatchIdea> matchById = <String, MatchIdea>{
      for (final MatchIdea m in matches) m.id: m,
    };
    for (final MapEntry<String, DateTime> entry in engagedAt.entries) {
      _pair(
        ScoreEventType.engaged,
        matchById[entry.key]!,
        entry.value,
        byId,
        all,
        at,
      );
    }

    // Corrections: a mis-tap taken back inside the mistake window, or a couple
    // removed by hand from "זוגות שיצאו".
    for (final ScoreEvent event in all.values.toList()) {
      final String? matchId = event.matchId;
      if (matchId == null) continue;
      final bool young = at.difference(event.at) < DatingHistory.mistakeWindow;
      if (event.type == ScoreEventType.dating) {
        if (excludedFromDating.contains(matchId) ||
            (young &&
                matchById.containsKey(matchId) &&
                !datingNow.contains(matchId))) {
          _remove(event.id);
        }
      } else if (event.type == ScoreEventType.engaged) {
        if (young &&
            matchById.containsKey(matchId) &&
            !engagedAt.containsKey(matchId)) {
          _remove(event.id);
        }
      }
    }

    final List<ScoreEvent> result = all.values.toList(growable: false);
    _memoKey = key();
    _memo = result;
    return result;
  }

  /// The day each proposal became a wedding: the first ledger mark, else the
  /// proposal's own `updatedAt` (couples married before the ledger existed).
  static Map<String, DateTime> engagementDates(
    List<MatchIdea> matches,
    List<MatchStatusEvent> statusEvents,
  ) {
    final Map<String, DateTime> byMatch = <String, DateTime>{};
    for (final MatchStatusEvent event in statusEvents) {
      if (event.toStatus != MatchStatus.married) continue;
      final DateTime? seen = byMatch[event.matchId];
      if (seen == null || event.createdAt.isBefore(seen)) {
        byMatch[event.matchId] = event.createdAt;
      }
    }
    return <String, DateTime>{
      for (final MatchIdea match in matches)
        if (match.status == MatchStatus.married)
          match.id: byMatch[match.id] ?? match.updatedAt,
    };
  }

  // --- Points per friend -----------------------------------------------------

  static Map<String, List<ScoreEvent>>? _index;

  static Map<String, List<ScoreEvent>> _byKey() {
    final Map<String, List<ScoreEvent>>? cached = _index;
    if (cached != null) return cached;
    final Map<String, List<ScoreEvent>> index = <String, List<ScoreEvent>>{};
    void add(String? key, ScoreEvent event) {
      if (key == null) return;
      (index[key] ??= <ScoreEvent>[]).add(event);
    }

    for (final ScoreEvent event in _all().values) {
      if (event.isPair) {
        add(event.aKey, event);
        add(event.bKey, event);
        add(event.aId == null ? null : 'id:${event.aId}', event);
        add(event.bId == null ? null : 'id:${event.bId}', event);
      } else {
        add(event.personKey, event);
        add(event.personId == null ? null : 'id:${event.personId}', event);
        add(
          event.cardOwnerUid == null ? null : 'u:${event.cardOwnerUid}',
          event,
        );
      }
    }
    return _index = index;
  }

  /// "נקודות פעילות" one friend brought: their base (1 from the contacts, 2
  /// for a personal card) plus 1 / 5 / 50 for every idea, couple and
  /// engagement they were part of.
  ///
  /// Not a share of the matchmaker's total: an idea between two friends is one
  /// point for the matchmaker and one on each of the two cards.
  static int pointsFor(Person person) {
    final Map<String, List<ScoreEvent>> index = _byKey();
    final Set<String> seen = <String>{};
    int base = 0;
    int activity = 0;
    for (final String key in keysOf(person)) {
      for (final ScoreEvent event in index[key] ?? const <ScoreEvent>[]) {
        if (!seen.add(event.id)) continue;
        switch (event.type) {
          case ScoreEventType.card:
            base = ScoreRules.card;
          case ScoreEventType.friend:
            if (base < ScoreRules.friend) base = ScoreRules.friend;
          default:
            activity += event.points;
        }
      }
    }
    return base + activity;
  }
}
