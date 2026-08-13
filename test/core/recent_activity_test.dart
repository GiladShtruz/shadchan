import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';

void main() {
  HomeActivityEntry entry(HomeItemKind kind, HomeActivityAction action) {
    return HomeActivityEntry(
      kind: kind,
      targetId: 'id',
      action: action,
      at: DateTime(2026, 8, 2),
    );
  }

  test('opening a card is not a performed recent action', () {
    expect(HomeActivityAction.openedPerson.isPerformedAction, isFalse);
    expect(HomeActivityAction.openedIdea.isPerformedAction, isFalse);
  });

  test('recent action wording describes the actual change', () {
    expect(
      entry(HomeItemKind.person, HomeActivityAction.createdPerson).label,
      'הוספת כרטיס',
    );
    expect(
      entry(HomeItemKind.person, HomeActivityAction.editedDetails).label,
      'ערכת כרטיס',
    );
    expect(
      entry(HomeItemKind.idea, HomeActivityAction.createdIdea).label,
      'הוספת רעיון',
    );
    expect(
      entry(HomeItemKind.idea, HomeActivityAction.changedStatus).label,
      'ערכת רעיון',
    );
  });
}
