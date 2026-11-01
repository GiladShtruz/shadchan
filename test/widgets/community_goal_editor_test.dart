import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/community_challenge.dart';
import 'package:shadchan/widgets/community_goal_editor.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets(
    'loads, previews and saves the metric, target and public heading',
    (tester) async {
      WeeklyCommunityGoal? saved;
      await tester.pumpWidget(
        _wrap(
          CommunityGoalEditor(
            load: () async => const WeeklyCommunityGoal(
              metric: ChallengeMetric.friends,
              target: 120,
            ),
            save: (goal) async {
              saved = goal;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final Finder fields = find.byType(TextFormField);
      expect(find.text('120'), findsOneWidget);
      await tester.enterText(fields.at(0), '300');
      await tester.enterText(fields.at(1), 'השבוע מחברים עוד חברים');
      expect(find.text('יעד שבועי: 300 חברים'), findsOneWidget);
      await tester.ensureVisible(find.text('שמירת היעד לכל הקהילה'));
      await tester.tap(find.text('שמירת היעד לכל הקהילה'));
      await tester.pump();
      expect(saved?.metric, ChallengeMetric.friends);
      expect(saved?.target, 300);
      expect(saved?.title, 'השבוע מחברים עוד חברים');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('rejects a zero target before writing', (tester) async {
    int saves = 0;
    await tester.pumpWidget(
      _wrap(
        CommunityGoalEditor(
          load: () async => null,
          save: (_) async {
            saves++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.ensureVisible(find.text('שמירת היעד לכל הקהילה'));
    await tester.tap(find.text('שמירת היעד לכל הקהילה'));
    await tester.pump();
    expect(saves, 0);
    expect(find.textContaining('יש להזין מספר בין 1'), findsOneWidget);
  });

  testWidgets(
    'a failed load offers retry and never replaces the remote target with defaults',
    (tester) async {
      int loads = 0;
      await tester.pumpWidget(
        _wrap(
          CommunityGoalEditor(
            load: () async {
              if (++loads == 1) throw StateError('offline');
              return const WeeklyCommunityGoal(
                metric: ChallengeMetric.ideas,
                target: 700,
              );
            },
            save: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('שמירת היעד לכל הקהילה'), findsNothing);
      await tester.tap(find.text('ניסיון נוסף'));
      await tester.pumpAndSettle();
      expect(find.text('700'), findsOneWidget);
    },
  );
}
