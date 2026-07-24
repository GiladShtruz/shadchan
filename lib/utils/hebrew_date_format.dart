/// Small date helpers written by hand: `intl`'s locale data is not initialized
/// in this app, so its formatters must not be used at build time.
abstract final class HebrewDateFormat {
  static const List<String> months = <String>[
    'ינואר',
    'פברואר',
    'מרץ',
    'אפריל',
    'מאי',
    'יוני',
    'יולי',
    'אוגוסט',
    'ספטמבר',
    'אוקטובר',
    'נובמבר',
    'דצמבר',
  ];

  /// "15.8" — day and month, the way a date is said out loud.
  static String shortDate(DateTime date) => '${date.day}.${date.month}';

  /// "15 באוגוסט 2026".
  static String longDate(DateTime date) =>
      '${date.day} ב${months[date.month - 1]} ${date.year}';

  /// "אוגוסט 2026".
  static String monthAndYear(DateTime date) =>
      '${months[date.month - 1]} ${date.year}';
}
