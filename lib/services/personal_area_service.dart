import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_card_sync.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';

abstract final class PersonalAreaService {
  static Future<Map<String, Object?>> personalActivity(String uid) async {
    final doc = await FirebaseFirestore.instance
        .doc('users/$uid/private/cardActivity')
        .get(const GetOptions(source: Source.server));
    return <String, Object?>{
      for (final entry in (doc.data() ?? <String, dynamic>{}).entries)
        entry.key: entry.value is Timestamp
            ? (entry.value as Timestamp).toDate()
            : entry.value,
    };
  }

  static Future<Map<String, dynamic>> call(
    String name, [
    Map<String, Object?> data = const {},
  ]) async {
    if (await PersonalCardService.durableUid() == null) {
      throw StateError('נדרשת התחברות');
    }
    final result = await FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<void> updateStatus(
    BuildContext context,
    ProfileStatus status,
  ) async {
    if (!OfflineGuard.allow(context)) {
      return;
    }
    final cards = context.read<PersonalCardProvider>();
    if (cards.card == null || cards.card!.profileStatus == status) return;
    try {
      await cards.setStatus(status);
      final published =
          FirebaseBootstrap.isReady &&
          cards.card != null &&
          await PersonalCardSync.publishNow(cards.card!);
      if (!context.mounted) return;
      if (!published) {
        AppNotice.show(
          context,
          'הסטטוס נשמר במכשיר ויתעדכן אצל השדכנים כשהחיבור יחזור.',
        );
        return;
      }
      await offerUpdate(context);
    } catch (_) {
      if (context.mounted) {
        AppNotice.show(context, 'לא הצלחנו לשמור את הסטטוס. כדאי לנסות שוב.');
      }
    }
  }

  static Future<void> editCard(BuildContext context) async {
    if (!OfflineGuard.allow(context)) {
      return;
    }
    await context.push('/me/card');
  }

  static Future<void> offerUpdate(BuildContext context) async {
    final cards = context.read<PersonalCardProvider>();
    if (!cards.hasCard ||
        !FirebaseBootstrap.isReady ||
        !context.read<CardAccessProvider>().approved.any(
          (row) => row.canReadCard,
        )) {
      return;
    }
    bool requested = false;
    try {
      final uid = await PersonalCardService.durableUid();
      if (uid == null || !context.mounted) return;
      // Eligibility is server-owned; the callable checks the limit again atomically.
      final activity = await personalActivity(uid);
      final nudged = activity['nudgedAt'];
      if (nudged is DateTime && DateTime.now().difference(nudged).inDays < 30) {
        return;
      }
      if (!context.mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('עדכנת את הכרטיס שלך!'),
          content: Text(
            'רוצה להזכיר לחברים השדכנים שלך לחשוב {עליך|עלייך}? החברים שקיבלו ממך גישה יוכלו לקבל עדכון שהכרטיס שלך התחדש. תוכן השינוי לא יישלח.'
                .forGender(context.userGender),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('לא עכשיו'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('לעדכן את החברים ❤️'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      requested = true;
      if (cards.card != null &&
          !await PersonalCardSync.publishNow(cards.card!)) {
        throw StateError('הכרטיס עדיין לא סונכרן');
      }
      await call('remindMyMatchmakers');
      if (context.mounted) AppNotice.show(context, 'התזכורת לחברים נשלחה ❤️');
    } catch (_) {
      if (requested && context.mounted) {
        AppNotice.show(
          context,
          'לא ניתן לשלוח עדכון כרגע. אפשר לנסות שוב מאוחר יותר.',
        );
      }
    }
  }

  static Future<void> invite(BuildContext context) async {
    final cards = context.read<PersonalCardProvider>();
    if (!cards.hasCard) {
      AppNotice.show(
        context,
        'כדי להזמין חבר עם גישה, יש להשלים את הכרטיס קודם',
      );
      return;
    }
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    final email = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text(
          'מזמינים חבר לחשוב {עליך|עלייך}'.forGender(context.userGender),
        ),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'לאיזה אימייל החבר יתחבר לשדכן? רק החשבון המאומת הזה יקבל גישה לכרטיס שלך. ההזמנה אינה כוללת גישה ל״מה אני מחפש/ת״.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'האימייל של החבר'),
                validator: (value) =>
                    RegExp(
                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                    ).hasMatch(value?.trim() ?? '')
                    ? null
                    : 'יש להזין אימייל תקין',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(dialog, controller.text.trim());
              }
            },
            child: const Text('יצירת הזמנה אישית'),
          ),
        ],
      ),
    );
    // The dialog's exit animation still owns its text field until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (email == null || !context.mounted) return;
    final origin = ShareUtils.originOf(context);
    try {
      if (!await PersonalCardSync.publishNow(cards.card!)) {
        throw StateError('לא סונכרן');
      }
      final result = await call('createPersonalInvite', {'email': email});
      final name = context.mounted
          ? context.read<UserProfileProvider>().firstName ?? ''
          : '';
      await Share.share(
        'היי! זה $name 😊 אשמח לעזרתך במחשבה על רעיון מתאים בשדכן. הכנתי לך הזמנה אישית שתיתן לך גישה לכרטיס שלי, כדי שנוכל למצוא יחד רעיון מתאים ❤️\nלהתחברות עם $email:\n${result['url']}',
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (context.mounted) {
        AppNotice.show(
          context,
          'לא הצלחנו ליצור הזמנה כרגע. כדאי לבדוק את החיבור.',
        );
      }
    }
  }

  static void openMatchmaking(BuildContext context) {
    WorkspaceStore.setMatchmakerEnabled(true);
    WorkspaceStore.setLastArea(WorkArea.matchmaker);
    context.go('/people?personalCards=1');
  }
}
