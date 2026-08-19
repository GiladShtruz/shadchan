import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// How the app can reach one contact by message.
enum ContactChannel {
  /// A mobile number, so WhatsApp is worth offering.
  whatsapp,

  /// A number that exists but is not one WhatsApp runs on — an Israeli
  /// landline, a service number, something too short to dial abroad.
  sms,

  /// No number at all. Nothing to offer but a way to add one.
  none,
}

/// Which messaging control a contact should get.
///
/// The app used to draw a WhatsApp button on everybody with a `phone` field,
/// including landlines and including people created from "הוספת שם מחוץ למאגר"
/// who have no number at all — a button that could only ever fail.
///
/// **There is no per-contact "has WhatsApp" fact to read.** WhatsApp's own
/// contact rows are an Android account type the app never imports, it says
/// nothing about iOS, and it would be stale for anybody typed in by hand. So
/// the decision is made from the number itself, which is the part that is
/// actually knowable: a mobile line can plausibly have WhatsApp, a landline
/// cannot.
abstract final class ContactChannels {
  /// Israeli mobile numbers all begin `05`. `02/03/04/08/09` are landlines and
  /// `07x` (bar `05`) is VoIP — none of them run WhatsApp.
  static const String _israeliMobilePrefix = '05';

  static ContactChannel forPhone(String? rawPhone) {
    final String digits = PhoneUtils.digitsOnly(rawPhone ?? '');
    if (digits.isEmpty) {
      return ContactChannel.none;
    }

    // Not dialable as an international number: too short, or otherwise not
    // something `wa.me` would accept.
    if (PhoneUtils.toWhatsAppNumber(rawPhone) == null) {
      return ContactChannel.sms;
    }

    // A local Israeli number is the only case where the prefix tells us the
    // line type. A foreign number normalises to something that does not start
    // with `0`, and nothing about it is knowable, so it keeps WhatsApp.
    final String? local = PhoneUtils.normalizeForComparison(rawPhone);
    if (local != null &&
        local.startsWith('0') &&
        !local.startsWith(_israeliMobilePrefix)) {
      return ContactChannel.sms;
    }

    return ContactChannel.whatsapp;
  }

  static ContactChannel forPerson(Person? person) => forPhone(person?.phone);

  /// Opens the phone's own messaging app on [rawPhone], optionally with [body]
  /// already typed in. Returns false when there is no number to open.
  static Future<bool> openSms(String? rawPhone, {String? body}) async {
    final String digits = PhoneUtils.digitsOnly(rawPhone ?? '');
    if (digits.isEmpty) {
      return false;
    }

    final String trimmedBody = (body ?? '').trim();
    return launchUrl(
      Uri(
        scheme: 'sms',
        path: rawPhone!.trim(),
        queryParameters: trimmedBody.isEmpty
            ? null
            : <String, String>{'body': trimmedBody},
      ),
      mode: LaunchMode.externalApplication,
    );
  }
}
