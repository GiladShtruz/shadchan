import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/matchmaker_connection.dart';
import 'package:shadchan/utils/known_matchmakers.dart';

const String me = 'me';

MatchmakerConnection row(
  String from,
  String to,
  MatchmakerConnectionStatus status, {
  Map<String, String> names = const <String, String>{},
  DateTime? updatedAt,
}) => MatchmakerConnection(
  id: MatchmakerConnection.idFor(from, to),
  fromUid: from,
  toUid: to,
  status: status,
  names: names,
  updatedAt: updatedAt,
);

void main() {
  final DateTime now = DateTime(2026, 11, 16, 12);

  test('one document per pair, whoever asks', () {
    expect(MatchmakerConnection.idFor('b', 'a'), 'a_b');
    expect(MatchmakerConnection.idFor('a', 'b'), 'a_b');
  });

  test('three groups: connected, requests, contacts — each person once', () {
    final KnownMatchmakerGroups groups = KnownMatchmakers.build(
      me: me,
      helpers: <CardHelper>[
        const CardHelper(uid: 'a', name: 'אבי'),
        const CardHelper(uid: 'b', name: 'בתיה'),
        const CardHelper(uid: 'c', name: 'כרמל'),
        const CardHelper(uid: 'd', name: 'דנה'),
      ],
      connections: <MatchmakerConnection>[
        row(me, 'a', MatchmakerConnectionStatus.approved),
        row('b', me, MatchmakerConnectionStatus.pending),
        row(me, 'c', MatchmakerConnectionStatus.pending),
      ],
    );
    expect(groups.connected.map((m) => m.uid), <String>['a']);
    expect(groups.connected.single.state, KnownMatchmakerState.connected);
    // Waiting for me first, then my own.
    expect(groups.requests.map((m) => m.uid), <String>['b', 'c']);
    expect(groups.requests.first.state, KnownMatchmakerState.incoming);
    expect(groups.requests.last.state, KnownMatchmakerState.outgoing);
    expect(groups.incomingCount, 1);
    expect(groups.contacts.map((m) => m.uid), <String>['d']);
    expect(groups.contacts.single.state, KnownMatchmakerState.none);
  });

  test('nobody is listed who was not already known', () {
    final KnownMatchmakerGroups groups = KnownMatchmakers.build(
      me: me,
      helpers: const <CardHelper>[],
      connections: <MatchmakerConnection>[
        // A request from somebody not in my phone: they chose to reach me.
        row(
          'x',
          me,
          MatchmakerConnectionStatus.pending,
          names: <String, String>{'x': 'יוסי'},
        ),
        // A "not now" with somebody no longer in my phone: gone.
        row('y', me, MatchmakerConnectionStatus.declined),
        row(me, 'z', MatchmakerConnectionStatus.declined),
      ],
    );
    expect(groups.requests.single.uid, 'x');
    expect(groups.requests.single.name, 'יוסי');
    expect(groups.requests.single.inContacts, isFalse);
    expect(groups.contacts, isEmpty);
  });

  test('saved in each other\'s phones lead the contacts, then activity', () {
    final KnownMatchmakerGroups groups = KnownMatchmakers.build(
      me: me,
      helpers: <CardHelper>[
        CardHelper(
          uid: 'recent',
          name: 'א',
          lastActiveAt: now.subtract(const Duration(hours: 1)),
        ),
        const CardHelper(uid: 'unknown', name: 'ב'),
        CardHelper(
          uid: 'mutual',
          name: 'ג',
          mutual: true,
          lastActiveAt: now.subtract(const Duration(days: 20)),
        ),
        CardHelper(
          uid: 'older',
          name: 'ד',
          lastActiveAt: now.subtract(const Duration(days: 3)),
        ),
      ],
      connections: const <MatchmakerConnection>[],
    );
    expect(groups.contacts.map((m) => m.uid), <String>[
      'mutual',
      'recent',
      'older',
      'unknown',
    ]);
    // Mutual is a priority, never a connection.
    expect(groups.connected, isEmpty);
    expect(groups.contacts.first.state, KnownMatchmakerState.none);
  });

  test('the name saved in my phone wins over the one they signed up with', () {
    final KnownMatchmakerGroups groups = KnownMatchmakers.build(
      me: me,
      helpers: const <CardHelper>[
        CardHelper(uid: 'a', name: 'Avi Cohen', phoneHash: 'h1'),
      ],
      connections: const <MatchmakerConnection>[],
      nameOf: (CardHelper h) => h.phoneHash == 'h1' ? 'אבי מהישיבה' : null,
    );
    expect(groups.contacts.single.name, 'אבי מהישיבה');
  });

  test('a "not now" said to me waits thirty days; one I said does not', () {
    final MatchmakerConnection toMe = row(
      me,
      'a',
      MatchmakerConnectionStatus.declined,
      updatedAt: now.subtract(const Duration(days: 3)),
    );
    expect(KnownMatchmakers.stateOf(toMe, me), KnownMatchmakerState.declined);
    expect(toMe.canAskAgain(me, now), isFalse);
    expect(toMe.canAskAgain(me, now.add(const Duration(days: 28))), isTrue);

    final MatchmakerConnection byMe = row(
      'a',
      me,
      MatchmakerConnectionStatus.declined,
      updatedAt: now,
    );
    expect(KnownMatchmakers.stateOf(byMe, me), KnownMatchmakerState.none);
    expect(byMe.canAskAgain(me, now), isTrue);
  });

  test('the details line is activity and database size, nothing typed', () {
    final KnownMatchmaker m = KnownMatchmaker(
      uid: 'a',
      name: 'אבי',
      state: KnownMatchmakerState.none,
      lastActiveAt: DateTime.now(),
      databaseCount: 40,
    );
    expect(m.detailsLine, 'פעיל היום · 40 חברים במאגר');
  });

  test('a row reads back from the server shape', () {
    final MatchmakerConnection? c = MatchmakerConnection.fromMap(
      'a_b',
      <String, dynamic>{
        'uids': <String>['a', 'b'],
        'fromUid': 'a',
        'toUid': 'b',
        'status': 'pending',
        'names': <String, Object?>{'a': ' אבי ', 'b': 'בתיה'},
      },
    );
    expect(c, isNotNull);
    expect(c!.isIncomingFor('b'), isTrue);
    expect(c.isOutgoingFor('a'), isTrue);
    expect(c.names['a'], 'אבי');
    expect(
      MatchmakerConnection.fromMap('x', <String, dynamic>{'status': 'odd'}),
      isNull,
    );
  });
}
