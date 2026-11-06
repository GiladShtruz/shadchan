import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    await shareCard(
      text: _shareText(person),
      photoPaths: person.photosPaths,
      origin: origin,
    );
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
    await shareCard(
      text: text,
      photoPaths: <String>[...photoPaths, ?photoPath],
      origin: origin,
    );
  }

  /// **The one way a card leaves the app as a share.** Every photo and the
  /// text go together as one share — one album with one caption in WhatsApp,
  /// never a message per photo and never the same text three times.
  ///
  /// * The photos are the files that exist, each once, in the card's order.
  /// * The text is the card's, with [CommunityLinks.sharedCardCredit] once at
  ///   its foot.
  /// * **Android** opens the system share sheet natively
  ///   (`MainActivity.shareCardWithChooser`): `share_plus` puts the text on the
  ///   intent as one string, which WhatsApp copies onto every photo of a
  ///   multi-photo share. Natively the text goes to WhatsApp as a caption list
  ///   — the text on the first photo, nothing on the rest — and as the usual
  ///   string to every other app.
  /// * **iOS** shares the files and the text in one activity sheet.
  ///
  /// Returns false when there was nothing to share.
  static Future<bool> shareCard({
    required String? text,
    required Iterable<String> photoPaths,
    Rect? origin,
  }) async {
    final String card = (text ?? '').trim();
    final List<String> photos = existingPhotos(photoPaths);
    // Nothing to send is nothing to send. Without this guard a candidate with
    // no card text and no photos would share the credit on its own, which is
    // an advertisement somebody did not mean to forward.
    if (card.isEmpty && photos.isEmpty) {
      return false;
    }
    final String shareText = CommunityLinks.creditCard(card);
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? shown = await cardChannel.invokeMethod<bool>(
          'shareCard',
          <String, Object>{'text': shareText, 'paths': photos},
        );
        if (shown == true) {
          return true;
        }
      } on PlatformException {
        // Falls through to the plugin's share sheet.
      } on MissingPluginException {
        // Same — a test, or an engine without the channel.
      }
    }
    if (photos.isNotEmpty) {
      await Share.shareXFiles(
        photos.map((String path) => XFile(path)).toList(),
        text: shareText,
        sharePositionOrigin: origin,
      );
    } else {
      await Share.share(shareText, sharePositionOrigin: origin);
    }
    return true;
  }

  /// The native side of card shares on Android — see `MainActivity`.
  static const MethodChannel cardChannel = MethodChannel(
    'shadchan/whatsapp_direct',
  );

  /// [paths] that exist on this device, each once, in order.
  static List<String> existingPhotos(Iterable<String> paths) {
    final Set<String> seen = <String>{};
    return <String>[
      for (final String path in paths)
        if (path.trim().isNotEmpty &&
            seen.add(path) &&
            File(path).existsSync() &&
            File(path).lengthSync() > 0)
          path,
    ];
  }

  /// Whether [person] has anything a card share would carry.
  static bool hasShareableCard(Person? person) {
    if (person == null) {
      return false;
    }
    return _shareText(person).isNotEmpty ||
        _existingPhotoPaths(person).isNotEmpty;
  }

  /// Shares the two cards of one idea together: each side's text under their
  /// name, every photo of both, and the credit once at the foot.
  ///
  /// A side with nothing to send is simply left out, so this also works when
  /// only one of the two has a card. Returns false when neither has one.
  static Future<bool> shareCouple(
    Person first,
    Person second, {
    Rect? origin,
  }) async {
    final List<Person> sides = <Person>[
      first,
      second,
    ].where(hasShareableCard).toList();
    if (sides.isEmpty) {
      return false;
    }
    final String text = <String>[
      for (final Person side in sides)
        <String>[
          side.fullName.trim(),
          _shareText(side),
        ].where((String part) => part.isNotEmpty).join('\n'),
    ].join('\n\n———\n\n');
    return shareCard(
      text: text,
      photoPaths: <String>[
        for (final Person side in sides) ...side.photosPaths,
      ],
      origin: origin,
    );
  }

  static List<String> _existingPhotoPaths(Person person) =>
      existingPhotos(person.photosPaths);

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
