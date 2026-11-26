import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/ai_usage.dart';
import 'package:shadchan/services/feature_usage.dart';
import 'package:shadchan/widgets/admin_usage_section.dart';

/// The admin dashboard's raw material: token counts per AI answer, the page /
/// feature tally, and the arithmetic that turns them into money.
void main() {
  test(
    'one AI answer adds its tokens to the total, the month and the feature',
    () {
      final Map<String, Object?> inc = AiUsage.incrementsFor(
        AiFeature.import,
        input: 1200,
        output: 350,
        at: DateTime(2026, 11, 26),
      );
      expect(inc['calls'], 1);
      expect(inc['inputTokens'], 1200);
      expect(inc['outputTokens'], 350);
      expect(inc['months.2026-11.inputTokens'], 1200);
      expect(inc['features.import.calls'], 1);
    },
  );

  test('pages are tallied by path, with ids folded away', () {
    expect(FeatureUsage.normalize('/people/3f2a-9c'), '/people/:id');
    expect(FeatureUsage.normalize('/known-matchmakers'), '/known-matchmakers');
    expect(FeatureUsage.normalize('/chats/aB1_cD2?name=x'), '/chats/:id');
  });

  test('a code used twice is counted twice', () {
    FeatureUsage.resetForTest();
    FeatureUsage.hit('feature:tags', at: DateTime(2026, 11, 1));
    FeatureUsage.hit('feature:tags', at: DateTime(2026, 11, 3));
    final Map<String, Object?> tally = FeatureUsage.snapshot();
    expect((tally['feature:tags']! as Map)['n'], 2);
    expect((tally['feature:tags']! as Map)['first'], '2026-11-01');
    expect((tally['feature:tags']! as Map)['last'], '2026-11-03');
    FeatureUsage.resetForTest();
  });

  test('prices turn tokens and bytes into money', () {
    const AdminPricing pricing = AdminPricing(
      aiInputPerMillion: 0.5,
      aiOutputPerMillion: 3,
      storagePerGbMonth: 0.026,
      usdToIls: 4,
    );
    expect(pricing.aiCost(2000000, 1000000), closeTo(4, 1e-9));
    expect(pricing.storageCost(10e9), closeTo(0.26, 1e-9));
    expect(pricing.money(1), r'$1.00 (₪4.00)');
  });
}
