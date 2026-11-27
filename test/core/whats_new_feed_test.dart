import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/whats_new_feed.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 27, 12);

  WhatsNewEvent e(
    String key,
    WhatsNewSide side, {
    Duration ago = const Duration(hours: 1),
    String text = 'משהו',
  }) => WhatsNewEvent(
    key: key,
    kind: WhatsNewKind.news,
    side: side,
    text: text,
    at: now.subtract(ago),
  );

  group('WhatsNewFeed.build', () {
    final List<WhatsNewEvent> events = <WhatsNewEvent>[
      e('mm', WhatsNewSide.matchmaker, ago: const Duration(hours: 3)),
      e('me', WhatsNewSide.personal, ago: const Duration(hours: 2)),
      e('both', WhatsNewSide.both, ago: const Duration(hours: 1)),
    ];

    List<String> keys(List<WhatsNewEvent> l) =>
        l.map((WhatsNewEvent x) => x.key).toList();

    test('a matchmaker only sees matchmaking', () {
      expect(
        keys(
          WhatsNewFeed.build(events, single: false, matchmaker: true, now: now),
        ),
        <String>['both', 'mm'],
      );
    });

    test('a single only sees their own side', () {
      expect(
        keys(
          WhatsNewFeed.build(events, single: true, matchmaker: false, now: now),
        ),
        <String>['both', 'me'],
      );
    });

    test('both: one mixed feed, newest first', () {
      expect(
        keys(
          WhatsNewFeed.build(events, single: true, matchmaker: true, now: now),
        ),
        <String>['both', 'me', 'mm'],
      );
    });

    test('old, future and empty events are left out; one line per key', () {
      final List<WhatsNewEvent> feed = WhatsNewFeed.build(
        <WhatsNewEvent>[
          e('old', WhatsNewSide.both, ago: const Duration(days: 20)),
          e('future', WhatsNewSide.both, ago: const Duration(hours: -2)),
          e('blank', WhatsNewSide.both, text: '  '),
          e('dup', WhatsNewSide.both, ago: const Duration(hours: 5)),
          e('dup', WhatsNewSide.both, ago: const Duration(hours: 1)),
        ],
        single: true,
        matchmaker: true,
        now: now,
      );
      expect(keys(feed), <String>['dup']);
      expect(feed.single.at, now.subtract(const Duration(hours: 1)));
    });

    test('capped', () {
      final List<WhatsNewEvent> many = <WhatsNewEvent>[
        for (int i = 0; i < 40; i++)
          e('k$i', WhatsNewSide.both, ago: Duration(minutes: i + 1)),
      ];
      expect(
        WhatsNewFeed.build(many, single: true, matchmaker: true, now: now),
        hasLength(WhatsNewFeed.maxLines),
      );
    });
  });

  group('ideas opened', () {
    test('today only', () {
      final WhatsNewEvent? line = WhatsNewFeed.ideasOpened(<DateTime>[
        now.subtract(const Duration(hours: 1)),
        now.subtract(const Duration(hours: 2)),
        now.subtract(const Duration(hours: 3)),
      ], now: now);
      expect(line?.text, 'פתחת היום 3 רעיונות');
    });

    test('today and earlier this week', () {
      final WhatsNewEvent? line = WhatsNewFeed.ideasOpened(<DateTime>[
        now.subtract(const Duration(hours: 1)),
        now.subtract(const Duration(days: 2)),
        now.subtract(const Duration(days: 3)),
      ], now: now);
      expect(line?.text, 'פתחת היום רעיון אחד · 3 השבוע');
    });

    test('nothing lately: no line', () {
      expect(
        WhatsNewFeed.ideasOpened(<DateTime>[
          now.subtract(const Duration(days: 30)),
        ], now: now),
        isNull,
      );
    });
  });
}
