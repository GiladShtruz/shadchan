import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/services/couple_workspace_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:url_launcher/url_launcher.dart';

/// "נתונים" in the support console — the administrators' dashboard.
///
/// Everything here is a count the server computed (`functions/src/
/// admin_stats.ts`), every three hours or on "רענון עכשיו". Nothing on this
/// screen can name anybody: there is no list of users, no drill-down, no
/// number, only figures and how they moved. Funnels, retention and cohorts
/// are the Firebase console's own reports, one tap away at the foot.
class AdminStatsTab extends StatefulWidget {
  const AdminStatsTab({super.key});

  static const String consoleUrl =
      'https://console.firebase.google.com/project/shadchan-gilad/analytics';

  @override
  State<AdminStatsTab> createState() => _AdminStatsTabState();
}

enum _Window { today, week, month, all }

class _AdminStatsTabState extends State<AdminStatsTab> {
  Map<String, dynamic>? _current;

  /// Daily snapshots, oldest first — the trends and the week-on-week change.
  List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  _Window _window = _Window.week;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      final DocumentSnapshot<Map<String, dynamic>> current = await db
          .doc('adminStats/current')
          .get();
      final QuerySnapshot<Map<String, dynamic>> days = await db
          .collection('adminStats/history/days')
          .orderBy(FieldPath.documentId, descending: true)
          .limit(90)
          .get();
      if (!mounted) return;
      setState(() {
        _current = current.data();
        _history = days.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                  <String, dynamic>{...d.data(), 'day': d.id},
            )
            .toList()
            .reversed
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'לא הצלחנו לטעון את הנתונים.';
      });
    }
  }

  Future<void> _refreshNow() async {
    final OverlayState? notices = AppNotice.capture(context);
    setState(() => _refreshing = true);
    try {
      await CoupleWorkspaceService.call('refreshAdminStatsNow');
      await _load();
      AppNotice.showOn(notices, 'הנתונים עודכנו');
    } catch (_) {
      AppNotice.showOn(notices, 'הרענון נכשל. הנתונים יתעדכנו בעדכון הבא.');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _exportCsv(Rect? origin) async {
    final OverlayState? notices = AppNotice.capture(context);
    try {
      final String csv = AdminStatsCsv.build(_history);
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/shadchan_stats.csv');
      // A byte-order mark so Excel reads the Hebrew headers as UTF-8.
      await file.writeAsString('﻿$csv');
      await Share.shareXFiles(<XFile>[
        XFile(file.path, mimeType: 'text/csv'),
      ], sharePositionOrigin: origin);
    } catch (_) {
      AppNotice.showOn(notices, 'הייצוא נכשל');
    }
  }

  num _n(String block, String key) {
    final Object? section = _current?[block];
    if (section is Map) {
      final Object? value = section[key];
      if (value is num) return value;
    }
    return 0;
  }

  /// The same figure a week ago, from the daily snapshots.
  num? _weekAgo(String block, String key) {
    if (_history.length < 2) return null;
    final DateTime target = DateTime.now().subtract(const Duration(days: 7));
    Map<String, dynamic>? best;
    for (final Map<String, dynamic> day in _history) {
      final DateTime? when = DateTime.tryParse(day['day'] as String? ?? '');
      if (when != null && !when.isAfter(target)) best = day;
    }
    final Object? section = best?[block];
    if (section is Map && section[key] is num) return section[key] as num;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('לנסות שוב')),
          ],
        ),
      );
    }
    if (_current == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'עוד אין נתונים. הם מחושבים בשרת כל שלוש שעות.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _refreshing ? null : _refreshNow,
                child: const Text('לחשב עכשיו'),
              ),
            ],
          ),
        ),
      );
    }

    final int computed = (_current!['computedAt'] as num?)?.toInt() ?? 0;
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(computed);
    final String when =
        '${at.day}.${at.month} ${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'עודכן: $when',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _refreshing ? null : _refreshNow,
                icon: _refreshing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('רענון עכשיו'),
              ),
            ],
          ),
          SegmentedButton<_Window>(
            segments: const <ButtonSegment<_Window>>[
              ButtonSegment<_Window>(value: _Window.today, label: Text('היום')),
              ButtonSegment<_Window>(
                value: _Window.week,
                label: Text('7 ימים'),
              ),
              ButtonSegment<_Window>(
                value: _Window.month,
                label: Text('30 ימים'),
              ),
              ButtonSegment<_Window>(value: _Window.all, label: Text('הכל')),
            ],
            selected: <_Window>{_window},
            showSelectedIcon: false,
            onSelectionChanged: (Set<_Window> s) =>
                setState(() => _window = s.first),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'מדדי ליבה',
            accent: AppColors.primaryDark,
            children: _coreTiles(),
          ),
          _Section(
            title: 'השבוע בשדכן',
            accent: AppColors.secondary,
            children: <Widget>[
              _Tile(
                'משתמשים חדשים',
                _n('users', 'new7'),
                previous: _n('users', 'newPrev7'),
              ),
              _Tile('כרטיסים חדשים שהושלמו', _n('singles', 'newActive7')),
              _Tile('קשרי אמון חדשים', _n('access', 'newApprovals7')),
              _Tile('רעיונות חדשים', _n('ideas', 'newWeek')),
              _Tile('זוגות שהתחילו לצאת', _n('ideas', 'datingWeek')),
              _Tile(
                'פעילים השבוע (WAU)',
                _n('activity', 'wau'),
                previous: _n('activity', 'wauPrev'),
              ),
            ],
          ),
          _Section(
            title: 'רווקים וכרטיסים אישיים',
            accent: AppColors.femaleAccent,
            children: <Widget>[
              _Tile(
                'התחילו כרטיס',
                _n('singles', 'cardsStarted'),
                previous: _weekAgo('singles', 'cardsStarted'),
              ),
              _Tile(
                'כרטיסים פעילים',
                _n('singles', 'cardsActive'),
                previous: _weekAgo('singles', 'cardsActive'),
              ),
              _Tile('קיבלו בקשת גישה', _n('singles', 'gotRequest')),
              _Tile('אישרו שדכן אחד לפחות', _n('singles', 'approvedOne')),
              _Tile('אישרו 2 ומעלה', _n('singles', 'approvedTwoPlus')),
            ],
          ),
          _Section(
            title: 'גישה וקשרי אמון',
            accent: AppColors.primary,
            children: <Widget>[
              _Tile(
                'קשרי אמון פעילים',
                _n('access', 'trustLinks'),
                previous: _weekAgo('access', 'trustLinks'),
              ),
              _Tile('בקשות ממתינות', _n('access', 'pending')),
              _Tile('בקשות חדשות (7 ימים)', _n('access', 'newRequests7')),
              _Tile(
                'שדכנים מורשים לרווק (ממוצע)',
                _n('access', 'avgMatchmakersPerSingle'),
              ),
              _Tile(
                'כרטיסים עם גישה למאגר (ממוצע)',
                _n('access', 'avgCardsPerDatabase'),
              ),
            ],
          ),
          _Section(
            title: 'רעיונות',
            accent: AppColors.secondary,
            children: <Widget>[
              _Tile('רעיונות (כל הזמנים)', _n('ideas', 'ideasAll')),
              _Tile('זוגות שיצאו (כל הזמנים)', _n('ideas', 'datingAll')),
              _Tile(
                'אחוז רעיונות שהגיעו ליציאה',
                _n('ideas', 'datingPercent'),
                suffix: '%',
              ),
              _Tile('חתונות (כל הזמנים)', _n('ideas', 'weddingsAll')),
            ],
          ),
          _Section(
            title: 'צמיחת מאגרים',
            accent: AppColors.primaryDark,
            children: <Widget>[
              _Tile('מאגרים', _n('databases', 'count')),
              _Tile('ממוצע חברים', _n('databases', 'average')),
              _Tile('חציון חברים', _n('databases', 'median')),
              _Tile('הגיעו ל־5 חברים', _n('databases', 'reached5')),
              _Tile('הגיעו ל־10 חברים', _n('databases', 'reached10')),
              _Buckets(
                values: <String, num>{
                  '1–4': _n('databases', 'b1_4'),
                  '5–9': _n('databases', 'b5_9'),
                  '10–24': _n('databases', 'b10_24'),
                  '25–49': _n('databases', 'b25_49'),
                  '50+': _n('databases', 'b50plus'),
                },
              ),
            ],
          ),
          if (_history.length >= 2)
            _Section(
              title: 'מגמות (90 ימים)',
              accent: AppColors.primary,
              children: <Widget>[
                _Trend('משתמשים', _series('users', 'total')),
                _Trend('פעילים בשבוע', _series('activity', 'wau')),
                _Trend('כרטיסים פעילים', _series('singles', 'cardsActive')),
                _Trend('קשרי אמון', _series('access', 'trustLinks')),
              ],
            ),
          const SizedBox(height: 8),
          Builder(
            builder: (BuildContext context) => OutlinedButton.icon(
              onPressed: _history.isEmpty
                  ? null
                  : () {
                      final RenderBox? box =
                          context.findRenderObject() as RenderBox?;
                      _exportCsv(
                        box == null
                            ? null
                            : box.localToGlobal(Offset.zero) & box.size,
                      );
                    },
              icon: const Icon(Icons.download_rounded),
              label: const Text('ייצוא המדדים ל־CSV'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(AdminStatsTab.consoleUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.insights_outlined),
            label: const Text('משפכים, חזרת משתמשים וקבוצות — ב־Firebase'),
          ),
          const SizedBox(height: 12),
          Text(
            'כל המספרים כאן הם ספירות בלבד, בלי שמות ובלי פרטים. חשבונות מנהלים '
            'אינם נספרים (${_n('users', 'internalExcluded')} הוחרגו).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _coreTiles() {
    switch (_window) {
      case _Window.today:
        return <Widget>[
          _Tile('משתמשים חדשים', _n('users', 'newToday')),
          _Tile('פעילים היום', _n('activity', 'dau')),
          _Tile('כרטיסים פעילים', _n('singles', 'cardsActive')),
          _Tile('קשרי אמון פעילים', _n('access', 'trustLinks')),
        ];
      case _Window.week:
        return <Widget>[
          _Tile(
            'משתמשים חדשים',
            _n('users', 'new7'),
            previous: _n('users', 'newPrev7'),
          ),
          _Tile(
            'משתמשים פעילים',
            _n('activity', 'wau'),
            previous: _n('activity', 'wauPrev'),
          ),
          _Tile('שדכנים פעילים', _n('activity', 'activeMatchmakersWeek')),
          _Tile(
            'רווקים עם כרטיס פעיל',
            _n('singles', 'cardsActive'),
            previous: _weekAgo('singles', 'cardsActive'),
          ),
          _Tile('בקשות גישה', _n('access', 'newRequests7')),
          _Tile('אישורי גישה', _n('access', 'newApprovals7')),
          _Tile('רעיונות חדשים', _n('ideas', 'newWeek')),
          _Tile('זוגות שהתחילו לצאת', _n('ideas', 'datingWeek')),
        ];
      case _Window.month:
        return <Widget>[
          _Tile(
            'משתמשים חדשים',
            _n('users', 'new30'),
            previous: _n('users', 'newPrev30'),
          ),
          _Tile('משתמשים פעילים (MAU)', _n('activity', 'mau')),
          _Tile('WAU / MAU', _n('activity', 'wauMauPercent'), suffix: '%'),
          _Tile(
            'שדכנים פעילים בחודש',
            _n('activity', 'activeMatchmakersMonth'),
          ),
          _Tile('רעיונות חדשים', _n('ideas', 'newMonth')),
          _Tile('זוגות שהתחילו לצאת', _n('ideas', 'datingMonth')),
          _Tile('חתונות', _n('ideas', 'weddingsMonth')),
        ];
      case _Window.all:
        return <Widget>[
          _Tile(
            'משתמשים',
            _n('users', 'total'),
            previous: _weekAgo('users', 'total'),
          ),
          _Tile('רווקים עם כרטיס פעיל', _n('singles', 'cardsActive')),
          _Tile('קשרי אמון פעילים', _n('access', 'trustLinks')),
          _Tile('רעיונות', _n('ideas', 'ideasAll')),
          _Tile('זוגות שיצאו', _n('ideas', 'datingAll')),
          _Tile('חתונות', _n('ideas', 'weddingsAll')),
          _Tile('נקודות פעילות', _n('activity', 'pointsAll')),
        ];
    }
  }

  List<num> _series(String block, String key) => <num>[
    for (final Map<String, dynamic> day in _history)
      if (day[block] is Map && (day[block] as Map)[key] is num)
        (day[block] as Map)[key] as num,
  ];
}

/// The CSV the export writes: one row per day, counts only.
abstract final class AdminStatsCsv {
  static const List<(String, String, String)> columns =
      <(String, String, String)>[
        ('users', 'total', 'משתמשים'),
        ('users', 'new7', 'משתמשים חדשים 7 ימים'),
        ('activity', 'dau', 'פעילים ביום'),
        ('activity', 'wau', 'פעילים בשבוע'),
        ('activity', 'mau', 'פעילים בחודש'),
        ('activity', 'activeMatchmakersWeek', 'שדכנים פעילים בשבוע'),
        ('singles', 'cardsStarted', 'התחילו כרטיס'),
        ('singles', 'cardsActive', 'כרטיסים פעילים'),
        ('access', 'trustLinks', 'קשרי אמון'),
        ('access', 'pending', 'בקשות ממתינות'),
        ('ideas', 'newWeek', 'רעיונות השבוע'),
        ('ideas', 'datingWeek', 'יוצאים השבוע'),
        ('ideas', 'ideasAll', 'רעיונות כל הזמנים'),
        ('ideas', 'datingAll', 'יצאו כל הזמנים'),
        ('ideas', 'weddingsAll', 'חתונות כל הזמנים'),
        ('databases', 'count', 'מאגרים'),
        ('databases', 'average', 'ממוצע חברים למאגר'),
        ('databases', 'median', 'חציון חברים למאגר'),
      ];

  static String build(List<Map<String, dynamic>> days) {
    final StringBuffer out = StringBuffer()
      ..writeln(<String>['תאריך', for (final c in columns) c.$3].join(','));
    for (final Map<String, dynamic> day in days) {
      final List<String> row = <String>[day['day']?.toString() ?? ''];
      for (final (String block, String key, String _) in columns) {
        final Object? section = day[block];
        final Object? value = section is Map ? section[key] : null;
        row.add(value is num ? value.toString() : '');
      }
      out.writeln(row.join(','));
    }
    return out.toString();
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.accent,
    required this.children,
  });

  final String title;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HomePaperCard(
        stripe: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: children),
          ],
        ),
      ),
    );
  }
}

/// One figure, with its change against the previous period when known.
class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.previous, this.suffix = ''});

  final String label;
  final num value;
  final num? previous;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final num? before = previous;
    String? change;
    Color? changeColor;
    if (before != null && before > 0) {
      final double pct = (value - before) / before * 100;
      change = '${pct >= 0 ? '+' : ''}${pct.round()}%';
      changeColor = pct >= 0
          ? AppColors.statusMarried
          : theme.colorScheme.error;
    }
    final String shown = value is int || value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return Container(
      width: 150,
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
            '$shown$suffix',
            textDirection: TextDirection.ltr,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall, maxLines: 2),
          if (change != null)
            Text(
              '$change מול התקופה הקודמת',
              style: theme.textTheme.labelSmall?.copyWith(color: changeColor),
            ),
        ],
      ),
    );
  }
}

class _Buckets extends StatelessWidget {
  const _Buckets({required this.values});

  final Map<String, num> values;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final num most = values.values.fold<num>(
      0,
      (num a, num b) => a > b ? a : b,
    );
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final MapEntry<String, num> e in values.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 48,
                    child: Text(
                      e.key,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: most == 0 ? 0 : e.value / most,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${e.value.round()}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A small line of one figure over the daily snapshots.
class _Trend extends StatelessWidget {
  const _Trend(this.label, this.values);

  final String label;
  final List<num> values;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: SizedBox(
              height: 36,
              child: CustomPaint(
                painter: _SparkPainter(values, theme.colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            values.isEmpty ? '—' : '${values.last.round()}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<num> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final double lo = values.reduce((num a, num b) => a < b ? a : b).toDouble();
    final double hi = values.reduce((num a, num b) => a > b ? a : b).toDouble();
    final double span = hi - lo == 0 ? 1 : hi - lo;
    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      // Oldest on the right, newest on the left — the page reads right to left.
      final double x = size.width - size.width * i / (values.length - 1);
      final double y = size.height - (values[i] - lo) / span * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values;
}
