import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadchan/services/face_crop_service.dart';
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
      return FaceCenteredPhoto(path: firstPhotoPath, diameter: radius * 2);
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

/// A photo cropped into a circle around the face rather than around the middle
/// of the frame, so a head that sits high or off to one side is not cut off.
///
/// The alignment comes from [FaceCropService]. When it is already cached the
/// first frame is drawn with it; otherwise the photo is shown centred and
/// settles onto the face once detection finishes, which happens once per photo
/// for the whole life of the app.
class FaceCenteredPhoto extends StatefulWidget {
  const FaceCenteredPhoto({
    super.key,
    required this.path,
    required this.diameter,
  });

  final String path;
  final double diameter;

  @override
  State<FaceCenteredPhoto> createState() => _FaceCenteredPhotoState();
}

class _FaceCenteredPhotoState extends State<FaceCenteredPhoto> {
  late Alignment _alignment;

  @override
  void initState() {
    super.initState();
    _loadAlignment();
  }

  @override
  void didUpdateWidget(FaceCenteredPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _loadAlignment();
    }
  }

  void _loadAlignment() {
    final String path = widget.path;
    final Alignment? known = FaceCropService.cached(path);
    _alignment = known ?? Alignment.center;
    if (known != null) {
      return;
    }

    FaceCropService.resolve(path).then((Alignment alignment) {
      // The widget may have been recycled onto another person's photo while
      // detection was running.
      if (mounted && widget.path == path && alignment != _alignment) {
        setState(() => _alignment = alignment);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.file(
        File(widget.path),
        width: widget.diameter,
        height: widget.diameter,
        fit: BoxFit.cover,
        alignment: _alignment,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          return Container(
            width: widget.diameter,
            height: widget.diameter,
            color: AppColors.primaryLight,
            alignment: Alignment.center,
            child: Icon(
              Icons.person_outline,
              color: AppColors.primary,
              size: widget.diameter * 0.575,
            ),
          );
        },
      ),
    );
  }
}
