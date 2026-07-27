import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';

void main() {
  late Directory hiveDirectory;
  late Box<dynamic> settingsBox;
  late ReligiousLevelsProvider religiousLevelsProvider;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'people_filters_sheet_test_',
    );
    Hive.init(hiveDirectory.path);
    settingsBox = await Hive.openBox<dynamic>('settings');
    religiousLevelsProvider = ReligiousLevelsProvider(settingsBox);
  });

  tearDownAll(() async {
    religiousLevelsProvider.dispose();
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('people filters match the compact card layout and clear state', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<ReligiousLevelsProvider>.value(
        value: religiousLevelsProvider,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: PeopleFiltersSheet(
                initialGender: Gender.male,
                initialAgeRange: const RangeValues(20, 55),
                ageBounds: (min: 18, max: 70),
                initialReligiousLevels: const <ReligiousLevel>[
                  ReligiousLevel.haredi,
                ],
                initialProfileStatuses: const <ProfileStatus>[
                  ProfileStatus.available,
                ],
                heightBounds: (min: 120, max: 200),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('סינון אנשים'), findsOneWidget);
    expect(find.text('הכל'), findsOneWidget);
    expect(find.text('מגיל'), findsOneWidget);
    expect(find.text('הצג תוצאות'), findsOneWidget);
    expect(find.text('נקה'), findsOneWidget);
    expect(_chip(tester, 'זכר').selected, isTrue);
    expect(_chip(tester, 'פנוי').selected, isTrue);
    expect(_chip(tester, 'חרדי').selected, isTrue);

    await tester.ensureVisible(find.text('סינון מורחב'));
    await tester.tap(find.text('סינון מורחב'));
    await tester.pumpAndSettle();

    expect(find.text('גובה'), findsOneWidget);
    expect(find.text('מצב משפחתי'), findsOneWidget);

    await tester.tap(find.text('נקה'));
    await tester.pumpAndSettle();

    expect(_chip(tester, 'הכל').selected, isTrue);
    expect(_chip(tester, 'זכר').selected, isFalse);
    expect(_chip(tester, 'פנוי').selected, isFalse);
    expect(_chip(tester, 'חרדי').selected, isFalse);
  });

  testWidgets('status filters stay whole on a single row', (
    WidgetTester tester,
  ) async {
    // The narrowest phone we support is where `בהפסקה` used to be ellipsized.
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<ReligiousLevelsProvider>.value(
        value: religiousLevelsProvider,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: PeopleFiltersSheet(
                initialGender: Gender.male,
                initialAgeRange: const RangeValues(20, 55),
                ageBounds: (min: 18, max: 70),
                initialReligiousLevels: const <ReligiousLevel>[],
                initialProfileStatuses: const <ProfileStatus>[],
                heightBounds: (min: 120, max: 200),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final List<String> statuses = <String>['פנוי', 'תפוס', 'בהפסקה'];
    final List<double> tops = <double>[];
    for (final String label in statuses) {
      final Finder text = find.text(label);
      expect(text, findsOneWidget, reason: label);
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        text,
      );
      // Full word, never cut with an ellipsis.
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      tops.add(
        tester
            .getTopLeft(
              find.ancestor(of: text, matching: find.byType(ChoiceChip)).first,
            )
            .dy,
      );
    }
    expect(tops.toSet(), hasLength(1), reason: 'all three sit on one row');
  });
}

ChoiceChip _chip(WidgetTester tester, String label) {
  final Finder finder = find.ancestor(
    of: find.text(label),
    matching: find.byType(ChoiceChip),
  );
  return tester.widget<ChoiceChip>(finder.first);
}
