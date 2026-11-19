import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_duplicates.dart';

/// One person in the pool of the connected matchmakers' shared cards — which
/// may be held by more than one of them.
class SharedPoolEntry {
  SharedPoolEntry(this.cards, {required this.certain});

  /// Every shared card that is (or may be) this person, best first.
  final List<SharedCard> cards;

  /// **True when the cards are certainly one person** — the same phone or
  /// the same personal card. False when they were joined only because they
  /// look alike (name, gender, age): the entry then says which matchmakers
  /// hold *a* card like it, so the reader chooses whom to ask.
  final bool certain;

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

  /// "מהמאגר של יונתן" / "אצל יונתן ושרה" / "אצל יונתן, שרה ועוד 2".
  String get sourceLabel {
    final List<String> names = <String>[
      for (final SharedCard c in holders) c.ownerFirstName,
    ];
    if (names.length == 1) return 'מהמאגר של ${names.first}';
    if (names.length == 2) return 'אצל ${names[0]} ו${names[1]}';
    return 'אצל ${names[0]}, ${names[1]} ועוד ${names.length - 2}';
  }
}

/// **The pool of the connected matchmakers' cards, each person once.**
///
/// The same single is often in more than one friend's database. Shown three
/// times, they would read as three people, and the reader would ask three
/// matchmakers about one. So:
///
///  - **certainly the same person** — the same phone (hashed: nobody sees the
///    number) or the same personal card — one entry, one card;
///  - **probably the same person** — a name that differs by a letter or two,
///    the same gender, ages a year apart — still one entry, but marked
///    uncertain and naming every matchmaker holding such a card;
///  - **somebody already in the reader's own database** — left out: they are
///    the reader's friend already.
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
    final List<bool> rootCertain = List<bool>.filled(n, true);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    void join(int a, int b, {required bool certain}) {
      final int ra = find(a);
      final int rb = find(b);
      if (ra == rb) {
        if (!certain) rootCertain[ra] = false;
        return;
      }
      parent[rb] = ra;
      rootCertain[ra] = rootCertain[ra] && rootCertain[rb] && certain;
    }

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        final SharedCard a = pool[i];
        final SharedCard b = pool[j];
        if (sameForSure(a, b)) {
          join(i, j, certain: true);
        }
      }
    }
    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (find(i) == find(j)) continue;
        if (pool[i].ownerUid == pool[j].ownerUid) continue;
        if (looksAlike(pool[i], pool[j])) join(i, j, certain: false);
      }
    }

    final Map<int, List<SharedCard>> groups = <int, List<SharedCard>>{};
    for (int i = 0; i < n; i++) {
      groups.putIfAbsent(find(i), () => <SharedCard>[]).add(pool[i]);
    }
    final List<SharedPoolEntry> entries = <SharedPoolEntry>[
      for (final MapEntry<int, List<SharedCard>> g in groups.entries)
        SharedPoolEntry(
          g.value..sort(_richestFirst),
          certain: g.value.length == 1 || rootCertain[g.key],
        ),
    ];
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

  static int _richestFirst(SharedCard a, SharedCard b) {
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
