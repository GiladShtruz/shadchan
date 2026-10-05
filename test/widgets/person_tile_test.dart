import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/person_list_card.dart';

/// The grid of המאגר שלי: a square keeps everything a row has, and fits.
void main() {
  final Person person = Person(
    id: 'p1',
    firstName: 'אלישבע־מרים',
    lastName: 'כהן־שטרנברג',
    gender: Gender.female,
    manualAge: 27,
    religiousLevel: ReligiousLevel.datiLeumiTorani,
    phone: '0521234567',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  for (final double scale in <double>[1.0, 1.5]) {
    testWidgets('a tile fits two to a 320px row at ${scale}x text', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 640),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Builder(
                  builder: (BuildContext context) => Center(
                    child: SizedBox(
                      width: (320 - 32 - 8) / 2,
                      height: PersonListCard.tileExtent(context),
                      child: PersonListCard(
                        tile: true,
                        person: person,
                        onTap: () {},
                        onOpenWhatsApp: () {},
                        onOpenMatches: () {},
                        keepWhatsAppSlot: true,
                        onStatusPicked: (_, _) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Nothing the row offers is dropped: the name, the status and the
      // two buttons.
      expect(find.text('אלישבע־מרים כהן־שטרנברג'), findsOneWidget);
      expect(find.byTooltip('התאמות'), findsOneWidget);
      expect(find.byTooltip('שינוי סטטוס'), findsOneWidget);
    });
  }
}
