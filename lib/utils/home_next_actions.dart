import 'package:flutter/material.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';

/// What kind of thing "הפעולות הבאות שלך" is asking for.
///
/// The order of the values *is* the priority order: a reminder the matchmaker
/// set themselves outranks anything the app worked out on its own, and a couple
/// who have been out for a month outranks a card that has gone quiet.
enum HomeActionKind {
  /// A reminder the matchmaker asked for has come due.
  reminderDue,

  /// A couple has been dating long enough that it is worth asking how it went.
  datingCheckIn,

  /// An open proposal nobody has moved in weeks.
  staleIdea,

  /// An older card missing fields the app has since added.
  missingDetails,

  /// A friend with no open proposal at all.
  noIdeas,

  /// A card nobody has touched in months.
  staleCard;

  IconData get icon {
    switch (this) {
      case HomeActionKind.reminderDue:
        return Icons.notifications_active_outlined;
      case HomeActionKind.datingCheckIn:
        return Icons.favorite_outline;
      case HomeActionKind.staleIdea:
        return Icons.hourglass_bottom_outlined;
      case HomeActionKind.missingDetails:
        return Icons.edit_note_outlined;
      case HomeActionKind.noIdeas:
        return Icons.person_search_outlined;
      case HomeActionKind.staleCard:
        return Icons.history_outlined;
    }
  }
}

/// One recommendation, with the reason it earned its place.
class HomeNextAction {
  const HomeNextAction._({
    required this.kind,
    required this.title,
    required this.reason,
    required this.overdueDays,
    this.person,
    this.match,
    this.personA,
    this.personB,
  });

  const HomeNextAction.person({
    required HomeActionKind kind,
    required Person person,
    required String title,
    required String reason,
    int overdueDays = 0,
  }) : this._(
         kind: kind,
         person: person,
         title: title,
         reason: reason,
         overdueDays: overdueDays,
       );

  const HomeNextAction.idea({
    required HomeActionKind kind,
    required MatchIdea match,
    required Person? personA,
    required Person? personB,
    required String title,
    required String reason,
    int overdueDays = 0,
  }) : this._(
         kind: kind,
         match: match,
         personA: personA,
         personB: personB,
         title: title,
         reason: reason,
         overdueDays: overdueDays,
       );

  final HomeActionKind kind;

  final Person? person;
  final MatchIdea? match;
  final Person? personA;
  final Person? personB;

  final String title;

  /// One short sentence. Never invented — every line is backed by a date, a
  /// status or a field that is genuinely empty.
  final String reason;

  /// How far past its moment this is. Used only to order items of the same
  /// kind, so the most overdue reminder leads the reminders.
  final int overdueDays;

  bool get isPerson => person != null;

  /// Stable identity, so the pager can be reasoned about in tests.
  String get id =>
      isPerson ? '${kind.name}:p:${person!.id}' : '${kind.name}:m:${match!.id}';
}

/// "הפעולות הבאות שלך" — what the app thinks is most worth doing right now.
///
/// Deliberately *not* the board and deliberately not chronological. The board
/// holds what the matchmaker put there by hand; this is the app's own reading of
/// the database, ranked by how much each item is asking for attention. An item
/// that is acted on stops qualifying by itself, so there is no done button and
/// nothing to dismiss.
abstract final class HomeNextActions {
  /// A couple out for about this long is worth a "how is it going?".
  static const int datingCheckInDays = 28;

  /// An open proposal nobody has moved for this long.
  static const int staleIdeaDays = 21;

  /// A card nobody has edited for this long.
  static const int staleCardDays = 120;

  /// A card added before the newer fields existed is only worth nagging about
  /// once it has settled — a friend added this morning is simply unfinished.
  static const int missingDetailsMinAgeDays = 14;

  /// How many cards the row shows at a time.
  static const int pageSize = 3;

  /// The whole ranked list. The screen pages through it three at a time.
  static List<HomeNextAction> build({
    required List<Person> people,
    required List<MatchIdea> matches,
    required Person? Function(String id) personById,
    DateTime? Function(String personId)? personReminder,
    DateTime? now,
    int limit = 30,
  }) {
    final DateTime today = now ?? DateTime.now();
    final List<HomeNextAction> found = <HomeNextAction>[];

    final List<Person> visible = people
        .where(
          (Person person) =>
              !person.hidden &&
              !person.needsReview &&
              !person.profileStatus.isArchived,
        )
        .toList();

    final Set<String> peopleWithOpenIdea = <String>{};
    for (final MatchIdea match in matches) {
      if (match.status.isArchived) {
        continue;
      }
      peopleWithOpenIdea
        ..add(match.personAId)
        ..add(match.personBId);
    }

    // --- proposals ---------------------------------------------------------
    for (final MatchIdea match in matches) {
      if (match.status.isArchived) {
        continue;
      }
      final Person? a = personById(match.personAId);
      final Person? b = personById(match.personBId);
      if (a == null || b == null) {
        continue;
      }
      final String title = '${_firstName(a)} & ${_firstName(b)}';
      final DateTime? reminder = match.reminderDate;
      final int idleDays = today.difference(match.updatedAt).inDays;

      if (reminder != null && !reminder.isAfter(today)) {
        found.add(
          HomeNextAction.idea(
            kind: HomeActionKind.reminderDue,
            match: match,
            personA: a,
            personB: b,
            title: title,
            reason: (match.reminderNote ?? '').trim().isNotEmpty
                ? 'הגיע מועד התזכורת: ${match.reminderNote!.trim()}'
                : 'הגיע מועד התזכורת שביקשת',
            overdueDays: today.difference(reminder).inDays,
          ),
        );
        continue;
      }

      if (match.status == MatchStatus.dating) {
        if (idleDays >= datingCheckInDays) {
          found.add(
            HomeNextAction.idea(
              kind: HomeActionKind.datingCheckIn,
              match: match,
              personA: a,
              personB: b,
              title: title,
              reason: 'יוצאים כבר ${_duration(idleDays)} — כדאי לבדוק מה איתם',
              overdueDays: idleDays,
            ),
          );
        }
        // A couple who are out and were updated recently need nothing.
        continue;
      }

      if (idleDays >= staleIdeaDays) {
        found.add(
          HomeNextAction.idea(
            kind: HomeActionKind.staleIdea,
            match: match,
            personA: a,
            personB: b,
            title: title,
            reason: 'הרעיון לא התקדם כבר ${_duration(idleDays)}',
            overdueDays: idleDays,
          ),
        );
      }
    }

    // --- people ------------------------------------------------------------
    for (final Person person in visible) {
      final String name = person.fullName.trim();
      final DateTime? reminder = personReminder?.call(person.id);
      if (reminder != null && !reminder.isAfter(today)) {
        found.add(
          HomeNextAction.person(
            kind: HomeActionKind.reminderDue,
            person: person,
            title: name,
            reason: 'הגיע מועד התזכורת שביקשת',
            overdueDays: today.difference(reminder).inDays,
          ),
        );
        continue;
      }

      final int ageDays = today.difference(person.createdAt).inDays;
      final int idleDays = today.difference(person.updatedAt).inDays;
      final List<String> missing = _missingBasics(person);

      if (missing.isNotEmpty && ageDays >= missingDetailsMinAgeDays) {
        found.add(
          HomeNextAction.person(
            kind: HomeActionKind.missingDetails,
            person: person,
            title: name,
            reason: 'חסר בכרטיס: ${missing.join(', ')}',
            overdueDays: ageDays,
          ),
        );
        continue;
      }

      if (!peopleWithOpenIdea.contains(person.id) &&
          person.profileStatus == ProfileStatus.available) {
        found.add(
          HomeNextAction.person(
            kind: HomeActionKind.noIdeas,
            person: person,
            title: name,
            reason: 'אין לו כרגע אף רעיון פתוח',
            overdueDays: ageDays,
          ),
        );
        continue;
      }

      if (idleDays >= staleCardDays) {
        found.add(
          HomeNextAction.person(
            kind: HomeActionKind.staleCard,
            person: person,
            title: name,
            reason: 'הכרטיס לא עודכן כבר ${_duration(idleDays)}',
            overdueDays: idleDays,
          ),
        );
      }
    }

    // Most urgent kind first; inside a kind, whatever is furthest past its
    // moment. `id` breaks the last tie so the order never wobbles between two
    // builds of the same data.
    found.sort((HomeNextAction a, HomeNextAction b) {
      final int byKind = a.kind.index.compareTo(b.kind.index);
      if (byKind != 0) {
        return byKind;
      }
      final int byOverdue = b.overdueDays.compareTo(a.overdueDays);
      return byOverdue != 0 ? byOverdue : a.id.compareTo(b.id);
    });

    return found.length > limit ? found.sublist(0, limit) : found;
  }

  /// The fields newer versions of the app ask for and an older card may never
  /// have been given. Only ever the three that change what the matching sees —
  /// a missing photo or note is nobody's business.
  static List<String> _missingBasics(Person person) {
    return <String>[
      if (person.age == null) 'גיל',
      if (person.religiousLevel == null) 'סגנון דתי',
      if (person.maritalStatus == null) 'מצב משפחתי',
      if (person.region == null) 'אזור בארץ',
    ];
  }

  static String _duration(int days) {
    if (days >= 365) {
      final int years = days ~/ 365;
      return years == 1 ? 'שנה' : '$years שנים';
    }
    if (days >= 60) {
      return '${days ~/ 30} חודשים';
    }
    if (days >= 30) {
      return 'חודש';
    }
    if (days >= 14) {
      return '${days ~/ 7} שבועות';
    }
    if (days >= 7) {
      return 'שבוע';
    }
    return '$days ימים';
  }

  static String _firstName(Person person) {
    final String first = person.firstName.trim();
    return first.isNotEmpty ? first : person.fullName.trim();
  }
}
