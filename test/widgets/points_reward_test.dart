import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/widgets/points_reward.dart';

void main() {
  test('the word follows what happened', () {
    expect(
      PointsReward.labelFor(friends: 1, ideas: 0, couples: 0, engagements: 0),
      'נוסף למאגר',
    );
    expect(
      PointsReward.labelFor(friends: 3, ideas: 0, couples: 0, engagements: 0),
      'נוספו למאגר',
    );
    expect(
      PointsReward.labelFor(friends: 0, ideas: 1, couples: 0, engagements: 0),
      'רעיון נפתח',
    );
    expect(
      PointsReward.labelFor(friends: 0, ideas: 0, couples: 1, engagements: 0),
      'מעולה!',
    );
    expect(
      PointsReward.labelFor(friends: 0, ideas: 0, couples: 1, engagements: 1),
      'מזל טוב!',
    );
  });

  testWidgets('a small pill that goes away by itself and blocks nothing', (
    tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => taps++,
              child: const Text('x'),
            ),
          ),
        ),
      ),
    );
    final OverlayState overlay = tester.state<OverlayState>(
      find.byType(Overlay).first,
    );
    PointsReward.show(overlay, points: 1, label: 'נוסף למאגר');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('נוסף למאגר'), findsOneWidget);
    await tester.tap(find.text('x'));
    expect(taps, 1);
    await tester.pump(PointsReward.visibleFor);
    expect(find.textContaining('נוסף למאגר'), findsNothing);
  });
}
