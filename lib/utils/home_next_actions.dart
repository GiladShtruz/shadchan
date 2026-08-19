import 'package:flutter/material.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

/// What kind of thing "הפעולות הבאות שלך" is asking for.
///
/// The order of the values is the priority order *within one round* of the
/// list — it is no longer the order of the list itself. A due reminder still
/// outranks everything (see [HomeNextActions.build]), but below that the kinds
/// are dealt out one at a time rather than in blocks, so the row never becomes
/// "every open proposal, and then every card nobody updated".
enum HomeActionKind {
  /// A reminder the matchmaker asked for has come due.
  reminderDue,

  /// A couple has been dating long enough that it is worth asking how it went.
  datingCheckIn,

  /// An open proposal nobody has moved in weeks.
  staleIdea,

  /// A whole week without a friend added to the database.
  addFriendNudge,

  /// A whole week without a new idea.
  newIdeaNudge,

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
      case HomeActionKind.addFriendNudge:
        return Icons.group_add_outlined;
      case HomeActionKind.newIdeaNudge:
        return Icons.lightbulb_outline;
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

  /// An action about the matchmaker's own habit rather than about one record —
  /// "כבר שבוע לא הוספת חבר למאגר". It has no person and no proposal behind it,
  /// so the card draws its kind's icon where a face would go and the screen
  /// routes it by [kind] rather than by id.
  const HomeNextAction.prompt({
    required HomeActionKind kind,
    required String title,
    required String reason,
    int overdueDays = 0,
  }) : this._(
         kind: kind,
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

  /// True for the habit prompts, which have no record to open.
  bool get isPrompt => person == null && match == null;

  /// Stable identity, so the row can be reasoned about in tests.
  String get id {
    if (person != null) {
      return '${kind.name}:p:${person!.id}';
    }
    if (match != null) {
      return '${kind.name}:m:${match!.id}';
    }
    return '${kind.name}:prompt';
  }
}

/// "הפעולות הבאות שלך" — what the app thinks is most worth doing right now.
///
/// Deliberately *not* the board and deliberately not chronological. The board
/// holds what the matchmaker put there by hand; this is the app's own reading of
/// the database. An item that is acted on stops qualifying by itself, so there
/// is no done button and nothing to dismiss.
///
/// **The list is mixed, not grouped.** Due reminders lead, all of them, because
/// they are the only items carrying a date the matchmaker chose themselves.
/// Everything under them is dealt out one kind at a time — a stale idea, then a
/// nudge, then a card missing a field, then a friend with no idea, and round
/// again. Sorting purely by kind produced a row that opened with every open
/// proposal and only reached the people much later, which reads as two separate
/// lists glued together and means the second one is never seen.
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

  /// How long a quiet stretch has to be before the app mentions it.
  static const int quietStretchDays = 7;

  /// The whole ranked list. The screen scrolls through it horizontally.
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
            reason: 'אין {לו|לה} כרגע אף רעיון פתוח'.forPerson(person),
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

    found.addAll(_quietStretchPrompts(visible, matches, today));

    // Inside one kind: whatever is furthest past its moment, with `id` breaking
    // the last tie so the order never wobbles between two builds of the same
    // data.
    found.sort((HomeNextAction a, HomeNextAction b) {
      final int byKind = a.kind.index.compareTo(b.kind.index);
      if (byKind != 0) {
        return byKind;
      }
      final int byOverdue = b.overdueDays.compareTo(a.overdueDays);
      return byOverdue != 0 ? byOverdue : a.id.compareTo(b.id);
    });

    final List<HomeNextAction> ranked = _mix(found);
    return ranked.length > limit ? ranked.sublist(0, limit) : ranked;
  }

  /// The two habit prompts: a week with no friend added, a week with no idea.
  ///
  /// Neither is offered to a database that has not started yet — telling
  /// somebody with no friends that they have not added one in a week is not a
  /// nudge, it is a scolding for not having used the app. The friends prompt
  /// waits for a first friend and the ideas prompt for a second, which is the
  /// point at which an idea is possible at all.
  static List<HomeNextAction> _quietStretchPrompts(
    List<Person> people,
    List<MatchIdea> matches,
    DateTime today,
  ) {
    final List<HomeNextAction> prompts = <HomeNextAction>[];

    DateTime? latest(Iterable<DateTime> dates) {
      DateTime? newest;
      for (final DateTime date in dates) {
        if (newest == null || date.isAfter(newest)) {
          newest = date;
        }
      }
      return newest;
    }

    if (people.isNotEmpty) {
      final DateTime? lastAdded = latest(
        people.map((Person person) => person.createdAt),
      );
      final int quiet = lastAdded == null
          ? quietStretchDays
          : today.difference(lastAdded).inDays;
      if (quiet >= quietStretchDays) {
        prompts.add(
          HomeNextAction.prompt(
            kind: HomeActionKind.addFriendNudge,
            title: 'הוספת חבר',
            reason: 'כבר שבוע לא הוספת חבר למאגר',
            overdueDays: quiet,
          ),
        );
      }
    }

    if (people.length >= 2) {
      final DateTime? lastIdea = latest(
        matches.map((MatchIdea match) => match.createdAt),
      );
      final int quiet = lastIdea == null
          ? quietStretchDays
          : today.difference(lastIdea).inDays;
      if (quiet >= quietStretchDays) {
        prompts.add(
          HomeNextAction.prompt(
            kind: HomeActionKind.newIdeaNudge,
            title: 'רעיון חדש',
            reason: 'כבר שבוע לא חשבת על רעיון חדש',
            overdueDays: quiet,
          ),
        );
      }
    }

    return prompts;
  }

  /// Due reminders first, then one of each remaining kind per round.
  ///
  /// [sorted] must already be ordered by kind and then by urgency, which is what
  /// makes the round-robin deal the most pressing item of each kind first.
  static List<HomeNextAction> _mix(List<HomeNextAction> sorted) {
    final List<HomeNextAction> reminders = <HomeNextAction>[];
    final Map<HomeActionKind, List<HomeNextAction>> buckets =
        <HomeActionKind, List<HomeNextAction>>{};

    for (final HomeNextAction action in sorted) {
      if (action.kind == HomeActionKind.reminderDue) {
        reminders.add(action);
        continue;
      }
      buckets.putIfAbsent(action.kind, () => <HomeNextAction>[]).add(action);
    }

    final List<HomeNextAction> mixed = <HomeNextAction>[...reminders];
    int taken = 0;
    while (taken < buckets.length) {
      taken = 0;
      for (final HomeActionKind kind in HomeActionKind.values) {
        final List<HomeNextAction>? bucket = buckets[kind];
        if (bucket == null) {
          continue;
        }
        if (bucket.isEmpty) {
          taken++;
          continue;
        }
        mixed.add(bucket.removeAt(0));
      }
    }

    return mixed;
  }

  /// The fields newer versions of the app ask for and an older card may never
  /// have been given.
  ///
  /// Deliberately only two. A missing marital status or region is *not* a
  /// reason to ask anyone for an update — plenty of perfectly usable cards
  /// never carry either, and asking for them turned the row into a list of
  /// every card in the database. Age and religious style are different: the
  /// matching is built on them, so a card without them cannot be suggested at
  /// all.
  static List<String> _missingBasics(Person person) {
    return <String>[
      if (person.age == null) 'גיל',
      if (person.religiousLevel == null) 'סגנון דתי',
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
