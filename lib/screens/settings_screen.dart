import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/app_icons.dart';
import 'package:shadchan/dialogs/app_menu.dart';
import 'package:shadchan/dialogs/community_dialogs.dart';
import 'package:shadchan/dialogs/home_area_dialog.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "הגדרות" — a page of its own, at last.
///
/// **The settings left the profile.** They were a group on `/profile`, halfway
/// down a page that opens with a photograph, a name, an account and a personal
/// card — so the matchmaker's own page was mostly not about them, and the
/// settings were mostly not findable. Every row here opens a screen; nothing
/// here toggles anything, which is what keeps the list scannable and is why
/// "שיתוף האפליקציה" — which fires the share sheet on the spot — sits under
/// "פעולות נוספות" rather than among the settings proper.
///
/// The profile keeps exactly one row pointing here. That row, and not this
/// page, is what a matchmaker looks for.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final AccountProvider account = context.watch<AccountProvider>();
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final bool bothAreas =
        WorkspaceStore.matchmakerEnabled &&
        context.watch<PersonalCardProvider>().hasCard;

    return Scaffold(
      appBar: AppBar(title: const Text('הגדרות')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: <Widget>[
            // The feedback console, for the handful of accounts that have one.
            // First on the page rather than last: a queue somebody has to
            // scroll to is a queue that grows.
            if (account.isSupportAdmin)
              SettingsGroup(
                title: 'ניהול',
                accent: dark
                    ? AppColors.femaleAccentDm
                    : AppColors.femaleAccent,
                children: <Widget>[
                  SettingsRow(
                    icon: Icons.inbox_outlined,
                    title: 'מרכז הפידבק',
                    subtitle: 'טיפים לאישור, פניות, הערות ותקלות',
                    onTap: () => context.push('/support/admin'),
                  ),
                ],
              ),

            SettingsGroup(
              title: 'הגדרות',
              children: <Widget>[
                // Only for an account with both areas: the page a launch
                // opens on. Asked once by [HomeAreaDialog]; changed here.
                if (bothAreas)
                  SettingsRow(
                    icon: Icons.home_outlined,
                    title: 'עמוד הבית',
                    subtitle: switch (WorkspaceStore.launchArea) {
                      WorkArea.personal => 'האזור האישי',
                      WorkArea.matchmaker => 'אזור השדכן',
                    },
                    onTap: () async {
                      await HomeAreaDialog.show(
                        context,
                        userGender: context.read<UserProfileProvider>().gender,
                      );
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                SettingsRow(
                  icon: Icons.palette_outlined,
                  title: 'תצוגה וערכת נושא',
                  onTap: () => context.push('/profile/appearance'),
                ),
                SettingsRow(
                  icon: Icons.folder_outlined,
                  title: 'גיבוי וייצוא',
                  subtitle: 'גיבוי בענן, שחזור, ייצוא לאקסל וייבוא',
                  onTap: () => context.push('/profile/data'),
                ),
                // Its own row rather than a line inside the backup screen.
                // Privacy is the subject somebody comes looking for by name,
                // and a subject nobody finds is a promise nobody reads.
                SettingsRow(
                  icon: Icons.lock_outline_rounded,
                  title: 'פרטיות',
                  onTap: () => context.push('/support/privacy'),
                ),
                SettingsRow(
                  icon: AppIcons.help,
                  title: 'עזרה ושאלות נפוצות',
                  onTap: () => context.push('/support/help'),
                ),
                SettingsRow(
                  icon: Icons.forum_outlined,
                  title: 'דיווח תקלות ויצירת קשר',
                  onTap: () => context.push('/profile/help'),
                ),
              ],
            ),

            // Everything that is not a setting: the group, the invitation to
            // pass the app on, and what other matchmakers wrote.
            SettingsGroup(
              title: 'פעולות נוספות',
              accent: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
              children: <Widget>[
                if (CommunityLinks.hasUpdatesGroup)
                  SettingsRow(
                    icon: Icons.groups_outlined,
                    title: 'הצטרפות לקבוצת העדכונים',
                    subtitle: CommunityPromptsStore.isInUpdatesGroup
                        ? 'סימנת שאתם כבר בקבוצה'
                        : null,
                    // The dialog rather than the link: it is the only place
                    // that can hear "אני כבר בקבוצה", which is the one answer
                    // that stops the reminders.
                    onTap: () => UpdatesGroupDialog.show(context),
                  ),
                SettingsRow(
                  icon: Icons.share_outlined,
                  title: 'שיתוף האפליקציה עם חבר',
                  trailing: const SizedBox.shrink(),
                  onTap: () =>
                      shareTheApp(origin: ShareUtils.originOf(context)),
                ),
                SettingsRow(
                  icon: Icons.auto_stories_outlined,
                  title: 'טיפים לשדכנים',
                  onTap: () => context.push('/profile/tips-list'),
                ),
              ],
            ),
            const SettingsVersionFooter(),
          ],
        ),
      ),
    );
  }
}
