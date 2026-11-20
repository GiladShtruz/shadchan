import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';

CardAccess _row(
  String matchmaker,
  CardAccessStatus status, {
  bool? cardGranted,
}) => CardAccess(
  ownerUid: 'owner',
  matchmakerUid: matchmaker,
  status: status,
  requestedBy: 'matchmaker',
  cardGranted: cardGranted,
);

void main() {
  group('one row per owner, out of every row the matchmaker can read', () {
    test('a pending row never hides an approval, in either order', () {
      final CardAccess approved = _row('me', CardAccessStatus.approved);
      final CardAccess pending = _row('couple-db', CardAccessStatus.pending);
      for (final List<CardAccess> rows in <List<CardAccess>>[
        <CardAccess>[approved, pending],
        <CardAccess>[pending, approved],
      ]) {
        final Map<String, CardAccess> best = CardAccessProvider.bestRowPerOwner(
          rows,
        );
        expect(best['owner']!.status, CardAccessStatus.approved);
        expect(best['owner']!.canReadCard, isTrue);
      }
    });

    test('a grant that opens the card beats one that does not', () {
      final Map<String, CardAccess> best =
          CardAccessProvider.bestRowPerOwner(<CardAccess>[
            _row('a', CardAccessStatus.approved, cardGranted: false),
            _row('b', CardAccessStatus.approved),
          ]);
      expect(best['owner']!.matchmakerUid, 'b');
    });

    test("the owner's block stands", () {
      final Map<String, CardAccess> best = CardAccessProvider.bestRowPerOwner(
        <CardAccess>[
          _row('a', CardAccessStatus.approved),
          _row('b', CardAccessStatus.blocked),
        ],
      );
      expect(best['owner']!.status, CardAccessStatus.blocked);
    });
  });
}
