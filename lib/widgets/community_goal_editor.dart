import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadchan/services/community_goal_service.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_challenge.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// Administrator editor with an explicit preview of what every member sees.
class CommunityGoalEditor extends StatefulWidget {
  const CommunityGoalEditor({
    super.key,
    this.load = CommunityGoalService.fetch,
    this.save = CommunityGoalService.save,
  });

  final Future<WeeklyCommunityGoal?> Function() load;
  final Future<void> Function(WeeklyCommunityGoal) save;

  @override
  State<CommunityGoalEditor> createState() => _CommunityGoalEditorState();
}

class _CommunityGoalEditorState extends State<CommunityGoalEditor> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _target = TextEditingController();
  final TextEditingController _title = TextEditingController();
  ChallengeMetric _metric = ChallengeMetric.ideas;
  bool _loading = true;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final WeeklyCommunityGoal? goal = await widget.load();
      if (!mounted) return;
      _metric =
          goal?.metric ??
          CommunityChallenge.metricFor(CommunityPeriods.weekKey());
      _target.text = '${goal?.target ?? _metric.openingTarget}';
      _title.text = goal?.title ?? '';
    } catch (_) {
      if (!mounted) return;
      _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _target.dispose();
    _title.dispose();
    super.dispose();
  }

  WeeklyCommunityGoal get _goal => WeeklyCommunityGoal(
    metric: _metric,
    target: int.tryParse(_target.text) ?? 0,
    title: _title.text.trim(),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.save(_goal);
      if (mounted) AppNotice.show(context, 'היעד השבועי עודכן לכל הקהילה');
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'היעד לא נשמר. כדאי לבדוק את החיבור ולנסות שוב.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('לא הצלחנו לטעון את היעד השבועי'),
            TextButton(onPressed: _load, child: const Text('ניסיון נוסף')),
          ],
        ),
      );
    }
    final CommunityChallenge preview = CommunityChallenge.build(
      weekKey: CommunityPeriods.weekKey(),
      week: CommunityTotals.empty,
      goal: _goal,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'היעד השבועי של הקהילה',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'היעד מופיע בעמוד הבית של כולם. ההתקדמות מתאפסת בתחילת כל שבוע; ההגדרה נשארת עד לשינוי הבא.',
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<ChallengeMetric>(
              initialValue: _metric,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'מה סופרים ביעד?'),
              items: <DropdownMenuItem<ChallengeMetric>>[
                for (final metric in ChallengeMetric.values)
                  DropdownMenuItem(
                    value: metric,
                    child: Text(metric.targetNoun),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _metric = value!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _target,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'ערך היעד השבועי'),
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final int? target = int.tryParse(value ?? '');
                return target == null ||
                        target < 1 ||
                        target > WeeklyCommunityGoal.maxTarget
                    ? 'יש להזין מספר בין 1 ל־${WeeklyCommunityGoal.maxTarget}'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'כותרת להצגה למשתמשים (לא חובה)',
                helperText: 'ללא כותרת יופיע ניסוח אוטומטי עם ערך היעד.',
              ),
              maxLength: WeeklyCommunityGoal.maxTitleLength,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text('תצוגה למשתמשים'),
            const SizedBox(height: 8),
            Text(
              preview.headline,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('יעד שבועי: ${_goal.target} ${_metric.shortNoun}'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.flag_outlined),
              label: Text(_saving ? 'שומר...' : 'שמירת היעד לכל הקהילה'),
            ),
          ],
        ),
      ),
    );
  }
}
