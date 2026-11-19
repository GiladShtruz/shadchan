import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The matchmaker's own small photo at the start of the home greeting — the
/// right, in RTL — or, with no photo yet, a clear "+" that adds one.
///
/// This replaces the separate "הוסף תמונת פרופיל" line that used to sit
/// lower on the page: the place a face belongs is next to the name.
///
/// With a photo, a tap opens the profile; without one, a tap opens the
/// gallery and the chosen picture becomes the profile photo at once.
class HomeGreetingAvatar extends StatelessWidget {
  const HomeGreetingAvatar({super.key, this.size = 46});

  final double size;

  Future<void> _addPhoto(BuildContext context) async {
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final String? path = await PhotoPickerService.pickSinglePhoto(context);
    if (path == null) return;
    await profile.setPhotoPath(path);
  }

  @override
  Widget build(BuildContext context) {
    final String? path = context.select<UserProfileProvider, String?>(
      (UserProfileProvider p) => p.photoPath,
    );
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color blue = dark ? AppColors.primaryDarkDm : AppColors.primary;

    if (path == null) {
      return Semantics(
        button: true,
        label: 'הוספת תמונת פרופיל',
        child: Tooltip(
          message: 'הוספת תמונת פרופיל',
          child: InkResponse(
            onTap: () => _addPhoto(context),
            radius: size / 2 + 4,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: blue.withValues(alpha: dark ? 0.18 : 0.10),
                border: Border.all(color: blue, width: 1.6),
              ),
              child: Icon(Icons.add_rounded, size: size * 0.55, color: blue),
            ),
          ),
        ),
      );
    }

    final int cache = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Semantics(
      button: true,
      label: 'הפרופיל שלי',
      child: InkResponse(
        onTap: () => context.push('/profile'),
        radius: size / 2 + 4,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.surface, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: Image(
              // Decoded at the size it is drawn: a full camera photo for a
              // 46px circle is the kind of work that makes a scroll stutter.
              image: ResizeImage(
                FileImage(File(path)),
                width: cache,
                height: cache,
                policy: ResizeImagePolicy.fit,
              ),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => ColoredBox(
                color: blue.withValues(alpha: 0.12),
                child: Icon(Icons.person_outline, color: blue),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
