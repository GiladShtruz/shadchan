import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_config.dart';

/// One card of "אולי שווה לחשוב עליהם": a person plus the gentle reason they
/// came up.
class HomeSuggestion {
  const HomeSuggestion({required this.person, required this.reason});

  final Person person;
  final String reason;
}

/// Picks the people worth a second look on the home screen.
///
/// The wording is deliberately an observation and never an instruction — the
/// matchmaker decides what needs doing, the app only points at what quietly
/// slipped out of view.
abstract final class HomeSuggestions {
  static List<HomeSuggestion> build({
    required List<Person> people,
    required List<MatchIdea> matches,
    int limit = HomeConfig.worthThinkingCount,
  }) {
    final DateTime now = DateTime.now();
    final Set<String> withOpenIdea = <String>{};
    final Map<String, DateTime> lastIdeaAt = <String, DateTime>{};

    for (final MatchIdea match in matches) {
      for (final String personId in <String>[match.personAId, match.personBId]) {
        if (!match.status.isArchived) {
          withOpenIdea.add(personId);
        }
        final DateTime? previous = lastIdeaAt[personId];
        if (previous == null || match.createdAt.isAfter(previous)) {
          lastIdeaAt[personId] = match.createdAt;
        }
      }
    }

    final List<HomeSuggestion> neglected = <HomeSuggestion>[];
    final List<HomeSuggestion> justAdded = <HomeSuggestion>[];
    final List<HomeSuggestion> noIdea = <HomeSuggestion>[];
    final List<HomeSuggestion> justUpdated = <HomeSuggestion>[];

    for (final Person person in people) {
      if (!_isEligible(person)) {
        continue;
      }

      final bool hasOpenIdea = withOpenIdea.contains(person.id);
      final DateTime? lastIdea = lastIdeaAt[person.id];
      final int daysSinceLastIdea = lastIdea == null
          ? now.difference(person.createdAt).inDays
          : now.difference(lastIdea).inDays;
      final int daysSinceAdded = now.difference(person.createdAt).inDays;
      final int daysSinceUpdated = now.difference(person.updatedAt).inDays;

      if (!hasOpenIdea &&
          daysSinceLastIdea >= HomeConfig.notThoughtAboutAfterDays) {
        neglected.add(
          HomeSuggestion(person: person, reason: _notThoughtAbout(person)),
        );
      } else if (daysSinceAdded <= HomeConfig.recentlyChangedWithinDays) {
        justAdded.add(
          HomeSuggestion(person: person, reason: _recentlyAdded(person)),
        );
      } else if (!hasOpenIdea) {
        noIdea.add(
          HomeSuggestion(person: person, reason: _noOpenIdea(person)),
        );
      } else if (daysSinceUpdated <= HomeConfig.recentlyChangedWithinDays) {
        justUpdated.add(
          HomeSuggestion(person: person, reason: 'הכרטיס עודכן לאחרונה'),
        );
      }
    }

    // Longest out of sight leads, then the newest faces, then everyone without
    // an open idea, ordered by how long they have been waiting.
    neglected.sort(_byUpdatedAtAscending);
    justAdded.sort(_byCreatedAtDescending);
    noIdea.sort(_byUpdatedAtAscending);
    justUpdated.sort(_byUpdatedAtDescending);

    final List<HomeSuggestion> ordered = <HomeSuggestion>[
      ...neglected,
      ...justAdded,
      ...noIdea,
      ...justUpdated,
    ];
    return ordered.length > limit ? ordered.sublist(0, limit) : ordered;
  }

  static bool _isEligible(Person person) {
    return !person.hidden &&
        !person.needsReview &&
        !person.profileStatus.isArchived &&
        !person.profileStatus.pausesMatches &&
        person.gender != Gender.unknown;
  }

  static int _byUpdatedAtAscending(HomeSuggestion a, HomeSuggestion b) {
    return a.person.updatedAt.compareTo(b.person.updatedAt);
  }

  static int _byCreatedAtDescending(HomeSuggestion a, HomeSuggestion b) {
    return b.person.createdAt.compareTo(a.person.createdAt);
  }

  static int _byUpdatedAtDescending(HomeSuggestion a, HomeSuggestion b) {
    return b.person.updatedAt.compareTo(a.person.updatedAt);
  }

  static String _notThoughtAbout(Person person) {
    return person.gender == Gender.female
        ? 'לא חשבת עליה לאחרונה'
        : 'לא חשבת עליו לאחרונה';
  }

  static String _noOpenIdea(Person person) {
    return person.gender == Gender.female
        ? 'אין לה כרגע רעיון פתוח'
        : 'אין לו כרגע רעיון פתוח';
  }

  static String _recentlyAdded(Person person) {
    return person.gender == Gender.female
        ? 'נוספה למאגר לאחרונה'
        : 'נוסף למאגר לאחרונה';
  }
}
