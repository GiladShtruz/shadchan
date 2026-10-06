import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// The shelves of "הלוח שלי" — the chips across its top.
///
/// [all] is not a kind of row: it is every kind the matchmaker has chosen to
/// see there (see [BoardAllCategories]). Every other value is one kind of row,
/// and its own chip always shows all of it, whatever "הכל" was set to.
enum BoardCategory {
  all('הכל'),
  cards('כרטיסים וגישה'),
  alerts('התראות'),
  openIdeas('רעיונות פתוחים'),
  suggestions('הצעות מהמאגר');

  const BoardCategory(this.label);

  final String label;

  /// The four that are kinds of row.
  static const List<BoardCategory> kinds = <BoardCategory>[
    cards,
    alerts,
    openIdeas,
    suggestions,
  ];

  /// What a dedicated chip says when it has nothing to show.
  String get emptyLine => switch (this) {
    all => 'הלוח ריק כרגע',
    cards => 'אין כרגע עדכונים על כרטיסים או גישה',
    alerts => 'אין התראות או תזכורות פעילות',
    openIdeas => 'אין רעיונות פתוחים',
    suggestions => 'אין כרגע הצעות חדשות מהמאגר',
  };
}

/// How much a row asks of the matchmaker, most first. Declaration order is
/// the order: it only decides between rows **close in time** — see
/// [HomeBoardFeed.arrange].
enum BoardPriority {
  /// Something only the matchmaker can do: ask for a card's access, send a
  /// greeting that is due.
  action,

  /// A reminder that came due, a notice not yet read, something pinned.
  alert,

  /// A friend's card that changed, access that was given.
  cardChange,

  /// An open proposal and its next step.
  openIdea,

  /// A pair the database suggests.
  suggestion,
}

/// One row before it is placed: what it is, what it is about, and when
/// something last happened in it.
class BoardFeedEntry<T> {
  const BoardFeedEntry({
    required this.value,
    required this.category,
    required this.priority,
    required this.activityAt,
    this.alsoIn = const <BoardCategory>{},
  });

  final T value;

  /// The shelf it belongs to — what counts for variety in "הכל".
  final BoardCategory category;

  /// Other chips it also answers to: an open proposal whose reminder came due
  /// is a reminder *and* an open proposal, drawn once in "הכל" and once in
  /// each of the two chips.
  final Set<BoardCategory> alsoIn;
  final BoardPriority priority;

  /// The last thing that happened in it — not when it was created. A status
  /// change, a reminder coming due, a card edited all bring a row back up.
  final DateTime activityAt;

  bool isIn(BoardCategory chip) =>
      chip == BoardCategory.all || chip == category || alsoIn.contains(chip);
}

/// Places the board's rows.
///
/// **Newest first, then most important — and never one kind for long.**
///
/// 1. Rows are grouped by how long ago something happened in them ([ages]):
///    today, the last three days, the week, the month, before. Within a
///    group, the row asking more of the matchmaker ([BoardPriority]) goes
///    first, and between two of the same weight the newer one. So a
///    proposal that moved this morning sits above a reminder that came due
///    last week, but a reminder that came due this morning sits above a
///    proposal that moved this morning.
/// 2. Then no shelf may run more than [maxRun] rows in a row while another
///    shelf still has something below: the next row of a different shelf is
///    pulled up to break the run. Twenty friends sharing their cards in one
///    evening cannot bury the open proposals and the reminders under them —
///    they arrive two at a time, between the other work.
///
/// Suggestions from the database break a run only when nothing of the
/// matchmaker's own is left to do it — they are what the board offers when
/// it is thin, never what interrupts it.
abstract final class HomeBoardFeed {
  /// The age groups, newest first. A row belongs to the first it fits.
  static const List<Duration> ages = <Duration>[
    Duration(days: 1),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 30),
  ];

  /// The longest stretch of one shelf before another is pulled up.
  static const int maxRun = 2;

  static int ageGroup(DateTime at, DateTime now) {
    final Duration ago = now.difference(at);
    for (int i = 0; i < ages.length; i++) {
      if (ago < ages[i]) {
        return i;
      }
    }
    return ages.length;
  }

  static List<BoardFeedEntry<T>> arrange<T>(
    Iterable<BoardFeedEntry<T>> entries, {
    required DateTime now,
  }) {
    final List<BoardFeedEntry<T>> sorted = entries.toList()
      ..sort((BoardFeedEntry<T> a, BoardFeedEntry<T> b) {
        final int byAge = ageGroup(
          a.activityAt,
          now,
        ).compareTo(ageGroup(b.activityAt, now));
        if (byAge != 0) {
          return byAge;
        }
        final int byWeight = a.priority.index.compareTo(b.priority.index);
        if (byWeight != 0) {
          return byWeight;
        }
        return b.activityAt.compareTo(a.activityAt);
      });

    final List<BoardFeedEntry<T>> out = <BoardFeedEntry<T>>[];
    final List<BoardFeedEntry<T>> rest = sorted;
    while (rest.isNotEmpty) {
      int pick = 0;
      if (_runOf(out) >= maxRun && rest.first.category == out.last.category) {
        final BoardCategory running = out.last.category;
        int breaker = rest.indexWhere(
          (BoardFeedEntry<T> e) =>
              e.category != running && e.category != BoardCategory.suggestions,
        );
        if (breaker < 0) {
          breaker = rest.indexWhere(
            (BoardFeedEntry<T> e) => e.category != running,
          );
        }
        if (breaker > 0) {
          pick = breaker;
        }
      }
      out.add(rest.removeAt(pick));
    }
    return out;
  }

  static int _runOf<T>(List<BoardFeedEntry<T>> placed) {
    if (placed.isEmpty) {
      return 0;
    }
    final BoardCategory last = placed.last.category;
    int run = 0;
    for (int i = placed.length - 1; i >= 0; i--) {
      if (placed[i].category != last) {
        break;
      }
      run++;
    }
    return run;
  }

  /// The rows a chip shows, already [arrange]d. "הכל" shows a row when any
  /// shelf it belongs to is switched on there.
  static List<BoardFeedEntry<T>> forChip<T>(
    List<BoardFeedEntry<T>> arranged,
    BoardCategory chip, {
    required Set<BoardCategory> inAll,
  }) {
    if (chip != BoardCategory.all) {
      return arranged.where((BoardFeedEntry<T> e) => e.isIn(chip)).toList();
    }
    return arranged
        .where(
          (BoardFeedEntry<T> e) =>
              inAll.contains(e.category) ||
              e.alsoIn.any((BoardCategory c) => inAll.contains(c)),
        )
        .toList();
  }
}

/// Which shelves "הכל" shows — "התאמת הלוח שלי". Every one until the
/// matchmaker says otherwise.
///
/// **Switching a shelf off only takes it out of "הכל".** Nothing is deleted,
/// no notification stops, and the shelf's own chip still shows all of it.
abstract final class BoardAllCategories {
  static const String _key = 'home.boardAllHidden';

  static String? _pending;

  static Set<BoardCategory> get shown {
    final Object? raw =
        _pending ??
        (Hive.isBoxOpen('settings')
            ? Hive.box<dynamic>('settings').get(_key)
            : null);
    final Set<String> hidden = raw is String && raw.isNotEmpty
        ? raw.split(',').toSet()
        : <String>{};
    return <BoardCategory>{
      for (final BoardCategory c in BoardCategory.kinds)
        if (!hidden.contains(c.name)) c,
    };
  }

  static set shown(Set<BoardCategory> value) {
    final String raw = <String>[
      for (final BoardCategory c in BoardCategory.kinds)
        if (!value.contains(c)) c.name,
    ].join(',');
    _pending = raw;
    persistHomeSetting(_key, raw);
  }

  static void resetForTest() => _pending = null;
}

/// When the matchmaker last opened a row from the board — what stops a row
/// they already dealt with from still looking new.
abstract final class BoardSeen {
  static const String _key = 'home.boardSeen';

  static Map<String, int>? _cache;

  static Map<String, int> get _map {
    final Map<String, int>? cached = _cache;
    if (cached != null) {
      return cached;
    }
    final Map<String, int> map = <String, int>{};
    final Object? raw = Hive.isBoxOpen('settings')
        ? Hive.box<dynamic>('settings').get(_key)
        : null;
    if (raw is String && raw.isNotEmpty) {
      for (final String pair in raw.split('|')) {
        final int at = pair.lastIndexOf('=');
        final int? millis = at < 0
            ? null
            : int.tryParse(pair.substring(at + 1));
        if (millis != null) {
          map[pair.substring(0, at)] = millis;
        }
      }
    }
    return _cache = map;
  }

  static DateTime? at(String key) {
    final int? millis = _map[key];
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Whether something happened at [activityAt] that the matchmaker has not
  /// opened since.
  static bool isNew(String key, DateTime activityAt) {
    final DateTime? seen = at(key);
    return seen == null || activityAt.isAfter(seen);
  }

  static void mark(String key, {DateTime? now}) {
    final Map<String, int> map = _map;
    map[key] = (now ?? DateTime.now()).millisecondsSinceEpoch;
    // Kept small: only the most recent marks matter.
    if (map.length > 300) {
      final List<MapEntry<String, int>> newest = map.entries.toList()
        ..sort(
          (MapEntry<String, int> a, MapEntry<String, int> b) =>
              b.value.compareTo(a.value),
        );
      map
        ..clear()
        ..addEntries(newest.take(200));
    }
    persistHomeSetting(
      _key,
      map.entries
          .map((MapEntry<String, int> e) => '${e.key}=${e.value}')
          .join('|'),
    );
  }

  static void resetForTest() => _cache = null;
}
