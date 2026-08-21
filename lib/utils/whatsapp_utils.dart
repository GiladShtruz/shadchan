import 'dart:io';

import 'package:hive/hive.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:url_launcher/url_launcher.dart';

abstract final class WhatsAppUtils {
  static const String onboardingMessageKey = 'whatsappOnboardingMessage';
  static const String defaultOnboardingMessage = '''
היי 👋🏽 מה קורה?
אני עושה איזה מאגר היכרויות קטן ואישי לחברים, וחשבתי עליך 🙂
אם זה רלוונטי - אשמח לכמה משפטים על עצמך ו- 2-3 תמונות
מתאים לך?''';

  /// The "בקש פרטים" message opened from a profile that is missing a card. The
  /// wording is gendered by the recipient. Once the matchmaker saves a custom
  /// version it is used as-is for everyone.
  static const String detailsRequestMessageKey =
      'whatsappDetailsRequestMessage';

  static const String _detailsRequestMale = '''
היי! אני חושב על חברים לשידוכים ואשמח לחשוב גם עליך 😊
תרצה לשלוח לי כרטיס שלך ותמונה?
ואם מתאים לך, אפשר גם לכתוב לי בהודעה נפרדת כמה מילים על מה אתה מחפש, כדי שאוכל לדייק יותר בהצעות.''';

  static const String _detailsRequestFemale = '''
היי! אני חושב על חברים לשידוכים ואשמח לחשוב גם עלייך 😊
תרצי לשלוח לי כרטיס שלך ותמונה?
ואם מתאים לך, אפשר גם לכתוב לי בהודעה נפרדת כמה מילים על מה את מחפשת, כדי שאוכל לדייק יותר בהצעות.''';

  /// The gendered default request-details text (no custom override applied).
  static String defaultDetailsRequestMessage(Gender gender) {
    return gender == Gender.female
        ? _detailsRequestFemale
        : _detailsRequestMale;
  }

  /// The request-details text to actually use: the matchmaker's saved custom
  /// text when present, otherwise the gendered default.
  static String currentDetailsRequestMessage(Gender gender) {
    if (Hive.isBoxOpen('settings')) {
      final Box<dynamic> box = Hive.box<dynamic>('settings');
      final String? saved = box.get(detailsRequestMessageKey) as String?;
      if (saved != null && saved.trim().isNotEmpty) {
        return saved.trim();
      }
    }
    return defaultDetailsRequestMessage(gender);
  }

  /// Whether the matchmaker has saved a custom request-details text.
  static bool hasCustomDetailsRequestMessage() {
    if (!Hive.isBoxOpen('settings')) {
      return false;
    }
    final String? saved =
        Hive.box<dynamic>('settings').get(detailsRequestMessageKey) as String?;
    return saved != null && saved.trim().isNotEmpty;
  }

  static Future<void> saveDetailsRequestMessage(String message) async {
    final Box<dynamic> box = Hive.box<dynamic>('settings');
    await box.put(detailsRequestMessageKey, message.trim());
  }

  static Future<void> resetDetailsRequestMessage() async {
    await Hive.box<dynamic>('settings').delete(detailsRequestMessageKey);
  }

  /// Opens WhatsApp with the request-details message pre-filled (editable
  /// before sending). Returns false when the person has no valid phone number.
  static Future<bool> openDetailsRequest(Person person) async {
    final String? phone = PhoneUtils.toWhatsAppNumber(person.phone);
    if (phone == null) {
      return false;
    }

    return launchUrl(
      Uri.https('wa.me', '/$phone', <String, String>{
        'text': currentDetailsRequestMessage(person.gender),
      }),
      mode: LaunchMode.externalApplication,
    );
  }

  static Uri? buildChatUri(Person person, {String? onboardingMessage}) {
    final String? phone = PhoneUtils.toWhatsAppNumber(person.phone);
    if (phone == null) {
      return null;
    }

    if (person.needsReview) {
      return Uri.https('wa.me', '/$phone', <String, String>{
        'text': _normalizeMessage(onboardingMessage),
      });
    }

    return Uri.https('wa.me', '/$phone');
  }

  static Future<bool> openChat(Person person) async {
    final String? message = person.needsReview
        ? currentOnboardingMessage()
        : null;
    final Uri? uri = buildChatUri(person, onboardingMessage: message);
    if (uri == null) {
      return false;
    }

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Opens a chat with an arbitrary number (used for a candidate's contact
  /// person, who is not a [Person] in the database). Returns false when the
  /// number is missing or not a valid phone number.
  static Future<bool> openChatWithPhone(String? rawPhone) async {
    final String? phone = PhoneUtils.toWhatsAppNumber(rawPhone);
    if (phone == null) {
      return false;
    }

    return launchUrl(
      Uri.https('wa.me', '/$phone'),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Sends [card]'s saved card — **its text and every one of its photos** — to
  /// [recipient]. Returns false when the recipient has no valid number and the
  /// card has nothing worth sending.
  ///
  /// **A card is its photos as much as its words**, and this path used to drop
  /// them. It built a `wa.me` link, which can carry text and nothing else, so
  /// the one route a card travels most often — straight into the chat of the
  /// person being proposed to — was the one route that arrived without a face.
  /// Everywhere else in the app a card leaves through [ShareUtils], with the
  /// gallery attached.
  ///
  /// So it now splits on whether there is anything to attach:
  ///
  /// * **photos** → the system share sheet, carrying the text and the whole
  ///   gallery. WhatsApp is one tap inside it, and the recipient is picked
  ///   there; no share API can hand files to one named chat, and arriving with
  ///   the photos is worth the extra tap;
  /// * **text only** → the direct chat, exactly as before. There is nothing to
  ///   attach, so there is no reason to make anybody pick a contact twice.
  static Future<bool> sendCardTo(Person recipient, Person card) async {
    final String text = (card.description ?? '').trim();
    final List<String> photos = card.photosPaths
        .where((String path) => File(path).existsSync())
        .toList();
    if (text.isEmpty && photos.isEmpty) {
      return false;
    }

    // Credited like every other way a card leaves the app.
    final String message = CommunityLinks.creditCard(text);

    if (photos.isNotEmpty) {
      await Share.shareXFiles(
        photos.map((String path) => XFile(path)).toList(),
        text: message,
      );
      return true;
    }

    final String? phone = PhoneUtils.toWhatsAppNumber(recipient.phone);
    if (phone == null) {
      return false;
    }
    return launchUrl(
      Uri.https('wa.me', '/$phone', <String, String>{'text': message}),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Whether [card] has anything to send at all — text, photos, or both.
  static bool hasSendableCard(Person? card) {
    if (card == null) {
      return false;
    }
    return (card.description ?? '').trim().isNotEmpty ||
        card.photosPaths.any((String path) => File(path).existsSync());
  }

  static String currentOnboardingMessage() {
    if (!Hive.isBoxOpen('settings')) {
      return defaultOnboardingMessage;
    }

    final Box<dynamic> box = Hive.box<dynamic>('settings');
    final String? savedMessage = box.get(onboardingMessageKey) as String?;
    return _normalizeMessage(savedMessage);
  }

  static Future<void> saveOnboardingMessage(String message) async {
    final Box<dynamic> box = Hive.box<dynamic>('settings');
    await box.put(onboardingMessageKey, _normalizeMessage(message));
  }

  static Future<void> resetOnboardingMessage() async {
    final Box<dynamic> box = Hive.box<dynamic>('settings');
    await box.delete(onboardingMessageKey);
  }

  static String _normalizeMessage(String? message) {
    final String trimmed = message?.trim() ?? '';
    return trimmed.isEmpty ? defaultOnboardingMessage : trimmed;
  }
}
