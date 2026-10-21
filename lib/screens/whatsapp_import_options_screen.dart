import 'package:flutter/material.dart';
import 'package:shadchan/services/ai_import_runner.dart';
import 'package:shadchan/services/whatsapp_import_service.dart';

/// The user controls the scope before any AI request is made.
class WhatsAppImportOptionsScreen extends StatefulWidget {
  const WhatsAppImportOptionsScreen({
    super.key,
    required this.chat,
    required this.alreadyImported,
    required this.now,
  });

  final WhatsAppChat chat;
  final Set<String> alreadyImported;
  final DateTime now;

  static Future<AiImportPlan?> show(
    BuildContext context, {
    required WhatsAppChat chat,
    required Set<String> alreadyImported,
  }) {
    return Navigator.of(context).push<AiImportPlan>(
      MaterialPageRoute<AiImportPlan>(
        builder: (_) => WhatsAppImportOptionsScreen(
          chat: chat,
          alreadyImported: alreadyImported,
          now: DateTime.now(),
        ),
      ),
    );
  }

  @override
  State<WhatsAppImportOptionsScreen> createState() =>
      _WhatsAppImportOptionsScreenState();
}

enum _Period { month, threeMonths, year, all }

class _WhatsAppImportOptionsScreenState
    extends State<WhatsAppImportOptionsScreen> {
  _Period _period = _Period.threeMonths;

  DateTime? get _since => switch (_period) {
        _Period.month => widget.now.subtract(const Duration(days: 30)),
        _Period.threeMonths => widget.now.subtract(const Duration(days: 90)),
        _Period.year => widget.now.subtract(const Duration(days: 365)),
        _Period.all => null,
      };

  @override
  Widget build(BuildContext context) {
    final plan = AiImportRunner.planChat(
      widget.chat,
      since: _since,
      alreadyImported: widget.alreadyImported,
    );
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('הכנת ייבוא מ-WhatsApp')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('בחרו מה לקרוא מהקבוצה',
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'הודעות הקבוצה נקראות במכשיר. רק ההודעות שתבחרו יישלחו '
            'לניתוח בעזרת AI לאחר אישורכם.',
          ),
          const SizedBox(height: 20),
          Text('מאיזו תקופה?', style: theme.textTheme.titleMedium),
          ...<(_Period, String)>[
            (_Period.month, '30 הימים האחרונים'),
            (_Period.threeMonths, '90 הימים האחרונים (מומלץ)'),
            (_Period.year, 'השנה האחרונה'),
            (_Period.all, 'כל ההיסטוריה'),
          ].map((option) => RadioListTile<_Period>(
                title: Text(option.$2),
                value: option.$1,
                groupValue: _period,
                onChanged: (value) {
                  if (value != null) setState(() => _period = value);
                },
              )),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('הייבוא הקרוב',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Text('הודעות מתאימות לתקופה: ${plan.eligible}'),
                  Text('כבר עובדו במכשיר: ${plan.skipped}'),
                  Text('הודעות לניתוח עכשיו: ${plan.messageCount}'),
                  if (plan.remaining > 0)
                    Text('ממתינות לסבב הבא: ${plan.remaining}'),
                  if (plan.outsidePeriod > 0)
                    Text('מחוץ לתקופה: ${plan.outsidePeriod}'),
                  if (plan.undated > 0)
                    Text('ללא תאריך מזוהה: ${plan.undated}. '
                        'בחרו "כל ההיסטוריה" כדי לכלול אותן.'),
                  const SizedBox(height: 10),
                  const Text(
                    'עד 200 הודעות ו-5 בקשות AI בסבב. '
                    'אורך הטקסט מוגבל גם הוא; הודעה ארוכה מדי לא תעובד, '
                    'כדי למנוע חריגה מהתקציב.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (plan.isEmpty)
            const Text(
              'לא נמצאו הודעות חדשות בבחירה הזו. '
              'אפשר לבחור תקופה אחרת או לבדוק מה כבר יובא.',
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: plan.isEmpty
                ? null
                : () => Navigator.of(context).pop(plan),
            child: Text('נתחו ${plan.messageCount} הודעות'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('לא עכשיו'),
          ),
        ],
      ),
    );
  }
}
