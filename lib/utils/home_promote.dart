import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_suggestions.dart';

/// One thing on the home screen worth coming back to, and the reason it is
/// being shown.
class HomePromoteItem {
  const HomePromoteItem.person({
    required this.person,
    required this.title,
    required this.reason,
  }) : match = null,
       personA = null,
       personB = null;

  const HomePromoteItem.idea({
    required this.match,
    required this.personA,
    required this.personB,
    required this.title,
    required this.reason,
  }) : person = null;

  final Person? person;
  final MatchIdea? match;
  final Person? personA;
  final Person? personB;

  final String title;

  /// One short sentence. Never an instruction and never invented: every line
  /// here is backed by a record — a date, a status, a note that exists.
  final String reason;

  bool get isPerson => person != null;

  /// A stable identity for the rotation, so the same item is recognised across
  /// visits.
  String get id => isPerson ? 'p:${person!.id}' : 'm:${match!.id}';
}

/// "שווה לקדם": a mixed handful of people and proposals with a reason each.
///
/// It is deliberately not a task list. There is no done button, no counter and
/// no order to work through — an item that is ignored simply comes round again
/// later, and one that is acted on stops qualifying by itself. What makes it
/// bearable to see every day is that it *changes*: the ranked list is rotated
/// by the number of visits, so the same five faces are not waiting each time.
abstract final class HomePromote {
  static const int minItems = 3;
  static const int maxItems = 5;

  /// A profile untouched for this long is worth a second look. Measured on the
  /// last real edit — never on having opened the screen, which would let simply
  /// looking at someone count as attending to them.
  static const int staleProfileDays = 90;
  static const int staleIdeaDays = 21;
  static const int newFriendDays = 14;
  static const int oldNoteDays = 120;

  static List<HomePromoteItem> build({
    required List<Person> people,
    required List<MatchIdea> matches,
    required Person? Function(String id) personById,
    List<PersonEvent> events = const <PersonEvent>[],
    List<PersonNote> notes = const <PersonNote>[],
    List<HomeActivityEntry> activity = const <HomeActivityEntry>[],
    DateTime? now,
    int rotation = 0,
    int limit = maxItems,
  }) {
    final DateTime today = now ?? DateTime.now();
    final List<Person> visible = people
        .where(
          (Person person) =>
              !person.hidden &&
              !person.needsReview &&
              !person.profileStatus.isArchived,
        )
        .toList();
    if (visible.isEmpty && matches.isEmpty) {
      return const <HomePromoteItem>[];
    }

    final Set<String> peopleWithOpenIdea = <String>{};
    for (final MatchIdea match in matches) {
      if (match.status.isArchived) {
        continue;
      }
      peopleWithOpenIdea
        ..add(match.personAId)
        ..add(match.personBId);
    }

    final Map<String, PersonNote> newestNote = <String, PersonNote>{};
    for (final PersonNote note in notes) {
      if (note.isAutomatic) {
        continue;
      }
      final PersonNote? current = newestNote[note.personId];
      if (current == null || note.createdAt.isAfter(current.createdAt)) {
        newestNote[note.personId] = note;
      }
    }

    final List<HomePromoteItem> candidates = <HomePromoteItem>[];

    // --- people ------------------------------------------------------------
    for (final Person person in visible) {
      final String name = person.fullName.trim();
      final int daysSinceAdded = today.difference(person.createdAt).inDays;
      final int daysSinceUpdated = today.difference(person.updatedAt).inDays;
      final bool hasIdea = peopleWithOpenIdea.contains(person.id);

      if (daysSinceAdded <= newFriendDays && !hasIdea) {
        candidates.add(
          HomePromoteItem.person(
            person: person,
            title: name,
            reason: 'נוסף לאחרונה ועדיין לא נפתח לו רעיון',
          ),
        );
        continue;
      }
      if (daysSinceUpdated >= staleProfileDays) {
        candidates.add(
          HomePromoteItem.person(
            person: person,
            title: name,
            reason: 'הכרטיס לא עודכן כבר ${_months(daysSinceUpdated)}',
          ),
        );
        continue;
      }
      final PersonNote? note = newestNote[person.id];
      if (note != null &&
          today.difference(note.createdAt).inDays >= oldNoteDays) {
        candidates.add(
          HomePromoteItem.person(
            person: person,
            title: name,
            reason: 'יש הערה ישנה שאולי פותחת שוב כיוון',
          ),
        );
        continue;
      }
      if (!hasIdea) {
        candidates.add(
          HomePromoteItem.person(
            person: person,
            title: name,
            reason: 'אין לו כרגע רעיון פתוח',
          ),
        );
      }
    }

    // --- proposals ---------------------------------------------------------
    for (final MatchIdea match in matches) {
      if (match.status.isArchived || match.status == MatchStatus.dating) {
        continue;
      }
      final Person? a = personById(match.personAId);
      final Person? b = personById(match.personBId);
      if (a == null || b == null) {
        continue;
      }
      final String title = '${_firstName(a)} & ${_firstName(b)}';
      final int daysSinceUpdated = today.difference(match.updatedAt).inDays;

      if (daysSinceUpdated >= staleIdeaDays) {
        candidates.add(
          HomePromoteItem.idea(
            match: match,
            personA: a,
            personB: b,
            title: title,
            reason: 'הרעיון לא עודכן כבר ${_weeks(daysSinceUpdated)}',
          ),
        );
        continue;
      }
      if (match.status == MatchStatus.idea ||
          match.status == MatchStatus.checking) {
        candidates.add(
          HomePromoteItem.idea(
            match: match,
            personA: a,
            personB: b,
            title: title,
            reason: 'הצעה פתוחה שכדאי לקדם',
          ),
        );
      }
    }

    if (candidates.isEmpty) {
      return const <HomePromoteItem>[];
    }

    // People and proposals alternate rather than clumping, so the row never
    // reads as five of the same thing.
    final List<HomePromoteItem> peopleItems = candidates
        .where((HomePromoteItem item) => item.isPerson)
        .toList();
    final List<HomePromoteItem> ideaItems = candidates
        .where((HomePromoteItem item) => !item.isPerson)
        .toList();

    final List<HomePromoteItem> ordered = <HomePromoteItem>[];
    for (int i = 0; i < candidates.length; i++) {
      final List<HomePromoteItem> source = (i.isEven || ideaItems.isEmpty)
          ? peopleItems
          : ideaItems;
      final List<HomePromoteItem> other = identical(source, peopleItems)
          ? ideaItems
          : peopleItems;
      final List<HomePromoteItem> pick = source.isNotEmpty ? source : other;
      if (pick.isEmpty) {
        break;
      }
      ordered.add(pick.removeAt(0));
    }

    // The rotation is what stops this from being the same five items forever.
    final int size = ordered.length.clamp(0, limit);
    if (size == 0) {
      return const <HomePromoteItem>[];
    }
    final int offset = ordered.isEmpty ? 0 : (rotation * size) % ordered.length;
    return <HomePromoteItem>[
      for (int i = 0; i < size; i++) ordered[(offset + i) % ordered.length],
    ];
  }

  /// The same people, but as a long continuous list rather than a row of five —
  /// what "עוצרים רגע לחשוב על שידוך?" opens onto. No session, no target, no
  /// number of people to get through: one is a fine amount.
  static List<HomeSuggestion> thinkingList({
    required List<Person> people,
    required List<MatchIdea> matches,
    List<PersonEvent> events = const <PersonEvent>[],
    List<HomeActivityEntry> activity = const <HomeActivityEntry>[],
    int limit = 40,
  }) {
    return HomeSuggestions.build(
      people: people,
      matches: matches,
      events: events,
      activity: activity,
      limit: limit,
    );
  }

  static String _months(int days) {
    final int months = days ~/ 30;
    if (months >= 12) {
      final int years = months ~/ 12;
      return years == 1 ? 'שנה' : '$years שנים';
    }
    if (months <= 1) {
      return 'חודש';
    }
    if (months == 2) {
      return 'חודשיים';
    }
    return '$months חודשים';
  }

  static String _weeks(int days) {
    final int weeks = days ~/ 7;
    if (weeks >= 8) {
      return _months(days);
    }
    if (weeks <= 1) {
      return 'שבוע';
    }
    if (weeks == 2) {
      return 'שבועיים';
    }
    return '$weeks שבועות';
  }

  static String _firstName(Person person) {
    final String first = person.firstName.trim();
    return first.isNotEmpty ? first : person.fullName.trim();
  }
}
