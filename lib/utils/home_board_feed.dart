import 'dart:math' as math;

/// What kind of thing a row on "הלוח שלי" is, in the order the board cares
/// about them.
///
/// Declaration order *is* the priority: a reminder that just came due outranks
/// an open proposal, which outranks something pinned a while ago, which
/// outranks a reminder that has been overdue for weeks. The last two are not
/// the matchmaker's own work at all — they are what the app offers when the
/// board would otherwise be thin.
enum BoardFeedKind {
  freshReminder(4.0),
  openIdea(3.0),
  pinned(2.0),
  oldReminder(1.0),
  suggestedIdea(0.4),
  thinkAbout(0.3);

  const BoardFeedKind(this.weight);

  /// Where the first item of this kind starts in the mix. See
  /// [HomeBoardFeed.mix].
  final double weight;

  /// Offered by the app rather than put there by the matchmaker.
  bool get isFiller =>
      this == BoardFeedKind.suggestedIdea || this == BoardFeedKind.thinkAbout;
}

/// One row of the mixed board, with the kind it was dealt from.
class BoardFeedItem<T> {
  const BoardFeedItem(this.kind, this.value);

  final BoardFeedKind kind;
  final T value;
}

/// Deals the board's sources into one feed.
///
/// **One feed, not four shelves.** The board used to be every due reminder,
/// then every pinned note, then every open proposal — which on a busy day is
/// twelve reminders before the first proposal, and reads as a report rather
/// than a desk. So each source keeps its own ranking, and the sources are
/// interleaved: every item scores its kind's [BoardFeedKind.weight], less a
/// step for each item of its kind ahead of it, plus a little seeded jitter;
/// the best head is dealt next, **never the same kind twice in a row** while
/// another kind is left. The priorities still show — a fresh reminder is
/// almost always first — but a second reminder waits behind an open proposal.
///
/// **Different every day, stable within one.** The jitter comes from [seed],
/// which the home screen derives from the date and from a tap on the
/// wordmark; the board does not reshuffle under the matchmaker's finger every
/// time a reminder ticks over, and does not greet them in the same order every
/// morning either.
abstract final class HomeBoardFeed {
  /// How far each item falls behind the one of its own kind ahead of it.
  static const double step = 0.9;

  /// The most the seed can move an item. Below [step], so the order *within*
  /// a kind is never disturbed — only how the kinds meet.
  static const double jitter = 0.6;

  /// The board aims for at least this many rows; the app's own suggestions
  /// only fill up to here.
  static const int target = 10;

  static List<BoardFeedItem<T>> mix<T>(
    Map<BoardFeedKind, List<T>> queues, {
    required int seed,
  }) {
    final math.Random random = math.Random(seed);
    final Map<BoardFeedKind, List<double>> scores =
        <BoardFeedKind, List<double>>{};
    final Map<BoardFeedKind, int> heads = <BoardFeedKind, int>{};
    int total = 0;
    for (final BoardFeedKind kind in BoardFeedKind.values) {
      final List<T> queue = queues[kind] ?? <T>[];
      scores[kind] = <double>[
        for (int i = 0; i < queue.length; i++)
          kind.weight - step * i + random.nextDouble() * jitter,
      ];
      heads[kind] = 0;
      total += queue.length;
    }

    final List<BoardFeedItem<T>> out = <BoardFeedItem<T>>[];
    BoardFeedKind? previous;
    while (out.length < total) {
      BoardFeedKind? best;
      BoardFeedKind? bestAny;
      for (final BoardFeedKind kind in BoardFeedKind.values) {
        final int head = heads[kind]!;
        if (head >= scores[kind]!.length) {
          continue;
        }
        final double score = scores[kind]![head];
        if (bestAny == null || score > scores[bestAny]![heads[bestAny]!]) {
          bestAny = kind;
        }
        if (kind != previous &&
            (best == null || score > scores[best]![heads[best]!])) {
          best = kind;
        }
      }
      final BoardFeedKind pick = best ?? bestAny!;
      out.add(BoardFeedItem<T>(pick, queues[pick]![heads[pick]!]));
      heads[pick] = heads[pick]! + 1;
      previous = pick;
    }
    return out;
  }

  /// How many filler rows the board may take, given how many rows the
  /// matchmaker's own work already fills.
  static int fillerRoom(int ownRows) => math.max(0, target - ownRows);

  /// Takes up to [room] fillers alternately from [a] and [b], so a thin board
  /// is topped up with both kinds rather than with whichever came first.
  static (List<A>, List<B>) splitFillers<A, B>(List<A> a, List<B> b, int room) {
    final List<A> takeA = <A>[];
    final List<B> takeB = <B>[];
    int ia = 0;
    int ib = 0;
    while (takeA.length + takeB.length < room &&
        (ia < a.length || ib < b.length)) {
      final bool turnA = (takeA.length + takeB.length).isEven;
      if ((turnA && ia < a.length) || ib >= b.length) {
        takeA.add(a[ia++]);
      } else {
        takeB.add(b[ib++]);
      }
    }
    return (takeA, takeB);
  }

  /// A seed that changes once a day and whenever [refresh] does.
  static int seedFor(DateTime now, int refresh) {
    final int day = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(2024)).inDays;
    return day * 7919 + refresh;
  }
}
