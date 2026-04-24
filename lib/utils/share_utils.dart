import 'dart:io';

import 'package:share_plus/share_plus.dart';
import 'package:shadchan/models/person.dart';

abstract final class ShareUtils {
  static Future<void> sharePerson(Person person) async {
    final String shareText = (person.description ?? '').trim();

    final List<String> photoPaths = _existingPhotoPaths(person);

    if (photoPaths.isNotEmpty) {
      await Share.shareXFiles(
        photoPaths.map((String path) => XFile(path)).toList(),
        text: shareText,
      );
      return;
    }

    await Share.share(shareText);
  }

  static List<String> _existingPhotoPaths(Person person) {
    return person.photosPaths
        .where((String path) => File(path).existsSync())
        .toList();
  }
}
