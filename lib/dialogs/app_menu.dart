import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/dialogs/community_dialogs.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/widgets/home_app_bar.dart';

/// What the overflow menu can do.
enum AppMenuAction {
  settings,
  updatesGroup,
  share,
  report,
  help,
  contact,
  feedbackCenter,
}

/// The three-dots menu in the top banner.
///
/// Everything on it also lives in the settings — this is the short way, not a
/// second home for any of it. It is the one place in the app where "how do I
/// get help" is answered without first finding the settings, which is exactly
/// the moment somebody needs it.
///
/// **A popup anchored to the button, not a bottom sheet.** It was a sheet, on
/// the theory that six rows with icons is a sheet's shape. That was the wrong
/// read of the gesture: a sheet is what a *page* opens, and three dots in a
/// corner are a control — the menu belongs to the button and should come out of
/// it. Losing the subtitles is the price, and none of them said anything the
/// row's own title did not.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key, this.boxed = false});

  /// Draws the trigger as one of the home bar's rounded squares instead of a
  /// bare icon button, and as a hamburger rather than three dots — in a row of
  /// boxed controls the vertical dots read as a cropped icon.
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppMenuAction>(
      tooltip: 'תפריט',
      icon: boxed ? const _BoxedMenuIcon() : const Icon(Icons.more_vert),
      // The boxed trigger draws its own square, so the icon button's default
      // 48px splash box would sit on top of it.
      padding: EdgeInsets.zero,
      iconSize: boxed ? HomeBarButton.size : null,
      position: PopupMenuPosition.under,
      // The corner it hangs from is the corner it was tapped in. Without this
      // Material centres the popup on the button, which on a phone pushes it
      // past the edge of the screen.
      constraints: const BoxConstraints(minWidth: 220),
      onSelected: (AppMenuAction action) => _run(context, action),
      // Read rather than watched, and read *here* — inside `itemBuilder`, which
      // runs when the menu is opened. Watching `AccountProvider` from the bar
      // itself would create it on the first frame, which is exactly what puts
      // Firebase back on the startup path.
      itemBuilder: (BuildContext context) => <PopupMenuEntry<AppMenuAction>>[
        if (context.read<AccountProvider>().isSupportAdmin)
          _item(
            AppMenuAction.feedbackCenter,
            Icons.inbox_outlined,
            'מרכז הפידבק',
          ),
        _item(AppMenuAction.settings, Icons.settings_outlined, 'הגדרות'),
        if (CommunityLinks.hasUpdatesGroup)
          _item(
            AppMenuAction.updatesGroup,
            Icons.groups_outlined,
            'קבוצת העדכונים',
          ),
        _item(AppMenuAction.share, Icons.ios_share_outlined, 'שיתוף האפליקציה'),
        _item(
          AppMenuAction.report,
          Icons.forum_outlined,
          'שליחת תקלה או רעיון',
        ),
        _item(AppMenuAction.help, Icons.help_outline_rounded, 'עזרה והדרכה'),
        _item(AppMenuAction.contact, Icons.mail_outline_rounded, 'יצירת קשר'),
      ],
    );
  }

  static PopupMenuItem<AppMenuAction> _item(
    AppMenuAction value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<AppMenuAction>(
      value: value,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  static void _run(BuildContext context, AppMenuAction action) {
    switch (action) {
      case AppMenuAction.settings:
        context.push('/profile');
      case AppMenuAction.updatesGroup:
        // The dialog rather than the link, because the link alone has no way of
        // hearing "אני כבר בקבוצה" — and that is the only answer that stops the
        // reminders.
        UpdatesGroupDialog.show(context);
      case AppMenuAction.share:
        shareTheApp();
      case AppMenuAction.report:
        context.push('/support/report');
      case AppMenuAction.help:
        context.push('/support/help');
      case AppMenuAction.contact:
        CommunityLinks.openSupportEmail();
      case AppMenuAction.feedbackCenter:
        context.push('/support/admin');
    }
  }
}

/// The hamburger inside the home bar's rounded square.
///
/// Drawn rather than delegated to [HomeBarButton] because the tap belongs to
/// the `PopupMenuButton` around it — the menu has to hang from this box, and a
/// button inside a button would swallow that.
class _BoxedMenuIcon extends StatelessWidget {
  const _BoxedMenuIcon();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Container(
      width: HomeBarButton.size,
      height: HomeBarButton.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.9),
        ),
      ),
      child: Icon(
        Icons.menu_rounded,
        size: 20,
        color: dark ? theme.colorScheme.onSurface : AppColors.primaryInk,
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
