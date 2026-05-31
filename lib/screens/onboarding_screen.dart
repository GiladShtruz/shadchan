import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/enums.dart';

/// Shown on first launch so the matchmaker can introduce themselves. Name and
/// gender are required, a photo is optional.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _nameController = TextEditingController();
  Gender _selectedGender = Gender.male;
  String? _photoPath;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(
                Icons.favorite,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'ברוך הבא שדכן!',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'איזה כיף שאתה רוצה לחשוב על חברים שלך!',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              Center(child: _PhotoPicker(
                photoPath: _photoPath,
                onTap: _pickPhoto,
                onRemove: _photoPath == null
                    ? null
                    : () => setState(() => _photoPath = null),
              )),
              const SizedBox(height: 32),
              Text('איך קוראים לך?', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'השם שלך',
                  prefixIcon: Icon(Icons.person_outline),
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
              const SizedBox(height: 40),
              FilledButton(
                onPressed: _canContinue && !_saving ? _continue : null,
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

  bool get _canContinue => _nameController.text.trim().isNotEmpty;

  Future<void> _continue() async {
    setState(() => _saving = true);
    try {
      await context.read<UserProfileProvider>().saveProfile(
        name: _nameController.text,
        gender: _selectedGender,
        photoPath: _photoPath,
      );
      if (!mounted) {
        return;
      }
      // First stop after onboarding: add some contacts to the app.
      context.go('/people/import');
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
                backgroundImage:
                    path != null ? FileImage(File(path)) : null,
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
