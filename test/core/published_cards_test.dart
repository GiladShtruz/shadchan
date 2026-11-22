import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/account_sync_codec.dart';
import 'package:shadchan/services/published_cards.dart';

/// The phone's record of the cards it published (`networkCards`,
/// `partnerCards`), kept so a change does not read every card back from the
/// server (2026-11-22).
void main() {
  test('the record survives a round trip', () {
    final Map<String, PublishedCard> cards = <String, PublishedCard>{
      'p1': const PublishedCard(
        paths: <String>['sharedCards/u/p1/a.jpg'],
        readers: <String>['r1', 'r2'],
        valuesPrint: 'abc',
      ),
      'p2': const PublishedCard(paths: <String>[]),
    };
    final Map<String, PublishedCard>? back = PublishedCards.decode(
      PublishedCards.encode(cards),
    );
    expect(back, isNotNull);
    expect(back!['p1']!.paths, <String>['sharedCards/u/p1/a.jpg']);
    expect(back['p1']!.readers, <String>['r1', 'r2']);
    expect(back['p1']!.valuesPrint, 'abc');
    expect(back['p2']!.valuesPrint, isNull);
  });

  test('no record, an emptied record or garbage means "ask the server"', () {
    expect(PublishedCards.decode(null), isNull);
    expect(PublishedCards.decode(''), isNull);
    expect(PublishedCards.decode('not json'), isNull);
    expect(PublishedCards.decode('[1,2]'), isNull);
  });

  test('a card is unchanged only when its values print matches', () {
    const PublishedCard held = PublishedCard(
      paths: <String>[],
      valuesPrint: 'abc',
    );
    expect(held.sameValues(const <String, Object?>{}, 'abc'), isTrue);
    expect(held.sameValues(const <String, Object?>{}, 'xyz'), isFalse);
    // Values no longer known: always written again.
    expect(
      held.unknownValues().sameValues(const <String, Object?>{}, 'abc'),
      isFalse,
    );
  });

  test('a card read from the server is compared field by field', () {
    final PublishedCard held = PublishedCard.fromServer(<String, dynamic>{
      'firstName': 'יעל',
      'age': 25,
      'photoPaths': <Object?>['a.jpg'],
      'readers': <Object?>['r2', 'r1'],
    });
    expect(held.readers, <String>['r1', 'r2']);
    expect(
      held.sameValues(<String, Object?>{'firstName': 'יעל', 'age': 25}, ''),
      isTrue,
    );
    expect(
      held.sameValues(<String, Object?>{'firstName': 'יעל', 'age': 26}, ''),
      isFalse,
    );
  });

  test('the records stay on this phone', () {
    expect(AccountSyncCodec.isSyncedSetting('partner.held.uid1'), isFalse);
    expect(AccountSyncCodec.isSyncedSetting('network.held.uid1'), isFalse);
  });
}
