import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:url_launcher/url_launcher.dart';

abstract final class WhatsAppUtils {
  static const String onboardingMessageKey = 'whatsappOnboardingMessage';
  static const String defaultOnboardingMessage = '''
היי 👋🏽 מה קורה?
אני עושה איזה מאגר היכרויות קטן ואישי לחברים, וחשבתי עליך 🙂
אם זה רלוונטי - אשמח לכמה משפטים על עצמך ו- 2-3 תמונות
מתאים לך?''';

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
