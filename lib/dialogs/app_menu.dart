import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/dialogs/community_dialogs.dart';
import 'package:shadchan/dialogs/privacy_policy_dialog.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/widgets/home_app_bar.dart';

/// What the overflow menu can do.
enum AppMenuAction {
  marriedFriends,
  profile,
  settings,
  updatesGroup,
  share,
  report,
  help,
  contact,
  privacyPolicy,
  feedbackCenter,
}

/// Which of the two menus a bar is wearing.
///
/// **בית and the two lists do not want the same menu, and folding them into
/// one made both worse.** המאגר שלי and הרעיונות שלי are working screens: what
/// is wanted from a corner there is the short way to the weddings, to the
/// matchmaker's own page, to the settings and to "something is broken". בית is
/// where somebody sits for a moment, and its menu is the one that has always
/// carried the app itself — sharing it, the community group, the guide, an
/// address to write to, the privacy policy.
///
/// So there are two, and they share only their shape.
enum AppMenuVariant {
  /// The home screen's own menu: the app, and the ways to reach a person.
  home,

  /// המאגר שלי and הרעיונות שלי: four rows, all of them destinations.
  list,
}

/// The menu behind the hamburger in the top banner.
///
/// Everything on it also lives in the settings — this is the short way, not a
/// second home for any of it. It is the one place in the app where "how do I
/// get help" is answered without first finding the settings, which is exactly
/// the moment somebody needs it.
///
/// **A popup anchored to the button, not a bottom sheet.** It was a sheet, on
/// the theory that six rows with icons is a sheet's shape. That was the wrong
/// read of the gesture: a sheet is what a *page* opens, and a control in a
/// corner is a control — the menu belongs to the button and should come out of
/// it.
///
/// **Two menus, one button.** On המאגר שלי and הרעיונות שלי it is four rows in
/// three groups — the weddings, the matchmaker's own page, the settings, and
/// the way to say something is broken — because those are working screens and
/// what a corner is reached for there is a destination. On בית it is the menu
/// the home screen has always had: the settings, and then everything that is
/// about the app itself rather than about the database. See [AppMenuVariant].
///
/// The rows carry their icon in a tinted square rather than bare, which is what
/// stops a column of thin grey glyphs from reading as disabled.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({
    super.key,
    this.boxed = false,
    this.variant = AppMenuVariant.list,
  });

  /// Which of the two menus this button opens.
  final AppMenuVariant variant;

  /// Trims the trigger down to the bare three dots at the bar's outer edge:
  /// no rounded square, no border. The frame and the info glyph made the menu
  /// look like a third notification control sitting beside the bell and the
  /// search; the overflow dots are what a phone's menu is looked for, and with
  /// nothing drawn behind them the eye reads the boxed pair as the group and
  /// the dots as the corner.
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Widget button = PopupMenuButton<AppMenuAction>(
      tooltip: 'תפריט',
      icon: boxed ? const _BarMenuIcon() : const Icon(Icons.more_vert),
      // The bar trigger sizes itself, so the icon button's default 48px splash
      // box would spill past it and off the edge of the bar.
      padding: EdgeInsets.zero,
      iconSize: boxed ? HomeBarButton.size : null,
      position: PopupMenuPosition.under,
      // The corner it hangs from is the corner it was tapped in. Without this
      // Material centres the popup on the button, which on a phone pushes it
      // past the edge of the screen.
      constraints: const BoxConstraints(minWidth: 236, maxWidth: 300),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      color: theme.colorScheme.surface,
      elevation: 3,
      onSelected: (AppMenuAction action) => _run(context, action),
      // Read rather than watched, and read *here* — inside `itemBuilder`, which
      // runs when the menu is opened. Watching `AccountProvider` from the bar
      // itself would create it on the first frame, which is exactly what puts
      // Firebase back on the startup path.
      itemBuilder: (BuildContext context) => <PopupMenuEntry<AppMenuAction>>[
        if (context
            .read<AccountProvider>()
            .isSupportAdmin) ...<PopupMenuEntry<AppMenuAction>>[
          _item(
            AppMenuAction.feedbackCenter,
            Icons.inbox_outlined,
            'מרכז הפידבק',
          ),
          const PopupMenuDivider(height: 9),
        ],
        ...(variant == AppMenuVariant.home ? _homeRows() : _listRows()),
      ],
    );

    // **A `PopupMenuButton` is an `IconButton`, and an `IconButton` is 48
    // wide.** That is Material's minimum tap target and it is applied whatever
    // the icon size, so the bar's two popup triggers measured 48 while the bell
    // and the "+" beside them measured 36 — twelve pixels of nothing between
    // controls that are supposed to read as one cluster, and a home bar whose
    // "+" was wider than the same "+" on the other two tabs. Held to the bar
    // button's own square, the three squares finally sit against each other.
    return boxed
        ? SizedBox(
            width: HomeBarButton.size,
            height: HomeBarButton.size,
            child: button,
          )
        : button;
  }

  /// המאגר שלי and הרעיונות שלי: four destinations and nothing else.
  static List<PopupMenuEntry<AppMenuAction>> _listRows() {
    return <PopupMenuEntry<AppMenuAction>>[
      // The best thing that ever comes out of this app, first on the menu:
      // everybody the matchmaker knows who got married.
      _item(
        AppMenuAction.marriedFriends,
        Icons.celebration_outlined,
        'חברים שהתחתנו',
      ),
      const PopupMenuDivider(height: 9),
      _item(AppMenuAction.profile, Icons.person_outline, 'הפרופיל שלי'),
      _item(AppMenuAction.settings, Icons.settings_outlined, 'הגדרות'),
      const PopupMenuDivider(height: 9),
      _item(AppMenuAction.report, Icons.forum_outlined, 'שליחת תקלה או רעיון'),
    ];
  }

  /// בית: the settings, and then everything that is about the app rather than
  /// about the database — sharing it, the community group, the guide, an
  /// address to write to, the privacy policy.
  static List<PopupMenuEntry<AppMenuAction>> _homeRows() {
    return <PopupMenuEntry<AppMenuAction>>[
      _item(AppMenuAction.settings, Icons.settings_outlined, 'הגדרות'),
      const PopupMenuDivider(height: 9),
      _item(AppMenuAction.report, Icons.forum_outlined, 'שליחת תקלה או רעיון'),
      _item(AppMenuAction.share, Icons.ios_share_outlined, 'שיתוף האפליקציה'),
      if (CommunityLinks.hasUpdatesGroup)
        _item(
          AppMenuAction.updatesGroup,
          Icons.groups_outlined,
          'הצטרפות לקבוצת הקהילה',
        ),
      _item(AppMenuAction.help, Icons.help_outline_rounded, 'עזרה והדרכה'),
      _item(AppMenuAction.contact, Icons.mail_outline_rounded, 'יצירת קשר'),
      _item(
        AppMenuAction.privacyPolicy,
        Icons.privacy_tip_outlined,
        'מדיניות פרטיות',
      ),
    ];
  }

  static PopupMenuItem<AppMenuAction> _item(
    AppMenuAction value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<AppMenuAction>(
      value: value,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: _MenuRow(icon: icon, label: label),
    );
  }

  static void _run(BuildContext context, AppMenuAction action) {
    switch (action) {
      case AppMenuAction.marriedFriends:
        context.push('/married');
      case AppMenuAction.profile:
        context.push('/profile');
      case AppMenuAction.settings:
        // The settings are a page of their own now, so this goes straight to
        // them rather than to the profile that used to contain them.
        context.push('/profile/settings');
      case AppMenuAction.report:
        context.push('/support/report');
      case AppMenuAction.updatesGroup:
        // The dialog rather than the link, because the link alone has no way of
        // hearing "אני כבר בקבוצה" — and that is the only answer that stops the
        // reminders.
        UpdatesGroupDialog.show(context);
      case AppMenuAction.share:
        shareTheApp();
      case AppMenuAction.help:
        context.push('/support/help');
      case AppMenuAction.contact:
        CommunityLinks.openSupportEmail();
      case AppMenuAction.privacyPolicy:
        // The dialog rather than `/privacy-policy`, so that reading it does not
        // cost the page somebody was already on. The full screen is still there
        // behind the settings link.
        PrivacyPolicyDialog.show(context);
      case AppMenuAction.feedbackCenter:
        context.push('/support/admin');
    }
  }
}

/// What the "+" on the home screen can start.
enum AddMenuAction { people, idea }

/// The "+" in the home banner, and the two things it can start.
///
/// **המאגר שלי and רעיונות each have one thing to add, and בית has two.** The
/// other two tabs' "+" goes straight to their own flow, because on those pages
/// there is nothing else it could mean. The home screen is above both of them,
/// so its "+" has to ask which — and a menu hanging off the button is the
/// cheapest possible way to ask: two rows, one tap each, and the same rows in
/// the same shape as the overflow menu beside it.
///
/// Each row leaves for the screen that does the work. Nothing is added from
/// inside the menu itself.
class AddMenuButton extends StatelessWidget {
  const AddMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Held to the same square as [ShadchanAddButton] on the other two tabs —
    // see the note in [AppMenuButton.build].
    return SizedBox(
      width: HomeBarButton.size,
      height: HomeBarButton.size,
      child: PopupMenuButton<AddMenuAction>(
        tooltip: 'הוספה',
        icon: const _BarAddIcon(),
        padding: EdgeInsets.zero,
        iconSize: HomeBarButton.size,
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 216, maxWidth: 300),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        color: theme.colorScheme.surface,
        elevation: 3,
        onSelected: (AddMenuAction action) {
          switch (action) {
            case AddMenuAction.people:
              AddPeopleDialog.show(context);
            case AddMenuAction.idea:
              context.push('/matches/add');
          }
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<AddMenuAction>>[
          PopupMenuItem<AddMenuAction>(
            value: AddMenuAction.people,
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: const _MenuRow(
              icon: Icons.person_add_alt_1_outlined,
              label: 'הוספת חברים',
            ),
          ),
          PopupMenuItem<AddMenuAction>(
            value: AddMenuAction.idea,
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: const _MenuRow(
              icon: Icons.favorite_border_rounded,
              label: 'הוספת רעיון',
            ),
          ),
        ],
      ),
    );
  }
}

/// The "+" inside the home bar's rounded square.
///
/// Drawn rather than delegated to [HomeBarButton] for the same reason
/// [_BarMenuIcon] is: the tap belongs to the `PopupMenuButton` around it, and a
/// button inside a button would swallow it. Unlike the menu dots this one keeps
/// its box — it is the same control as the "+" on המאגר שלי and רעיונות, and
/// the three bars have to agree.
class _BarAddIcon extends StatelessWidget {
  const _BarAddIcon();

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
        Icons.add,
        size: 20,
        color: dark ? theme.colorScheme.onSurface : AppColors.primaryInk,
      ),
    );
  }
}

/// One row of the menu: the icon in a soft square, the label beside it.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    return Row(
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ink.withValues(alpha: dark ? 0.20 : 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

/// The info glyph inside the home bar's rounded square.
///
/// It was a hamburger. A hamburger promises navigation — a drawer of places to
/// go — and this menu is nothing of the sort: every row on it is either help,
/// a way to reach a person, or something to read about the app. An "i" is what
/// that actually is, and it is also the glyph a reader looks for when the
/// question is "what does this thing do with my data".
///
/// Drawn rather than delegated to [HomeBarButton] because the tap belongs to
/// the `PopupMenuButton` around it — the menu has to hang from this box, and a
/// button inside a button would swallow that.
class _BarMenuIcon extends StatelessWidget {
  const _BarMenuIcon();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    // Still laid out on the bar button's square so the three controls keep a
    // common baseline and tap target — only nothing is painted behind it.
    return SizedBox(
      width: HomeBarButton.size,
      height: HomeBarButton.size,
      child: Icon(
        Icons.more_vert,
        size: 22,
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
