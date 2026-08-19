import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/intro_screens.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

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
  bool? _selectedIsSingle;
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
    _selectedIsSingle = profile.hasMaritalStatus ? profile.isSingle : null;
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
                '{ברוך הבא שדכן|ברוכה הבאה שדכנית}!'.forGender(_selectedGender),
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
                'מה המצב האישי שלך?',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: _missingMaritalStatus ? theme.colorScheme.error : null,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: true,
                    icon: const Icon(Icons.favorite_border_rounded),
                    label: Text('{רווק|רווקה}'.forGender(_selectedGender)),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    icon: const Icon(Icons.home_outlined),
                    label: Text('{נשוי|נשואה}'.forGender(_selectedGender)),
                  ),
                ],
                emptySelectionAllowed: true,
                selected: _selectedIsSingle == null
                    ? const <bool>{}
                    : <bool>{_selectedIsSingle!},
                onSelectionChanged: (Set<bool> selection) {
                  if (selection.isNotEmpty) {
                    setState(() => _selectedIsSingle = selection.first);
                  }
                },
              ),
              const SizedBox(height: 8),
              if (_missingMaritalStatus)
                Text(
                  'צריך לבחור מצב אישי',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              Text(
                'למשתמשים רווקים תופיע בפרופיל אפשרות לשמור ולשתף כרטיס אישי.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
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
      _selectedIsSingle != null;

  bool get _missingFirstName =>
      _showErrors && _firstNameController.text.trim().isEmpty;

  bool get _missingLastName =>
      _showErrors && _lastNameController.text.trim().isEmpty;

  bool get _missingMaritalStatus => _showErrors && _selectedIsSingle == null;

  /// The topmost unanswered question, so the red mark is one somebody can see.
  GlobalKey? get _firstMissingKey {
    if (_firstNameController.text.trim().isEmpty) {
      return _firstNameKey;
    }
    if (_lastNameController.text.trim().isEmpty) {
      return _lastNameKey;
    }
    if (_selectedIsSingle == null) {
      return _maritalStatusKey;
    }
    return null;
  }

  Future<void> _continue() async {
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

    setState(() => _saving = true);
    try {
      await context.read<UserProfileProvider>().saveProfile(
        name: _firstNameController.text,
        lastName: _lastNameController.text,
        gender: _selectedGender,
        isSingle: _selectedIsSingle!,
        photoPath: _photoPath,
      );
      if (!mounted) {
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

  Future<void> _pickPhoto() async {
    final bool hasPermission = await _ensureMediaPermission();
    if (!hasPermission || !mounted) {
      return;
    }

    try {
      final XFile? pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
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
      await File(pickedFile.path).copy(targetPath);

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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
        Text(
          path != null ? 'תמונה נבחרה' : 'הוספת תמונה (אופציונלי)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
