import 'package:flutter/material.dart';
import 'package:shadchan/utils/reminder_text_parser.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/gender_text.dart';

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
      (label: '3 חודשים', date: DateTime(base.year, base.month + 3, base.day)),
      (label: 'חצי שנה', date: DateTime(base.year, base.month + 6, base.day)),
      (label: 'שנה', date: DateTime(base.year + 1, base.month, base.day)),
    ];
  }

  /// The compact choices used after a person becomes busy or goes on a break.
  static List<({String label, DateTime date})> statusCheckIntervals(
    DateTime base,
  ) {
    return <({String label, DateTime date})>[
      (label: 'מחר', date: base.add(const Duration(days: 1))),
      (label: 'עוד שבוע', date: base.add(const Duration(days: 7))),
      (label: 'עוד שבועיים', date: base.add(const Duration(days: 14))),
      (label: 'עוד חודש', date: DateTime(base.year, base.month + 1, base.day)),
      (
        label: 'עוד 3 חודשים',
        date: DateTime(base.year, base.month + 3, base.day),
      ),
    ];
  }

  static Future<ReminderChoice?> show(
    BuildContext context, {
    String title = 'מתי להזכיר לך?',
    bool allowClear = false,
    bool allowSkip = false,
    String? recommendedLabel,
    List<({String label, DateTime date})> Function(DateTime base)?
    intervalsBuilder,
  }) {
    return showModalBottomSheet<ReminderChoice>(
      context: context,
      showDragHandle: true,
      // Scroll-controlled so every option fits on screen; the default sheet
      // caps at half the screen and cut off the last rows (`דלג`).
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
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
                // `דלג` sits first: skipping is the quickest way out of the
                // sheet, so it should not be hidden under the whole list.
                if (allowSkip) ...<Widget>[
                  ListTile(
                    leading: const Icon(Icons.skip_next_outlined),
                    title: const Text('דלג'),
                    subtitle: const Text('בלי תזכורת'),
                    onTap: () => Navigator.of(sheetContext).pop(),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                ],
                for (final ({String label, DateTime date}) option in intervals)
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(option.label),
                    trailing: option.label == recommendedLabel
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                sheetContext,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'מומלץ',
                              style: Theme.of(sheetContext).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      sheetContext,
                                    ).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          )
                        : null,
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(ReminderChoice(option.date)),
                  ),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('אחר'),
                  onTap: () async {
                    final DateTime? picked =
                        await showModalBottomSheet<DateTime>(
                          context: sheetContext,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (BuildContext context) =>
                              _CustomReminderSheet(base: base),
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
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CustomReminderSheet extends StatefulWidget {
  const _CustomReminderSheet({required this.base});

  final DateTime base;

  @override
  State<_CustomReminderSheet> createState() => _CustomReminderSheetState();
}

class _CustomReminderSheetState extends State<_CustomReminderSheet> {
  final TextEditingController _controller = TextEditingController();

  /// A [GenderText] template, resolved when it is drawn — `watch` for the
  /// matchmaker's gender is only legal inside `build`.
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'מתי להזכיר?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'אפשר לכתוב למשל: 45 ימים, 6 שבועות או 2 חודשים',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: '45 ימים',
                      errorText: _error?.forGender(context.userGender),
                    ),
                    onSubmitted: (_) => _submitText(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'בחירת תאריך',
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitText,
                child: const Text('קביעת תזכורת'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitText() {
    final DateTime? date = ReminderTextParser.parse(
      _controller.text,
      base: widget.base,
    );
    if (date == null) {
      setState(() {
        _error = '{כתוב|כתבי} מספר ואחריו ימים, שבועות או חודשים';
      });
      return;
    }
    Navigator.of(context).pop(date);
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: widget.base.add(const Duration(days: 1)),
      firstDate: widget.base,
      lastDate: DateTime(widget.base.year + 5),
      locale: const Locale('he'),
    );
    if (picked != null && mounted) {
      Navigator.of(context).pop(picked);
    }
  }
}
