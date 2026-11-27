import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/utils/admin_monitoring.dart';
import 'package:shadchan/utils/app_tokens.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';

typedef Json = Map<String, dynamic>;

Json _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Json> _list(Object? v) => v is List
    ? <Json>[
        for (final Object? e in v)
          if (e is Map) _map(e),
      ]
    : <Json>[];

Future<Json> _call(String name, Json data) async {
  final HttpsCallableResult<dynamic> result =
      await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
          )
          .call(data);
  return _map(result.data);
}

Future<void> _shareCsv(BuildContext context, String name, String csv) async {
  final OverlayState? notices = AppNotice.capture(context);
  try {
    final Directory dir = await getTemporaryDirectory();
    final File file = File('${dir.path}/shadchan_$name.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles(<XFile>[XFile(file.path, mimeType: 'text/csv')]);
  } catch (_) {
    AppNotice.showOn(notices, 'הייצוא נכשל');
  }
}

/// **The monitoring dashboard** — usage, users, features, AI, costs and
/// errors for one period, against the period before it, for support
/// administrators only (the callable checks; the data never reaches anybody
/// else). Everything comes from `adminAnalytics` (`functions/src/analytics.ts`)
/// in one call; a tap opens the detail, never a wall of numbers at once.
class AdminMonitoringView extends StatefulWidget {
  const AdminMonitoringView({super.key});

  @override
  State<AdminMonitoringView> createState() => _AdminMonitoringViewState();
}

class _AdminMonitoringViewState extends State<AdminMonitoringView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this);
  MonitoringPeriod _period = MonitoringPeriod.last(7, DateTime.now());
  String? _platform;
  String? _version;
  String? _userType;
  String? _cohort;
  String? _release;
  Json? _data;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Json data = await _call('adminAnalytics', <String, dynamic>{
        'from': _period.fromKey,
        'to': _period.toKey,
        'force': force,
        if (_release != null) 'release': _release,
        'segment': <String, dynamic>{
          'platform': ?_platform,
          'version': ?_version,
          'userType': ?_userType,
          'cohort': ?_cohort,
        },
      });
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'לא הצלחנו לטעון את הנתונים ($error)');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPeriod(MonitoringPeriod p) {
    setState(() => _period = p);
    _load();
  }

  Future<void> _pickMonth() async {
    final DateTime now = DateTime.now();
    final List<DateTime> months = <DateTime>[
      for (int i = 0; i < 12; i++) DateTime(now.year, now.month - i),
    ];
    final DateTime? chosen = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final DateTime m in months)
              ListTile(
                title: Text(MonitoringPeriod.monthName(m.month, m.year)),
                onTap: () => Navigator.of(context).pop(m),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      _setPeriod(MonitoringPeriod.month(chosen.year, chosen.month, now));
    }
  }

  Future<void> _pickRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026, 11),
      lastDate: now,
      initialDateRange: DateTimeRange(start: _period.from, end: _period.to),
    );
    if (r != null) _setPeriod(MonitoringPeriod.range(r.start, r.end));
  }

  Future<void> _pickSegment() async {
    final List<Json> versions = _list(_data?['knownVersions']);
    String? platform = _platform;
    String? version = _version;
    String? userType = _userType;
    String? cohort = _cohort;
    final bool? apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter set) {
          Widget choices(
            String title,
            Map<String?, String> options,
            String? value,
            ValueChanged<String?> pick,
          ) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    for (final MapEntry<String?, String> o in options.entries)
                      ChoiceChip(
                        label: Text(o.value),
                        selected: value == o.key,
                        onSelected: (_) => set(() => pick(o.key)),
                      ),
                  ],
                ),
              ],
            ),
          );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('פילוח', style: Theme.of(context).textTheme.titleLarge),
                  choices(
                    'פלטפורמה',
                    <String?, String>{
                      null: 'הכל',
                      'android': 'Android',
                      'ios': 'iOS',
                    },
                    platform,
                    (v) => platform = v,
                  ),
                  choices(
                    'סוג משתמש',
                    <String?, String>{
                      null: 'הכל',
                      'single': 'רווק/ה',
                      'matchmaker': 'שדכן/ית',
                      'both': 'רווק/ה + שדכן/ית',
                    },
                    userType,
                    (v) => userType = v,
                  ),
                  choices(
                    'ותק',
                    <String?, String>{
                      null: 'הכל',
                      'new': 'חדשים (30 יום)',
                      'veteran': 'ותיקים',
                    },
                    cohort,
                    (v) => cohort = v,
                  ),
                  choices(
                    'גרסת אפליקציה',
                    <String?, String>{
                      null: 'הכל',
                      for (final Json v in versions.take(8))
                        v['version'] as String: v['version'] as String,
                    },
                    version,
                    (v) => version = v,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('הצגה'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (apply == true) {
      setState(() {
        _platform = platform;
        _version = version;
        _userType = userType;
        _cohort = cohort;
      });
      _load();
    }
  }

  bool get _segmented =>
      _platform != null ||
      _version != null ||
      _userType != null ||
      _cohort != null;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final ThemeData theme = Theme.of(context);
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
    return Column(
      children: <Widget>[
        // The fixed filter: the same period for every tab.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: <Widget>[
              chip(
                'היום',
                _period.kind == PeriodKind.today,
                () => _setPeriod(MonitoringPeriod.today(now)),
              ),
              chip(
                '7 ימים',
                _period.kind == PeriodKind.week,
                () => _setPeriod(MonitoringPeriod.last(7, now)),
              ),
              chip(
                '30 ימים',
                _period.kind == PeriodKind.month30,
                () => _setPeriod(MonitoringPeriod.last(30, now)),
              ),
              chip(
                _period.kind == PeriodKind.calendarMonth
                    ? _period.label
                    : 'חודש…',
                _period.kind == PeriodKind.calendarMonth,
                _pickMonth,
              ),
              chip(
                _period.kind == PeriodKind.range ? _period.label : 'טווח…',
                _period.kind == PeriodKind.range,
                _pickRange,
              ),
              const SizedBox(width: 6),
              ActionChip(
                avatar: Icon(
                  Icons.filter_alt_outlined,
                  size: 18,
                  color: _segmented ? theme.colorScheme.primary : null,
                ),
                label: Text(_segmented ? 'פילוח פעיל' : 'פילוח'),
                onPressed: _pickSegment,
              ),
              IconButton(
                tooltip: 'רענון',
                onPressed: _loading ? null : () => _load(force: true),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const <Widget>[
            Tab(text: 'סקירה'),
            Tab(text: 'משתמשים'),
            Tab(text: 'פיצ\'רים'),
            Tab(text: 'AI'),
            Tab(text: 'עלויות'),
            Tab(text: 'תקלות'),
          ],
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _error != null && _data == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _data == null
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabs,
                  children: <Widget>[
                    _OverviewTab(
                      data: _data!,
                      period: _period,
                      onOpenTab: (int i) => _tabs.animateTo(i),
                    ),
                    _UsersTab(data: _data!, period: _period),
                    _FeaturesTab(data: _data!, period: _period),
                    _AiTab(data: _data!, period: _period),
                    _CostsTab(
                      data: _data!,
                      period: _period,
                      onChanged: () => _load(force: true),
                    ),
                    _ErrorsTab(
                      data: _data!,
                      period: _period,
                      release: _release,
                      onRelease: (String? v) {
                        setState(() => _release = v);
                        _load();
                      },
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces.

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HomePaperCard(
        stripe: context.tokens.maleAccent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// One key figure: value, label, change, and an optional tap.
class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, {this.change, this.note, this.onTap});

  final String label;
  final String value;
  final Object? change;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? delta = change == null && note == null
        ? null
        : (change != null ? MonitoringFormat.change(change) : null);
    final num c = MonitoringFormat.n(change);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 156,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              value,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall, maxLines: 2),
            if (delta != null)
              Text(
                delta,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: c > 0
                      ? Colors.green.shade700
                      : c < 0
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
            if (note != null)
              Text(
                note!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _wrap(List<Widget> tiles) =>
    Wrap(spacing: 8, runSpacing: 8, children: tiles);

/// "משוער" — every estimate is marked as one, never shown as a bill.
class _Estimated extends StatelessWidget {
  const _Estimated();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsetsDirectional.only(start: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text('משוער', style: Theme.of(context).textTheme.labelSmall),
  );
}

/// A small bar chart of a daily series.
class _Bars extends StatelessWidget {
  const _Bars(this.values, {this.height = 56});

  final List<num> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final num max = values.fold<num>(0, (num a, num b) => b > a ? b : a);
    final Color color = context.tokens.maleAccent;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final num v in values)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                height: max > 0 ? (v / max) * height : 0,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Column {
  const _Column(this.label, this.key, this.format, {this.numeric = true});

  final String label;
  final String key;
  final String Function(Json row) format;
  final bool numeric;
}

/// A table that sorts by any column (tap the heading) and searches.
class _Table extends StatefulWidget {
  const _Table({
    required this.rows,
    required this.columns,
    required this.sortKey,
    this.searchKeys = const <String>[],
    this.onTap,
    this.limit = 50,
  });

  final List<Json> rows;
  final List<_Column> columns;
  final String sortKey;
  final List<String> searchKeys;
  final ValueChanged<Json>? onTap;
  final int limit;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  late String _sort = widget.sortKey;
  bool _desc = true;
  String _query = '';
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Json> rows = sortAndFilter(
      widget.rows,
      sortKey: _sort,
      descending: _desc,
      query: _query,
      searchKeys: widget.searchKeys,
    );
    final List<Json> shown = _all ? rows : rows.take(widget.limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.searchKeys.isNotEmpty)
          TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'חיפוש',
            ),
            onChanged: (String v) => setState(() => _query = v),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowHeight: 36,
            dataRowMinHeight: 32,
            dataRowMaxHeight: 44,
            columnSpacing: 16,
            sortColumnIndex: widget.columns
                .indexWhere((_Column c) => c.key == _sort)
                .clamp(0, widget.columns.length - 1),
            sortAscending: !_desc,
            columns: <DataColumn>[
              for (final _Column c in widget.columns)
                DataColumn(
                  label: Text(c.label, style: theme.textTheme.labelMedium),
                  numeric: c.numeric,
                  onSort: (_, _) => setState(() {
                    if (_sort == c.key) {
                      _desc = !_desc;
                    } else {
                      _sort = c.key;
                      _desc = true;
                    }
                  }),
                ),
            ],
            rows: <DataRow>[
              for (final Json r in shown)
                DataRow(
                  onSelectChanged: widget.onTap == null
                      ? null
                      : (_) => widget.onTap!(r),
                  cells: <DataCell>[
                    for (final _Column c in widget.columns)
                      DataCell(Text(c.format(r))),
                  ],
                ),
            ],
          ),
        ),
        if (rows.length > widget.limit)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'פחות' : 'הכל (${rows.length})'),
          ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'אין נתונים בתקופה הזו',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

Widget _csvButton(BuildContext context, String name, String Function() build) =>
    TextButton.icon(
      onPressed: () => _shareCsv(context, name, build()),
      icon: const Icon(Icons.download_rounded, size: 18),
      label: const Text('CSV'),
    );

ListView _page(List<Widget> children) => ListView(
  padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
  children: children,
);

String _f(Json r, String k) => MonitoringFormat.count(r[k]);

// ---------------------------------------------------------------------------
// סקירה

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.data,
    required this.period,
    required this.onOpenTab,
  });

  final Json data;
  final MonitoringPeriod period;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final Json o = _map(data['overview']);
    final List<Json> series = _list(o['series']);
    final List<Json> anomalies = _list(data['anomalies']);
    return _page(<Widget>[
      _Card(
        title: '${period.label} · ${period.comparedWith}',
        children: <Widget>[
          _wrap(<Widget>[
            _Kpi(
              'משתמשים רשומים',
              _f(o, 'registered'),
              onTap: () => onOpenTab(1),
            ),
            _Kpi(
              'פעילים בתקופה',
              _f(o, 'activeUsers'),
              change: o['activeUsersChange'],
              onTap: () => onOpenTab(1),
            ),
            _Kpi('DAU (ממוצע)', _f(o, 'dau')),
            _Kpi('WAU', _f(o, 'wau')),
            _Kpi('MAU', _f(o, 'mau')),
            _Kpi('משתמשים חדשים', _f(o, 'newUsers'), onTap: () => onOpenTab(1)),
            _Kpi('רווקים פעילים', _f(o, 'activeSingles')),
            _Kpi('שדכנים פעילים', _f(o, 'activeMatchmakers')),
            _Kpi(
              'רעיונות שנפתחו',
              _f(o, 'ideas'),
              change: o['ideasChange'],
              onTap: () => onOpenTab(2),
            ),
            _Kpi(
              'זוגות שהתחילו לצאת',
              _f(o, 'couples'),
              change: o['couplesChange'],
            ),
            _Kpi(
              'עלות כוללת',
              MonitoringFormat.ils(o['totalIls']),
              note: 'משוער',
              onTap: () => onOpenTab(4),
            ),
            _Kpi(
              'עלות AI',
              MonitoringFormat.ils(o['aiIls']),
              onTap: () => onOpenTab(3),
            ),
            _Kpi(
              'תשתיות (לא AI)',
              MonitoringFormat.ils(o['infraIls']),
              note: 'משוער',
              onTap: () => onOpenTab(4),
            ),
          ]),
        ],
      ),
      if (series.length > 1)
        _Card(
          title: 'משתמשים פעילים ביום',
          children: <Widget>[
            _Bars(<num>[
              for (final Json s in series) MonitoringFormat.n(s['users']),
            ]),
          ],
        ),
      if (anomalies.isNotEmpty)
        _Card(
          title: 'חריגות (${anomalies.length})',
          children: <Widget>[
            for (final Json a in anomalies)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text('${a['detail']}'),
                subtitle: (a['email'] ?? a['uid']) == null
                    ? null
                    : Text('${a['email'] ?? ''} ${a['uid'] ?? ''}'.trim()),
                onTap: a['uid'] == null
                    ? null
                    : () => AdminUserAnalyticsScreen.open(
                        context,
                        '${a['uid']}',
                        period,
                      ),
              ),
          ],
        ),
      if (data['pricing'] is Map && _map(data['pricing'])['set'] != true)
        Text(
          'עוד לא הוזנו מחירים (עלויות ← מחירים) — עלויות יוצגו כ־₪0.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// משתמשים

class _UsersTab extends StatelessWidget {
  const _UsersTab({required this.data, required this.period});

  final Json data;
  final MonitoringPeriod period;

  @override
  Widget build(BuildContext context) {
    final Json m = _map(data['movement']);
    final Json o = _map(data['overview']);
    final Json r = _map(m['retention']);
    final Json t = _map(m['byType']);
    final List<Json> users = _list(data['users']);
    final List<Json> series = _list(o['series']);
    return _page(<Widget>[
      _Card(
        title: 'תנועת משתמשים',
        children: <Widget>[
          _wrap(<Widget>[
            _Kpi('הרשמות חדשות', _f(o, 'newUsers')),
            _Kpi(
              'DAU / WAU / MAU',
              '${_f(o, 'dau')} / ${_f(o, 'wau')} / ${_f(o, 'mau')}',
            ),
            _Kpi('חזרו אחרי הפסקה (14+ יום)', _f(m, 'returned')),
            _Kpi('הפסיקו להשתמש', _f(m, 'stopped')),
            _Kpi('Sessions', _f(m, 'sessions'), change: m['sessionsChange']),
            _Kpi('משך Session ממוצע', '${m['avgSessionMin'] ?? 0} דק׳'),
            _Kpi('ימים בשבוע למשתמש', '${m['avgDaysPerWeek'] ?? 0}'),
          ]),
          if (series.length > 1) ...<Widget>[
            const SizedBox(height: 8),
            Text('הרשמות ביום', style: Theme.of(context).textTheme.labelMedium),
            _Bars(<num>[
              for (final Json s in series) MonitoringFormat.n(s['signups']),
            ], height: 40),
          ],
        ],
      ),
      _Card(
        title: 'Retention (נרשמו בתקופה: ${r['cohort'] ?? 0})',
        trailing: _csvButton(
          context,
          'retention',
          () => toCsv(
            <String>['cohort', 'd1', 'd7', 'd30'],
            <List<Object?>>[
              <Object?>[r['cohort'], r['d1'], r['d7'], r['d30']],
            ],
          ),
        ),
        children: <Widget>[
          _wrap(<Widget>[
            _Kpi('יום 1', MonitoringFormat.percent(r['d1'])),
            _Kpi('יום 7', MonitoringFormat.percent(r['d7'])),
            _Kpi('יום 30', MonitoringFormat.percent(r['d30'])),
          ]),
          Text(
            'מי שנרשם בתקופה וחזר ביום 1, בשבוע השני או בחודש השני. "—" = עוד מוקדם לדעת.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      _Card(
        title: 'פילוח לפי סוג משתמש',
        children: <Widget>[
          _wrap(<Widget>[
            _Kpi('רווק/ה בלבד', _f(t, 'single')),
            _Kpi('שדכן/ית בלבד', _f(t, 'matchmaker')),
            _Kpi('רווק/ה + שדכן/ית', _f(t, 'both')),
          ]),
        ],
      ),
      _Card(
        title: 'משתמשים (${users.length})',
        trailing: _csvButton(
          context,
          'users',
          () => toCsv(
            <String>[
              'uid',
              'email',
              'type',
              'platform',
              'version',
              'last_active',
              'active_days',
              'sessions',
              'ai_calls',
              'ai_ils',
              'infra_ils_est',
              'total_ils_est',
              'cumulative_ils_est',
            ],
            <List<Object?>>[
              for (final Json u in users)
                <Object?>[
                  u['uid'],
                  u['email'],
                  u['ut'],
                  u['platform'],
                  u['version'],
                  u['lastDay'],
                  u['activeDays'],
                  u['sessions'],
                  u['aiCalls'],
                  u['aiIls'],
                  u['infraIls'],
                  u['totalIls'],
                  u['cumulativeIls'],
                ],
            ],
          ),
        ),
        children: <Widget>[
          Text(
            'ניטור בלבד — לא דירוג. לחיצה פותחת את פירוט המשתמש.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          _Table(
            rows: users,
            sortKey: 'totalIls',
            searchKeys: const <String>['email', 'uid'],
            onTap: (Json u) =>
                AdminUserAnalyticsScreen.open(context, '${u['uid']}', period),
            columns: <_Column>[
              _Column(
                'משתמש',
                'email',
                (Json u) => '${u['email'] ?? ''}'.isEmpty
                    ? '${u['uid']}'
                    : '${u['email']}',
                numeric: false,
              ),
              _Column(
                'סוג',
                'ut',
                (Json u) => _typeName(u['ut']),
                numeric: false,
              ),
              _Column('ימים', 'activeDays', (Json u) => _f(u, 'activeDays')),
              _Column('Sessions', 'sessions', (Json u) => _f(u, 'sessions')),
              _Column('אירועים', 'events', (Json u) => _f(u, 'events')),
              _Column('AI', 'aiCalls', (Json u) => _f(u, 'aiCalls')),
              _Column(
                'עלות בתקופה*',
                'totalIls',
                (Json u) => MonitoringFormat.ils(u['totalIls']),
              ),
              _Column(
                'מצטבר*',
                'cumulativeIls',
                (Json u) => MonitoringFormat.ils(u['cumulativeIls']),
              ),
            ],
          ),
          Text('* משוער', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ]);
  }
}

String _typeName(Object? t) => switch (t) {
  'single' => 'רווק/ה',
  'matchmaker' => 'שדכן/ית',
  'both' => 'שניהם',
  _ => '—',
};

// ---------------------------------------------------------------------------
// פיצ'רים

class _FeaturesTab extends StatelessWidget {
  const _FeaturesTab({required this.data, required this.period});

  final Json data;
  final MonitoringPeriod period;

  @override
  Widget build(BuildContext context) {
    final List<Json> features = _list(data['features']);
    final List<Json> actions = _list(data['actions']);
    final List<Json> funnels = _list(data['funnels']);
    final Map<String, String> names = <String, String>{
      for (final Json f in features) '${f['id']}': '${f['name']}',
    };
    final ThemeData theme = Theme.of(context);
    return _page(<Widget>[
      _Card(
        title: 'פיצ\'רים לפי שימוש',
        trailing: _csvButton(
          context,
          'features',
          () => toCsv(
            <String>[
              'feature',
              'users',
              'uses',
              'per_user',
              'share_of_active',
              'success_rate',
              'users_change',
              'uses_change',
            ],
            <List<Object?>>[
              for (final Json f in features)
                <Object?>[
                  f['id'],
                  f['users'],
                  f['uses'],
                  f['perUser'],
                  f['share'],
                  f['successRate'],
                  f['usersChange'],
                  f['usesChange'],
                ],
            ],
          ),
        ),
        children: <Widget>[
          _Table(
            rows: features,
            sortKey: 'users',
            searchKeys: const <String>['name', 'id'],
            columns: <_Column>[
              _Column(
                'פיצ\'ר',
                'name',
                (Json f) => '${f['name']}',
                numeric: false,
              ),
              _Column('משתמשים', 'users', (Json f) => _f(f, 'users')),
              _Column('שימושים', 'uses', (Json f) => _f(f, 'uses')),
              _Column('למשתמש', 'perUser', (Json f) => '${f['perUser'] ?? 0}'),
              _Column(
                '% מהפעילים',
                'share',
                (Json f) => MonitoringFormat.percent(f['share']),
              ),
              _Column(
                'שינוי',
                'usesChange',
                (Json f) => MonitoringFormat.change(f['usesChange']),
              ),
              _Column(
                'הצלחה',
                'successRate',
                (Json f) => MonitoringFormat.percent(f['successRate']),
              ),
            ],
          ),
        ],
      ),
      for (final Json funnel in funnels)
        _Card(
          title: 'משפך: ${funnel['title']}',
          children: <Widget>[
            for (final Json step in _list(funnel['steps']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(flex: 3, child: Text('${step['label']}')),
                    Expanded(
                      flex: 4,
                      child: LinearProgressIndicator(
                        value: (() {
                          final num first = MonitoringFormat.n(
                            _list(funnel['steps']).first['users'],
                          );
                          return first > 0
                              ? MonitoringFormat.n(step['users']) / first
                              : 0.0;
                        })().toDouble(),
                        minHeight: 8,
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(
                        '${_f(step, 'users')}${step['fromPrevious'] == null ? '' : ' · ${MonitoringFormat.percent(step['fromPrevious'])}'}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      _Card(
        title: 'פעולות (השלמה וכשל)',
        children: <Widget>[
          _Table(
            rows: <Json>[
              for (final Json a in actions)
                <String, dynamic>{
                  ...a,
                  'name':
                      '${names[a['feature']] ?? a['feature']} · ${a['action']}',
                },
            ],
            sortKey: 'users',
            searchKeys: const <String>['name'],
            columns: <_Column>[
              _Column(
                'פעולה',
                'name',
                (Json a) => '${a['name']}',
                numeric: false,
              ),
              _Column('משתמשים', 'users', (Json a) => _f(a, 'users')),
              _Column('התחילו', 'started', (Json a) => _f(a, 'started')),
              _Column('הושלמו', 'completed', (Json a) => _f(a, 'completed')),
              _Column('נכשלו', 'failed', (Json a) => _f(a, 'failed')),
              _Column(
                'הצלחה',
                'successRate',
                (Json a) => MonitoringFormat.percent(a['successRate']),
              ),
            ],
          ),
        ],
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// AI

class _AiTab extends StatelessWidget {
  const _AiTab({required this.data, required this.period});

  final Json data;
  final MonitoringPeriod period;

  @override
  Widget build(BuildContext context) {
    final Json ai = _map(data['ai']);
    final List<Json> byFeature = _list(ai['byFeature']);
    final List<Json> byUser = _list(ai['byUser']);
    final num tokens =
        MonitoringFormat.n(ai['inputTokens']) +
        MonitoringFormat.n(ai['outputTokens']);
    final num prev = MonitoringFormat.n(ai['prevIls']);
    final num now = MonitoringFormat.n(ai['ils']);
    return _page(<Widget>[
      _Card(
        title: 'AI · ${period.label}',
        children: <Widget>[
          _wrap(<Widget>[
            _Kpi('קריאות', _f(ai, 'calls')),
            _Kpi('משתמשים', _f(ai, 'users')),
            _Kpi('הצליחו / נכשלו', '${_f(ai, 'ok')} / ${_f(ai, 'failed')}'),
            _Kpi('ניסיונות חוזרים', _f(ai, 'retries')),
            _Kpi('זמן תגובה ממוצע', MonitoringFormat.ms(ai['avgLatencyMs'])),
            _Kpi('Input tokens', _f(ai, 'inputTokens')),
            _Kpi('Output tokens', _f(ai, 'outputTokens')),
            _Kpi('Total tokens', MonitoringFormat.count(tokens)),
            _Kpi(
              'עלות',
              MonitoringFormat.ils(now),
              change: prev > 0 ? ((now - prev) / prev * 100) : null,
            ),
          ]),
          Text(
            'ה־Tokens מדווחים על ידי ספק ה־AI עצמו; העלות מחושבת לפי גרסת המחירון שהייתה בתוקף בזמן כל קריאה '
            '(${_map(ai['pricingVersions']).keys.join(', ')}). שינוי מחיר לא משנה עלויות עבר.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      _Card(
        title: 'לפי פיצ\'ר',
        trailing: _csvButton(
          context,
          'ai_features',
          () => toCsv(
            <String>[
              'feature',
              'calls',
              'users',
              'ok',
              'failed',
              'retries',
              'avg_latency_ms',
              'input_tokens',
              'output_tokens',
              'ils',
              'models',
            ],
            <List<Object?>>[
              for (final Json f in byFeature)
                <Object?>[
                  f['id'],
                  f['calls'],
                  f['users'],
                  f['ok'],
                  f['failed'],
                  f['retries'],
                  f['avgLatencyMs'],
                  f['inputTokens'],
                  f['outputTokens'],
                  f['ils'],
                  _map(f['models']).keys.join(' '),
                ],
            ],
          ),
        ),
        children: <Widget>[
          _Table(
            rows: byFeature,
            sortKey: 'ils',
            columns: <_Column>[
              _Column(
                'פיצ\'ר',
                'name',
                (Json f) => '${f['name']}',
                numeric: false,
              ),
              _Column('שימושים', 'calls', (Json f) => _f(f, 'calls')),
              _Column('משתמשים', 'users', (Json f) => _f(f, 'users')),
              _Column(
                'עלות',
                'ils',
                (Json f) => MonitoringFormat.ils(f['ils']),
              ),
              _Column('כשלים', 'failed', (Json f) => _f(f, 'failed')),
              _Column(
                'זמן',
                'avgLatencyMs',
                (Json f) => MonitoringFormat.ms(f['avgLatencyMs']),
              ),
              _Column(
                'מודל',
                'models',
                (Json f) => _map(f['models']).keys.join(', '),
                numeric: false,
              ),
            ],
          ),
        ],
      ),
      _Card(
        title: 'לפי משתמש',
        trailing: _csvButton(
          context,
          'ai_users',
          () => toCsv(
            <String>[
              'uid',
              'email',
              'calls',
              'tokens',
              'ils_period',
              'ils_total',
              'features',
              'times_average',
            ],
            <List<Object?>>[
              for (final Json u in byUser)
                <Object?>[
                  u['uid'],
                  u['email'],
                  u['calls'],
                  u['tokens'],
                  u['ils'],
                  u['totalIls'],
                  (u['features'] as List?)?.join(' '),
                  u['timesAverage'],
                ],
            ],
          ),
        ),
        children: <Widget>[
          _Table(
            rows: byUser,
            sortKey: 'ils',
            searchKeys: const <String>['email', 'uid'],
            onTap: (Json u) =>
                AdminUserAnalyticsScreen.open(context, '${u['uid']}', period),
            columns: <_Column>[
              _Column(
                'משתמש',
                'email',
                (Json u) => '${u['email'] ?? ''}'.isEmpty
                    ? '${u['uid']}'
                    : '${u['email']}',
                numeric: false,
              ),
              _Column('פעולות', 'calls', (Json u) => _f(u, 'calls')),
              _Column('Tokens', 'tokens', (Json u) => _f(u, 'tokens')),
              _Column(
                'בתקופה',
                'ils',
                (Json u) => MonitoringFormat.ils(u['ils']),
              ),
              _Column(
                'סה"כ',
                'totalIls',
                (Json u) => MonitoringFormat.ils(u['totalIls']),
              ),
              _Column(
                'פי הממוצע',
                'timesAverage',
                (Json u) =>
                    u['timesAverage'] == null ? '—' : '×${u['timesAverage']}',
              ),
              _Column(
                'פיצ\'רים',
                'features',
                (Json u) =>
                    ((u['features'] as List?) ?? const <Object?>[]).join(', '),
                numeric: false,
              ),
            ],
          ),
        ],
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// עלויות

class _CostsTab extends StatelessWidget {
  const _CostsTab({
    required this.data,
    required this.period,
    required this.onChanged,
  });

  final Json data;
  final MonitoringPeriod period;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final Json c = _map(data['costs']);
    final List<Json> breakdown = _list(c['breakdown']);
    final List<Json> users = _list(data['users']);
    final ThemeData theme = Theme.of(context);
    return _page(<Widget>[
      _Card(
        title: 'עלות · ${period.label}',
        trailing: const _Estimated(),
        children: <Widget>[
          _wrap(<Widget>[
            _Kpi(
              'סה"כ',
              MonitoringFormat.ils(c['totalIls']),
              change: c['totalChange'],
              note: 'משוער',
            ),
            _Kpi('AI', MonitoringFormat.ils(c['aiIls'])),
            _Kpi('תשתיות', MonitoringFormat.ils(c['infraIls']), note: 'משוער'),
          ]),
          _ActualBill(
            period: period,
            estimatedIls: MonitoringFormat.n(c['totalIls']),
          ),
        ],
      ),
      _Card(
        title: 'פירוט',
        trailing: _csvButton(
          context,
          'costs',
          () => toCsv(
            <String>['item', 'amount', 'unit', 'ils', 'estimated'],
            <List<Object?>>[
              for (final Json b in breakdown)
                <Object?>[
                  b['id'],
                  b['amount'],
                  b['unit'],
                  b['ils'],
                  b['estimated'],
                ],
            ],
          ),
        ),
        children: <Widget>[
          for (final Json b in breakdown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text('${b['label']}')),
                  Text(
                    b['unit'] == 'bytes'
                        ? MonitoringFormat.bytes(b['amount'])
                        : '${_f(b, 'amount')} ${b['unit'] ?? ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      b['note'] != null
                          ? '${b['note']}'
                          : MonitoringFormat.ils(b['ils']),
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (b['estimated'] == true)
                    const _Estimated()
                  else
                    const SizedBox(width: 52),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'AI — לפי ה־Tokens שהספק דיווח ומחירון פנימי. כל השאר — לפי מונים שהאפליקציה סופרת לכל משתמש '
            '(קריאות/כתיבות, העלאות והורדות, קריאות Backend, נפח תמונות והקלטות) כפול המחירון: הערכה, '
            'לא חשבונית. החיוב בפועל — בדוח החיוב של Google Cloud.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      _Card(
        title: 'מדדים עסקיים',
        trailing: const _Estimated(),
        children: <Widget>[
          _wrap(<Widget>[
            _Kpi('למשתמש פעיל', MonitoringFormat.ils(c['perActiveUserIls'])),
            _Kpi(
              'למשתמש רשום',
              MonitoringFormat.ils(c['perRegisteredUserIls']),
            ),
            _Kpi('AI למשתמש AI', MonitoringFormat.ils(c['aiPerAiUserIls'])),
            _Kpi(
              'לרעיון שנפתח',
              c['perIdeaIls'] == null
                  ? '—'
                  : MonitoringFormat.ils(c['perIdeaIls']),
            ),
            _Kpi(
              'לזוג שיצא',
              c['perCoupleIls'] == null
                  ? '—'
                  : MonitoringFormat.ils(c['perCoupleIls']),
            ),
            _Kpi(
              'למשתמש חדש',
              c['perNewUserIls'] == null
                  ? '—'
                  : MonitoringFormat.ils(c['perNewUserIls']),
            ),
          ]),
        ],
      ),
      _Card(
        title: 'המשתמשים היקרים ביותר',
        children: <Widget>[
          _Table(
            rows: users,
            sortKey: 'totalIls',
            limit: 15,
            searchKeys: const <String>['email', 'uid'],
            onTap: (Json u) =>
                AdminUserAnalyticsScreen.open(context, '${u['uid']}', period),
            columns: <_Column>[
              _Column(
                'משתמש',
                'email',
                (Json u) => '${u['email'] ?? ''}'.isEmpty
                    ? '${u['uid']}'
                    : '${u['email']}',
                numeric: false,
              ),
              _Column(
                'AI',
                'aiIls',
                (Json u) => MonitoringFormat.ils(u['aiIls']),
              ),
              _Column(
                'תשתיות*',
                'infraIls',
                (Json u) => MonitoringFormat.ils(u['infraIls']),
              ),
              _Column(
                'בתקופה*',
                'totalIls',
                (Json u) => MonitoringFormat.ils(u['totalIls']),
              ),
              _Column(
                'מצטבר*',
                'cumulativeIls',
                (Json u) => MonitoringFormat.ils(u['cumulativeIls']),
              ),
              _Column('העלאות', 'uploads', (Json u) => _f(u, 'uploads')),
              _Column('Backend', 'backend', (Json u) => _f(u, 'backend')),
            ],
          ),
        ],
      ),
      _PricingCard(onChanged: onChanged),
      _ThresholdsCard(),
    ]);
  }
}

/// The actual bill for a calendar month, typed in from Google Cloud billing,
/// shown beside the estimate.
class _ActualBill extends StatefulWidget {
  const _ActualBill({required this.period, required this.estimatedIls});

  final MonitoringPeriod period;
  final num estimatedIls;

  @override
  State<_ActualBill> createState() => _ActualBillState();
}

class _ActualBillState extends State<_ActualBill> {
  static final DocumentReference<Map<String, dynamic>> _doc = FirebaseFirestore
      .instance
      .doc('adminConfig/billing');
  Json _months = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> s = await _doc.get();
      if (mounted) setState(() => _months = _map(s.data()?['months']));
    } catch (_) {}
  }

  Future<void> _edit(String month) async {
    final TextEditingController amount = TextEditingController(
      text: '${_map(_months[month])['ils'] ?? ''}',
    );
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('חיוב בפועל · $month'),
        content: TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'סכום החשבון מ־Google Cloud (₪)',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('שמירה'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final Json next = <String, dynamic>{
      ..._months,
      month: <String, dynamic>{'ils': double.tryParse(amount.text) ?? 0},
    };
    try {
      await _doc.set(<String, dynamic>{
        'months': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() => _months = next);
    } catch (_) {
      if (mounted) AppNotice.show(context, 'לא נשמר');
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? month = widget.period.monthKey;
    if (month == null) {
      return Text(
        'עלות בפועל מוצגת כשבוחרים חודש קלנדרי.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final Object? actual = _map(_months[month])['ils'];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        actual == null
            ? 'חיוב בפועל: לא הוזן'
            : 'חיוב בפועל: ${MonitoringFormat.ils(actual)}',
      ),
      subtitle: actual == null
          ? const Text('מתוך דוח החיוב של Google Cloud — להשוואה מול ההערכה')
          : Text('הערכה: ${MonitoringFormat.ils(widget.estimatedIls)}'),
      trailing: TextButton(
        onPressed: () => _edit(month),
        child: const Text('עדכון'),
      ),
    );
  }
}

/// The pricing table, as versions. A change adds a version in force from now;
/// past calls keep the version they were priced with.
class _PricingCard extends StatefulWidget {
  const _PricingCard({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_PricingCard> createState() => _PricingCardState();
}

class _PricingCardState extends State<_PricingCard> {
  static final DocumentReference<Map<String, dynamic>> _doc = FirebaseFirestore
      .instance
      .doc('adminConfig/pricing');
  List<Json> _versions = <Json>[];

  static const Map<String, String> _fields = <String, String>{
    'usdToIls': 'שער דולר',
    'aiIn': 'AI — \$ למיליון טוקנים נכנסים',
    'aiOut': 'AI — \$ למיליון טוקנים יוצאים',
    'readsPer100k': 'Firestore — \$ ל־100K קריאות',
    'writesPer100k': 'Firestore — \$ ל־100K כתיבות',
    'deletesPer100k': 'Firestore — \$ ל־100K מחיקות',
    'storageGbMonth': 'אחסון — \$ ל־GB לחודש',
    'egressGb': 'תעבורה — \$ ל־GB',
    'fnPerMillion': 'Functions — \$ למיליון קריאות',
  };

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> s = await _doc.get();
      if (mounted) setState(() => _versions = _list(s.data()?['versions']));
    } catch (_) {}
  }

  Future<void> _addVersion() async {
    final Json current = _versions.isEmpty
        ? <String, dynamic>{'usdToIls': 3.7}
        : _versions.last;
    final Map<String, TextEditingController> c =
        <String, TextEditingController>{
          for (final String k in _fields.keys)
            k: TextEditingController(text: '${current[k] ?? 0}'),
        };
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('גרסת מחירון חדשה'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'בתוקף מעכשיו. עלויות עבר נשארות לפי הגרסה שבה חושבו. המחירים מתוך המחירון של Google Cloud.',
            ),
            for (final MapEntry<String, String> f in _fields.entries)
              TextField(
                controller: c[f.key],
                decoration: InputDecoration(labelText: f.value),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('שמירה'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final Json version = <String, dynamic>{
      'id': 'v${_versions.length + 1}',
      'from': DateTime.now().millisecondsSinceEpoch,
      for (final String k in _fields.keys) k: double.tryParse(c[k]!.text) ?? 0,
    };
    try {
      await _doc.set(<String, dynamic>{
        'versions': <Json>[..._versions, version],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _read();
      widget.onChanged();
    } catch (_) {
      if (mounted) AppNotice.show(context, 'לא נשמר');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _Card(
      title: 'מחירון',
      trailing: TextButton(
        onPressed: _addVersion,
        child: const Text('גרסה חדשה'),
      ),
      children: <Widget>[
        if (_versions.isEmpty)
          Text(
            'לא הוזנו מחירים — כל העלויות יחושבו כ־0.',
            style: theme.textTheme.bodySmall,
          ),
        for (final Json v in _versions.reversed)
          Text(
            '${v['id']} · מ־${DateTime.fromMillisecondsSinceEpoch(MonitoringFormat.n(v['from']).toInt()).toString().substring(0, 16)} · '
            'AI \$${v['aiIn']}/\$${v['aiOut']} · אחסון \$${v['storageGbMonth']}/GB · ₪/\$ ${v['usdToIls']}',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// Internal thresholds; crossing one notifies every administrator (checked
/// hourly by `checkAnalyticsThresholds`).
class _ThresholdsCard extends StatefulWidget {
  @override
  State<_ThresholdsCard> createState() => _ThresholdsCardState();
}

class _ThresholdsCardState extends State<_ThresholdsCard> {
  static final DocumentReference<Map<String, dynamic>> _doc = FirebaseFirestore
      .instance
      .doc('adminConfig/thresholds');
  static const Map<String, String> _fields = <String, String>{
    'aiDailyIls': 'עלות AI יומית מעל (₪)',
    'userDailyIls': 'משתמש בודד ביום מעל (₪)',
    'featureSpikeFactor': 'קפיצה בשימוש בפיצ\'ר — פי (מול ממוצע שבועי)',
    'errorRatePercent': 'שיעור כשלים מעל (%)',
  };
  final Map<String, TextEditingController> _c = <String, TextEditingController>{
    for (final String k in _fields.keys) k: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _doc
        .get()
        .then((DocumentSnapshot<Map<String, dynamic>> s) {
          final Json d = s.data() ?? <String, dynamic>{};
          if (!mounted) return;
          setState(() {
            for (final String k in _fields.keys) {
              _c[k]!.text = '${d[k] ?? 0}';
            }
          });
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    for (final TextEditingController c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await _doc.set(<String, dynamic>{
        for (final String k in _fields.keys)
          k: double.tryParse(_c[k]!.text) ?? 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) AppNotice.show(context, 'הספים נשמרו');
    } catch (_) {
      if (mounted) AppNotice.show(context, 'לא נשמר');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'ספים והתראות',
      trailing: TextButton(onPressed: _save, child: const Text('שמירה')),
      children: <Widget>[
        Text(
          '0 = כבוי. נבדק כל שעה; מעבר סף שולח התראה לכל המנהלים, פעם ביום לכל חריגה.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final MapEntry<String, String> f in _fields.entries)
          TextField(
            controller: _c[f.key],
            decoration: InputDecoration(labelText: f.value, isDense: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// תקלות

class _ErrorsTab extends StatelessWidget {
  const _ErrorsTab({
    required this.data,
    required this.period,
    required this.release,
    required this.onRelease,
  });

  final Json data;
  final MonitoringPeriod period;
  final String? release;
  final ValueChanged<String?> onRelease;

  @override
  Widget build(BuildContext context) {
    final List<Json> errors = _list(data['errors']);
    final List<Json> perf = _list(data['performance']);
    final List<Json> versions = _list(data['versions']);
    final List<Json> known = _list(data['knownVersions']);
    final Json? rel = data['release'] is Map ? _map(data['release']) : null;
    const Map<String, String> metrics = <String, String>{
      'app~start': 'פתיחת האפליקציה',
      'home~load': 'טעינת הבית',
      'people~load': 'טעינת המאגר',
      'card_open~load': 'פתיחת כרטיס',
      'chats~load': 'טעינת צ\'אט',
      'ai~latency': 'זמן תגובת AI',
    };
    return _page(<Widget>[
      _Card(
        title: 'תקלות · ${period.label}',
        trailing: _csvButton(
          context,
          'errors',
          () => toCsv(
            <String>[
              'feature',
              'code',
              'users',
              'count',
              'version',
              'platform',
              'last',
              'avg_ms',
            ],
            <List<Object?>>[
              for (final Json e in errors)
                <Object?>[
                  e['feature'],
                  e['code'],
                  e['users'],
                  e['count'],
                  e['version'],
                  e['platform'],
                  DateTime.fromMillisecondsSinceEpoch(
                    MonitoringFormat.n(e['last']).toInt(),
                  ).toIso8601String(),
                  e['avgMs'],
                ],
            ],
          ),
        ),
        children: <Widget>[
          _wrap(<Widget>[
            _Kpi('בקשות שנכשלו', _f(data, 'failedRequests')),
            _Kpi('Timeouts', _f(data, 'timeouts')),
          ]),
          _Table(
            rows: errors,
            sortKey: 'users',
            searchKeys: const <String>['name', 'code', 'version'],
            columns: <_Column>[
              _Column(
                'מסך/פיצ\'ר',
                'name',
                (Json e) => '${e['name']}',
                numeric: false,
              ),
              _Column(
                'סוג',
                'code',
                (Json e) => '${e['code']}',
                numeric: false,
              ),
              _Column('משתמשים', 'users', (Json e) => _f(e, 'users')),
              _Column('מופעים', 'count', (Json e) => _f(e, 'count')),
              _Column(
                'גרסה',
                'version',
                (Json e) => '${e['version']}',
                numeric: false,
              ),
              _Column(
                'פלטפורמה',
                'platform',
                (Json e) => '${e['platform']}',
                numeric: false,
              ),
              _Column('אחרון', 'last', (Json e) {
                final DateTime t = DateTime.fromMillisecondsSinceEpoch(
                  MonitoringFormat.n(e['last']).toInt(),
                );
                return '${t.day}.${t.month} ${t.hour}:${t.minute.toString().padLeft(2, '0')}';
              }),
              _Column(
                'זמן',
                'avgMs',
                (Json e) => MonitoringFormat.ms(e['avgMs']),
              ),
            ],
          ),
        ],
      ),
      _Card(
        title: 'ביצועים',
        children: <Widget>[
          _Table(
            rows: <Json>[
              for (final Json p in perf)
                <String, dynamic>{
                  ...p,
                  'name': metrics[p['metric']] ?? '${p['metric']}',
                },
            ],
            sortKey: 'count',
            columns: <_Column>[
              _Column(
                'מדד',
                'name',
                (Json p) => '${p['name']}',
                numeric: false,
              ),
              _Column('מדידות', 'count', (Json p) => _f(p, 'count')),
              _Column(
                'ממוצע',
                'avgMs',
                (Json p) => MonitoringFormat.ms(p['avgMs']),
              ),
              _Column(
                'מקסימום',
                'maxMs',
                (Json p) => MonitoringFormat.ms(p['maxMs']),
              ),
              _Column(
                'איטיים (2ש׳+)',
                'slowShare',
                (Json p) => MonitoringFormat.percent(p['slowShare']),
              ),
            ],
          ),
        ],
      ),
      _Card(
        title: 'לפי גרסת אפליקציה',
        children: <Widget>[
          _Table(
            rows: versions,
            sortKey: 'users',
            columns: <_Column>[
              _Column(
                'גרסה',
                'version',
                (Json v) => '${v['version']}',
                numeric: false,
              ),
              _Column('משתמשים', 'users', (Json v) => _f(v, 'users')),
              _Column('Sessions', 'sessions', (Json v) => _f(v, 'sessions')),
              _Column(
                'Session (דק׳)',
                'avgSessionMin',
                (Json v) => '${v['avgSessionMin']}',
              ),
              _Column(
                'שגיאות למשתמש',
                'errorsPerUser',
                (Json v) => '${v['errorsPerUser']}',
              ),
              _Column(
                'כשלים',
                'failRate',
                (Json v) => MonitoringFormat.percent(v['failRate']),
              ),
              _Column(
                'פתיחה',
                'avgStartMs',
                (Json v) => MonitoringFormat.ms(v['avgStartMs']),
              ),
            ],
          ),
        ],
      ),
      _Card(
        title: 'לפני / אחרי שחרור גרסה',
        children: <Widget>[
          Wrap(
            spacing: 6,
            children: <Widget>[
              for (final Json v in known.take(6))
                ChoiceChip(
                  label: Text('${v['version']}'),
                  selected: release == v['version'],
                  onSelected: (bool on) =>
                      onRelease(on ? '${v['version']}' : null),
                ),
            ],
          ),
          if (rel != null) _ReleaseCompare(rel),
          if (rel == null)
            Text(
              'בחרו גרסה: שבוע לפני שהופיעה מול השבוע שאחרי.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    ]);
  }
}

class _ReleaseCompare extends StatelessWidget {
  const _ReleaseCompare(this.rel);

  final Json rel;

  @override
  Widget build(BuildContext context) {
    final Json b = _map(rel['before']);
    final Json a = _map(rel['after']);
    Widget row(String label, String key, String Function(Object?) f) => Row(
      children: <Widget>[
        Expanded(child: Text(label)),
        SizedBox(width: 80, child: Text(f(b[key]), textAlign: TextAlign.end)),
        SizedBox(
          width: 80,
          child: Text(
            f(a[key]),
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('גרסה ${rel['version']} · מ־${rel['firstDay']}'),
              ),
              const SizedBox(
                width: 80,
                child: Text('לפני', textAlign: TextAlign.end),
              ),
              const SizedBox(
                width: 80,
                child: Text('אחרי', textAlign: TextAlign.end),
              ),
            ],
          ),
          row('משתמשים פעילים', 'activeUsers', MonitoringFormat.count),
          row('DAU', 'dau', MonitoringFormat.count),
          row('Sessions', 'sessions', MonitoringFormat.count),
          row('Session (דק׳)', 'avgSessionMin', (Object? v) => '${v ?? 0}'),
          row('רעיונות', 'ideas', MonitoringFormat.count),
          row('שגיאות', 'errors', MonitoringFormat.count),
          row('שיעור כשלים', 'failRate', MonitoringFormat.percent),
          row('זמן פתיחה', 'avgStartMs', MonitoringFormat.ms),
          row('Retention יום 1', 'retentionD1', MonitoringFormat.percent),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Drill-down

/// One account in detail — administrators only (the callable checks).
class AdminUserAnalyticsScreen extends StatefulWidget {
  const AdminUserAnalyticsScreen({
    super.key,
    required this.uid,
    required this.period,
  });

  final String uid;
  final MonitoringPeriod period;

  static Future<void> open(
    BuildContext context,
    String uid,
    MonitoringPeriod period,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AdminUserAnalyticsScreen(uid: uid, period: period),
    ),
  );

  @override
  State<AdminUserAnalyticsScreen> createState() =>
      _AdminUserAnalyticsScreenState();
}

class _AdminUserAnalyticsScreenState extends State<AdminUserAnalyticsScreen> {
  Json? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _call('adminUserAnalytics', <String, dynamic>{
          'uid': widget.uid,
          'from': widget.period.fromKey,
          'to': widget.period.toKey,
        })
        .then((Json d) {
          if (mounted) setState(() => _data = d);
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = '$e');
        });
  }

  @override
  Widget build(BuildContext context) {
    final Json? d = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'משתמש' : '${d['email'] ?? widget.uid}'),
      ),
      body: d == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : _page(<Widget>[
              _Card(
                title: 'פרטים',
                children: <Widget>[
                  SelectableText('uid: ${widget.uid}'),
                  Text('נרשם: ${d['signedUp'] ?? '—'}'),
                  Text('פעילות אחרונה: ${d['lastActive'] ?? '—'}'),
                  Text(
                    'סוג: ${_typeName(d['userType'])} · ${d['platform'] ?? ''} · גרסה ${d['version'] ?? ''}',
                  ),
                ],
              ),
              _Card(
                title: 'שימוש · ${widget.period.label}',
                children: <Widget>[
                  _wrap(<Widget>[
                    _Kpi('ימים פעילים', _f(d, 'activeDays')),
                    _Kpi('Sessions', _f(d, 'sessions')),
                    _Kpi('Session ממוצע', '${d['avgSessionMin'] ?? 0} דק׳'),
                    _Kpi(
                      'חברים במאגר',
                      d['friends'] == null ? '—' : _f(d, 'friends'),
                    ),
                    _Kpi('רעיונות', d['ideas'] == null ? '—' : _f(d, 'ideas')),
                    _Kpi('הודעות צ\'אט', _f(d, 'chatMessages')),
                    _Kpi('פעולות AI', _f(d, 'aiCalls')),
                    _Kpi(
                      'תמונות / הקלטות',
                      '${d['photos'] ?? '—'} / ${d['voice'] ?? '—'}',
                    ),
                    _Kpi('אחסון', MonitoringFormat.bytes(d['storageBytes'])),
                    _Kpi('העלאות', _f(d, 'uploads')),
                  ]),
                ],
              ),
              _Card(
                title: 'עלות',
                trailing: const _Estimated(),
                children: <Widget>[
                  _wrap(<Widget>[
                    _Kpi('AI', MonitoringFormat.ils(d['aiIls'])),
                    _Kpi(
                      'תשתיות',
                      MonitoringFormat.ils(d['infraIls']),
                      note: 'משוער',
                    ),
                    _Kpi(
                      'סה"כ בתקופה',
                      MonitoringFormat.ils(d['totalIls']),
                      note: 'משוער',
                    ),
                    _Kpi(
                      'מצטבר',
                      d['cumulativeIls'] == null
                          ? '—'
                          : MonitoringFormat.ils(d['cumulativeIls']),
                      note: 'משוער',
                    ),
                  ]),
                ],
              ),
              _Card(
                title: 'פיצ\'רים שבהם השתמש',
                children: <Widget>[
                  for (final Json f in _list(d['features']))
                    Row(
                      children: <Widget>[
                        Expanded(child: Text('${f['id']}')),
                        Text(_f(f, 'uses')),
                      ],
                    ),
                ],
              ),
              _Card(
                title: 'לפי יום',
                children: <Widget>[
                  _Bars(<num>[
                    for (final Json x in _list(d['days']))
                      MonitoringFormat.n(x['events']),
                  ]),
                ],
              ),
            ]),
    );
  }
}
