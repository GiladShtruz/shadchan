import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// The handful of addresses that connect the app to the people behind it.
///
/// One file rather than strings written into six screens, because every one of
/// these outlives the screen it is shown on: an invite link is regenerated, a
/// support address changes hands, a store listing gets an id only after the
/// first submission.
///
/// **An empty link is a real state, not a bug.** Where a link has not been set
/// yet the feature that would use it is left out of the UI entirely rather than
/// drawn as a button that opens nothing — see [hasUpdatesGroup].
abstract final class CommunityLinks {
  /// Where a written question goes. The one support channel: no WhatsApp line,
  /// deliberately, so a support conversation is never mixed in with the
  /// matchmaking ones on the same phone.
  static const String supportEmail = 'shadchanapp123@gmail.com';

  /// The quiet WhatsApp updates group — administrators post, nobody else.
  ///
  /// Stored as the bare invite, without the `?s=cl&p=a&ilr=0` tracking suffix
  /// WhatsApp appends when the link is copied out of the app: those parameters
  /// describe the copy, not the group, and one of them has been known to send
  /// the opener to a preview page instead of the join sheet.
  ///
  /// Empty would be a real state, not a bug — see [hasUpdatesGroup].
  static const String updatesGroupUrl =
      'https://chat.whatsapp.com/JEgy5ukjnlzKlZzytyXafx';

  static bool get hasUpdatesGroup => updatesGroupUrl.trim().isNotEmpty;

  /// The Android listing, derived from the applicationId in
  /// `android/app/build.gradle.kts`, so it is right without anybody keeping it
  /// in sync.
  static const String androidPackage = 'com.gilad.shadchan';

  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$androidPackage';

  /// The App Store listing. Empty until the app has been submitted and Apple
  /// has assigned it a number — on iOS the share message and the rating prompt
  /// fall back to the Play listing rather than to a dead link.
  static const String appStoreUrl = '';

  /// Where a friend should be sent to download it, from whichever phone the
  /// invitation is being written on.
  static String get downloadUrl {
    if (Platform.isIOS && appStoreUrl.trim().isNotEmpty) {
      return appStoreUrl;
    }
    return playStoreUrl;
  }

  /// Whether there is a store listing to send someone to for a rating. On iOS
  /// with no listing id yet there is nothing to open, so the prompt stays away.
  static bool get hasStoreListing =>
      !Platform.isIOS || appStoreUrl.trim().isNotEmpty;

  /// A `mailto:` for [supportEmail], with the subject and body already filled.
  ///
  /// Built by hand rather than through `Uri(queryParameters:)`, which encodes a
  /// space as `+` — correct for a form post and wrong for a mail client, several
  /// of which drop the pluses straight into the subject line.
  static Uri mailto({String subject = '', String body = ''}) {
    final List<String> parts = <String>[
      if (subject.trim().isNotEmpty)
        'subject=${Uri.encodeComponent(subject.trim())}',
      if (body.trim().isNotEmpty) 'body=${Uri.encodeComponent(body.trim())}',
    ];
    final String query = parts.isEmpty ? '' : '?${parts.join('&')}';
    return Uri.parse('mailto:$supportEmail$query');
  }

  /// Opens the phone's mail app on a new message to support. Returns false when
  /// there is no mail app to open, so the caller can say so rather than leaving
  /// a tap with no visible result.
  static Future<bool> openSupportEmail({
    String subject = 'פנייה מאפליקציית שדכן',
    String body = '',
  }) async {
    try {
      return await launchUrl(
        mailto(subject: subject, body: body),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      return false;
    }
  }

  /// Opens an external link — the group invite, a store listing. Same
  /// swallow-and-report contract as [openSupportEmail].
  static Future<bool> openLink(String url) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || url.trim().isEmpty) {
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }

  /// The line every card carries out of the app with it.
  ///
  /// **A card leaves this app more often than a person does.** A candidate's
  /// details are forwarded from matchmaker to matchmaker, pasted into groups and
  /// screenshotted, and every one of those hops used to lose the fact that it
  /// came from here. One line at the foot of the card is the only marketing in
  /// the product, and it rides on the thing people already wanted to send.
  ///
  /// Kept short and factual on purpose: a card is somebody's shidduch, not an
  /// advertising surface, and a paragraph under it would be read as spam by the
  /// person it was forwarded to — see [shareMessage] for the *invitation*,
  /// which is a different thing said in a different voice.
  static String get sharedCardCredit =>
      'שותף מ"שדכן" - יומן אישי לניהול הצעות.\n'
      'להורדה: $downloadUrl';

  /// [card] with [sharedCardCredit] under it, separated by a blank line so it
  /// reads as a footer rather than as the last sentence of the card.
  ///
  /// Returns the credit alone for an empty card — a card with no text but with
  /// photos is still a card being shared, and the photos are the content. It is
  /// the caller's job not to share nothing at all.
  ///
  /// Never appends twice. A description that already carries the credit is one
  /// somebody pasted back in after receiving it, and a card ending in two
  /// identical footers is worse than one ending in none.
  static String creditCard(String card) {
    final String trimmed = card.trim();
    if (trimmed.contains(sharedCardCredit)) {
      return trimmed;
    }
    if (trimmed.isEmpty) {
      return sharedCardCredit;
    }
    return '$trimmed\n\n$sharedCardCredit';
  }

  /// The invitation, exactly as the matchmaker sends it.
  ///
  /// Written as one voice speaking to a friend rather than as marketing copy —
  /// this message is forwarded by a person, under their own name, to people who
  /// know them.
  static String get shareMessage =>
      'היי! אני משתמש באפליקציית ׳שדכן׳ וחשבתי שזה יכול לעניין גם אותך :)\n'
      'זו אפליקציה שעוזרת לעשות סדר בחברים שחושבים עליהם לשידוכים, ברעיונות '
      'שעולים ובכל מה שקורה איתם – הכול ביומן אישי ופרטי.\n'
      'שווה לך לנסות, נראה לי שזה ממש יכול להתאים לך:\n'
      '$downloadUrl';
}
