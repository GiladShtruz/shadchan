import 'package:flutter/material.dart';

/// The result of picking a reminder date: a date, or an explicit "clear".
class ReminderChoice {
  const ReminderChoice(this.date);

  final DateTime? date;
}

/// The small "מתי להזכיר?" menu that opens over the card. Offers the common
/// intervals plus a calendar, and never leaves the current screen.
abstract final class ReminderPickerSheet {
  /// Builds the default interval options relative to [base] (today).
  static List<({String label, DateTime date})> _defaultIntervals(
    DateTime base,
  ) {
    return <({String label, DateTime date})>[
      (label: 'מחר', date: base.add(const Duration(days: 1))),
      (label: 'בעוד שבוע', date: base.add(const Duration(days: 7))),
      (label: 'בעוד חודש', date: DateTime(base.year, base.month + 1, base.day)),
      (
        label: 'בעוד חודשיים',
        date: DateTime(base.year, base.month + 2, base.day),
      ),
      (
        label: 'בעוד חצי שנה',
        date: DateTime(base.year, base.month + 6, base.day),
      ),
    ];
  }

  /// The interval options used when someone is put on a break — "לבדוק שוב בעוד
  /// שבוע / שבועיים / חודש / 3 חודשים / חצי שנה / שנה".
  static List<({String label, DateTime date})> breakIntervals(DateTime base) {
    return <({String label, DateTime date})>[
      (label: 'שבוע', date: base.add(const Duration(days: 7))),
      (label: 'שבועיים', date: base.add(const Duration(days: 14))),
      (label: 'חודש', date: DateTime(base.year, base.month + 1, base.day)),
      (
        label: '3 חודשים',
        date: DateTime(base.year, base.month + 3, base.day),
      ),
      (
        label: 'חצי שנה',
        date: DateTime(base.year, base.month + 6, base.day),
      ),
      (label: 'שנה', date: DateTime(base.year + 1, base.month, base.day)),
    ];
  }

  static Future<ReminderChoice?> show(
    BuildContext context, {
    String title = 'מתי להזכיר לך?',
    bool allowClear = false,
    bool allowSkip = false,
    List<({String label, DateTime date})> Function(DateTime base)?
    intervalsBuilder,
  }) {
    return showModalBottomSheet<ReminderChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final DateTime today = DateTime.now();
        final DateTime base = DateTime(today.year, today.month, today.day);
        final List<({String label, DateTime date})> intervals =
            (intervalsBuilder ?? _defaultIntervals)(base);

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                ),
                for (final ({String label, DateTime date}) option in intervals)
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(option.label),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(ReminderChoice(option.date)),
                  ),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('אחר'),
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: sheetContext,
                      initialDate: base.add(const Duration(days: 1)),
                      firstDate: base,
                      lastDate: DateTime(base.year + 5),
                    );
                    if (picked != null && sheetContext.mounted) {
                      Navigator.of(sheetContext).pop(ReminderChoice(picked));
                    }
                  },
                ),
                if (allowClear)
                  ListTile(
                    leading: const Icon(Icons.notifications_off_outlined),
                    title: const Text('הסרת התזכורת'),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(const ReminderChoice(null)),
                  ),
                if (allowSkip)
                  ListTile(
                    leading: const Icon(Icons.arrow_back),
                    title: const Text('דלג'),
                    onTap: () => Navigator.of(sheetContext).pop(),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
