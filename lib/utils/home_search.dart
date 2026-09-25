import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';

/// Where on a card a piece of text was found — and so where the profile opens
/// when that result is tapped.
enum HomeSearchField {
  card('כרטיס'),
  city('מקום מגורים'),
  region('אזור'),
  note('הערה'),
  tag('תגית'),
  religiousLevel('סגנון דתי'),
  contact('איש קשר');

  const HomeSearchField(this.label);

  /// The small word beside the excerpt: where it came from.
  final String label;

  /// Which part of the profile a tap on this result opens.
  String get focus {
    switch (this) {
      case HomeSearchField.card:
        return 'card';
      case HomeSearchField.note:
        return 'notes';
      case HomeSearchField.city:
      case HomeSearchField.region:
      case HomeSearchField.tag:
      case HomeSearchField.religiousLevel:
      case HomeSearchField.contact:
        return 'details';
    }
  }
}

/// A few words around a match, with the match itself located inside them so
/// it can be drawn bold.
class SearchExcerpt {
  const SearchExcerpt({
    required this.text,
    required this.matchStart,
    required this.matchLength,
  });

  final String text;
  final int matchStart;
  final int matchLength;

  String get before => text.substring(0, matchStart);
  String get match => text.substring(matchStart, matchStart + matchLength);
  String get after => text.substring(matchStart + matchLength);
}

/// One piece of a card's text that contains the query.
class ContentHit {
  const ContentHit({
    required this.person,
    required this.field,
    required this.excerpt,
    this.noteId,
  });

  final Person person;
  final HomeSearchField field;
  final SearchExcerpt excerpt;

  /// The note it was found in, for a hit in the notes.
  final String? noteId;
}

class HomeSearchResults {
  const HomeSearchResults({required this.people, required this.content});

  /// People whose name or number matches — the top of the results.
  final List<Person> people;

  /// Everything else that matched, card by card, under its own heading.
  final List<ContentHit> content;

  bool get isEmpty => people.isEmpty && content.isEmpty;
}

/// **The home search looks through the whole database, word by word.** Not
/// only names: the card text, where they live, the notes, the tags, the
/// religious style, the go-between. "ירושלים" finds the friends whose card
/// says Jerusalem and the ones who live there; "טבע" finds every card with
/// the word in it. Plain text matching — no AI, nothing that guesses.
///
/// המאגר שלי and הרעיונות שלי keep their own, narrower searches.
abstract final class HomeSearch {
  /// How many content hits one person may contribute, so one long card full
  /// of the word does not push everybody else off the list.
  static const int hitsPerPerson = 3;

  /// Characters of context kept before and after a match.
  static const int contextBefore = 28;
  static const int contextAfter = 52;

  static HomeSearchResults run(
    String rawQuery,
    Iterable<Person> people, {
    required List<PersonNote> Function(String personId) notesFor,
  }) {
    final String query = normalize(rawQuery);
    if (query.isEmpty) {
      return const HomeSearchResults(
        people: <Person>[],
        content: <ContentHit>[],
      );
    }

    final List<Person> byName = <Person>[];
    final List<ContentHit> content = <ContentHit>[];

    final List<Person> sorted = people.where((Person p) => !p.hidden).toList()
      ..sort(
        (Person a, Person b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );

    // A number is looked for among the phones only once it is long enough to
    // mean something — "05" is half the database.
    final String digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    for (final Person person in sorted) {
      final bool phoneHit =
          digits.length >= 3 &&
          (person.phone ?? '')
              .replaceAll(RegExp(r'[^0-9]'), '')
              .contains(digits);
      if (normalize(person.fullName).contains(query) || phoneHit) {
        byName.add(person);
      }

      final List<ContentHit> hits = <ContentHit>[];
      void consider(HomeSearchField field, String? text, {String? noteId}) {
        if (hits.length >= hitsPerPerson || text == null) {
          return;
        }
        final SearchExcerpt? excerpt = excerptOf(text, query);
        if (excerpt != null) {
          hits.add(
            ContentHit(
              person: person,
              field: field,
              excerpt: excerpt,
              noteId: noteId,
            ),
          );
        }
      }

      consider(HomeSearchField.city, person.city);
      consider(HomeSearchField.region, person.region?.displayName);
      consider(HomeSearchField.card, person.description);
      consider(
        HomeSearchField.religiousLevel,
        person.religiousLevel == null ? null : person.religiousLevelLabel,
      );
      for (final String tag in person.tags) {
        consider(HomeSearchField.tag, tag);
      }
      consider(HomeSearchField.note, person.notes);
      for (final PersonNote note in notesFor(person.id)) {
        if (!note.isAutomatic) {
          consider(HomeSearchField.note, note.text, noteId: note.id);
        }
      }
      consider(HomeSearchField.contact, person.inquiryContactName);
      content.addAll(hits);
    }

    return HomeSearchResults(people: byName, content: content);
  }

  /// Lower case, niqqud dropped, runs of whitespace folded — so a query typed
  /// casually still finds a card written carefully.
  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp('[֑-ׇ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// A short excerpt of [text] around the first place [query] (already
  /// normalised) appears, or null when it does not. Cut at word boundaries,
  /// with an ellipsis wherever text was left out.
  static SearchExcerpt? excerptOf(String text, String query) {
    if (query.isEmpty) {
      return null;
    }
    // Niqqud is dropped from the text itself too, so the positions in the
    // normalised copy are the positions in what is drawn.
    final String clean = text
        .replaceAll(RegExp('[֑-ׇ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final int at = clean.toLowerCase().indexOf(query);
    if (at < 0) {
      return null;
    }

    int start = at - contextBefore;
    int end = at + query.length + contextAfter;
    bool cutStart = start > 0;
    bool cutEnd = end < clean.length;
    start = start.clamp(0, clean.length);
    end = end.clamp(0, clean.length);
    if (cutStart) {
      final int space = clean.indexOf(' ', start);
      if (space >= 0 && space < at) {
        start = space + 1;
      }
    }
    if (cutEnd) {
      final int space = clean.lastIndexOf(' ', end);
      if (space > at + query.length) {
        end = space;
      }
    }
    cutStart = start > 0;
    cutEnd = end < clean.length;

    final String lead = cutStart ? '…' : '';
    final String body = clean.substring(start, end);
    return SearchExcerpt(
      text: '$lead$body${cutEnd ? '…' : ''}',
      matchStart: lead.length + (at - start),
      matchLength: query.length,
    );
  }
}
