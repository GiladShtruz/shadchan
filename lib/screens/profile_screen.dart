import 'dart:async';
import 'package:shadchan/utils/app_tokens.dart';
import 'package:shadchan/utils/avatar_image.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadchan/screens/personal_area_screen.dart';
import 'package:shadchan/services/usage_actions.dart';
import 'package:shadchan/screens/partner_space_screen.dart';
import 'package:shadchan/utils/app_navigation.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/dialogs/account_dialogs.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/about_me_sheet.dart';
import 'package:shadchan/dialogs/matchmaker_shares_sheet.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/community_profile.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/settings_widgets.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/widgets/matchmaker_rank_badge.dart';

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
  const ProfileScreen({
    super.key,
    this.focusSettings = false,
    this.focusUsage = false,
  });

  /// Opens the page with "השימוש שלי בשדכן" scrolled into view.
  final bool focusUsage;

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
  final GlobalKey _usageKey = GlobalKey();

  void _onUsageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WorkspaceStore.revision.removeListener(_onUsageChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WorkspaceStore.revision.addListener(_onUsageChanged);
    if (widget.focusSettings || widget.focusUsage) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollTo(widget.focusUsage ? _usageKey : _settingsKey),
      );
    }
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final BuildContext? target = key.currentContext;
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
    context.watch<PersonalCardProvider>();
    final bool matchmaker = WorkspaceStore.matchmakerEnabled;
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    // The page's groups take the palette in turn, so the profile is not one
    // long column of blue: copper for the matchmaker's own number, blue for
    // the account, rose for what other matchmakers see, the light blue for
    // the settings.
    final Color copper = dark
        ? AppColors.secondaryDarkDm
        : context.tokens.ctaAccent;
    final Color rose = dark
        ? AppColors.femaleAccentDm
        : context.tokens.femaleAccent;
    final Color sky = dark
        ? AppColors.metricCouplesDm
        : context.tokens.maleAccent;

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
          ],
        ),
      ),
      const SizedBox(height: 18),

      // 1.5. The personal card, in full, for somebody who keeps one: the
      // card, its status, "מה אני מחפש/ת", the recording and who sees it.
      // One profile — the card is part of it, not an area somewhere else.
      if (profile.isSingle) ...<Widget>[
        const PersonalCardProfileSection(),
        const SizedBox(height: 16),
      ],

      // "השימוש שלי בשדכן": the two capabilities of this one account.
      KeyedSubtree(
        key: _usageKey,
        child: SettingsGroup(
          title: 'השימוש שלי בשדכן',
          accent: copper,
          children: <Widget>[
            SwitchListTile(
              secondary: const Icon(Icons.badge_outlined),
              title: const Text('יש לי כרטיס אישי'),
              subtitle: Text(
                'כרטיס שרק {אתה מעדכן|את מעדכנת}, והשדכנים שלך רואים'.forGender(
                  profile.gender,
                ),
              ),
              value: profile.isSingle,
              onChanged: (bool on) => UsageActions.setHasCard(context, on),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.diversity_1_outlined),
              title: Text(
                '{אני חושב|אני חושבת} על חברים'.forGender(profile.gender),
              ),
              subtitle: const Text('מאגר חברים, רעיונות ושדכנים שותפים'),
              value: matchmaker,
              onChanged: (bool on) => UsageActions.setMatchmaking(context, on),
            ),
          ],
        ),
      ),

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
                purpose: !matchmaker
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
      // so that is never in doubt: a few rows, each saying what is currently
      // filled in, and the whole of the public page behind them.
      // "המרחב הזוגי שלנו": both of them, and the three ways in — or, before
      // there is one, the invitation to open it.
      if (matchmaker) const PartnerSpaceProfileArea(),
      // Matchmakers among the contacts — the colleagues already known.
      if (matchmaker)
        SettingsGroup(
          title: 'שדכנים',
          accent: sky,
          children: <Widget>[
            SettingsRow(
              icon: Icons.handshake_outlined,
              title: 'שדכנים שאני מכיר',
              subtitle: 'שדכנים מאנשי הקשר שלך שמשתמשים בשדכן',
              onTap: () => AppNavigation.open(context, '/known-matchmakers'),
            ),
          ],
        ),
      if (matchmaker)
        SettingsGroup(
          title: 'מה שדכנים אחרים רואים',
          accent: rose,
          children: <Widget>[
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
        appBar: AppBar(titleSpacing: 20, title: const Text('הפרופיל שלי')),
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
      foregroundImage: photoUrl == null
          ? null
          : avatarImage(context, photoUrl!, diameter: 40),
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
        const _OwnRank(),
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

/// The matchmaker's own rank under their name, from the ideas they opened.
class _OwnRank extends StatelessWidget {
  const _OwnRank();

  @override
  Widget build(BuildContext context) {
    final MatchRepository? matches = _maybeWatchRepo<MatchRepository>(context);
    final PersonRepository? people = _maybeWatchRepo<PersonRepository>(context);
    if (matches == null || people == null) {
      return const SizedBox.shrink();
    }
    final int ideas = ActivityStats.allTime(
      people: people.getAll(),
      matches: matches.getAll(),
      matchStatusEvents: matches.getAllStatusEvents(),
      excludedFromDating: DatingCountExclusions.all(),
    ).ideas;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: MatchmakerRankBadge(
        own: true,
        ideas: ideas,
        gender: _maybeWatchRepo<UserProfileProvider>(context)?.gender,
      ),
    );
  }
}

T? _maybeWatchRepo<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
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
      foregroundImage: hasPhoto
          ? ResizeImage(
              FileImage(File(path)),
              width: (radius * 2 * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              policy: ResizeImagePolicy.fit,
            )
          : null,
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
                color: dark
                    ? AppColors.secondaryDarkDm
                    : context.tokens.ctaAccent,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: Icon(
                hasPhoto ? Icons.edit : Icons.add_a_photo_outlined,
                size: 14,
                color: context.tokens.onAccent,
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
