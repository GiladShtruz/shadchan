import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/utils/reminder_schedule_plan.dart';

PlannedReminder<String> _at(String id, DateTime at) =>
    PlannedReminder<String>(at: at, item: id);

void main() {
  test('a few reminders on one day keep their own notifications', () {
    final ReminderSchedulePlan<String> plan =
        ReminderSchedulePlan.build(<PlannedReminder<String>>[
          _at('b', DateTime(2026, 12, 1, 9)),
          _at('a', DateTime(2026, 11, 20, 9)),
          _at('c', DateTime(2026, 12, 1, 9)),
        ], maxNotifications: 40);

    expect(plan.bundles, isEmpty);
    expect(plan.single.map((PlannedReminder<String> r) => r.item), <String>[
      'a',
      'b',
      'c',
    ]);
  });

  test('more than three on one day become one summary', () {
    final List<PlannedReminder<String>> sameDay = <PlannedReminder<String>>[
      for (int i = 0; i < 12; i++) _at('m$i', DateTime(2026, 12, 1, 9)),
    ];
    final ReminderSchedulePlan<String> plan = ReminderSchedulePlan.build(
      <PlannedReminder<String>>[
        ...sameDay,
        _at('other', DateTime(2026, 12, 2, 9)),
      ],
      maxNotifications: 40,
    );

    expect(plan.bundles, hasLength(1));
    expect(plan.bundles.single.count, 12);
    expect(plan.single.single.item, 'other');
    expect(plan.notificationCount, 2);
  });

  test('the cap keeps the soonest notifications', () {
    final ReminderSchedulePlan<String> plan = ReminderSchedulePlan.build(
      <PlannedReminder<String>>[
        for (int day = 30; day >= 1; day--)
          _at('d$day', DateTime(2027, 1, day, 9)),
      ],
      maxNotifications: 5,
    );

    expect(plan.single.map((PlannedReminder<String> r) => r.item), <String>[
      'd1',
      'd2',
      'd3',
      'd4',
      'd5',
    ]);
  });

  test('a summary counts as one notification against the cap', () {
    final ReminderSchedulePlan<String> plan =
        ReminderSchedulePlan.build(<PlannedReminder<String>>[
          for (int i = 0; i < 10; i++) _at('x$i', DateTime(2027, 1, 1, 9)),
          _at('later', DateTime(2027, 1, 2, 9)),
        ], maxNotifications: 2);

    expect(plan.bundles, hasLength(1));
    expect(plan.single.single.item, 'later');
  });
}
