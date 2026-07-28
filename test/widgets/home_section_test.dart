import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The home rows are fixed-size boxes on purpose, so the whole screen reads as
/// one system. That only holds if the fullest possible card still fits inside
/// the box — including at a larger system font, where the card grows with it.
void main() {
  Widget wrap(Widget child, {double textScale = 1.0}) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  Widget fullestCard() {
    return HomeMiniCard(
      // The tallest leading block: two ringed avatars.
      leading: const HomeCardCoupleAvatars(personA: null, personB: null),
      title: 'ישראלה בת אברהם',
      subtitle: 'הערה ארוכה שנשברת לשתי שורות מלאות בכרטיס',
      footer: const HomeCardFooter(
        label: 'ממתין לתשובה',
        icon: Icons.schedule,
        tinted: true,
      ),
      menu: const Icon(Icons.more_vert, size: 16),
      onTap: () {},
    );
  }

  testWidgets('the fullest card fits its fixed box', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(Center(child: fullestCard())));

    expect(tester.takeException(), isNull);
    final Size size = tester.getSize(find.byType(HomeMiniCard));
    expect(size.width, HomeConfig.cardWidth);
    expect(size.height, HomeConfig.cardHeight);
  });

  testWidgets('the card grows with the system font instead of overflowing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(Center(child: fullestCard()), textScale: 1.6),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(HomeMiniCard)).height,
      greaterThan(HomeConfig.cardHeight),
    );
  });

  testWidgets('a carousel leaves the next card peeking in', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        HomeCarousel(
          itemCount: 6,
          itemBuilder: (BuildContext context, int index) => fullestCard(),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    // Two whole cards plus a visible slice of the third: that slice is the
    // only affordance telling the user the row scrolls.
    const double used =
        HomeConfig.carouselPadding +
        HomeConfig.cardWidth * 2 +
        HomeConfig.cardGap * 2;
    expect(used, lessThan(360));
    expect(used + HomeConfig.cardWidth, greaterThan(360));
  });
}
