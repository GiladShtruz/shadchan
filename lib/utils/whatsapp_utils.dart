import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:url_launcher/url_launcher.dart';

abstract final class WhatsAppUtils {
  static const String onboardingMessage = '''
היי 🙂 מה קורה?

אני רוצה להכניס אותך לאפליקציית שדכן (אפליקציית שידוכים ממאגר אישי), זורם לך? רק לי יש גישה

אם כן, אשמח לפרטים שלך:
- תאריך לידה
- כרטיסיה לשליחה - כמה משפטים על עצמך (5-10 שורות, משהו קליל שמייצג אותך)
- 2-3 תמונות עדכניות 📸''';

  static Uri? buildChatUri(Person person) {
    final String? phone = PhoneUtils.toWhatsAppNumber(person.phone);
    if (phone == null) {
      return null;
    }

    if (person.needsReview) {
      return Uri.https('wa.me', '/$phone', <String, String>{
        'text': onboardingMessage,
      });
    }

    return Uri.https('wa.me', '/$phone');
  }

  static Future<bool> openChat(Person person) async {
    final Uri? uri = buildChatUri(person);
    if (uri == null) {
      return false;
    }

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
