import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
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

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryLight,
      child: Text(
        person.initials.isEmpty ? '?' : person.initials,
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.75,
        ),
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
