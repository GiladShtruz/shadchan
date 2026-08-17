import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/dialogs/community_dialogs.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/utils/community_links.dart';

/// The three-dots menu in the top banner.
///
/// Everything on it also lives in the settings, under "קהילה, עזרה ומשוב" —
/// this is the short way, not a second home for any of it. It is the one place
/// in the app where "how do I get help" is answered without first finding the
/// settings, which is exactly the moment somebody needs it.
///
/// A sheet rather than a `PopupMenuButton`: six rows with icons and one of them
/// two lines long is a sheet's shape, and on a phone a popup anchored to the
/// corner would run off the edge.
abstract final class AppMenuSheet {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // The page's own context is handed down, because every row here closes
      // the sheet first and then does something. By that point the sheet's
      // context is defunct, and the one thing that still needs a live context —
      // raising the group dialog — has to use the page underneath.
      builder: (BuildContext sheetContext) => _AppMenu(host: context),
    );
  }
}

class _AppMenu extends StatelessWidget {
  const _AppMenu({required this.host});

  final BuildContext host;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final GoRouter router = GoRouter.of(context);

    void go(String route) {
      Navigator.of(context).pop();
      router.push(route);
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('הגדרות'),
            onTap: () => go('/profile'),
          ),
          if (CommunityLinks.hasUpdatesGroup)
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('הצטרפות לקבוצת העדכונים'),
              subtitle: CommunityPromptsStore.isInUpdatesGroup
                  ? const Text('סימנת שאתם כבר בקבוצה')
                  : null,
              // The dialog rather than the link, because the link alone has no
              // way of hearing "אני כבר בקבוצה" — and that is the only answer
              // that stops the reminders.
              onTap: () {
                Navigator.of(context).pop();
                if (host.mounted) {
                  UpdatesGroupDialog.show(host);
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('שיתוף האפליקציה עם חבר'),
            onTap: () {
              Navigator.of(context).pop();
              shareTheApp();
            },
          ),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('שליחת תקלה / רעיון לשיפור'),
            onTap: () => go('/support/report'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text('עזרה והדרכה'),
            onTap: () => go('/support/help'),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline_rounded),
            title: const Text('יצירת קשר'),
            subtitle: Text(
              CommunityLinks.supportEmail,
              style: theme.textTheme.bodySmall,
            ),
            onTap: () {
              Navigator.of(context).pop();
              CommunityLinks.openSupportEmail();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Opens the phone's own share sheet with the invitation already written.
///
/// The message and the download link are one string rather than a subject and a
/// body: this is forwarded in WhatsApp far more often than it is emailed, and
/// WhatsApp keeps only the text.
Future<void> shareTheApp() async {
  try {
    await Share.share(CommunityLinks.shareMessage);
  } on Object {
    // A phone with nothing to share to throws rather than returning. There is
    // nothing useful to say about it, and nothing was lost.
  }
}
