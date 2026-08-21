import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/about_me_sheet.dart';
import 'package:shadchan/dialogs/app_menu.dart';
import 'package:shadchan/dialogs/community_dialogs.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "הפרופיל שלי" — the matchmaker's own page, and the one place the app's
/// settings live. The home screen used to carry a gear icon; it now carries the
/// user's photo, and everything that was behind the gear is here, under the
/// person it belongs to.
///
/// **The page reads top to bottom as "me, then my settings, then the extras".**
/// Who I am — the photograph, the name, the line I wrote about myself — then
/// the account that protects all of it, then my own card if I have one, then
/// the settings, then the handful of things that are neither: the community
/// group, passing the app on, the tips. Nothing in the settings group *does*
/// anything on its own; every row there opens a screen. That is what makes the
/// group scannable, and it is why "שיתוף האפליקציה" — which fires the share
/// sheet on the spot — sits under "פעולות נוספות" instead.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.focusSettings = false});

  /// Opens the page with the settings group scrolled into view.
  ///
  /// The top banner's menu offers "הגדרות", and the settings are a group on
  /// this page rather than a screen of their own — so the menu has to be able
  /// to land on the group, not merely on the page that contains it. Anything
  /// else makes the shortest route to the settings the one that drops somebody
  /// at the top of a page and asks them to scroll.
  final bool focusSettings;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// The anchor [ProfileScreen.focusSettings] scrolls to.
  final GlobalKey _settingsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.focusSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSettings());
    }
  }

  Future<void> _scrollToSettings() async {
    final BuildContext? target = _settingsKey.currentContext;
    if (target == null || !mounted) {
      return;
    }
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      // Not flush with the top: the group's own heading has to come with it,
      // and a heading pinned to the very first pixel reads as cut off.
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final AccountProvider account = context.watch<AccountProvider>();
    final SyncProvider sync = context.watch<SyncProvider>();
    final bool hasCard =
        (profile.personalCard ?? '').trim().isNotEmpty ||
        profile.personalCardPhotos.isNotEmpty;

    final List<Widget> sections = <Widget>[
      // 1. Who this is: the photograph, the full name, and the one line they
      // wrote about themselves.
      _ProfileHeader(
        profile: profile,
        onEditPhoto: () => _editPhoto(profile),
        onEditAbout: () => _editAbout(profile),
      ),
      const SizedBox(height: 6),
      // The answer was already given during sign-up. All that is left here is a
      // quiet way back to it if it ever changes — not a section of its own.
      _PersonalStatusLine(
        profile: profile,
        onChangeRequested: () => _changePersonalStatus(profile),
      ),
      const SizedBox(height: 20),

      // 2. The account, immediately under the person it belongs to. It used to
      // be the last group on the page, which put the one row that protects
      // everything else below every row it protects.
      _AccountGroup(
        account: account,
        onSignIn: () => context.push('/sign-in'),
        onSignOut: () => _confirmSignOut(account, sync),
      ),

      // 3. A single matchmaker's own card — one row, and a page behind it. The
      // card used to be previewed here in full, above the settings, whether or
      // not there was anything in it.
      if (profile.isSingle)
        SettingsGroup(
          title: 'הכרטיס שלי',
          children: <Widget>[
            SettingsRow(
              icon: Icons.badge_outlined,
              title: 'כרטיס השידוכים שלי',
              subtitle: hasCard
                  ? 'צפייה, שיתוף ועריכה'
                  : 'עוד לא מילאת אותו — אפשר למלא עכשיו',
              onTap: () => context.push('/profile/card'),
            ),
          ],
        ),

      // The feedback console, for the handful of accounts that have one. It
      // used to be the last group on the page — which is where somebody puts a
      // screen they never intend to open — and the tips waiting for approval
      // sat on a *different* row further up. One entry, above the settings, so
      // what users sent is never far from the top of the page.
      if (account.isSupportAdmin)
        SettingsGroup(
          title: 'ניהול',
          children: <Widget>[
            SettingsRow(
              icon: Icons.inbox_outlined,
              title: 'מרכז הפידבק',
              subtitle: 'טיפים לאישור, פניות, הערות ותקלות',
              onTap: () => context.push('/support/admin'),
            ),
          ],
        ),

      // 4. The settings themselves: one row per subject, one screen behind
      // each. Everything here opens something; nothing here toggles anything.
      KeyedSubtree(
        key: _settingsKey,
        child: SettingsGroup(
          title: 'הגדרות',
          children: <Widget>[
            SettingsRow(
              icon: Icons.palette_outlined,
              title: 'תצוגה וערכת נושא',
              onTap: () => context.push('/profile/appearance'),
            ),
            SettingsRow(
              icon: Icons.style_outlined,
              title: 'עריכת סגנונות דתיים',
              onTap: () => context.push('/profile/religious-levels'),
            ),
            SettingsRow(
              icon: Icons.folder_outlined,
              title: 'גיבוי וייצוא',
              subtitle: 'גיבוי בענן, שחזור, ייצוא לאקסל וייבוא',
              onTap: () => context.push('/profile/data'),
            ),
            // Its own row rather than a line inside the backup screen. Privacy
            // is the subject somebody comes looking for by name, and a subject
            // nobody finds is a promise nobody reads.
            SettingsRow(
              icon: Icons.lock_outline_rounded,
              title: 'פרטיות',
              onTap: () => context.push('/support/privacy'),
            ),
            SettingsRow(
              icon: Icons.help_outline_rounded,
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
      ),

      // 5. Everything that is not a setting: the group, the invitation to pass
      // the app on, and what other matchmakers wrote.
      SettingsGroup(
        title: 'פעולות נוספות',
        children: <Widget>[
          if (CommunityLinks.hasUpdatesGroup)
            SettingsRow(
              icon: Icons.groups_outlined,
              title: 'הצטרפות לקבוצת העדכונים',
              subtitle: CommunityPromptsStore.isInUpdatesGroup
                  ? 'סימנת שאתם כבר בקבוצה'
                  : null,
              // The dialog rather than the link: it is the only place that can
              // hear "אני כבר בקבוצה", which is the one answer that stops the
              // reminders.
              onTap: () => UpdatesGroupDialog.show(context),
            ),
          SettingsRow(
            icon: Icons.ios_share_outlined,
            title: 'שיתוף האפליקציה עם חבר',
            trailing: const SizedBox.shrink(),
            onTap: shareTheApp,
          ),
          SettingsRow(
            icon: Icons.auto_stories_outlined,
            title: 'טיפים לשדכנים',
            onTap: () => context.push('/profile/tips-list'),
          ),
        ],
      ),
      const _SettingsFooter(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('הפרופיל שלי'), centerTitle: true),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sections.length,
          itemBuilder: (BuildContext context, int index) => sections[index],
        ),
      ),
    );
  }

  // --- The photo ----------------------------------------------------------

  Future<void> _editPhoto(UserProfileProvider profile) async {
    final bool hasPhoto = profile.photoPath != null;
    if (!hasPhoto) {
      await _pickPhoto(profile);
      return;
    }

    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('החלפת התמונה'),
                onTap: () => Navigator.of(sheetContext).pop('replace'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: const Text('הסרת התמונה'),
                onTap: () => Navigator.of(sheetContext).pop('remove'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) {
      return;
    }
    if (choice == 'remove') {
      await profile.setPhotoPath(null);
      return;
    }
    await _pickPhoto(profile);
  }

  Future<void> _pickPhoto(UserProfileProvider profile) async {
    final String? path = await PhotoPickerService.pickSinglePhoto(context);
    if (path == null) {
      return;
    }
    await profile.setPhotoPath(path);
  }

  // --- The line about themselves ------------------------------------------

  /// Always reachable, whether or not sign-up left anything here — which is the
  /// other half of "the field is optional": somebody who skipped it has to be
  /// able to find it later, and somebody who wrote it in a hurry has to be able
  /// to change it.
  Future<void> _editAbout(UserProfileProvider profile) async {
    final String? about = await AboutMeSheet.show(
      context,
      initialText: profile.about ?? '',
      gender: profile.gender,
    );
    if (about == null) {
      return;
    }
    await profile.setAbout(about);
  }

  // --- Personal status ----------------------------------------------------

  /// Offered from the quiet line under the name. Changing to married hides the
  /// personal card rather than deleting it, so nothing is lost by answering.
  Future<void> _changePersonalStatus(UserProfileProvider profile) async {
    final Gender? gender = profile.gender;
    final bool? isSingle = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.favorite_border_rounded),
                title: Text('{רווק|רווקה}'.forGender(gender)),
                trailing: profile.isSingle ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: Text('{נשוי|נשואה}'.forGender(gender)),
                trailing: profile.isSingle ? null : const Icon(Icons.check),
                onTap: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        );
      },
    );
    if (isSingle == null || isSingle == profile.isSingle) {
      return;
    }
    await profile.setIsSingle(isSingle);
  }

  // --- The account --------------------------------------------------------

  /// Asks first, and says what is actually lost. Signing out is not
  /// destructive here — the database is in Hive either way — and saying so is
  /// the difference between a confirmation and a scare.
  Future<void> _confirmSignOut(
    AccountProvider account,
    SyncProvider sync,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('יציאה מהחשבון?'),
          content: const Text(
            'המאגר שלך שמור במכשיר וימשיך לעבוד כרגיל. רק החיבור לחשבון '
            'Google יתנתק.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('יציאה'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await account.signOut();
    // The ledger describes what is in *that* account's cloud tree. Signing
    // back into a different one and diffing against it would leave the new
    // account's backup missing everything the old one happened to hold.
    await sync.forget();
  }
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({
    required this.account,
    required this.onSignIn,
    required this.onSignOut,
  });

  final AccountProvider account;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (account.isSignedIn) {
      final String? email = account.email;
      return SettingsGroup(
        title: 'חשבון',
        children: <Widget>[
          SettingsRow(
            icon: Icons.account_circle_outlined,
            leadingOverride: _AccountAvatar(
              photoUrl: account.photoUrl,
              displayName: account.displayName ?? email,
            ),
            title: account.displayName ?? email ?? 'מחובר',
            subtitle: email,
          ),
          SettingsRow(
            icon: Icons.logout,
            leadingOverride: account.isBusy ? const SettingsSpinner() : null,
            title: 'יציאה מהחשבון',
            destructive: true,
            enabled: !account.isBusy,
            trailing: const SizedBox.shrink(),
            onTap: onSignOut,
          ),
        ],
      );
    }

    if (!account.isFirebaseReady) {
      return const SettingsGroup(
        title: 'חשבון',
        children: <Widget>[
          SettingsRow(
            icon: Icons.cloud_off_outlined,
            title: 'החיבור לחשבון אינו זמין כרגע',
            subtitle: 'יש לוודא חיבור לאינטרנט ולנסות שוב מאוחר יותר',
            enabled: false,
          ),
        ],
      );
    }

    return SettingsGroup(
      title: 'חשבון',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FilledButton(
                onPressed: onSignIn,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                child: const Text('התחברות לחשבון'),
              ),
              const SizedBox(height: 10),
              Text(
                'התחברות מאפשרת לגבות את המאגר, לשחזר אותו במכשיר חדש ולהיות '
                'חלק מקהילת השדכנים.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The three lines at the foot of the settings, in the smallest type on the
/// page. Nobody comes here for them, and everybody expects to find them here.
class _SettingsFooter extends StatelessWidget {
  const _SettingsFooter();

  /// Kept beside the two links rather than in an "מידע" card of its own, which
  /// is what it used to have.
  static const String version = '1.0.0';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      child: Column(
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: <Widget>[
              TextButton(
                onPressed: () => context.push('/privacy-policy'),
                style: _linkStyle,
                child: Text('תנאי שימוש', style: style),
              ),
              Text('·', style: style),
              TextButton(
                onPressed: () => context.push('/privacy-policy'),
                style: _linkStyle,
                child: Text('מדיניות פרטיות', style: style),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('גרסה $version', style: style),
        ],
      ),
    );
  }

  static final ButtonStyle _linkStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

/// The Google profile picture, falling back to the initial and then to a
/// generic icon — the photo is a remote URL and may simply not load.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.photoUrl, required this.displayName});

  final String? photoUrl;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String initial = (displayName ?? '').trim().isEmpty
        ? ''
        : displayName!.trim().characters.first;

    return CircleAvatar(
      radius: 20,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
      child: initial.isEmpty
          ? Icon(
              Icons.person_outline,
              size: 20,
              color: theme.colorScheme.onPrimaryContainer,
            )
          : Text(
              initial,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
    );
  }
}

/// The photograph and the full name, and under them the one line the
/// matchmaker wrote about themselves.
///
/// **The name is the full name, not the greeting name.** The home screen greets
/// by the first name alone, which is how people are spoken to; this is the
/// matchmaker's own page, which is how they are *identified*, and a page headed
/// "רבקה" tells its owner nothing they did not know.
///
/// The line under it has three states and they are all one row: what they
/// wrote, an invitation to write something when they skipped it during sign-up,
/// and — for a profile with no photograph — the note about the photograph,
/// which is worth saying exactly once and only while it is still true. Tapping
/// the row always opens the editor.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.onEditPhoto,
    required this.onEditAbout,
  });

  final UserProfileProvider profile;
  final VoidCallback onEditPhoto;
  final VoidCallback onEditAbout;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Gender? gender = profile.gender;
    final String? about = profile.about;

    return Column(
      children: <Widget>[
        UserProfileAvatar(
          photoPath: profile.photoPath,
          gender: gender,
          name: profile.name,
          radius: 46,
          onTap: onEditPhoto,
          showEditBadge: true,
        ),
        const SizedBox(height: 12),
        Text(
          profile.name ?? '{שדכן|שדכנית}'.forGender(gender),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onEditAbout,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    about ?? '${AboutMe.label} · הוספה',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                      fontStyle: about == null ? null : FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  about == null ? Icons.add_rounded : Icons.edit_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (profile.photoPath == null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            'אפשר להוסיף תמונה — היא תופיע בראש עמוד הבית',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The personal status, as small as it can be while still being changeable.
///
/// Whether the matchmaker is single was settled during sign-up; repeating it as
/// a titled card on the profile gave a one-off answer permanent furniture.
class _PersonalStatusLine extends StatelessWidget {
  const _PersonalStatusLine({
    required this.profile,
    required this.onChangeRequested,
  });

  final UserProfileProvider profile;
  final VoidCallback onChangeRequested;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Gender? gender = profile.gender;
    final String label = profile.isSingle
        ? '{רווק|רווקה}'.forGender(gender)
        : '{נשוי|נשואה}'.forGender(gender);

    return Center(
      child: TextButton(
        onPressed: onChangeRequested,
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          textStyle: theme.textTheme.bodySmall,
          visualDensity: VisualDensity.compact,
        ),
        child: Text('$label · שינוי'),
      ),
    );
  }
}

/// The matchmaker's own photo, drawn the same way wherever it appears: the home
/// app bar, and the head of this screen. Falls back to the initial of their
/// name, and to a plain person icon when there is no name either.
class UserProfileAvatar extends StatelessWidget {
  const UserProfileAvatar({
    super.key,
    required this.photoPath,
    required this.gender,
    this.name,
    this.radius = 16,
    this.onTap,
    this.showEditBadge = false,
  });

  final String? photoPath;
  final Gender? gender;
  final String? name;
  final double radius;
  final VoidCallback? onTap;

  /// Draws the small camera badge that says the photo can be added or changed.
  final bool showEditBadge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? path = photoPath;
    final bool hasPhoto = path != null && File(path).existsSync();
    final String initial = (name ?? '').trim().isEmpty
        ? ''
        : name!.trim().characters.first;

    // Without a photo the circle wears the same gender tint every other avatar
    // in the app does, so the matchmaker's own face reads as one of them.
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = AppColors.genderAccent(
      gender ?? Gender.unknown,
      dark: dark,
    );

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.genderSurface(
        gender ?? Gender.unknown,
        dark: dark,
      ),
      foregroundImage: hasPhoto ? FileImage(File(path)) : null,
      child: hasPhoto
          ? null
          : (initial.isNotEmpty
                ? Text(
                    initial,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: radius * 0.8,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  )
                : Icon(Icons.person_outline, size: radius, color: accent)),
    );

    if (showEditBadge) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          avatar,
          PositionedDirectional(
            bottom: 0,
            end: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: Icon(
                hasPhoto ? Icons.edit : Icons.add_a_photo_outlined,
                size: 14,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      );
    }

    if (onTap == null) {
      return avatar;
    }

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: avatar,
    );
  }
}
