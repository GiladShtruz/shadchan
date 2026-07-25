import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/person_avatar_assets.dart';
import 'package:shadchan/models/person.dart';

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.person, required this.radius});

  final Person person;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String? firstPhotoPath = _firstExistingPhotoPath();

    if (firstPhotoPath != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(File(firstPhotoPath)),
      );
    }

    final String? avatarAsset = PersonAvatarAssets.pathFor(
      person.gender,
      person.avatarIndex,
    );
    if (avatarAsset != null) {
      final double diameter = radius * 2;
      final double pixelRatio = MediaQuery.devicePixelRatioOf(context);
      final int cacheSize = (diameter * pixelRatio).ceil();
      return ClipOval(
        child: Image.asset(
          avatarAsset,
          width: diameter,
          height: diameter,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          fit: BoxFit.cover,
        ),
      );
    }

    // Unknown gender keeps a simple, neutral standard person icon.
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryLight,
      child: Icon(
        Icons.person_outline,
        color: AppColors.primary,
        size: radius * 1.15,
      ),
    );
  }

  String? _firstExistingPhotoPath() {
    if (person.photosPaths.isEmpty) {
      return null;
    }

    final String path = person.photosPaths.first;
    return File(path).existsSync() ? path : null;
  }
}
