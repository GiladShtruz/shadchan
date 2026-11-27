/// The monitoring dashboard's pure parts: the period filter, number and money
/// formatting, sorting and CSV — kept out of the screen so they are tested.
library;

/// The fixed filter at the top of the dashboard.
enum PeriodKind { today, week, month30, calendarMonth, range }

class MonitoringPeriod {
  const MonitoringPeriod(this.kind, this.from, this.to);

  final PeriodKind kind;

  /// Israel calendar days, inclusive.
  final DateTime from;
  final DateTime to;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  factory MonitoringPeriod.today(DateTime now) =>
      MonitoringPeriod(PeriodKind.today, _day(now), _day(now));

  /// The last [days] days, today included.
  factory MonitoringPeriod.last(int days, DateTime now) => MonitoringPeriod(
    days == 7 ? PeriodKind.week : PeriodKind.month30,
    _day(now).subtract(Duration(days: days - 1)),
    _day(now),
  );

  /// A calendar month — up to today when it is the current one.
  factory MonitoringPeriod.month(int year, int month, DateTime now) {
    final DateTime first = DateTime(year, month);
    final DateTime last = DateTime(year, month + 1, 0);
    return MonitoringPeriod(
      PeriodKind.calendarMonth,
      first,
      last.isAfter(now) ? _day(now) : last,
    );
  }

  factory MonitoringPeriod.range(DateTime from, DateTime to) =>
      MonitoringPeriod(PeriodKind.range, _day(from), _day(to));

  int get days => to.difference(from).inDays + 1;

  static String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String get fromKey => key(from);
  String get toKey => key(to);

  /// The month key (`2026-11`) when the period is exactly one calendar month.
  String? get monthKey => kind == PeriodKind.calendarMonth
      ? '${from.year}-${from.month.toString().padLeft(2, '0')}'
      : null;

  static const List<String> _months = <String>[
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

  static String monthName(int month, int year) => '${_months[month - 1]} $year';

  String get label => switch (kind) {
    PeriodKind.today => 'היום',
    PeriodKind.week => '7 ימים',
    PeriodKind.month30 => '30 ימים',
    PeriodKind.calendarMonth => monthName(from.month, from.year),
    PeriodKind.range => '${from.day}.${from.month} – ${to.day}.${to.month}',
  };

  /// What the comparison is against: the same length just before.
  String get comparedWith => switch (kind) {
    PeriodKind.today => 'מול אתמול',
    PeriodKind.week => 'מול 7 הימים שלפני',
    PeriodKind.month30 => 'מול 30 הימים שלפני',
    PeriodKind.calendarMonth => 'מול התקופה המקבילה שלפני',
    PeriodKind.range => 'מול תקופה באותו אורך שלפני',
  };
}

abstract final class MonitoringFormat {
  static num n(Object? v) => v is num ? v : 0;

  /// "1,234" / "12.5K".
  static String count(Object? value) {
    final num v = n(value);
    if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v.abs() >= 1e4) return '${(v / 1e3).toStringAsFixed(1)}K';
    if (v is double && v != v.roundToDouble()) return v.toStringAsFixed(1);
    final String s = v.round().toString();
    return s.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (Match m) => '${m[1]},',
    );
  }

  /// "₪12.40", "<₪0.01".
  static String ils(Object? value) {
    final num v = n(value);
    if (v > 0 && v < 0.01) return '<₪0.01';
    return '₪${v.toStringAsFixed(v >= 100 ? 0 : 2)}';
  }

  static String bytes(Object? value) {
    final num v = n(value);
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)} GB';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)} MB';
    if (v >= 1e3) return '${(v / 1e3).round()} KB';
    return '${v.round()} B';
  }

  static String ms(Object? value) {
    if (value == null) return '—';
    final num v = n(value);
    return v >= 1000
        ? '${(v / 1000).toStringAsFixed(1)} ש׳'
        : '${v.round()} מ״ש';
  }

  /// "+12%" / "−4%" / "חדש" (nothing before) / "" (no change known).
  static String change(Object? value) {
    if (value == null) return 'חדש';
    final num v = n(value);
    if (v == 0) return '0%';
    return '${v > 0 ? '+' : '−'}${v.abs().toStringAsFixed(v.abs() >= 10 ? 0 : 1)}%';
  }

  static String percent(Object? value) =>
      value == null ? '—' : '${n(value).toStringAsFixed(1)}%';
}

/// Rows from the server, sorted by one column and filtered by a search.
List<Map<String, dynamic>> sortAndFilter(
  List<Map<String, dynamic>> rows, {
  required String sortKey,
  bool descending = true,
  String query = '',
  List<String> searchKeys = const <String>[],
}) {
  final String q = query.trim().toLowerCase();
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[
    for (final Map<String, dynamic> r in rows)
      if (q.isEmpty ||
          searchKeys.any(
            (String k) => '${r[k] ?? ''}'.toLowerCase().contains(q),
          ))
        r,
  ];
  int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
    final Object? x = a[sortKey];
    final Object? y = b[sortKey];
    if (x is num || y is num) {
      final num xa = x is num ? x : double.negativeInfinity;
      final num yb = y is num ? y : double.negativeInfinity;
      return xa.compareTo(yb);
    }
    return '${x ?? ''}'.compareTo('${y ?? ''}');
  }

  out.sort((a, b) => descending ? cmp(b, a) : cmp(a, b));
  return out;
}

/// A CSV document (comma-separated, quoted where needed), with a BOM so
/// Excel reads Hebrew headers as UTF-8.
String toCsv(List<String> headers, List<List<Object?>> rows) {
  String cell(Object? v) {
    final String s = v == null ? '' : '$v';
    return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return '﻿${<List<Object?>>[headers, ...rows].map((List<Object?> r) => r.map(cell).join(',')).join('\n')}\n';
}
