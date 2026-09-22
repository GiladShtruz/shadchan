import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/widgets/first_visit_tip.dart';

void main() {
  setUp(FirstVisitTips.resetForTest);

  test(
    'a tip belongs to the first visit only, whether or not it was closed',
    () {
      expect(
        FirstVisitTips.takeFirstVisit(FirstVisitTopic.friendProfile),
        isTrue,
      );
      expect(
        FirstVisitTips.takeFirstVisit(FirstVisitTopic.friendProfile),
        isFalse,
      );
      // Each screen has its own first visit.
      expect(FirstVisitTips.takeFirstVisit(FirstVisitTopic.addFriends), isTrue);
    },
  );

  testWidgets('the tip says its piece and closes', (WidgetTester tester) async {
    int closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: FirstVisitTip(
              icon: Icons.ios_share_rounded,
              headline: 'שתף מתוך הווטסאפ תמונה וכמה מילים על החבר שלך!',
              lines: const <String>['שורה שנייה'],
              onDismiss: () => closed++,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('שתף מתוך הווטסאפ תמונה וכמה מילים על החבר שלך!'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('סגירה'));
    expect(closed, 1);
  });
}
