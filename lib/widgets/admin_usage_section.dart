import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadchan/utils/app_tokens.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The prices usage is turned into money with — typed in by an administrator
/// from the Google Cloud price list (`adminConfig/pricing`), because prices
/// change and no price in the code would stay right.
class AdminPricing {
  const AdminPricing({
    this.aiInputPerMillion = 0,
    this.aiOutputPerMillion = 0,
    this.storagePerGbMonth = 0,
    this.usdToIls = 3.7,
  });

  factory AdminPricing.fromJson(Map<String, dynamic>? json) {
    double d(String k, double fallback) =>
        (json?[k] as num?)?.toDouble() ?? fallback;
    return AdminPricing(
      aiInputPerMillion: d('aiInputPerMillion', 0),
      aiOutputPerMillion: d('aiOutputPerMillion', 0),
      storagePerGbMonth: d('storagePerGbMonth', 0),
      usdToIls: d('usdToIls', 3.7),
    );
  }

  /// USD per million tokens read / written by the model.
  final double aiInputPerMillion;
  final double aiOutputPerMillion;

  /// USD per GB of Cloud Storage per month.
  final double storagePerGbMonth;
  final double usdToIls;

  bool get isSet =>
      aiInputPerMillion > 0 || aiOutputPerMillion > 0 || storagePerGbMonth > 0;

  /// Tokens → USD.
  double aiCost(num input, num output) =>
      input / 1e6 * aiInputPerMillion + output / 1e6 * aiOutputPerMillion;

  /// Bytes held → USD a month.
  double storageCost(num bytes) => bytes / 1e9 * storagePerGbMonth;

  /// "$1.20 (₪4.44)".
  String money(double usd) {
    String two(double v) => v < 0.01 && v > 0 ? '<0.01' : v.toStringAsFixed(2);
    return '\$${two(usd)} (₪${two(usd * usdToIls)})';
  }
}

/// Readable names for the codes `FeatureUsage` tallies.
abstract final class FeatureNames {
  static const Map<String, String> _names = <String, String>{
    'screen:/home': 'בית',
    'screen:/people': 'המאגר שלי',
    'screen:/matches': 'הרעיונות שלי',
    'screen:/chats': 'צ\'אטים',
    'screen:/chats/:id': 'שיחה',
    'screen:/profile': 'פרופיל',
    'screen:/profile/settings': 'הגדרות',
    'screen:/people/:id': 'פרופיל של חבר',
    'screen:/people/import': 'הוספה מאנשי הקשר',
    'screen:/people/add': 'הוספה ידנית',
    'screen:/people/ai': 'ייבוא באמצעות AI',
    'screen:/matches/add': 'פתיחת רעיון',
    'screen:/matches/:id': 'רעיון',
    'screen:/ideas/new': 'רעיונות שהמאגר מציע',
    'screen:/network': 'המאגר המשותף',
    'screen:/known-matchmakers': 'שדכנים שאני מכיר',
    'screen:/partner': 'מרחב זוגי',
    'screen:/reminders': 'התראות',
    'screen:/activity': 'פעילות וקהילה',
    'screen:/board': 'הלוח שלי',
    'screen:/card-friends': 'חברים עם כרטיס אישי',
    'screen:/me/card': 'הכרטיס האישי שלי',
    'screen:/me/matchmakers': 'השדכנים שלי',
    'screen:/married': 'חברים שהתחתנו',
    'screen:/stats/month': 'נתונים חודשיים',
    'feature:tags': 'תגיות',
    'feature:ai_import': 'ייבוא AI',
    'feature:matches': 'התאמות',
    'feature:board': 'הלוח שלי',
    'feature:search': 'חיפוש',
    'feature:filter': 'סינון',
    'feature:share_card': 'שיתוף כרטיס',
    'feature:notes': 'הערות על חבר',
    'feature:voice_note': 'הקלטה קולית',
    'feature:personal_area': 'אזור אישי',
    'feature:reminders': 'תזכורות',
    'feature:new_ideas': 'רעיונות מהמאגר',
  };

  static String of(String code) => _names[code] ?? code;
}

/// "עלויות ושימוש" in the support console: what the AI and the stored files
/// cost, who uses the most, and which pages and features are used at all.
class AdminUsageSection extends StatefulWidget {
  const AdminUsageSection({super.key, required this.usage});

  /// `adminStats/current.usage` (see `functions/src/usage_stats.ts`), or null
  /// before the server has computed it once.
  final Map<String, dynamic>? usage;

  @override
  State<AdminUsageSection> createState() => _AdminUsageSectionState();
}

class _AdminUsageSectionState extends State<AdminUsageSection> {
  static const String pricingDoc = 'adminConfig/pricing';
  AdminPricing _pricing = const AdminPricing();
  bool _showAllFeatures = false;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  Future<void> _loadPricing() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .doc(pricingDoc)
          .get();
      if (mounted) setState(() => _pricing = AdminPricing.fromJson(doc.data()));
    } catch (_) {
      // Prices not set yet: counts are still shown.
    }
  }

  Future<void> _editPricing() async {
    final Map<String, TextEditingController> fields =
        <String, TextEditingController>{
          'aiInputPerMillion': TextEditingController(
            text: '${_pricing.aiInputPerMillion}',
          ),
          'aiOutputPerMillion': TextEditingController(
            text: '${_pricing.aiOutputPerMillion}',
          ),
          'storagePerGbMonth': TextEditingController(
            text: '${_pricing.storagePerGbMonth}',
          ),
          'usdToIls': TextEditingController(text: '${_pricing.usdToIls}'),
        };
    const Map<String, String> labels = <String, String>{
      'aiInputPerMillion': 'AI — דולר למיליון טוקנים נכנסים',
      'aiOutputPerMillion': 'AI — דולר למיליון טוקנים יוצאים',
      'storagePerGbMonth': 'אחסון — דולר ל־GB לחודש',
      'usdToIls': 'שער דולר',
    };
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('מחירים לחישוב העלות'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'המחירים מתוך מחירון Google Cloud למודל ולאחסון שבשימוש. '
              'משמשים רק לחישוב ההערכה כאן.',
            ),
            for (final MapEntry<String, TextEditingController> e
                in fields.entries)
              TextField(
                controller: e.value,
                decoration: InputDecoration(labelText: labels[e.key]),
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
    if (save != true || !mounted) return;
    final Map<String, Object> data = <String, Object>{
      for (final MapEntry<String, TextEditingController> e in fields.entries)
        e.key: double.tryParse(e.value.text) ?? 0,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      await FirebaseFirestore.instance.doc(pricingDoc).set(data);
      await _loadPricing();
    } catch (_) {
      if (mounted) AppNotice.show(context, 'לא הצלחנו לשמור את המחירים');
    }
  }

  static num _n(Object? map, String key) =>
      map is Map ? (map[key] as num? ?? 0) : 0;

  static String _bytes(num bytes) {
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(2)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    return '${(bytes / 1e3).round()} KB';
  }

  static String _tokens(num tokens) {
    if (tokens >= 1e6) return '${(tokens / 1e6).toStringAsFixed(2)}M';
    if (tokens >= 1e3) return '${(tokens / 1e3).toStringAsFixed(1)}K';
    return '$tokens';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, dynamic>? usage = widget.usage;
    final TextStyle? small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (usage == null) {
      return _card(context, 'עלויות ושימוש', <Widget>[
        Text(
          'יופיע אחרי הריענון הבא של הנתונים בשרת (פעם ב־12 שעות או '
          '"רענון עכשיו").',
          style: small,
        ),
      ]);
    }
    final Object? ai = usage['ai'];
    final Object? storage = usage['storage'];
    final List<Object?> features = usage['features'] is List
        ? usage['features'] as List<Object?>
        : const <Object?>[];
    final double aiAll = _pricing.aiCost(
      _n(ai, 'inputTokens'),
      _n(ai, 'outputTokens'),
    );
    final double aiMonth = _pricing.aiCost(
      _n(ai, 'monthInputTokens'),
      _n(ai, 'monthOutputTokens'),
    );
    final num storedBytes =
        _n(storage, 'photoBytes') + _n(storage, 'voiceBytes');

    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );

    final List<Object?> aiTop = ai is Map && ai['top'] is List
        ? ai['top'] as List<Object?>
        : const <Object?>[];
    final List<Object?> storageTop = storage is Map && storage['top'] is List
        ? storage['top'] as List<Object?>
        : const <Object?>[];
    final Map<Object?, Object?> byFeature = ai is Map && ai['byFeature'] is Map
        ? ai['byFeature'] as Map<Object?, Object?>
        : const <Object?, Object?>{};
    const Map<String, String> aiFeatureNames = <String, String>{
      'card': 'קריאת כרטיס בודד',
      'import': 'ייבוא מרוכז',
      'chat': 'פקודה בצ\'אט',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _card(context, 'עלויות (הערכה)', <Widget>[
          if (!_pricing.isSet)
            Text('עוד לא הוזנו מחירים — מוצגות כמויות בלבד.', style: small),
          line(
            'AI החודש (${ai is Map ? ai['month'] : ''})',
            _pricing.isSet
                ? _pricing.money(aiMonth)
                : '${_tokens(_n(ai, 'monthInputTokens'))} / '
                      '${_tokens(_n(ai, 'monthOutputTokens'))}',
          ),
          line(
            'AI מאז ומעולם',
            _pricing.isSet
                ? _pricing.money(aiAll)
                : '${_tokens(_n(ai, 'inputTokens'))} / '
                      '${_tokens(_n(ai, 'outputTokens'))}',
          ),
          line(
            'אחסון תמונות והקלטות (${_bytes(storedBytes)})',
            _pricing.isSet
                ? '${_pricing.money(_pricing.storageCost(storedBytes))} לחודש'
                : _bytes(storedBytes),
          ),
          const SizedBox(height: 4),
          Text(
            'קריאות וכתיבות למסד הנתונים, תעבורה ופונקציות אינם נספרים כאן — '
            'החשבון המלא בדוח החיוב של Google Cloud.',
            style: small,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _editPricing,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('עדכון מחירים'),
            ),
          ),
        ]),
        _card(context, 'שימוש ב־AI', <Widget>[
          line('חשבונות שהשתמשו', '${_n(ai, 'accounts')}'),
          line(
            'בקשות (סה"כ / החודש)',
            '${_n(ai, 'calls')} / ${_n(ai, 'monthCalls')}',
          ),
          for (final MapEntry<Object?, Object?> e in byFeature.entries)
            line(
              aiFeatureNames['${e.key}'] ?? '${e.key}',
              '${_n(e.value, 'calls')} בקשות · '
              '${_tokens(_n(e.value, 'inputTokens') + _n(e.value, 'outputTokens'))}',
            ),
          if (aiTop.isNotEmpty) ...<Widget>[
            const Divider(),
            Text('המשתמשים שצרכו הכי הרבה', style: theme.textTheme.labelLarge),
            for (final Object? row in aiTop.take(15))
              line(
                _who(row),
                _pricing.isSet
                    ? _pricing.money(
                        _pricing.aiCost(
                          _n(row, 'inputTokens'),
                          _n(row, 'outputTokens'),
                        ),
                      )
                    : '${_n(row, 'calls')} בקשות · '
                          '${_tokens(_n(row, 'inputTokens') + _n(row, 'outputTokens'))}',
              ),
          ],
        ]),
        _card(context, 'אחסון בענן לפי משתמש', <Widget>[
          line('חשבונות עם קבצים', '${_n(storage, 'accounts')}'),
          line('תמונות', '${_n(storage, 'photos')}'),
          line('הקלטות', '${_n(storage, 'voice')}'),
          if (storageTop.isNotEmpty) ...<Widget>[
            const Divider(),
            for (final Object? row in storageTop.take(15))
              line(_who(row), _bytes(_n(row, 'bytes'))),
          ],
        ]),
        _card(context, 'אילו חלקים באפליקציה בשימוש', <Widget>[
          Text(
            'לפי מספר החשבונות שהשתמשו ב־30 הימים האחרונים. מסכים ופעולות '
            'בתחתית הרשימה הם המועמדים לשיפור או להסרה.',
            style: small,
          ),
          for (final Object? row
              in _showAllFeatures ? features : features.take(15))
            if (row is Map)
              line(
                FeatureNames.of('${row['code']}'),
                '${row['accounts30']} חשבונות · ${row['uses']} שימושים',
              ),
          if (features.length > 15)
            TextButton(
              onPressed: () =>
                  setState(() => _showAllFeatures = !_showAllFeatures),
              child: Text(_showAllFeatures ? 'פחות' : 'כל הרשימה'),
            ),
        ]),
      ],
    );
  }

  static String _who(Object? row) {
    if (row is! Map) return '';
    final String email = '${row['email'] ?? ''}';
    return email.isNotEmpty ? email : '${row['uid']}';
  }

  Widget _card(BuildContext context, String title, List<Widget> children) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HomePaperCard(
        stripe: context.tokens.ctaAccent,
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
            ...children,
          ],
        ),
      ),
    );
  }
}
