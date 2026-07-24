import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
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

    // No photo: fall back to a gender icon inside a gender-tinted circle — a
    // man in blue, a woman in pink. Unknown gender keeps the neutral initials.
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Gender gender = person.gender;
    if (gender == Gender.male || gender == Gender.female) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.genderSurface(gender, dark: dark),
        child: Icon(
          gender == Gender.female ? Icons.woman : Icons.man,
          color: AppColors.genderAccent(gender, dark: dark),
          size: radius * 1.2,
        ),
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
