import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/names.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:uuid/uuid.dart';

enum ContactsPermissionState { granted, denied, permanentlyDenied }

class ContactImportLoadProgress {
  const ContactImportLoadProgress({
    required this.processedCount,
    required this.totalCount,
  });

  final int processedCount;
  final int totalCount;

  double? get value {
    if (totalCount == 0) {
      return null;
    }

    return processedCount / totalCount;
  }
}

class ContactImportCandidate {
  const ContactImportCandidate({
    required this.deviceContactId,
    required this.displayName,
    required this.phone,
    required this.normalizedPhone,
    required this.alreadyExists,
    required this.hasAdditionalPhones,
    required this.isFilteredByName,
  });

  final String deviceContactId;
  final String displayName;
  final String phone;
  final String normalizedPhone;
  final bool alreadyExists;
  final bool hasAdditionalPhones;
  final bool isFilteredByName;

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

/// A contact staged for import, waiting for its quick details to be confirmed.
///
/// It is deliberately short-lived: the flow that created it either confirms it
/// into the database or discards it before the screen is left.
class StagedContact {
  const StagedContact({required this.person, required this.isNewRecord});

  final Person person;

  /// True when the draft was written by this staging call, false when an
  /// already existing (soft-deleted) contact was reused.
  final bool isNewRecord;
}

abstract final class ContactsImportService {
  static const Uuid _uuid = Uuid();
  static const String _cacheBoxName = 'contact_import_cache';
  static const String _cacheCandidatesKey = 'candidates_v2';
  static const int _processingBatchSize = 100;
  static const List<String> _blockedNameKeywords = <String>[
    ...familyKeywords,
    ...religiousTitlesKeywords,
    ...professionalKeywords,
    ...businessKeywords,
    ...suspiciousKeywords,
  ];
  static final List<String> _normalizedBlockedNameKeywords =
      _blockedNameKeywords
          .map(_normalizeNameFilterText)
          .where((String keyword) => keyword.trim().isNotEmpty)
          .toSet()
          .toList(growable: false);
  static final Set<String> _normalizedNameAllowlist = nameFilterAllowlist
      .map((String name) => _normalizeNameFilterText(name).trim())
      .where((String name) => name.isNotEmpty)
      .toSet();

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

  static Future<List<ContactImportCandidate>> loadCachedCandidates(
    PersonRepository personRepository,
  ) async {
    final Box<dynamic> cacheBox = await _openCacheBox();
    final Object? rawCandidates = cacheBox.get(_cacheCandidatesKey);
    if (rawCandidates is! List) {
      return const <ContactImportCandidate>[];
    }

    final Set<String> existingPhones = personRepository.getNormalizedPhones();
    final Set<String> hiddenPhones = personRepository
        .getHiddenNormalizedPhones();
    final List<ContactImportCandidate> candidates = rawCandidates
        .map(
          (Object? rawCandidate) =>
              _candidateFromCache(rawCandidate, existingPhones, hiddenPhones),
        )
        .whereType<ContactImportCandidate>()
        .toList();

    _sortCandidatesByName(candidates);
    return candidates;
  }

  static Future<List<ContactImportCandidate>> loadCandidates(
    PersonRepository personRepository, {
    void Function(ContactImportLoadProgress progress)? onProgress,
  }) async {
    final Set<String> existingPhones = personRepository.getNormalizedPhones();
    final Set<String> hiddenPhones = personRepository
        .getHiddenNormalizedPhones();
    final List<Contact> contacts = await FlutterContacts.getAll(
      properties: <ContactProperty>{
        ContactProperty.name,
        ContactProperty.phone,
      },
    );

    final List<ContactImportCandidate> candidates = <ContactImportCandidate>[];
    for (int index = 0; index < contacts.length; index++) {
      final Contact contact = contacts[index];
      final ContactImportCandidate? candidate = buildCandidate(
        deviceContactId: contact.id ?? contact.hashCode.toString(),
        displayName: _resolveDisplayName(contact),
        phones: contact.phones.map((Phone phone) => phone.number).toList(),
        existingPhones: existingPhones,
        hiddenPhones: hiddenPhones,
      );

      if (candidate != null && !candidate.alreadyExists) {
        candidates.add(candidate);
      }

      if (index % _processingBatchSize == 0 || index == contacts.length - 1) {
        onProgress?.call(
          ContactImportLoadProgress(
            processedCount: index + 1,
            totalCount: contacts.length,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }

    _sortCandidatesByName(candidates);
    await _saveCandidatesToCache(candidates);

    return candidates;
  }

  static ContactImportCandidate? buildCandidate({
    required String deviceContactId,
    required String displayName,
    required List<String> phones,
    required Set<String> existingPhones,
    Set<String> hiddenPhones = const <String>{},
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
      if (!isSuggestedMobilePhone(phone)) {
        continue;
      }

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
      isFilteredByName:
          isFilteredByName(trimmedName) ||
          hiddenPhones.contains(normalizedPhone),
    );
  }

  static bool isSuggestedMobilePhone(String phone) {
    final String compactPhone = phone
        .trim()
        .replaceAll(RegExp(r'[\s\-().]'), '')
        .replaceAll('־', '');

    return compactPhone.startsWith('05') || compactPhone.startsWith('+9725');
  }

  static bool isFilteredByName(String displayName) {
    final String trimmed = _normalizeNameFilterText(displayName).trim();
    if (trimmed.isEmpty) {
      return false;
    }

    // A name that contains a known legitimate word (first/last name) is never
    // auto-filtered, even if it happens to contain a blocked substring.
    final List<String> words = trimmed.split(' ');
    if (words.any(_normalizedNameAllowlist.contains)) {
      return false;
    }

    final String normalizedName = ' $trimmed ';
    return _normalizedBlockedNameKeywords.any(normalizedName.contains);
  }

  static String _normalizeNameFilterText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e]'), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
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

  /// Creates or reuses a hidden draft for one contact.
  ///
  /// A draft is not part of the database: it only becomes a real contact once
  /// the quick details are confirmed ([PersonRepository.activatePendingContactDraft]).
  /// If they are not, the caller must hand the result back to
  /// [discardStagedCandidate] — nothing is ever left waiting to be filled in.
  ///
  /// [StagedContact.isNewRecord] tells the two cases apart: a draft written
  /// here for the first time can be deleted outright, while a contact that was
  /// only soft-deleted keeps everything it already had.
  static Future<StagedContact?> stageSingleCandidate(
    ContactImportCandidate candidate,
    PersonRepository personRepository, {
    Gender gender = Gender.unknown,
    String source = 'סריקה',
  }) async {
    final Person? existing = personRepository.findByPhone(candidate.phone);
    if (existing != null) {
      if (!existing.hidden) {
        return null;
      }
      existing
        ..needsReview = true
        ..source = source;
      await personRepository.savePendingContactDraft(existing);
      return StagedContact(person: existing, isNewRecord: false);
    }

    final ({String firstName, String lastName}) parsedName = splitDisplayName(
      candidate.displayName,
    );
    final DateTime now = DateTime.now();
    final Person person = Person(
      id: _uuid.v4(),
      firstName: parsedName.firstName,
      lastName: parsedName.lastName,
      gender: gender,
      phone: candidate.phone.trim(),
      source: source,
      createdAt: now,
      updatedAt: now,
      needsReview: true,
      hidden: true,
    );

    await personRepository.savePendingContactDraft(person);
    return StagedContact(person: person, isNewRecord: true);
  }

  /// Undoes [stageSingleCandidate] when the matchmaker cancels the details:
  /// a draft written for this run is deleted, and a contact that already
  /// existed goes back to being soft-deleted. Either way nothing is left in a
  /// "waiting for details" state.
  static Future<void> discardStagedCandidate(
    StagedContact staged,
    PersonRepository personRepository,
  ) {
    return personRepository.discardContactDraft(
      staged.person,
      deleteRecord: staged.isNewRecord,
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

  static void _sortCandidatesByName(List<ContactImportCandidate> candidates) {
    candidates.sort((ContactImportCandidate a, ContactImportCandidate b) {
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  }

  static Future<Box<dynamic>> _openCacheBox() async {
    if (Hive.isBoxOpen(_cacheBoxName)) {
      return Hive.box<dynamic>(_cacheBoxName);
    }

    return Hive.openBox<dynamic>(_cacheBoxName);
  }

  static Future<void> _saveCandidatesToCache(
    List<ContactImportCandidate> candidates,
  ) async {
    final Box<dynamic> cacheBox = await _openCacheBox();
    await cacheBox.put(
      _cacheCandidatesKey,
      candidates.map(_candidateToCache).toList(growable: false),
    );
  }

  static Map<String, Object> _candidateToCache(
    ContactImportCandidate candidate,
  ) {
    return <String, Object>{
      'deviceContactId': candidate.deviceContactId,
      'displayName': candidate.displayName,
      'phone': candidate.phone,
      'normalizedPhone': candidate.normalizedPhone,
      'hasAdditionalPhones': candidate.hasAdditionalPhones,
      'isFilteredByName': candidate.isFilteredByName,
    };
  }

  static ContactImportCandidate? _candidateFromCache(
    Object? rawCandidate,
    Set<String> existingPhones,
    Set<String> hiddenPhones,
  ) {
    if (rawCandidate is! Map) {
      return null;
    }

    final String? deviceContactId = rawCandidate['deviceContactId'] as String?;
    final String? displayName = rawCandidate['displayName'] as String?;
    final String? phone = rawCandidate['phone'] as String?;
    final String? normalizedPhone = rawCandidate['normalizedPhone'] as String?;
    if (deviceContactId == null ||
        displayName == null ||
        phone == null ||
        normalizedPhone == null ||
        existingPhones.contains(normalizedPhone)) {
      return null;
    }

    return ContactImportCandidate(
      deviceContactId: deviceContactId,
      displayName: displayName,
      phone: phone,
      normalizedPhone: normalizedPhone,
      alreadyExists: false,
      hasAdditionalPhones: rawCandidate['hasAdditionalPhones'] == true,
      // Recompute from the name (rather than trusting the cached flag) so
      // changes to the filtering logic / allowlist take effect immediately,
      // even for contacts loaded from the cache.
      isFilteredByName:
          isFilteredByName(displayName) ||
          hiddenPhones.contains(normalizedPhone),
    );
  }
}
