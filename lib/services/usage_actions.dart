import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/intro_screens.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// Switching a capability on or off — "יש לי כרטיס אישי", "אני חושב על
/// חברים" — always in the same account, never a new sign-up.
abstract final class UsageActions {
  /// Switches the matchmaker's tools on and opens the one home, with the
  /// matchmaker's introduction the first time.
  static Future<void> startMatchmaking(BuildContext context) async {
    WorkspaceStore.setMatchmakerEnabled(true);
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    if (!profile.hasSeenIntro) {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext introContext) => IntroScreens(
            onFinished: () async {
              await profile.markIntroSeen();
              if (introContext.mounted) {
                Navigator.of(introContext).pop();
              }
            },
          ),
        ),
      );
    }
    if (context.mounted) {
      context.go('/home');
    }
  }

  /// "אני חושב על חברים" — on or off. Off keeps the database whole: the tabs
  /// go away, nothing is deleted, and switching back brings everything back.
  static Future<void> setMatchmaking(BuildContext context, bool on) async {
    if (on) {
      await startMatchmaking(context);
      return;
    }
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    if (!profile.isSingle) {
      AppNotice.show(
        context,
        'צריך להשאיר לפחות שימוש אחד — כרטיס אישי או חשיבה על חברים.',
      );
      return;
    }
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('להסתיר את כלי השדכנות?'),
        content: Text(
          'המאגר והרעיונות נשמרים בחשבון ולא נמחקים. אפשר להחזיר אותם בכל עת '
                  'מ"השימוש שלי בשדכן".'
              .forGender(profile.gender),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('הסתרה'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    WorkspaceStore.setMatchmakerEnabled(false);
    if (context.mounted) context.go('/profile');
  }

  /// "יש לי כרטיס אישי" — on or off. Off hides the card from the app (and
  /// from the matchmakers, as a married status always did); it is not
  /// deleted, and switching back brings it back.
  static Future<void> setHasCard(BuildContext context, bool on) async {
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    if (!on && !WorkspaceStore.matchmakerEnabled) {
      AppNotice.show(
        context,
        'צריך להשאיר לפחות שימוש אחד — כרטיס אישי או חשיבה על חברים.',
      );
      return;
    }
    await profile.setIsSingle(on);
  }
}
