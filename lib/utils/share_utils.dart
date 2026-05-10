import 'dart:io';

import 'package:share_plus/share_plus.dart';
import 'package:shadchan/models/person.dart';

abstract final class ShareUtils {
  static Future<void> sharePerson(Person person) async {
    final String shareText = _shareText(person);

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

  static String _shareText(Person person) {
    final String description = (person.description ?? '').trim();
    final String inquiryContact = _inquiryContactText(person);
    if (inquiryContact.isEmpty) {
      return description;
    }

    final String inquiryLine = 'לבירורים: $inquiryContact';
    if (description.isEmpty) {
      return inquiryLine;
    }

    return '$description\n\n$inquiryLine';
  }

  static String _inquiryContactText(Person person) {
    final String name = (person.inquiryContactName ?? '').trim();
    final String phone = (person.inquiryContactPhone ?? '').trim();
    if (name.isEmpty && phone.isEmpty) {
      return '';
    }
    if (name.isEmpty) {
      return phone;
    }
    if (phone.isEmpty) {
      return name;
    }
    return '$name $phone';
  }
}
