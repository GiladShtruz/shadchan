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

  /// Shares a free piece of text, optionally with a photo — used by the
  /// matchmaker's own card on the profile screen, which is not a [Person].
  static Future<void> shareText(String text, {String? photoPath}) async {
    final String trimmed = text.trim();
    if (photoPath != null && File(photoPath).existsSync()) {
      await Share.shareXFiles(<XFile>[XFile(photoPath)], text: trimmed);
      return;
    }
    await Share.share(trimmed);
  }

  static List<String> _existingPhotoPaths(Person person) {
    return person.photosPaths
        .where((String path) => File(path).existsSync())
        .toList();
  }

  /// Shares only the card text: the contact's own details are shared
  /// separately, on purpose, through [shareInquiryContact].
  static String _shareText(Person person) {
    return (person.description ?? '').trim();
  }

  /// Shares the person's contact ("איש קשר") as plain text. Returns false when
  /// there is no contact recorded.
  static Future<bool> shareInquiryContact(Person person) async {
    final String contact = inquiryContactText(person);
    if (contact.isEmpty) {
      return false;
    }

    await Share.share('${person.fullName.trim()} — איש קשר: $contact'.trim());
    return true;
  }

  static String inquiryContactText(Person person) {
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
