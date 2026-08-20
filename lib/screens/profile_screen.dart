import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
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
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/person_photo_editor.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "הפרופיל שלי" — the matchmaker's own page, and the one place the app's
/// settings live. The home screen used to carry a gear icon; it now carries the
/// user's photo, and everything that was behind the gear is here, under the
/// person it belongs to.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// Whether the personal card preview is showing its full text.
  bool _personalCardExpanded = false;

  @override
  Widget build(BuildContext context) {
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final AccountProvider account = context.watch<AccountProvider>();
    final SyncProvider sync = context.watch<SyncProvider>();

    final List<Widget> sections = <Widget>[
      _ProfileHeader(profile: profile, onEditPhoto: () => _editPhoto(profile)),
      const SizedBox(height: 6),
      // The answer was already given during sign-up. All that is left here is a
      // quiet way back to it if it ever changes — not a section of its own.
      _PersonalStatusLine(
        profile: profile,
        onChangeRequested: () => _changePersonalStatus(profile),
      ),
      const SizedBox(height: 18),
      if (profile.isSingle) ...<Widget>[
        _PersonalCardCard(
          profile: profile,
          expanded: _personalCardExpanded,
          onToggleExpanded: () =>
              setState(() => _personalCardExpanded = !_personalCardExpanded),
          onEditCard: () => _editPersonalCard(profile),
          onShareCard: () => _sharePersonalCard(profile),
        ),
        const SizedBox(height: 22),
      ],

      // The feedback console, for the handful of accounts that have one, at the
      // very top. It used to be the last group on the page, below the account —
      // which is where somebody puts a screen they never intend to open, and
      // the tips waiting for approval sat on a *different* row further up. One
      // entry, first, so what users sent is never further away than the profile
      // picture.
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

      // Everything below is one row per subject and a screen behind it. The
      // page used to carry nine headings and every option in the app at once,
      // which meant the two things people actually come here for — the backup
      // and the account — were somewhere in the middle of forty rows.
      SettingsGroup(
        title: 'התאמה אישית',
        children: <Widget>[
          SettingsRow(
            icon: Icons.palette_outlined,
            title: 'תצוגה וערכת נושא',
            onTap: () => context.push('/profile/appearance'),
          ),
          SettingsRow(
            icon: Icons.style_outlined,
            title: 'סגנונות דתיים',
            onTap: () => context.push('/profile/religious-levels'),
          ),
        ],
      ),
      SettingsGroup(
        title: 'המאגר והנתונים שלי',
        children: <Widget>[
          SettingsRow(
            icon: Icons.folder_outlined,
            title: 'גיבוי, ייצוא ופרטיות',
            subtitle: 'גיבוי בענן, שחזור, ייצוא לאקסל וייבוא',
            onTap: () => context.push('/profile/data'),
          ),
        ],
      ),
      SettingsGroup(
        title: 'קהילה ושיתוף',
        children: <Widget>[
          if (CommunityLinks.hasUpdatesGroup)
            SettingsRow(
              icon: Icons.groups_outlined,
              title: 'קבוצת העדכונים',
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
            onTap: shareTheApp,
          ),
          SettingsRow(
            icon: Icons.lightbulb_outline,
            title: 'טיפים לשדכנים',
            onTap: () => context.push('/profile/tips-list'),
          ),
          SettingsRow(
            icon: Icons.edit_note_outlined,
            title: 'הוספת טיפ',
            onTap: () => context.push('/profile/tips'),
          ),
        ],
      ),
      SettingsGroup(
        title: 'עזרה ומשוב',
        children: <Widget>[
          SettingsRow(
            icon: Icons.support_agent_outlined,
            title: 'עזרה, תקלות ויצירת קשר',
            onTap: () => context.push('/profile/help'),
          ),
        ],
      ),
      _AccountGroup(
        account: account,
        onSignIn: () => context.push('/sign-in'),
        onSignOut: () => _confirmSignOut(account, sync),
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

  // --- The personal card --------------------------------------------------

  Future<void> _editPersonalCard(UserProfileProvider profile) async {
    final List<String> initialPhotos = profile.personalCardPhotos;
    final _PersonalCardDraft? draft =
        await showModalBottomSheet<_PersonalCardDraft>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (BuildContext sheetContext) {
            return _PersonalCardEditorSheet(
              initialText: profile.personalCard ?? '',
              initialPhotos: initialPhotos,
            );
          },
        );
    if (draft == null) {
      return;
    }
    await profile.setPersonalCardContent(
      text: draft.text,
      photoPaths: draft.photos,
    );
    PhotoPickerService.deletePhotoFiles(
      initialPhotos.where((String path) => !draft.photos.contains(path)),
    );
  }

  Future<void> _sharePersonalCard(UserProfileProvider profile) async {
    final String card = profile.personalCard ?? '';
    final List<String> photos = profile.personalCardPhotos;
    if (card.isEmpty && photos.isEmpty) {
      return;
    }
    await ShareUtils.shareText(card, photoPaths: photos);
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

/// The account group: connected, or the clearest invitation in the settings to
/// connect one.
///
/// Signed out it is deliberately the most prominent thing on the page after the
/// profile itself — a filled button and one sentence — because it is the only
/// row here that protects everything the others act on. Signed in it collapses
/// to the address and a quiet way out.
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

/// The photo, the name and one gendered line of welcome.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.onEditPhoto});

  final UserProfileProvider profile;
  final VoidCallback onEditPhoto;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Gender? gender = profile.gender;

    return Column(
      children: <Widget>[
        UserProfileAvatar(
          photoPath: profile.photoPath,
          gender: gender,
          radius: 46,
          onTap: onEditPhoto,
          showEditBadge: true,
        ),
        const SizedBox(height: 12),
        Text(
          profile.name ?? '{שדכן|שדכנית}'.forGender(gender),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          profile.photoPath == null
              ? 'אפשר להוסיף תמונה — היא תופיע בראש עמוד הבית'
              : 'תודה {שאתה חושב|שאת חושבת} על החברים שלך'.forGender(gender),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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

/// The matchmaker's own card, at the top of their page and only when they are
/// single.
///
/// It is a preview, not an editor: the text alone, four lines of it, with the
/// two things anyone ever wants to do with it — change it, send it — as icons
/// in the corner. Anything more would make a card that has to be scrolled past
/// on the way to the settings underneath.
class _PersonalCardCard extends StatelessWidget {
  const _PersonalCardCard({
    required this.profile,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEditCard,
    required this.onShareCard,
  });

  final UserProfileProvider profile;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEditCard;
  final VoidCallback onShareCard;

  /// Roughly how many lines fit in the collapsed preview.
  static const int _previewLines = 4;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String card = (profile.personalCard ?? '').trim();
    final List<String> photos = profile.personalCardPhotos;
    final bool hasCard = card.isNotEmpty || photos.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'הכרטיס שלך',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (hasCard) ...<Widget>[
                  IconButton(
                    onPressed: onEditCard,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'עריכת הכרטיס',
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  IconButton(
                    onPressed: onShareCard,
                    icon: const Icon(Icons.ios_share, size: 20),
                    tooltip: 'שיתוף הכרטיס',
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
            if (!hasCard) ...<Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Text(
                  'כאן אפשר לשמור את הכרטיס שלך, כדי לשתף אותו בקלות בכל פעם '
                  'שצריך.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: onEditCard,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('יצירת הכרטיס'),
                  ),
                ),
              ),
            ] else ...<Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Text(
                  card.isEmpty ? 'הכרטיס שלך שמור כאן.' : card,
                  maxLines: expanded ? null : _previewLines,
                  overflow: expanded
                      ? TextOverflow.clip
                      : TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
              if (_isLong(card))
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: onToggleExpanded,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: theme.textTheme.bodySmall,
                    ),
                    child: Text(expanded ? 'הצג פחות' : 'הצג עוד'),
                  ),
                ),
              if (photos.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _PersonalCardPhotos(photos: photos),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Cheap stand-in for "does not fit in the preview": either it already has
  /// more lines than the preview shows, or it is long enough to wrap past it.
  static bool _isLong(String card) {
    return '\n'.allMatches(card).length >= _previewLines || card.length > 180;
  }
}

/// Every photo saved on the personal card, laid out under its text.
///
/// The card used to show its text and nothing else, so the only way to find out
/// which photos were attached — or how many — was to open the editor. That is
/// the wrong moment to discover it: this card exists to be *shared*, the photos
/// go with it, and nobody should have to send it once to learn what it sends.
/// They are all here, in the order they will go out in, with the first one
/// marked because that is the one that leads.
class _PersonalCardPhotos extends StatelessWidget {
  const _PersonalCardPhotos({required this.photos});

  final List<String> photos;

  static const double _thumbSize = 74;

  Future<void> _open(BuildContext context, int index) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext dialogContext) =>
          _PersonalCardPhotoViewer(photos: photos, initialIndex: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.photo_library_outlined,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  photos.length == 1
                      ? 'תמונה אחת תישלח יחד עם הכרטיס'
                      : '${photos.length} תמונות יישלחו יחד עם הכרטיס',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _thumbSize,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Flush with the card's text on the start edge; the trailing gap is
            // the card's own padding.
            padding: const EdgeInsetsDirectional.only(end: 8),
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              return _PersonalCardThumb(
                path: photos[index],
                isFirst: index == 0,
                size: _thumbSize,
                onTap: () => _open(context, index),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PersonalCardThumb extends StatelessWidget {
  const _PersonalCardThumb({
    required this.path,
    required this.isFirst,
    required this.size,
    required this.onTap,
  });

  final String path;
  final bool isFirst;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox.square(
      dimension: size,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.file(
                File(path),
                fit: BoxFit.cover,
                // A photo whose file has gone is shown as a gap rather than as
                // a red error box on the matchmaker's own profile.
                errorBuilder: (_, _, _) => Icon(
                  Icons.broken_image_outlined,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (isFirst)
                PositionedDirectional(
                  start: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    color: Colors.black54,
                    child: const Text(
                      'ראשית',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The photos at full size, swipeable, on a dark ground.
class _PersonalCardPhotoViewer extends StatelessWidget {
  const _PersonalCardPhotoViewer({
    required this.photos,
    required this.initialIndex,
  });

  final List<String> photos;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: photos.length,
              itemBuilder: (BuildContext context, int index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.file(File(photos[index]), fit: BoxFit.contain),
                  ),
                );
              },
            ),
          ),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 8,
            end: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'סגירה',
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalCardDraft {
  const _PersonalCardDraft({required this.text, required this.photos});

  final String text;
  final List<String> photos;
}

class _PersonalCardEditorSheet extends StatefulWidget {
  const _PersonalCardEditorSheet({
    required this.initialText,
    required this.initialPhotos,
  });

  final String initialText;
  final List<String> initialPhotos;

  @override
  State<_PersonalCardEditorSheet> createState() =>
      _PersonalCardEditorSheetState();
}

class _PersonalCardEditorSheetState extends State<_PersonalCardEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  late final List<String> _photos = List<String>.of(widget.initialPhotos);
  final Set<String> _newPhotos = <String>{};
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    if (!_submitted) {
      PhotoPickerService.deletePhotoFiles(_newPhotos);
    }
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final List<String> added = await PhotoPickerService.pickPhotos(
      context,
      personId: 'my_personal_card',
    );
    if (!mounted || added.isEmpty) {
      return;
    }
    setState(() {
      _photos.addAll(added);
      _newPhotos.addAll(added);
    });
  }

  void _setPrimary(int index) {
    if (index <= 0 || index >= _photos.length) {
      return;
    }
    setState(() {
      final String path = _photos.removeAt(index);
      _photos.insert(0, path);
    });
  }

  void _removePhoto(int index) {
    final String removed = _photos.removeAt(index);
    if (_newPhotos.remove(removed)) {
      PhotoPickerService.deletePhotoFiles(<String>[removed]);
    }
    setState(() {});
  }

  void _reorderPhotos(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final String path = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, path);
    });
  }

  void _save() {
    _submitted = true;
    Navigator.of(context).pop(
      _PersonalCardDraft(
        text: _controller.text.trim(),
        photos: List<String>.unmodifiable(_photos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, keyboard + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'עריכת הכרטיס האישי',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'אפשר לשמור טקסט חופשי, להוסיף כמה תמונות שרוצים ולסדר אותן.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                children: <Widget>[
                  TextField(
                    controller: _controller,
                    minLines: 6,
                    maxLines: 12,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'הטקסט שלי',
                      hintText: 'אפשר לכתוב או להדביק כאן את הכרטיס שלך',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PersonPhotoEditor(
                    photoPaths: _photos,
                    onAddPhoto: _addPhotos,
                    onSetPrimary: _setPrimary,
                    onRemove: _removePhoto,
                    onReorder: _reorderPhotos,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ביטול'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('שמירת הכרטיס'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The theme picker, moved here from the old settings screen unchanged.
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
