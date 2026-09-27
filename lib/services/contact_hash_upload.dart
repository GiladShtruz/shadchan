import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/sync_state_store.dart';
import 'package:shadchan/utils/phone_identity.dart';

enum ContactScanOutcome { uploaded, unchanged, noPermission, failed }

/// Publishes a card owner's address book — as phone hashes, never names or
/// numbers — so the server can tell which matchmakers are their friends.
///
/// Uploading is what lets the server both find "חברים שיכולים לעזור לי" and
/// enforce that only somebody saved in the owner's contacts may ask for the
/// card. A book that has not changed is not sent again, except once a day,
/// because the answer changes when friends join as matchmakers.
abstract final class ContactHashUpload {
  static const String _printKey = 'contactHashes.print';
  static const String _atKey = 'contactHashes.at';
  static const Duration _refreshAfter = Duration(days: 1);

  static Box<dynamic>? get _settings =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// The names this phone's own address book gives each number, by
  /// [PhoneIdentity.hash] — read on every scan, kept in memory only, never
  /// sent anywhere. It is how the personal area names a matchmaker the way
  /// the owner saved them, rather than the way the matchmaker signed up.
  static final ValueNotifier<Map<String, String>> contactNames =
      ValueNotifier<Map<String, String>>(const <String, String>{});

  /// The owner's own name for [phoneHash], if their contacts have one.
  static String? nameFor(String? phoneHash) {
    if (phoneHash == null) {
      return null;
    }
    final String? name = contactNames.value[phoneHash];
    return name == null || name.trim().isEmpty ? null : name.trim();
  }

  static Future<ContactsPermissionState> permission() =>
      ContactsImportService.checkPermission();

  static Future<ContactScanOutcome> run({bool force = false}) async {
    try {
      if (await ContactsImportService.checkPermission() !=
          ContactsPermissionState.granted) {
        return ContactScanOutcome.noPermission;
      }
      final List<Contact> contacts = await FlutterContacts.getAll(
        properties: <ContactProperty>{
          ContactProperty.name,
          ContactProperty.phone,
        },
      );
      final Set<String> hashes = <String>{};
      final Map<String, String> names = <String, String>{};
      for (final Contact contact in contacts) {
        final String name = ContactsImportService.displayNameOf(contact);
        for (final Phone phone in contact.phones) {
          final String? hash = PhoneIdentity.hash(phone.number);
          if (hash == null) {
            continue;
          }
          hashes.add(hash);
          if (name.isNotEmpty) {
            names.putIfAbsent(hash, () => name);
          }
        }
      }
      contactNames.value = names;
      final List<String> sorted = hashes.toList()..sort();
      final String print = SyncStateStore.fingerprint(<String, Object?>{
        'hashes': sorted,
      });
      final Object? at = _settings?.get(_atKey);
      final DateTime? last = at is String ? DateTime.tryParse(at) : null;
      if (!force &&
          _settings?.get(_printKey) == print &&
          last != null &&
          DateTime.now().difference(last) < _refreshAfter) {
        return ContactScanOutcome.unchanged;
      }
      if (!await PersonalCardService.publishContactHashes(sorted)) {
        return ContactScanOutcome.failed;
      }
      await _settings?.put(_printKey, print);
      await _settings?.put(_atKey, DateTime.now().toIso8601String());
      return ContactScanOutcome.uploaded;
    } catch (error) {
      debugPrint('ContactHashUpload failed: $error');
      return ContactScanOutcome.failed;
    }
  }

  static Future<void> forget() async {
    contactNames.value = const <String, String>{};
    await _settings?.deleteAll(<String>[_printKey, _atKey]);
  }
}
