import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_duplicates.dart';

/// One person in the pool of the connected matchmakers' shared cards — which
/// may be held by more than one of them.
class SharedPoolEntry {
  SharedPoolEntry(this.cards, {this.similar = const <SharedCard>[]});

  /// Every shared card that is **certainly** this person — the same phone or
  /// the same personal card — best first: a single's own personal card is
  /// the source of truth and always leads, so nothing a matchmaker typed by
  /// hand about them is shown beside it.
  final List<SharedCard> cards;

  /// Cards at *other* matchmakers that only look like this person (a similar
  /// name, the same gender, close ages). **Never joined into the entry** —
  /// they are listed as sources to check, and become one only once the same
  /// phone or the same personal card proves it.
  final List<SharedCard> similar;

  /// Kept for older callers: an entry is always one person for sure now.
  bool get certain => true;

  /// The card drawn for the entry.
  SharedCard get primary => cards.first;

  /// The matchmakers who hold it, in the order of [cards], each once.
  List<SharedCard> get holders {
    final Set<String> seen = <String>{};
    return <SharedCard>[
      for (final SharedCard c in cards)
        if (seen.add(c.ownerUid)) c,
    ];
  }

  bool get heldByMany => holders.length > 1;

  /// "דרך יונתן כהן" / "דרך 3 שדכנים".
  String get sourceLabel {
    final List<SharedCard> h = holders;
    if (h.length == 1) {
      final String name = h.first.ownerName.trim();
      return 'דרך ${name.isEmpty ? h.first.ownerFirstName : name}';
    }
    return 'דרך ${h.length} שדכנים';
  }
}

/// **The pool of the connected matchmakers' cards, each person once.**
///
/// The same single is often in more than one friend's database. Shown three
/// times, they would read as three people, and the reader would ask three
/// matchmakers about one. So:
///
///  - **certainly the same person** — the same phone (hashed: nobody sees the
///    number) or the same personal card — one entry, one card, and the list
///    of matchmakers who hold it. A personal card the single keeps leads;
///  - **perhaps the same person** — a name that differs by a letter or two,
///    the same gender, ages a year apart — **not joined**: each stays its own
///    entry and points at the other as a possible match, until it is proved;
///  - **somebody already in the reader's own database** (or the reader's own
///    personal card) — left out: no duplicate in "המאגר שלי".
///
/// Pure, so the rules are tested.
abstract final class SharedPool {
  /// How far apart two ages may be and still be one person.
  static const int ageSlack = 1;

  static List<SharedPoolEntry> build(
    Iterable<SharedCard> cards, {
    Set<String> myIdentities = const <String>{},
    Set<String> myCardOwners = const <String>{},
  }) {
    final List<SharedCard> pool = <SharedCard>[
      for (final SharedCard c in cards)
        if (!(c.identity != null && myIdentities.contains(c.identity)) &&
            !(c.cardOwnerUid != null && myCardOwners.contains(c.cardOwnerUid)))
          c,
    ];
    final int n = pool.length;
    final List<int> parent = List<int>.generate(n, (int i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (sameForSure(pool[i], pool[j])) {
          final int ri = find(i);
          final int rj = find(j);
          if (ri != rj) parent[rj] = ri;
        }
      }
    }

    final Map<int, List<SharedCard>> groups = <int, List<SharedCard>>{};
    for (int i = 0; i < n; i++) {
      groups.putIfAbsent(find(i), () => <SharedCard>[]).add(pool[i]);
    }
    final List<List<SharedCard>> lists = <List<SharedCard>>[
      for (final List<SharedCard> g in groups.values) g..sort(_bestFirst),
    ];
    final List<SharedPoolEntry> entries = <SharedPoolEntry>[];
    for (final List<SharedCard> group in lists) {
      final Set<String> holders = <String>{
        for (final SharedCard c in group) c.ownerUid,
      };
      final List<SharedCard> similar = <SharedCard>[
        for (final List<SharedCard> other in lists)
          if (!identical(other, group) &&
              group.any(
                (SharedCard a) => other.any(
                  (SharedCard b) =>
                      !holders.contains(b.ownerUid) && looksAlike(a, b),
                ),
              ))
            other.first,
      ];
      entries.add(SharedPoolEntry(group, similar: similar));
    }
    entries.sort(
      (SharedPoolEntry a, SharedPoolEntry b) =>
          (b.primary.updatedAt ?? DateTime(2000)).compareTo(
            a.primary.updatedAt ?? DateTime(2000),
          ),
    );
    return entries;
  }

  /// The same phone or the same personal card.
  static bool sameForSure(SharedCard a, SharedCard b) =>
      (a.identity != null && a.identity == b.identity) ||
      (a.cardOwnerUid != null && a.cardOwnerUid == b.cardOwnerUid);

  /// A similar full name, the same gender and close ages — never two cards
  /// the same matchmaker holds (they know their own friends apart), and never
  /// two different phones.
  static bool looksAlike(SharedCard a, SharedCard b) {
    if (a.identity != null && b.identity != null && a.identity != b.identity) {
      return false;
    }
    if (a.person.gender != b.person.gender ||
        a.person.gender == Gender.unknown) {
      return false;
    }
    final int? ageA = a.person.age;
    final int? ageB = b.person.age;
    if (ageA != null && ageB != null && (ageA - ageB).abs() > ageSlack) {
      return false;
    }
    final String nameA = '${a.person.firstName} ${a.person.lastName}'.trim();
    final String nameB = '${b.person.firstName} ${b.person.lastName}'.trim();
    if (a.person.lastName.trim().isEmpty || b.person.lastName.trim().isEmpty) {
      return false;
    }
    return PersonDuplicates.isSimilarName(nameA, nameB);
  }

  /// A personal card first — it is the single's own word — then the
  /// richest card.
  static int _bestFirst(SharedCard a, SharedCard b) {
    final int own = (b.cardOwnerUid != null ? 1 : 0).compareTo(
      a.cardOwnerUid != null ? 1 : 0,
    );
    if (own != 0) return own;
    final int photos = b.photoPaths.length.compareTo(a.photoPaths.length);
    if (photos != 0) return photos;
    final int text = (b.person.description ?? '').length.compareTo(
      (a.person.description ?? '').length,
    );
    if (text != 0) return text;
    return (b.updatedAt ?? DateTime(2000)).compareTo(
      a.updatedAt ?? DateTime(2000),
    );
  }
}
