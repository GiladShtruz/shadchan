import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';

/// Why a person came up in "חברים ששווה לחשוב עליהם".
///
/// Declaration order *is* the priority order: when several reasons hold for the
/// same person, the first one wins. It follows the product order — someone who
/// just became available, then a person the database found candidates for, then
/// a newcomer, then a card that changed, then people with no proposal, a
/// proposal that just closed, a long silence, and only last the open proposals.
enum HomeSuggestionReason {
  returnedToAvailable,
  matchesFound,
  newInDatabase,
  detailsAdded,
  cardUpdated,
  noIdeaYet,
  lastIdeaClosed,
  cardReady,
  notThoughtAbout,
  cardNotUpdated,
  openIdeasWaiting,
  severalOpenIdeas,
  oneOpenIdea,
  worthAThought;

  /// Whether the row should lead with the most recent of these (news) or with
  /// the oldest (neglect).
  bool get newestFirst {
    switch (this) {
      case HomeSuggestionReason.returnedToAvailable:
      case HomeSuggestionReason.matchesFound:
      case HomeSuggestionReason.newInDatabase:
      case HomeSuggestionReason.detailsAdded:
      case HomeSuggestionReason.cardUpdated:
      case HomeSuggestionReason.lastIdeaClosed:
        return true;
      case HomeSuggestionReason.noIdeaYet:
      case HomeSuggestionReason.cardReady:
      case HomeSuggestionReason.notThoughtAbout:
      case HomeSuggestionReason.cardNotUpdated:
      case HomeSuggestionReason.openIdeasWaiting:
      case HomeSuggestionReason.severalOpenIdeas:
      case HomeSuggestionReason.oneOpenIdea:
      case HomeSuggestionReason.worthAThought:
        return false;
    }
  }
}

/// One entry of "חברים ששווה לחשוב עליהם": a person, why they came up, and the
/// single sentence shown under their name.
class HomeSuggestion {
  const HomeSuggestion({
    required this.person,
    required this.kind,
    required this.reason,
  });

  final Person person;
  final HomeSuggestionReason kind;

  /// The one line under the name. Always phrased from a real record — nothing
  /// here is generated when the underlying fact does not exist.
  final String reason;
}

/// Picks the people worth a second look on the home screen.
///
/// The wording is deliberately an observation and never an instruction — the
/// matchmaker decides what needs doing, the app only points at what quietly
/// slipped out of view. Every sentence is backed by a record: a status change
/// that was logged, a card that really was edited, proposals that really are
/// open. When nothing specific is true, the person still gets the neutral
/// "אולי דווקא עכשיו יעלה לך הרעיון הנכון" rather than an invented fact.
abstract final class HomeSuggestions {
  static List<HomeSuggestion> build({
    required List<Person> people,
    required List<MatchIdea> matches,
    List<PersonEvent> events = const <PersonEvent>[],
    List<HomeActivityEntry> activity = const <HomeActivityEntry>[],
    int limit = HomeConfig.worthThinkingCount,
  }) {
    final DateTime now = DateTime.now();
    final List<Person> eligible = people.where(_isEligible).toList();
    if (eligible.isEmpty) {
      return const <HomeSuggestion>[];
    }

    final _MatchFacts facts = _MatchFacts.from(matches);
    final Map<String, DateTime> lastDetailsEdit = _lastDetailsEdit(activity);
    final Map<String, List<PersonEvent>> statusEvents = _statusEvents(events);
    final bool canScanPairs = people.length <= HomeConfig.matchScanMaxPeople;

    final List<HomeSuggestion> suggestions = <HomeSuggestion>[];
    for (final Person person in eligible) {
      final int openIdeas = facts.openIdeaCount(person.id);
      // Only someone with nothing in play is worth counting candidates for —
      // which also keeps the pairwise scan off the people who need it least.
      final int candidateCount = canScanPairs && openIdeas == 0
          ? _candidateCount(person, eligible, facts)
          : 0;
      final HomeSuggestionReason kind = _reasonFor(
        person: person,
        now: now,
        facts: facts,
        statusEvents: statusEvents[person.id] ?? const <PersonEvent>[],
        lastDetailsEdit: lastDetailsEdit[person.id],
        candidateCount: candidateCount,
      );
      suggestions.add(
        HomeSuggestion(
          person: person,
          kind: kind,
          reason: _sentence(
            kind,
            person,
            count: kind == HomeSuggestionReason.matchesFound
                ? candidateCount
                : openIdeas,
          ),
        ),
      );
    }

    suggestions.sort(_byPriorityThenTime);
    return suggestions.length > limit
        ? suggestions.sublist(0, limit)
        : suggestions;
  }

  // --- Which sentence applies ------------------------------------------------

  static HomeSuggestionReason _reasonFor({
    required Person person,
    required DateTime now,
    required _MatchFacts facts,
    required List<PersonEvent> statusEvents,
    required DateTime? lastDetailsEdit,
    required int candidateCount,
  }) {
    final int openIdeas = facts.openIdeaCount(person.id);
    final bool hasOpenIdea = openIdeas > 0;
    final int daysSinceAdded = now.difference(person.createdAt).inDays;
    final int daysSinceUpdated = now.difference(person.updatedAt).inDays;

    if (_justBecameAvailable(person, statusEvents, now)) {
      return HomeSuggestionReason.returnedToAvailable;
    }
    if (!hasOpenIdea &&
        candidateCount >= HomeConfig.matchesFoundMinCandidates) {
      return HomeSuggestionReason.matchesFound;
    }
    if (daysSinceAdded <= HomeConfig.recentlyChangedWithinDays) {
      return HomeSuggestionReason.newInDatabase;
    }
    if (lastDetailsEdit != null &&
        now.difference(lastDetailsEdit).inDays <=
            HomeConfig.recentlyChangedWithinDays) {
      return HomeSuggestionReason.detailsAdded;
    }
    if (daysSinceUpdated <= HomeConfig.recentlyChangedWithinDays) {
      return HomeSuggestionReason.cardUpdated;
    }
    if (!facts.hasAnyIdea(person.id)) {
      return HomeSuggestionReason.noIdeaYet;
    }

    final DateTime? closedAt = facts.lastClosedIdeaAt(person.id);
    if (!hasOpenIdea &&
        closedAt != null &&
        now.difference(closedAt).inDays <= HomeConfig.ideaClosedWithinDays) {
      return HomeSuggestionReason.lastIdeaClosed;
    }
    if (!hasOpenIdea && _cardIsComplete(person)) {
      return HomeSuggestionReason.cardReady;
    }

    final DateTime? lastIdeaAt = facts.lastIdeaAt(person.id);
    if (!hasOpenIdea &&
        lastIdeaAt != null &&
        now.difference(lastIdeaAt).inDays >=
            HomeConfig.notThoughtAboutAfterDays) {
      return HomeSuggestionReason.notThoughtAbout;
    }
    if (daysSinceUpdated >= HomeConfig.cardNotUpdatedAfterDays) {
      return HomeSuggestionReason.cardNotUpdated;
    }

    if (hasOpenIdea) {
      final DateTime? movedAt = facts.lastOpenIdeaUpdateAt(person.id);
      if (movedAt != null &&
          now.difference(movedAt).inDays >= HomeConfig.openIdeaStaleAfterDays) {
        return HomeSuggestionReason.openIdeasWaiting;
      }
      return openIdeas > 1
          ? HomeSuggestionReason.severalOpenIdeas
          : HomeSuggestionReason.oneOpenIdea;
    }

    return HomeSuggestionReason.worthAThought;
  }

  /// True when the person's own status log shows them coming back from
  /// תפוס / בהפסקה to פנוי. Read from the logged status events only — a person
  /// who simply happens to be available has no such line.
  static bool _justBecameAvailable(
    Person person,
    List<PersonEvent> statusEvents,
    DateTime now,
  ) {
    if (person.profileStatus != ProfileStatus.available ||
        statusEvents.isEmpty) {
      return false;
    }

    final PersonEvent latest = statusEvents.first;
    if (_statusOf(latest) != ProfileStatus.available) {
      return false;
    }
    if (now.difference(latest.createdAt).inDays >
        HomeConfig.recentlyChangedWithinDays) {
      return false;
    }
    if (statusEvents.length == 1) {
      // The only logged change is the one that made them available again: they
      // were not available before it, or it would not have been recorded.
      return true;
    }
    final ProfileStatus? previous = _statusOf(statusEvents[1]);
    return previous == ProfileStatus.busy || previous == ProfileStatus.onBreak;
  }

  /// The status a logged event moved a person to, recovered from the sentence
  /// [PersonRepository.updateProfileStatus] writes.
  static ProfileStatus? _statusOf(PersonEvent event) {
    for (final ProfileStatus status in ProfileStatus.values) {
      if (event.text.trim().endsWith(status.displayName)) {
        return status;
      }
    }
    return null;
  }

  /// A card with enough on it to propose from.
  static bool _cardIsComplete(Person person) {
    return person.age != null &&
        person.religiousLevel != null &&
        (person.description ?? '').trim().isNotEmpty &&
        person.photosPaths.isNotEmpty;
  }

  /// How many people in the database fit [person] and were never proposed to
  /// them. Only ever called on small enough databases — see
  /// [HomeConfig.matchScanMaxPeople].
  static int _candidateCount(
    Person person,
    List<Person> pool,
    _MatchFacts facts,
  ) {
    int count = 0;
    for (final Person candidate in pool) {
      if (candidate.id == person.id) {
        continue;
      }
      if (facts.hasPair(person.id, candidate.id)) {
        continue;
      }
      if (MatchSuggestionUtils.isSuggestedCandidate(
        source: person,
        candidate: candidate,
      )) {
        count++;
      }
    }
    return count;
  }

  // --- Wording ---------------------------------------------------------------

  static String _sentence(
    HomeSuggestionReason kind,
    Person person, {
    int count = 0,
  }) {
    final bool female = person.gender == Gender.female;

    switch (kind) {
      case HomeSuggestionReason.returnedToAvailable:
        return female
            ? 'חזרה להיות פנויה — שווה לחשוב עליה מחדש'
            : 'חזר להיות פנוי — שווה לחשוב עליו מחדש';
      case HomeSuggestionReason.matchesFound:
        return female
            ? 'יש במאגר $count אנשים שעשויים להתאים לה'
            : 'יש במאגר $count אנשים שעשויים להתאים לו';
      case HomeSuggestionReason.newInDatabase:
        return female
            ? 'חדשה במאגר — שווה להתחיל לחשוב עליה'
            : 'חדש במאגר — שווה להתחיל לחשוב עליו';
      case HomeSuggestionReason.detailsAdded:
        return 'נוספו פרטים חדשים — אולי הם יפתחו כיוון מתאים';
      case HomeSuggestionReason.cardUpdated:
        return female
            ? 'הכרטיס שלה עודכן — שווה להסתכל עליו מחדש'
            : 'הכרטיס שלו עודכן — שווה להסתכל עליו מחדש';
      case HomeSuggestionReason.noIdeaYet:
        return female
            ? 'עוד לא נפתח לה רעיון — אולי זה הזמן'
            : 'עוד לא נפתח לו רעיון — אולי זה הזמן';
      case HomeSuggestionReason.lastIdeaClosed:
        return 'הרעיון האחרון נסגר — אולי מתאים עכשיו כיוון חדש';
      case HomeSuggestionReason.cardReady:
        return female
            ? 'הכרטיס שלה מוכן — נשאר רק למצוא את החיבור'
            : 'הכרטיס שלו מוכן — נשאר רק למצוא את החיבור';
      case HomeSuggestionReason.notThoughtAbout:
        return female
            ? 'לא חשבת עליה לאחרונה — אולי הגיע הזמן לכיוון חדש'
            : 'לא חשבת עליו לאחרונה — אולי הגיע הזמן לכיוון חדש';
      case HomeSuggestionReason.cardNotUpdated:
        return female
            ? 'הכרטיס שלה לא עודכן לאחרונה — שווה לבדוק מה חדש'
            : 'הכרטיס שלו לא עודכן לאחרונה — שווה לבדוק מה חדש';
      case HomeSuggestionReason.openIdeasWaiting:
        return female
            ? 'הרעיונות שלה מחכים לעדכון — אולי הגיע הזמן לקדם'
            : 'הרעיונות שלו מחכים לעדכון — אולי הגיע הזמן לקדם';
      case HomeSuggestionReason.severalOpenIdeas:
        return female
            ? 'יש לה כבר $count רעיונות פתוחים — שווה לבדוק מה מתקדם'
            : 'יש לו כבר $count רעיונות פתוחים — שווה לבדוק מה מתקדם';
      case HomeSuggestionReason.oneOpenIdea:
        return female
            ? 'יש לה רעיון פתוח — שווה לבדוק אם אפשר לקדם אותו'
            : 'יש לו רעיון פתוח — שווה לבדוק אם אפשר לקדם אותו';
      case HomeSuggestionReason.worthAThought:
        return 'אולי דווקא עכשיו יעלה לך הרעיון הנכון';
    }
  }

  // --- Plumbing --------------------------------------------------------------

  static bool _isEligible(Person person) {
    return !person.hidden &&
        !person.needsReview &&
        !person.profileStatus.isArchived &&
        !person.profileStatus.pausesMatches &&
        person.gender != Gender.unknown;
  }

  static int _byPriorityThenTime(HomeSuggestion a, HomeSuggestion b) {
    final int byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) {
      return byKind;
    }
    return a.kind.newestFirst
        ? b.person.updatedAt.compareTo(a.person.updatedAt)
        : a.person.updatedAt.compareTo(b.person.updatedAt);
  }

  /// When each person's details were last edited by hand, from the activity
  /// trail the repositories already record.
  static Map<String, DateTime> _lastDetailsEdit(
    List<HomeActivityEntry> activity,
  ) {
    final Map<String, DateTime> result = <String, DateTime>{};
    for (final HomeActivityEntry entry in activity) {
      if (entry.kind != HomeItemKind.person ||
          entry.action != HomeActivityAction.editedDetails) {
        continue;
      }
      final DateTime? current = result[entry.targetId];
      if (current == null || entry.at.isAfter(current)) {
        result[entry.targetId] = entry.at;
      }
    }
    return result;
  }

  /// Status-change events per person, newest first.
  static Map<String, List<PersonEvent>> _statusEvents(
    List<PersonEvent> events,
  ) {
    final Map<String, List<PersonEvent>> result = <String, List<PersonEvent>>{};
    for (final PersonEvent event in events) {
      if (event.type != PersonEventType.statusChanged) {
        continue;
      }
      result.putIfAbsent(event.personId, () => <PersonEvent>[]).add(event);
    }
    for (final List<PersonEvent> list in result.values) {
      list.sort((PersonEvent a, PersonEvent b) {
        return b.createdAt.compareTo(a.createdAt);
      });
    }
    return result;
  }
}

/// Everything the reasons need to know about a person's proposals, gathered in
/// one pass so the row stays cheap to rebuild.
class _MatchFacts {
  _MatchFacts._();

  final Map<String, int> _open = <String, int>{};
  final Map<String, DateTime> _lastIdea = <String, DateTime>{};
  final Map<String, DateTime> _lastOpenUpdate = <String, DateTime>{};
  final Map<String, DateTime> _lastClosed = <String, DateTime>{};
  final Set<String> _pairs = <String>{};

  static _MatchFacts from(List<MatchIdea> matches) {
    final _MatchFacts facts = _MatchFacts._();
    for (final MatchIdea match in matches) {
      facts._pairs.add(_pairKey(match.personAId, match.personBId));
      for (final String id in <String>[match.personAId, match.personBId]) {
        facts._keepLatest(facts._lastIdea, id, match.createdAt);
        if (match.status.isArchived) {
          if (match.status != MatchStatus.married) {
            facts._keepLatest(facts._lastClosed, id, match.updatedAt);
          }
          continue;
        }
        facts._open[id] = (facts._open[id] ?? 0) + 1;
        facts._keepLatest(facts._lastOpenUpdate, id, match.updatedAt);
      }
    }
    return facts;
  }

  int openIdeaCount(String personId) => _open[personId] ?? 0;

  bool hasAnyIdea(String personId) => _lastIdea.containsKey(personId);

  DateTime? lastIdeaAt(String personId) => _lastIdea[personId];

  DateTime? lastOpenIdeaUpdateAt(String personId) => _lastOpenUpdate[personId];

  DateTime? lastClosedIdeaAt(String personId) => _lastClosed[personId];

  bool hasPair(String a, String b) => _pairs.contains(_pairKey(a, b));

  void _keepLatest(Map<String, DateTime> into, String id, DateTime at) {
    final DateTime? current = into[id];
    if (current == null || at.isAfter(current)) {
      into[id] = at;
    }
  }

  static String _pairKey(String a, String b) {
    return a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
  }
}
