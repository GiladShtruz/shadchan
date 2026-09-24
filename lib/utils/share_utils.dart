import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/community_links.dart';

/// Everything that leaves the app as a *card*.
///
/// **Every card carries [CommunityLinks.sharedCardCredit] out with it**, and
/// this is the only place that decides so — there are three ways a card can be
/// sent (a candidate's, the matchmaker's own, and one side of a proposal handed
/// to the other over WhatsApp) and a footer that only rode on two of them would
/// be worse than none, because the missing one is the case somebody notices.
///
/// A contact line is **not** a card and does not get one: "יעקב כהן — איש קשר:
/// 05…" is a detail somebody asked for, and three lines of app credit under it
/// would be the tail wagging the dog.
abstract final class ShareUtils {
  /// Where on the screen the share sheet should be anchored.
  ///
  /// **iOS refuses to share without it.** `share_plus` hands the activity
  /// controller to UIKit, and whenever that controller has a popover
  /// presentation controller — which on current iOS is not only iPad — an
  /// empty origin makes the plugin return an error instead of presenting
  /// anything at all. The share silently does nothing, which is exactly what
  /// sharing a card looked like on iPhone. Every share in the app is anchored
  /// through here, on the rect of the widget that was tapped.
  ///
  /// Falls back to a point in the middle of the screen when the context has no
  /// laid-out box of its own — an anchor in the wrong place still shares; no
  /// anchor does not.
  static Rect originOf(BuildContext context) {
    final RenderObject? object = context.findRenderObject();
    if (object is RenderBox && object.hasSize) {
      return object.localToGlobal(Offset.zero) & object.size;
    }
    final Size screen = MediaQuery.of(context).size;
    return Rect.fromCenter(
      center: Offset(screen.width / 2, screen.height / 2),
      width: 1,
      height: 1,
    );
  }

  static Future<void> sharePerson(Person person, {Rect? origin}) async {
    final List<String> photoPaths = _existingPhotoPaths(person);
    final String card = _shareText(person);

    // Nothing to send is nothing to send. Without this guard a candidate with
    // no card text and no photos would share the credit on its own, which is an
    // advertisement somebody did not mean to forward.
    if (card.isEmpty && photoPaths.isEmpty) {
      return;
    }

    final String shareText = CommunityLinks.creditCard(card);

    if (photoPaths.isNotEmpty) {
      await Share.shareXFiles(
        photoPaths.map((String path) => XFile(path)).toList(),
        text: shareText,
        sharePositionOrigin: origin,
      );
      return;
    }

    await Share.share(shareText, sharePositionOrigin: origin);
  }

  /// Shares a card written as free text, with any number of photos.
  /// [photoPath] remains for the older single-profile-photo call sites;
  /// [photoPaths] is the ordered gallery attached to the matchmaker's own card.
  static Future<void> shareText(
    String text, {
    String? photoPath,
    Iterable<String> photoPaths = const <String>[],
    Rect? origin,
  }) async {
    final String trimmed = text.trim();
    final List<String> existing = <String>[
      ...photoPaths.where((String path) => File(path).existsSync()),
      if (photoPath != null && File(photoPath).existsSync()) photoPath,
    ];
    if (trimmed.isEmpty && existing.isEmpty) {
      return;
    }

    final String shareText = CommunityLinks.creditCard(trimmed);
    if (existing.isNotEmpty) {
      await Share.shareXFiles(
        existing.map((String path) => XFile(path)).toList(),
        text: shareText,
        sharePositionOrigin: origin,
      );
      return;
    }
    await Share.share(shareText, sharePositionOrigin: origin);
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
  static Future<bool> shareInquiryContact(Person person, {Rect? origin}) async {
    final String contact = inquiryContactText(person);
    if (contact.isEmpty) {
      return false;
    }

    await Share.share(
      '${person.fullName.trim()} — איש קשר: $contact'.trim(),
      sharePositionOrigin: origin,
    );
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
