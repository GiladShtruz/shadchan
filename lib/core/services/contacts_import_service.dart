import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shadchan/core/constants/enums.dart';
import 'package:shadchan/core/utils/phone_utils.dart';
import 'package:shadchan/data/models/person.dart';
import 'package:shadchan/data/repositories/person_repository.dart';
import 'package:uuid/uuid.dart';

enum ContactsPermissionState { granted, denied, permanentlyDenied }

class ContactImportCandidate {
  const ContactImportCandidate({
    required this.deviceContactId,
    required this.displayName,
    required this.phone,
    required this.normalizedPhone,
    required this.alreadyExists,
    required this.hasAdditionalPhones,
  });

  final String deviceContactId;
  final String displayName;
  final String phone;
  final String normalizedPhone;
  final bool alreadyExists;
  final bool hasAdditionalPhones;

  bool matchesQuery(String query) {
    final String normalizedQuery = _normalizeSearchText(query);
    final String phoneQuery = PhoneUtils.digitsOnly(query);
    if (normalizedQuery.isEmpty && phoneQuery.isEmpty) {
      return true;
    }

    final String normalizedName = _normalizeSearchText(displayName);
    final bool matchesName =
        normalizedQuery.isNotEmpty &&
        normalizedQuery
            .split(' ')
            .every((String token) => normalizedName.contains(token));
    final bool matchesPhone =
        phoneQuery.isNotEmpty &&
        PhoneUtils.digitsOnly(phone).contains(phoneQuery);

    return matchesName || matchesPhone;
  }

  static String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e]'), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class ContactImportSelection {
  const ContactImportSelection({required this.candidate, required this.gender});

  final ContactImportCandidate candidate;
  final Gender gender;
}

class ContactImportResult {
  const ContactImportResult({
    required this.addedCount,
    required this.skippedExistingCount,
  });

  final int addedCount;
  final int skippedExistingCount;
}

abstract final class ContactsImportService {
  static const Uuid _uuid = Uuid();

  static Future<ContactsPermissionState> requestPermission() async {
    final PermissionStatus status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    return _mapPermissionStatus(status);
  }

  static Future<ContactsPermissionState> checkPermission() async {
    final PermissionStatus status = await FlutterContacts.permissions.check(
      PermissionType.read,
    );
    return _mapPermissionStatus(status);
  }

  static Future<void> openSettings() {
    return FlutterContacts.permissions.openSettings();
  }

  static Future<List<ContactImportCandidate>> loadCandidates(
    PersonRepository personRepository,
  ) async {
    final Set<String> existingPhones = personRepository.getNormalizedPhones();
    final List<Contact> contacts = await FlutterContacts.getAll(
      properties: <ContactProperty>{
        ContactProperty.name,
        ContactProperty.phone,
      },
    );

    final List<ContactImportCandidate> candidates = contacts
        .map(
          (Contact contact) => buildCandidate(
            deviceContactId: contact.id ?? contact.hashCode.toString(),
            displayName: _resolveDisplayName(contact),
            phones: contact.phones.map((Phone phone) => phone.number).toList(),
            existingPhones: existingPhones,
          ),
        )
        .whereType<ContactImportCandidate>()
        .toList();

    candidates.sort((ContactImportCandidate a, ContactImportCandidate b) {
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    return candidates;
  }

  static ContactImportCandidate? buildCandidate({
    required String deviceContactId,
    required String displayName,
    required List<String> phones,
    required Set<String> existingPhones,
  }) {
    final String trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      return null;
    }

    final List<String> cleanedPhones = phones
        .map((String phone) => phone.trim())
        .where((String phone) => phone.isNotEmpty)
        .toList();
    if (cleanedPhones.isEmpty) {
      return null;
    }

    String? selectedPhone;
    String? normalizedPhone;
    for (final String phone in cleanedPhones) {
      final String? normalized = PhoneUtils.normalizeForComparison(phone);
      if (normalized == null) {
        continue;
      }

      selectedPhone = phone;
      normalizedPhone = normalized;
      break;
    }

    if (selectedPhone == null || normalizedPhone == null) {
      return null;
    }

    return ContactImportCandidate(
      deviceContactId: deviceContactId,
      displayName: trimmedName,
      phone: selectedPhone,
      normalizedPhone: normalizedPhone,
      alreadyExists: existingPhones.contains(normalizedPhone),
      hasAdditionalPhones: cleanedPhones.length > 1,
    );
  }

  static ({String firstName, String lastName}) splitDisplayName(
    String displayName,
  ) {
    final String trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      return (firstName: '', lastName: '');
    }

    final List<String> parts = trimmedName.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return (firstName: parts.first, lastName: '');
    }

    return (firstName: parts.first, lastName: parts.sublist(1).join(' '));
  }

  static Future<ContactImportResult> importSelections(
    List<ContactImportSelection> selections,
    PersonRepository personRepository,
  ) async {
    int addedCount = 0;
    int skippedExistingCount = 0;
    final Set<String> importedPhones = <String>{};

    for (final ContactImportSelection selection in selections) {
      final ContactImportCandidate candidate = selection.candidate;
      final String normalizedPhone = candidate.normalizedPhone;
      if (personRepository.containsPhone(candidate.phone) ||
          importedPhones.contains(normalizedPhone)) {
        skippedExistingCount++;
        continue;
      }

      importedPhones.add(normalizedPhone);
      final ({String firstName, String lastName}) parsedName = splitDisplayName(
        candidate.displayName,
      );
      final DateTime now = DateTime.now();
      final Person person = Person(
        id: _uuid.v4(),
        firstName: parsedName.firstName,
        lastName: parsedName.lastName,
        gender: selection.gender,
        phone: candidate.phone.trim(),
        source: 'אנשי קשר',
        createdAt: now,
        updatedAt: now,
      );

      await personRepository.addImported(person);
      addedCount++;
    }

    await personRepository.finishImport();

    return ContactImportResult(
      addedCount: addedCount,
      skippedExistingCount: skippedExistingCount,
    );
  }

  static ContactsPermissionState _mapPermissionStatus(PermissionStatus status) {
    final String statusName = status.name;
    if (statusName == 'granted' || statusName == 'limited') {
      return ContactsPermissionState.granted;
    }
    if (statusName == 'permanentlyDenied') {
      return ContactsPermissionState.permanentlyDenied;
    }

    return ContactsPermissionState.denied;
  }

  static String _resolveDisplayName(Contact contact) {
    final String displayName = (contact.displayName ?? '').trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }

    final List<String> parts = <String>[
      (contact.name?.first ?? '').trim(),
      (contact.name?.last ?? '').trim(),
    ].where((String part) => part.isNotEmpty).toList();

    return parts.join(' ').trim();
  }
}
