import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadchan/services/account_health_service.dart';

/// The support console's "חשבונות" tab: find an account by its address or
/// user ID, and read how its sync is doing on each of its devices.
///
/// Only what a technical answer needs is shown — identity, ways in, whether
/// the move into the account was verified, record counts, last sync and the
/// sync log's error codes. No record of anybody in the database is ever
/// reachable from here; the report never contains one.
class AccountHealthLookup extends StatefulWidget {
  const AccountHealthLookup({super.key, this.find = AccountHealthService.find});

  /// Overridable in tests.
  final Future<AccountHealth?> Function(String query) find;

  @override
  State<AccountHealthLookup> createState() => _AccountHealthLookupState();
}

class _AccountHealthLookupState extends State<AccountHealthLookup> {
  final TextEditingController _query = TextEditingController();
  bool _busy = false;
  bool _searched = false;
  String? _error;
  AccountHealth? _result;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final String text = _query.text.trim();
    if (text.isEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AccountHealth? found = await widget.find(text);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = found;
        _searched = true;
      });
    } on Object {
      if (mounted) {
        setState(() => _error = 'לא הצלחנו לחפש. כדאי לבדוק חיבור ולנסות שוב.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AccountHealth? result = _result;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        Text(
          'חיפוש חשבון לפי מייל או User ID, לצורך תמיכה טכנית בלבד. '
          'מוצגים מצב הסנכרון והמיגרציה ומספרי רשומות — לא תוכן המאגר.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  labelText: 'מייל או User ID',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _busy ? null : _search,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('חיפוש'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error))
        else if (_searched && result == null)
          const Text(
            'לא נמצא דיווח לחשבון הזה. חשבון שעוד לא נפתח בגרסה עדכנית לא '
            'מדווח.',
          )
        else if (result != null)
          _AccountCard(health: result),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.health});

  final AccountHealth health;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MapEntry<String, Map<String, Object?>>> devices =
        health.devices.entries.toList()..sort(
          (a, b) => '${b.value['reportedAt'] ?? ''}'.compareTo(
            '${a.value['reportedAt'] ?? ''}',
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Line(label: 'User ID', value: health.uid, copyable: true),
        _Line(
          label: 'מייל',
          value: health.email.isEmpty ? '—' : health.email,
          copyable: health.email.isNotEmpty,
        ),
        _Line(
          label: 'אימות מייל',
          value: health.emailVerified ? 'מאומת' : 'לא מאומת',
        ),
        _Line(
          label: 'שיטות התחברות',
          value: health.providers.map(providerName).join(', '),
        ),
        if (health.createdAt != null)
          _Line(label: 'נוצר', value: _date(health.createdAt!)),
        if (health.updatedAt != null)
          _Line(label: 'דיווח אחרון', value: _date(health.updatedAt!)),
        const SizedBox(height: 12),
        Text(
          'מכשירים (${devices.length})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        for (final MapEntry<String, Map<String, Object?>> device in devices)
          _DeviceCard(id: device.key, report: device.value),
      ],
    );
  }

  static String providerName(String id) => switch (id) {
    'password' => 'מייל וסיסמה',
    'google.com' => 'Google',
    'apple.com' => 'Apple',
    _ => id,
  };
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.id, required this.report});

  final String id;
  final Map<String, Object?> report;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, Object?> migration = report['migration'] is Map
        ? Map<String, Object?>.from(report['migration']! as Map)
        : <String, Object?>{};
    final Map<String, Object?> counts = report['counts'] is Map
        ? Map<String, Object?>.from(report['counts']! as Map)
        : <String, Object?>{};
    final List<String> log = report['log'] is List
        ? (report['log']! as List<dynamic>).whereType<String>().toList()
        : <String>[];
    final String migrationState = migration['verifiedAt'] != null
        ? 'הושלמה ואומתה (${_iso(migration['verifiedAt'])})'
        : migration['startedAt'] != null
        ? 'התחילה ${_iso(migration['startedAt'])}, עוד לא אומתה'
        : report['initialPullDone'] == true
        ? 'המאגר נקרא מהחשבון'
        : 'עוד לא נקרא';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${report['device'] ?? report['platform'] ?? 'מכשיר'} · '
            '${report['os'] ?? ''} · ${report['appVersion'] ?? ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          _Line(label: 'מזהה מכשיר', value: id, copyable: true),
          _Line(label: 'מיגרציה', value: migrationState),
          if (migration['snapshot'] == true)
            const _Line(label: 'עותק לפני מיגרציה', value: 'נשמר במכשיר'),
          _Line(
            label: 'חברים / רעיונות',
            value: '${counts['people'] ?? 0} / ${counts['matches'] ?? 0}',
          ),
          _Line(
            label: 'הערות',
            value:
                '${counts['personNotes'] ?? 0} על חברים, '
                '${counts['matchNotes'] ?? 0} ברעיונות',
          ),
          if (migration['report'] is Map)
            _Line(
              label: 'ספירה מול החשבון',
              value: _report(
                Map<String, Object?>.from(migration['report']! as Map),
              ),
            ),
          _Line(
            label: 'סנכרון אחרון',
            value:
                'נשלח ${_iso(report['lastSentAt'])} · '
                'התקבל ${_iso(report['lastReceivedAt'])}',
          ),
          _Line(
            label: 'שגיאות',
            value:
                '${report['lastError'] ?? 'אין'} · כתיבות שנדחו: '
                '${report['writeFailures'] ?? 0}',
          ),
          _Line(
            label: 'התנגשויות / כפילויות שאוחדו',
            value:
                '${report['conflicts'] ?? 0} / '
                '${report['duplicatesMerged'] ?? 0}',
          ),
          if (log.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('יומן סנכרון'),
              children: <Widget>[
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(
                    log.join('\n'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _report(Map<String, Object?> report) {
    final List<String> parts = <String>[];
    for (final String key in <String>['people', 'matches', 'personNotes']) {
      final Object? entry = report[key];
      if (entry is Map) {
        parts.add('$key ${entry['device']}/${entry['account'] ?? '?'}');
      }
    }
    parts.add(
      'files ${(report['files'] as int? ?? 0) - (report['filesPending'] as int? ?? 0)}'
      '/${report['files'] ?? 0}',
    );
    return parts.join(' · ');
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
          if (copyable)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'העתקה',
              icon: const Icon(Icons.copy_rounded, size: 16),
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            ),
        ],
      ),
    );
  }
}

String _date(DateTime at) {
  final DateTime local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _iso(Object? value) {
  final DateTime? at = value is String ? DateTime.tryParse(value) : null;
  return at == null ? '—' : _date(at);
}
