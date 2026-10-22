import 'package:go_router/go_router.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/services/couple_workspace_service.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';

class CoupleWorkspaceScreen extends StatefulWidget {
  const CoupleWorkspaceScreen({super.key});
  @override
  State<CoupleWorkspaceScreen> createState() => _CoupleWorkspaceScreenState();
}

class _CoupleWorkspaceScreenState extends State<CoupleWorkspaceScreen> {
  final _code = TextEditingController();
  bool _married = false;
  bool _busy = false;
  String? _invitation;
  @override
  void initState() {
    super.initState();
    CoupleWorkspaceService.refresh().catchError((_) => null);
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      final sync = context.read<SyncProvider>();
      await sync.syncNow();
      await FirebaseFirestore.instance.waitForPendingWrites().timeout(
        const Duration(seconds: 30),
      );
      await action();
      await CoupleWorkspaceService.refresh();
      await sync.start();
      if (mounted) {
        final access = context.read<CardAccessProvider>();
        await access.stop();
        await access.start();
      }
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'הפעולה לא הושלמה. יש לוודא חיבור לאינטרנט וקוד תקין ולנסות שוב. הנתונים נשמרו.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    final preview = await CoupleWorkspaceService.call('previewCoupleInvite', {
      'code': code,
    });
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('חיבור למאגר של ${preview['name']}'),
        content: const Text(
          'שני המאגרים יתאחדו למאגר זוגי אחד. הכרטיסים, ההערות, הרעיונות והתגיות יהיו משותפים. אנשי הקשר במכשיר והתזכורות נשארים אישיים. הרשאות קודמות לכרטיסים אישיים יתבקשו מחדש בשם שניכם.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('אישור החיבור והמיזוג'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CoupleWorkspaceService.call('acceptCoupleInvite', {
        'code': code,
        'married': true,
        'confirmMerge': true,
      });
    }
  }

  Future<void> _split() async {
    final preview = await CoupleWorkspaceService.call('previewCoupleSplit');
    if (!mounted) return;
    final sides = (preview['sides'] as List).cast<Map>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('פיצול מאגר זוגי'),
        content: Text(
          '${sides.map((s) => "${s['name']}: ${s['people']} אנשים ו־${s['ideas']} רעיונות").join('\n')}\n\nכל אחד יקבל את האנשים שנוספו על ידו ואת המידע הרלוונטי. רעיון המחבר בין שני הצדדים יישמר במלואו אצל שניכם, כולל המשתתפים וההיסטוריה. לא ייווצר עותק מלא אוטומטי. הרשאות לכרטיסים אישיים שניתנו לזוג יבוטלו. עותק התאוששות של נתוני המאגר נשמר בשרת.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('אני מאשר/ת את הפיצול'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CoupleWorkspaceService.call('splitCoupleWorkspace', {
        'confirmed': true,
      });
    }
  }

  Future<void> _recoverPending() async {
    final box = await Hive.openBox<dynamic>('workspace_recovery');
    final keys = box.keys
        .whereType<String>()
        .where((k) => k.startsWith('${CoupleWorkspaceService.currentUid}:'))
        .toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('שינויים שטרם סונכרנו'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'שינויים מהמכשיר הזה שנשמרו לפני חיבור או פיצול המאגר. אפשר לייצא ולבדוק אותם לפני ייבוא דרך מסך הגיבוי.',
              ),
              if (keys.isEmpty) const Text('לא נמצאו שינויים שממתינים לשחזור.'),
              for (final key in keys)
                ListTile(
                  title: Text(key.substring(key.indexOf(':') + 1)),
                  trailing: const Icon(Icons.file_download_outlined),
                  onTap: () async {
                    final directory = await getTemporaryDirectory();
                    final file = await File(
                      '${directory.path}/shadchan-pending-${DateTime.now().millisecondsSinceEpoch}.json',
                    ).writeAsString(box.get(key) as String);
                    if (context.mounted) {
                      await Share.shareXFiles([
                        XFile(file.path),
                      ], sharePositionOrigin: ShareUtils.originOf(context));
                    }
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('סגירה'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<Map<String, dynamic>?>(
    valueListenable: CoupleWorkspaceService.membership,
    builder: (context, membership, _) => Scaffold(
      appBar: AppBar(title: const Text('מאגר זוגי')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const LinearProgressIndicator(),
          TextButton(
            onPressed: _recoverPending,
            child: const Text('שחזור שינויים שלא סונכרנו'),
          ),
          if (membership != null) ...[
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .doc('couples/${membership['databaseUid']}')
                  .snapshots(),
              builder: (context, snapshot) {
                final pairs =
                    snapshot.data?.data()?['possibleDuplicates'] as List? ?? [];
                final people = context.watch<PersonRepository>();
                if (pairs.isEmpty) return const SizedBox.shrink();
                return ExpansionTile(
                  title: const Text('כרטיסים שכדאי לבדוק'),
                  subtitle: const Text(
                    'ייתכן שאלו כרטיסים של אותו אדם. לא בוצע איחוד אוטומטי.',
                  ),
                  children: [
                    for (final pair in pairs)
                      if (pair is List &&
                          pair.length == 2 &&
                          people.getById(pair[0] as String) != null &&
                          people.getById(pair[1] as String) != null)
                        ListTile(
                          title: Text(
                            '${people.getById(pair[0] as String)!.fullName} / ${people.getById(pair[1] as String)!.fullName}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/people/${pair[0]}'),
                        ),
                  ],
                );
              },
            ),
            if (membership['state'] == 'merging')
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await CoupleWorkspaceService.call(
                          'resumeCoupleMigration',
                        );
                      }),
                child: const Text('השלמת המיזוג'),
              ),
            if (membership['state'] == 'splitting')
              FilledButton(
                onPressed: _busy ? null : () => _run(_split),
                child: const Text('השלמת הפיצול'),
              ),
            HomePaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'המאגר של ${membership['name']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text('שני חשבונות אישיים, מאגר שדכנות משותף אחד.'),
                  if (membership['state'] != 'active')
                    const Text(
                      'המיזוג או הפיצול בתהליך. אפשר לחזור לפעולה כדי להשלים אותה.',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ExpansionTile(
              title: const Text('ניהול מתקדם'),
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _run(_split),
                  child: const Text('פיצול מאגר זוגי'),
                ),
              ],
            ),
          ] else ...[
            const Text(
              'יצירת מאגר זוגי / צירוף בן או בת זוג',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'כל אחד מתחבר בחשבון האישי שלו. המאגר, הכרטיסים, ההערות והרעיונות משותפים. אנשי הקשר, WhatsApp והתזכורות נשארים אישיים.',
            ),
            CheckboxListTile(
              value: _married,
              onChanged: _busy ? null : (v) => setState(() => _married = v!),
              title: const Text('אנחנו בני זוג נשואים'),
            ),
            FilledButton(
              onPressed: !_married || _busy
                  ? null
                  : () => _run(() async {
                      final result = await CoupleWorkspaceService.call(
                        'createCoupleInvite',
                        {'married': true},
                      );
                      if (mounted) {
                        setState(() => _invitation = result['code'] as String);
                      }
                    }),
              child: const Text('יצירת הזמנה לבן/בת הזוג'),
            ),
            if (_invitation != null) ...[
              SelectableText(_invitation!, textDirection: TextDirection.ltr),
              TextButton(
                onPressed: () => Share.share(
                  'הזמנה למאגר הזוגי שלנו בשדכן. יש להיכנס בחשבון שלך, לפתוח הגדרות ← מאגר זוגי ולהזין את הקוד:\n$_invitation',
                  sharePositionOrigin: ShareUtils.originOf(context),
                ),
                child: const Text('שיתוף ההזמנה'),
              ),
            ],
            const Divider(height: 40),
            TextField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'קוד הזמנה שקיבלתי'),
              textDirection: TextDirection.ltr,
            ),
            OutlinedButton(
              onPressed: !_married || _busy ? null : () => _run(_join),
              child: const Text('בדיקת ההזמנה והצטרפות'),
            ),
          ],
        ],
      ),
    ),
  );
}
