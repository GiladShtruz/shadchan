import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Picks photos from the gallery and copies them into the app's own `photos`
/// directory, so a person's card keeps working even if the original is later
/// removed from the gallery. Shared by the add/edit form and the card editor.
abstract final class PhotoPickerService {
  /// Returns the paths of the copied photos; empty when the user cancelled or
  /// the pick failed (the failure is surfaced to the user here).
  static Future<List<String>> pickPhotos(
    BuildContext context, {
    required String personId,
  }) async {
    final bool hasPermission = await _ensureMediaPermission(context);
    if (!hasPermission || !context.mounted) {
      return const <String>[];
    }

    try {
      final List<XFile> pickedFiles = await ImagePicker().pickMultiImage();
      if (pickedFiles.isEmpty) {
        return const <String>[];
      }

      final Directory photosDirectory = await ensurePhotosDirectory();
      final List<String> copiedPhotoPaths = <String>[];
      final int timestamp = DateTime.now().millisecondsSinceEpoch;

      for (int index = 0; index < pickedFiles.length; index++) {
        final String targetPath =
            '${photosDirectory.path}${Platform.pathSeparator}${personId}_${timestamp}_$index.jpg';
        await File(pickedFiles[index].path).copy(targetPath);
        copiedPhotoPaths.add(targetPath);
      }

      return copiedPhotoPaths;
    } on PlatformException catch (error) {
      if (!context.mounted) {
        return const <String>[];
      }

      if (_looksLikePermissionError(error)) {
        await showPermissionExplanationDialog(context);
        return const <String>[];
      }

      _showSnackBar(context, 'לא הצלחנו לבחור תמונה כרגע');
      return const <String>[];
    } catch (_) {
      if (context.mounted) {
        _showSnackBar(context, 'לא הצלחנו לשמור את התמונה');
      }
      return const <String>[];
    }
  }

  static Future<Directory> ensurePhotosDirectory() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final Directory photosDirectory = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}photos',
    );
    if (!photosDirectory.existsSync()) {
      photosDirectory.createSync(recursive: true);
    }
    return photosDirectory;
  }

  /// Best-effort cleanup of photos copied during an edit that was abandoned.
  static void deletePhotoFiles(Iterable<String> paths) {
    for (final String path in paths) {
      final File file = File(path);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {
          // Leaving a stray file behind is better than crashing on cleanup.
        }
      }
    }
  }

  static Future<bool> _ensureMediaPermission(BuildContext context) async {
    if (Platform.isAndroid) {
      return true;
    }

    final PermissionStatus status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) {
      return true;
    }

    if (context.mounted) {
      await showPermissionExplanationDialog(
        context,
        openSettingsAction: status.isPermanentlyDenied || status.isRestricted,
      );
    }
    return false;
  }

  static bool _looksLikePermissionError(PlatformException error) {
    final String combined = '${error.code} ${error.message ?? ''}'
        .toLowerCase();
    return combined.contains('denied') || combined.contains('permission');
  }

  static Future<void> showPermissionExplanationDialog(
    BuildContext context, {
    bool openSettingsAction = false,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('נדרשת הרשאה'),
          content: const Text(
            'כדי להוסיף תמונה צריך לאשר גישה לגלריה בהגדרות המכשיר.',
          ),
          actions: <Widget>[
            if (openSettingsAction)
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await openAppSettings();
                },
                child: const Text('פתיחת הגדרות'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('הבנתי'),
            ),
          ],
        );
      },
    );
  }

  static void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
