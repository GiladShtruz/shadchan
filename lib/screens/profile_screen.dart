import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/dialogs/account_dialogs.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/about_me_sheet.dart';
import 'package:shadchan/dialogs/matchmaker_shares_sheet.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/community_profile.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/intro_screens.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/home_section.dart';
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
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    final bool hasCard = cards.hasCard;
    final bool matchmaker = WorkspaceStore.matchmakerEnabled;
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    // The page's groups take the palette in turn, so the profile is not one
    // long column of blue: copper for the matchmaker's own number, blue for
    // the account, rose for what other matchmakers see, the light blue for
    // the settings.
    final Color copper = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    final Color rose = dark ? AppColors.femaleAccentDm : AppColors.femaleAccent;
    final Color sky = dark ? AppColors.metricCouplesDm : AppColors.primary;

    final List<Widget> sections = <Widget>[
      // 1. Who this is: the photograph, the full name, and the one line they
      // wrote about themselves.
      //
      // On the home page's paper card, with the rule along its foot in the
      // matchmaker's own colour — the same card every block on בית wears.
      HomePaperCard(
        stripe: AppColors.genderAccent(
          profile.gender ?? Gender.unknown,
          dark: dark,
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          children: <Widget>[
            _ProfileHeader(
              profile: profile,
              onEditPhoto: () => _editPhoto(profile),
              onEditAbout: () => _editAbout(profile),
            ),
            const SizedBox(height: 2),
            // The answer was already given during sign-up. All that is left
            // here is a quiet way back to it if it ever changes — not a
            // section of its own.
            _PersonalStatusLine(
              profile: profile,
              onChangeRequested: () => _changePersonalStatus(profile),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),

      // 1.5. The user's own card, where it cannot be missed. A married user
      // has no card to manage, so has no entry at all.
      if (profile.isSingle) ...<Widget>[
        _MyCardEntry(
          hasCard: hasCard,
          deleted: cards.isDeleted,
          gender: profile.gender,
          onTap: () => hasCard || cards.isDeleted
              ? context.go('/me')
              : context.push('/me/card'),
        ),
        const SizedBox(height: 16),
      ],

      // Somebody who came only to manage their card can switch the
      // matchmaker's system on — same account, nothing new to sign up for.
      if (!matchmaker) ...<Widget>[
        SettingsGroup(
          title: 'שדכנות',
          children: <Widget>[
            SettingsRow(
              icon: Icons.diversity_1_outlined,
              title: 'להתחיל להכיר בין חברים',
              subtitle: 'לנהל מאגר של חברים ולחשוב על רעיונות לשידוכים',
              onTap: _startMatchmaking,
            ),
          ],
        ),
      ],

      // The user's own number — how friends' accounts find this one, for
      // the personal card in both directions.
      SettingsGroup(
        title: 'המספר שלי',
        accent: copper,
        children: <Widget>[
          SettingsRow(
            icon: Icons.phone_outlined,
            title: profile.myPhone ?? 'הוספת המספר שלי',
            subtitle: profile.myPhone == null
                ? (profile.isSingle
                      ? 'כדי שחברים יוכלו למצוא את הכרטיס שלך, ולהפך'
                      : 'כדי שחברים עם כרטיס אישי יוכלו למצוא אותך')
                : 'לא מופיע בכרטיס ולא נשלח בשיתוף',
            onTap: () async {
              final String? phone = await MyPhoneDialog.show(
                context,
                initial: profile.myPhone,
                purpose: profile.isSingle || !matchmaker
                    ? MyPhonePurpose.cardOwner
                    : MyPhonePurpose.matchmaker,
              );
              if (phone != null) {
                await profile.setMyPhone(phone);
              }
            },
          ),
        ],
      ),

      // 2. The account, immediately under the person it belongs to. It used to
      // be the last group on the page, which put the one row that protects
      // everything else below every row it protects.
      // Who is signed in, and nothing that ends it: leaving, switching and
      // deleting are at the foot of the page — see [_AccountActions].
      _AccountGroup(account: account, onSignIn: () => context.push('/sign-in')),

      // 3.5. What other matchmakers see.
      //
      // **Its own group, directly under the person it describes.** Everything
      // above it is private — the account, the matchmaker's own shidduch card —
      // and everything below it is app configuration. This is the one part of
      // the page that other people read, and it is drawn as a group of its own
      // so that is never in doubt: three rows, each saying what is currently
      // filled in, and the whole of the public page behind them.
      if (matchmaker)
        SettingsGroup(
          title: 'מה שדכנים אחרים רואים',
          accent: rose,
          children: <Widget>[
            SettingsRow(
              icon: Icons.person_pin_outlined,
              title: 'השם שלי בקהילה',
              subtitle: profile.communityName == null
                  ? '${profile.fullName ?? ''} · אפשר לבחור שם אחר לתצוגה'
                  : profile.communityName!,
              onTap: () => _editCommunityName(profile),
            ),
            SettingsRow(
              icon: Icons.badge_outlined,
              title: 'מה תרצה ששדכנים אחרים ידעו עליך?',
              subtitle: _sharesSummary(profile.communityShares),
              onTap: () => _editShares(profile),
            ),
            SettingsRow(
              icon: Icons.card_giftcard_rounded,
              title: 'הטבה לקהילה',
              subtitle:
                  profile.communityBenefit ??
                  'לא חובה — משהו שתרצה להציע לשדכנים אחרים',
              onTap: () => _editBenefit(profile),
            ),
            SettingsRow(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'מספר לפנייה בוואטסאפ',
              subtitle:
                  profile.communityPhone ??
                  'לא חובה — בלעדיו פשוט לא יופיע כפתור',
              onTap: () => _editCommunityPhone(profile),
            ),
          ],
        ),

      // 4. The settings — one row, and a page behind it.
      //
      // **They used to be a group on this page, and they should not have
      // been.** Six rows of app configuration sat between the matchmaker's own
      // card and the community links, which made their own page mostly about
      // something else and made the settings themselves a thing to scroll to.
      // Everything that was in that group is on `/profile/settings` now,
      // unchanged and in the same order; what is left here is the door.
      KeyedSubtree(
        key: _settingsKey,
        child: SettingsGroup(
          title: 'הגדרות',
          accent: sky,
          children: <Widget>[
            SettingsRow(
              icon: Icons.settings_outlined,
              title: 'הגדרות',
              subtitle: 'תצוגה, פרטיות, נתונים, עזרה ועוד',
              onTap: () => context.push('/profile/settings'),
            ),
          ],
        ),
      ),

      if (account.isSignedIn)
        _AccountActions(
          busy: account.isBusy,
          onSignOut: () => AccountDialogs.confirmSignOut(context),
        ),

      const SettingsVersionFooter(),
    ];

    // The home page's type scale, as the personal area and the activity
    // page use it — see [HomeTypography].
    return Theme(
      data: theme.copyWith(
        textTheme: HomeTypography.scale(theme.textTheme, dark: dark),
      ),
      child: Scaffold(
        // Somebody who is both a single with a personal area and a matchmaker
        // has two "profiles" in one account; the bar says which one this is.
        // The title starts on the same line the cards below start on.
        appBar: AppBar(
          titleSpacing: 20,
          title: Text(
            profile.isSingle && matchmaker
                ? 'הפרופיל שלי – {שדכן|שדכנית}'.forGender(profile.gender)
                : 'הפרופיל שלי',
          ),
        ),
        body: SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: sections.length,
            itemBuilder: (BuildContext context, int index) => sections[index],
          ),
        ),
      ),
    );
  }

  /// Switches the matchmaker's system on for a card-only user and takes them
  /// to its home screen, through the matchmaker's introduction the first time.
  Future<void> _startMatchmaking() async {
    WorkspaceStore.setMatchmakerEnabled(true);
    WorkspaceStore.setLastArea(WorkArea.matchmaker);
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
    if (mounted) {
      context.go('/home');
    }
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

  // --- The public page ----------------------------------------------------

  /// What the row says is filled in, without listing all of it.
  ///
  /// The prompts' own labels rather than the answers: "מאיפה אני בארץ · תפקיד
  /// או פעילות חברתית" tells somebody at a glance which questions they have
  /// answered, which is what a summary line is for. The answers themselves are
  /// one tap away, and on a settings row they would be cut mid-word anyway.
  static String _sharesSummary(List<MatchmakerShare> shares) {
    if (shares.isEmpty) {
      return 'עוד לא הוספת — אזור, אוכלוסייה, תפקיד ועוד';
    }
    return shares.map((MatchmakerShare share) => share.kind.label).join(' · ');
  }

  Future<void> _editShares(UserProfileProvider profile) async {
    final List<MatchmakerShare>? shares = await MatchmakerSharesSheet.show(
      context,
      initial: profile.communityShares,
    );
    if (shares == null) {
      return;
    }
    await profile.setCommunityShares(shares);
  }

  /// The name the leaderboard and the community lines show. Published at once
  /// rather than on the next app pause: somebody who just renamed themselves
  /// goes to the board to see it.
  Future<void> _editCommunityName(UserProfileProvider profile) async {
    final String? name = await CommunityNameSheet.show(
      context,
      initial: profile.communityName ?? '',
      accountName: profile.fullName ?? '',
    );
    if (name == null || !mounted) {
      return;
    }
    await profile.setCommunityName(name);
    if (!mounted) {
      return;
    }
    unawaited(
      context.read<CommunityProvider>().refresh(
        people: context.read<PersonRepository>(),
        matches: context.read<MatchRepository>(),
        profile: profile,
      ),
    );
  }

  Future<void> _editBenefit(UserProfileProvider profile) async {
    final String? benefit = await CommunityBenefitSheet.show(
      context,
      initial: profile.communityBenefit ?? '',
    );
    if (benefit == null) {
      return;
    }
    await profile.setCommunityBenefit(benefit);
  }

  Future<void> _editCommunityPhone(UserProfileProvider profile) async {
    final String? phone = await CommunityPhoneSheet.show(
      context,
      initial: profile.communityPhone ?? '',
    );
    if (phone == null) {
      return;
    }
    await profile.setCommunityPhone(phone);
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
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({required this.account, required this.onSignIn});

  final AccountProvider account;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (account.isSignedIn) {
      final String? email = account.accountEmail;
      return SettingsGroup(
        title: 'חשבון',
        children: <Widget>[
          SettingsRow(
            icon: Icons.account_circle_outlined,
            leadingOverride: account.isBusy
                ? const SettingsSpinner()
                : _AccountAvatar(
                    photoUrl: account.photoUrl,
                    displayName: account.displayName ?? email,
                  ),
            title: 'החשבון שלי',
            subtitle: email ?? account.displayName,
            onTap: () => context.push('/profile/account'),
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
                'המאגר שלך שייך לחשבון, ונפתח בכל מכשיר שמחובר אליו.',
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

/// "התנתקות", at the very foot of the page — quiet, and a dialog away from
/// happening. Deleting the account lives in "החשבון שלי".
class _AccountActions extends StatelessWidget {
  const _AccountActions({required this.busy, required this.onSignOut});

  final bool busy;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Widget action(String label, VoidCallback onPressed) {
      return TextButton(
        onPressed: busy ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          visualDensity: VisualDensity.compact,
          textStyle: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        children: <Widget>[
          Divider(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 4),
          action('התנתקות', onSignOut),
        ],
      ),
    );
  }
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
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: gender == null || gender == Gender.unknown
                ? null
                : AppColors.genderAccent(
                    gender,
                    dark: theme.brightness == Brightness.dark,
                  ),
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
                color: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: Icon(
                hasPhoto ? Icons.edit : Icons.add_a_photo_outlined,
                size: 14,
                color: AppColors.surface,
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

/// "הכרטיס שלי" at the top of the profile — the way into the personal area,
/// or the invitation to write a first card.
class _MyCardEntry extends StatelessWidget {
  const _MyCardEntry({
    required this.hasCard,
    required this.deleted,
    required this.gender,
    required this.onTap,
  });

  final bool hasCard;

  /// A card that was deleted: the entry offers to restore it.
  final bool deleted;
  final Gender? gender;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return HomePaperCard(
      stripe: AppColors.secondary,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              hasCard ? Icons.badge_outlined : Icons.add_card_outlined,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  deleted
                      ? 'שחזור הכרטיס שלי'
                      : hasCard
                      ? 'האזור האישי'
                      : 'יצירת הכרטיס שלי',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  deleted
                      ? 'הכרטיס שמור, ואפשר להחזיר אותו'
                      : hasCard
                      ? 'ניהול כרטיס השידוכים האישי, הסטטוס ומי רואה אותו'
                      : 'כרטיס אחד שרק {אתה מעדכן|את מעדכנת}, לחברים שמשדכים'
                            .forGender(gender),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
