import 'dart:async';
import 'package:shadchan/services/analytics_service.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/account_dialogs.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/person_extended_edit_screen.dart';
import 'package:shadchan/screens/intro_screens.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/image_shrink.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// Shown on first launch so the matchmaker can introduce themselves. Name,
/// gender and personal status are required; a photo is optional.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  Gender _selectedGender = Gender.male;

  /// "איך תרצה להשתמש בשדכן?" — preset from the answer given before
  /// signing in; asked here when there was none (an install from before).
  EntryRoute? _usage;
  String? _photoPath;
  bool _saving = false;
  bool _loadedExistingProfile = false;

  /// True once the button has been pressed with something still missing.
  ///
  /// **The button is never disabled.** A dead button explains nothing: someone
  /// who filled in a first name and stopped is left pressing a grey rectangle
  /// with no idea what the app is waiting for. Pressing it always does
  /// something — either it continues, or it says in red exactly which answer is
  /// missing and scrolls it into view. Nothing turns red before the first
  /// press, so nobody is scolded for a form they have not finished typing.
  bool _showErrors = false;

  /// Anchors for scrolling the first missing answer into view.
  final GlobalKey _firstNameKey = GlobalKey();
  final GlobalKey _lastNameKey = GlobalKey();
  final GlobalKey _maritalStatusKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedExistingProfile) {
      return;
    }
    _loadedExistingProfile = true;
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    // A profile saved before the name was split answers both of these from the
    // one joined value, so re-opening this screen never loses a surname.
    _firstNameController.text = profile.firstName ?? '';
    _lastNameController.text = profile.lastName ?? '';
    _selectedGender = profile.gender ?? Gender.male;
    _photoPath = profile.photoPath;
    _usage =
        WorkspaceStore.entryRoute ??
        (profile.hasMaritalStatus
            ? (profile.isSingle ? EntryRoute.both : EntryRoute.matchmaker)
            : null);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Somebody who came in as a card owner is not walked through the
    // matchmaker's introduction at all: the first thing they fill in is their
    // own card, and the name and gender on it become their profile.
    if (WorkspaceStore.entryRoute == EntryRoute.cardOwner) {
      return PersonExtendedEditScreen.ownerCard(onFinished: _finishAsCardOwner);
    }

    // The welcome comes first, on the very first launch only. It says what the
    // app is and — the part that actually changes behaviour — that the database
    // is private, before anybody is asked to type anything into it.
    if (!context.watch<UserProfileProvider>().hasSeenIntro) {
      return IntroScreens(
        onFinished: () => context.read<UserProfileProvider>().markIntroSeen(),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(Icons.favorite, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              // The greeting follows the gender chosen just below it, so the
              // app is speaking to the right person from its very first line.
              Text(
                'נעים להכיר!',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'איזה כיף {שאתה רוצה|שאת רוצה} לחשוב על החברים שלך!'.forGender(
                  _selectedGender,
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: _PhotoPicker(
                  photoPath: _photoPath,
                  onTap: _pickPhoto,
                  onRemove: _photoPath == null
                      ? null
                      : () => setState(() => _photoPath = null),
                ),
              ),
              const SizedBox(height: 32),
              Text('איך קוראים לך?', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              // Two fields rather than one, because the two are used for
              // different things: the home screen greets by the first name
              // alone, and a tip contributed to the community is signed in
              // full. Asking once, plainly, beats guessing later where one name
              // ends and the other begins.
              TextField(
                key: _firstNameKey,
                controller: _firstNameController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'שם פרטי',
                  prefixIcon: const Icon(Icons.person_outline),
                  errorText: _missingFirstName ? 'צריך למלא שם פרטי' : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                key: _lastNameKey,
                controller: _lastNameController,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'שם משפחה',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  errorText: _missingLastName ? 'צריך למלא שם משפחה' : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              Text('מגדר', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<Gender>(
                segments: const <ButtonSegment<Gender>>[
                  ButtonSegment<Gender>(
                    value: Gender.male,
                    icon: Icon(Icons.male),
                    label: Text('זכר'),
                  ),
                  ButtonSegment<Gender>(
                    value: Gender.female,
                    icon: Icon(Icons.female),
                    label: Text('נקבה'),
                  ),
                ],
                selected: <Gender>{_selectedGender},
                onSelectionChanged: (Set<Gender> selection) {
                  setState(() => _selectedGender = selection.first);
                },
              ),
              const SizedBox(height: 24),
              Text(
                key: _maritalStatusKey,
                'איך {תרצה|תרצי} להשתמש בשדכן?'.forGender(_selectedGender),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: _missingMaritalStatus ? theme.colorScheme.error : null,
                ),
              ),
              const SizedBox(height: 8),
              _UsageChoice(
                gender: _selectedGender,
                selected: _usage,
                onSelected: (EntryRoute usage) {
                  setState(() => _usage = usage);
                  if (usage == EntryRoute.cardOwner) {
                    // A single only: the card is the sign-up.
                    WorkspaceStore.chooseEntry(EntryRoute.cardOwner);
                  }
                },
              ),
              const SizedBox(height: 8),
              if (_missingMaritalStatus)
                Text(
                  'צריך לבחור איך להשתמש בשדכן',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              // Nothing about the community is asked for here. The line about
              // yourself and the public prompts are filled in later from the
              // profile — sign-up is only who you are.
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _saving ? null : _continue,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('יאללה, מתחילים!'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canContinue =>
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _usage != null;

  bool get _missingFirstName =>
      _showErrors && _firstNameController.text.trim().isEmpty;

  bool get _missingLastName =>
      _showErrors && _lastNameController.text.trim().isEmpty;

  bool get _missingMaritalStatus => _showErrors && _usage == null;

  /// The topmost unanswered question, so the red mark is one somebody can see.
  GlobalKey? get _firstMissingKey {
    if (_firstNameController.text.trim().isEmpty) {
      return _firstNameKey;
    }
    if (_lastNameController.text.trim().isEmpty) {
      return _lastNameKey;
    }
    if (_usage == null) {
      return _maritalStatusKey;
    }
    return null;
  }

  Future<void> _continue() async {
    final bool openCard = _usage == EntryRoute.both;
    if (!_canContinue) {
      final GlobalKey? missing = _firstMissingKey;
      setState(() => _showErrors = true);
      // The keyboard would otherwise cover the answer being pointed at.
      FocusScope.of(context).unfocus();
      HapticFeedback.mediumImpact();
      final BuildContext? target = missing?.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          alignment: 0.2,
        );
      }
      return;
    }

    // **A clear step for the photo.** It is still optional, but a matchmaker
    // with a face is somebody other matchmakers recognise — on the profile,
    // in the community, on the leaderboard and when connecting — so the
    // question is asked once, plainly, rather than left to a small circle at
    // the top of the form.
    if (_photoPath == null && !_photoAsked) {
      _photoAsked = true;
      final bool add = await _askForPhoto();
      if (!mounted) return;
      if (add) {
        await _pickPhoto();
        if (!mounted) return;
      }
    }

    setState(() => _saving = true);
    try {
      final UserProfileProvider profile = context.read<UserProfileProvider>();
      await profile.saveProfile(
        name: _firstNameController.text,
        lastName: _lastNameController.text,
        gender: _selectedGender,
        isSingle: _usage!.wantsCard,
        // No `about`: it is not asked for here, and an omitted value leaves
        // whatever the profile already has.
        photoPath: _photoPath,
      );
      WorkspaceStore.setMatchmakerEnabled(true);
      WorkspaceStore.chooseEntry(_usage!);
      Analytics.log(AnalyticsEvent.signup_completed, <String, Object?>{
        'user_type': _usage == EntryRoute.both ? 'both' : 'matchmaker',
      });
      if (!mounted) {
        return;
      }
      // The number is compulsory for a matchmaker (2026-11-20): it is how
      // matchmakers who know each other find each other, how friends who
      // keep a personal card find them, and how they reach each other on
      // WhatsApp. The dialog has no "דילוג"; it is asked until given.
      while (mounted && profile.myPhone == null) {
        final MyPhoneOutcome outcome = await MyPhoneDialog.showForSignUp(
          context,
          purpose: MyPhonePurpose.matchmaker,
          belongsToAnotherAccount: _belongsToAnotherAccount,
          mandatory: true,
        );
        CommunityPromptsStore.markMatchmakerPhoneAsked();
        if (!mounted) {
          return;
        }
        if (outcome.useExistingAccount) {
          await _switchToExistingAccount();
          return;
        }
        if (outcome.phone != null) {
          await profile.setMyPhone(outcome.phone);
        }
        if (!mounted) {
          return;
        }
      }
      if (openCard) {
        // Home first, the card editor on top of it: back from the editor
        // lands on the one home of the app.
        context.go('/home');
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) unawaited(context.push('/me/card'));
        return;
      }
      // Straight into the real home screen. Landing on the add-contacts flow
      // instead made the first thing the app ever showed a task standing
      // between the matchmaker and everything else; the invitation to add
      // friends is now a card on the home screen itself, which can be taken up
      // or scrolled past.
      context.go('/home');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// The card owner's sign-up ends when their first card is saved: the card's
  /// name and gender are the profile, and the app opens on their own area.
  Future<void> _finishAsCardOwner() async {
    final PersonalCardProvider cards = context.read<PersonalCardProvider>();
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final Person? card = cards.card;
    if (card == null) {
      return;
    }
    await profile.saveProfile(
      name: card.firstName,
      lastName: card.lastName,
      gender: card.gender,
      isSingle: true,
    );
    Analytics.log(AnalyticsEvent.signup_completed, <String, Object?>{
      'user_type': 'single',
    });
    WorkspaceStore.setMatchmakerEnabled(false);
    if (!mounted) {
      return;
    }
    // The number is what lets friends who match find this card. Asked here,
    // once, and skippable — the personal area asks again while it is missing.
    if (profile.myPhone == null) {
      final MyPhoneOutcome outcome = await MyPhoneDialog.showForSignUp(
        context,
        belongsToAnotherAccount: _belongsToAnotherAccount,
      );
      if (!mounted) {
        return;
      }
      if (outcome.useExistingAccount) {
        await _switchToExistingAccount();
        return;
      }
      if (outcome.phone != null) {
        await profile.setMyPhone(outcome.phone);
      }
    }
    if (mounted) {
      context.go('/home');
    }
  }

  /// Whether [phone] is already published under a different account.
  ///
  /// Read from `phoneDirectory`, the one place a number is tied to an
  /// account. No answer (offline, no Firebase) counts as no: the step must
  /// never stop somebody signing up.
  static Future<bool> _belongsToAnotherAccount(String phone) async {
    final String? hash = PhoneIdentity.hash(phone);
    if (hash == null) {
      return false;
    }
    final Map<String, dynamic>? entry = await PersonalCardService.lookup(
      hash,
    ).timeout(const Duration(seconds: 8), onTimeout: () => null);
    final Object? owner = entry?['uid'];
    if (owner is! String || owner.isEmpty) {
      return false;
    }
    return owner != await PersonalCardService.durableUid();
  }

  /// "התחברות לחשבון הקיים": this new account is left before anything is
  /// written into it, and the sign-in screen is where the other one is
  /// entered — in whichever way it was made.
  Future<void> _switchToExistingAccount() async {
    final OverlayState? notices = AppNotice.capture(context);
    await AccountDialogs.signOut(context);
    AppNotice.showOn(
      notices,
      'אפשר להתחבר עכשיו לחשבון הקיים, באותה דרך שבה נרשמת אליו.',
    );
  }

  bool _photoAsked = false;

  /// "רוצה להוסיף תמונת פרופיל?" — answers whether to open the gallery.
  Future<bool> _askForPhoto() async {
    final bool? add = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(Icons.add_a_photo_outlined),
        title: const Text('להוסיף תמונת פרופיל?'),
        content: const Text(
          'התמונה תופיע בפרופיל שלך, בקהילה, בדירוג ובחיבורים עם שדכנים '
          'אחרים — כך קל יותר לזהות אותך. אפשר גם להוסיף אחר כך.',
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('דילוג'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('הוספת תמונה'),
          ),
        ],
      ),
    );
    return add ?? false;
  }

  Future<void> _pickPhoto() async {
    final bool hasPermission = await _ensureMediaPermission();
    if (!hasPermission || !mounted) {
      return;
    }

    try {
      final XFile? pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: ImageShrink.pickerMaxSide,
        maxHeight: ImageShrink.pickerMaxSide,
        imageQuality: ImageShrink.pickerQuality,
      );
      if (pickedFile == null || !mounted) {
        return;
      }

      final Directory documentsDirectory =
          await getApplicationDocumentsDirectory();
      final Directory photosDirectory = Directory(
        '${documentsDirectory.path}${Platform.pathSeparator}photos',
      );
      if (!photosDirectory.existsSync()) {
        photosDirectory.createSync(recursive: true);
      }

      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      final String targetPath =
          '${photosDirectory.path}${Platform.pathSeparator}me_$timestamp.jpg';
      await ImageShrink.shrinkInto(File(pickedFile.path), targetPath);

      if (!mounted) {
        return;
      }
      setState(() => _photoPath = targetPath);
    } on PlatformException {
      if (mounted) {
        _showSnackBar('לא הצלחנו לבחור תמונה כרגע');
      }
    } catch (_) {
      if (mounted) {
        _showSnackBar('לא הצלחנו לשמור את התמונה');
      }
    }
  }

  Future<bool> _ensureMediaPermission() async {
    if (Platform.isAndroid) {
      return true;
    }

    final PermissionStatus status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) {
      return true;
    }

    if (mounted) {
      _showSnackBar('כדי להוסיף תמונה צריך לאשר גישה לגלריה בהגדרות המכשיר.');
    }
    return false;
  }

  void _showSnackBar(String message) {
    AppNotice.show(context, message);
  }
}

/// "איך תרצה להשתמש בשדכן?" — three answers, one account whichever is
/// picked. Changeable later from the profile ("השימוש שלי בשדכן").
class _UsageChoice extends StatelessWidget {
  const _UsageChoice({
    required this.gender,
    required this.selected,
    required this.onSelected,
  });

  final Gender gender;
  final EntryRoute? selected;
  final ValueChanged<EntryRoute> onSelected;

  static String labelOf(EntryRoute route, Gender? gender) => switch (route) {
    EntryRoute.cardOwner => '{רווק|רווקה}'.forGender(gender),
    EntryRoute.matchmaker => '{שדכן|שדכנית}'.forGender(gender),
    EntryRoute.both => '{רווק וגם שדכן|רווקה וגם שדכנית}'.forGender(gender),
  };

  static String hintOf(EntryRoute route) => switch (route) {
    EntryRoute.cardOwner => 'כרטיס אישי, והחברים שמשדכים רואים אותו',
    EntryRoute.matchmaker => 'מאגר של חברים ורעיונות לשידוכים',
    EntryRoute.both => 'הכרטיס שלך וגם המאגר — באותה אפליקציה',
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: <Widget>[
        for (final EntryRoute route in const <EntryRoute>[
          EntryRoute.cardOwner,
          EntryRoute.matchmaker,
          EntryRoute.both,
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: route == selected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: route == selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelected(route),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        route == selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              labelOf(route, gender),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              hintOf(route),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.photoPath,
    required this.onTap,
    required this.onRemove,
  });

  final String? photoPath;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? path = photoPath;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Stack(
          children: <Widget>[
            GestureDetector(
              onTap: onTap,
              child: CircleAvatar(
                radius: 52,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: path != null ? FileImage(File(path)) : null,
                child: path != null
                    ? null
                    : Icon(
                        Icons.add_a_photo_outlined,
                        size: 32,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 0,
                left: 0,
                child: GestureDetector(
                  onTap: onRemove,
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.errorContainer,
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (path == null)
          TextButton(onPressed: onTap, child: const Text('הוספת תמונת פרופיל'))
        else
          Text(
            'תמונה נבחרה',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (path == null)
          Text(
            'תופיע בפרופיל, בקהילה ובחיבורים עם שדכנים',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
