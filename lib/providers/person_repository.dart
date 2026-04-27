import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/services/notification_service.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/models/person.dart';
import 'package:uuid/uuid.dart';

class PersonRepository extends ChangeNotifier {
  PersonRepository(this._box, [this._noteBox]);

  final Box<Person> _box;
  final Box<PersonNote>? _noteBox;
  final Uuid _uuid = const Uuid();

  int get count => _box.length;

  int get pendingCount {
    int total = 0;
    for (final Person person in _box.values) {
      if (person.needsReview) total++;
    }
    return total;
  }

  int get activeCount => count - pendingCount;

  List<Person> getAll() {
    final List<Person> people = _box.values.toList();
    people.sort(_sortByFirstName);
    return people;
  }

  List<Person> getPending() {
    final List<Person> people = _box.values
        .where((Person person) => person.needsReview)
        .toList();
    people.sort(_sortByFirstName);
    return people;
  }

  Person? getById(String id) {
    return _box.get(id);
  }

  bool containsId(String id) {
    return _box.containsKey(id);
  }

  List<Person> search(String query) {
    final String normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return getAll();
    }

    final List<Person> people = _box.values.where((Person person) {
      return person.firstName.toLowerCase().contains(normalizedQuery) ||
          person.lastName.toLowerCase().contains(normalizedQuery);
    }).toList();

    people.sort(_sortByFirstName);
    return people;
  }

  List<Person> filter({
    Gender? gender,
    int? minAge,
    int? maxAge,
    List<ReligiousLevel>? religiousLevels,
    List<ProfileStatus>? profileStatuses,
    String? city,
    bool? favoritesOnly,
    bool includePending = false,
  }) {
    final String? normalizedCity = city?.trim().toLowerCase();
    final bool shouldFilterByCity =
        normalizedCity != null && normalizedCity.isNotEmpty;
    final bool shouldFilterByReligiousLevel =
        religiousLevels != null && religiousLevels.isNotEmpty;
    final List<ReligiousLevel> selectedReligiousLevels =
        religiousLevels ?? const <ReligiousLevel>[];
    final bool shouldFilterByProfileStatus =
        profileStatuses != null && profileStatuses.isNotEmpty;
    final List<ProfileStatus> selectedProfileStatuses =
        profileStatuses ?? const <ProfileStatus>[];

    final List<Person> people = _box.values.where((Person person) {
      if (!includePending && person.needsReview) {
        return false;
      }

      if (gender != null && person.gender != gender) {
        return false;
      }

      final int? personAge = person.age;
      if (minAge != null && (personAge == null || personAge < minAge)) {
        return false;
      }
      if (maxAge != null && (personAge == null || personAge > maxAge)) {
        return false;
      }

      if (shouldFilterByReligiousLevel &&
          !selectedReligiousLevels.contains(person.religiousLevel)) {
        return false;
      }

      if (shouldFilterByProfileStatus &&
          !selectedProfileStatuses.contains(person.profileStatus)) {
        return false;
      }

      if (shouldFilterByCity) {
        final String personCity = (person.city ?? '').trim().toLowerCase();
        if (personCity != normalizedCity) {
          return false;
        }
      }

      if (favoritesOnly == true && !person.isFavorite) {
        return false;
      }

      return true;
    }).toList();

    people.sort(_sortByFirstName);
    return people;
  }

  List<Person> getByGender(Gender gender) {
    final List<Person> people = _box.values
        .where((Person person) => person.gender == gender)
        .toList();
    people.sort(_sortByFirstName);
    return people;
  }

  Person? findByPhone(String phone) {
    final String? normalizedPhone = PhoneUtils.normalizeForComparison(phone);
    if (normalizedPhone == null) {
      return null;
    }

    for (final Person person in _box.values) {
      if (PhoneUtils.normalizeForComparison(person.phone) == normalizedPhone) {
        return person;
      }
    }

    return null;
  }

  bool containsPhone(String phone) {
    return findByPhone(phone) != null;
  }

  Set<String> getNormalizedPhones() {
    return _box.values
        .map((Person person) => PhoneUtils.normalizeForComparison(person.phone))
        .whereType<String>()
        .toSet();
  }

  Future<void> add(Person person) async {
    await _box.put(person.id, person);
    notifyListeners();
    _refreshBirthdayNotificationsInBackground();
  }

  Future<void> addImported(Person person) async {
    await _box.put(person.id, person);
  }

  Future<void> update(Person person) async {
    person.updatedAt = DateTime.now();
    person.needsReview = false;
    await person.save();
    notifyListeners();
    _refreshBirthdayNotificationsInBackground();
  }

  Future<void> delete(String id) async {
    final Box<PersonNote>? noteBox = _noteBox;
    if (noteBox != null) {
      final List<dynamic> noteKeys = noteBox.keys.where((dynamic key) {
        final PersonNote? note = noteBox.get(key);
        return note?.personId == id;
      }).toList();
      if (noteKeys.isNotEmpty) {
        await noteBox.deleteAll(noteKeys);
      }
    }

    await _box.delete(id);
    notifyListeners();
    _refreshBirthdayNotificationsInBackground();
  }

  Future<void> finishImport() async {
    notifyListeners();
    _refreshBirthdayNotificationsInBackground();
  }

  Future<void> toggleFavorite(String id) async {
    final Person? person = getById(id);
    if (person == null) {
      return;
    }

    person.isFavorite = !person.isFavorite;
    person.updatedAt = DateTime.now();
    await person.save();
    notifyListeners();
  }

  Future<void> updateManualAge(String id, int? newAge) async {
    final Person? person = getById(id);
    if (person == null || person.manualAge == newAge) {
      return;
    }

    person.manualAge = newAge;
    person.updatedAt = DateTime.now();
    await person.save();
    notifyListeners();
  }

  Future<void> updateCity(String id, String? newCity) async {
    final Person? person = getById(id);
    if (person == null) {
      return;
    }
    final String? normalized =
        (newCity == null || newCity.trim().isEmpty) ? null : newCity.trim();
    if (person.city == normalized) {
      return;
    }

    person.city = normalized;
    person.updatedAt = DateTime.now();
    await person.save();
    notifyListeners();
  }

  Future<void> updateGender(String id, Gender newGender) async {
    final Person? person = getById(id);
    if (person == null || person.gender == newGender) {
      return;
    }

    person.gender = newGender;
    person.updatedAt = DateTime.now();
    await person.save();
    notifyListeners();
  }

  Future<void> updateReligiousLevel(String id, ReligiousLevel? newLevel) async {
    final Person? person = getById(id);
    if (person == null || person.religiousLevel == newLevel) {
      return;
    }

    person.religiousLevel = newLevel;
    person.updatedAt = DateTime.now();
    await person.save();
    notifyListeners();
  }

  Future<void> updateProfileStatus(String id, ProfileStatus newStatus) async {
    final Person? person = getById(id);
    if (person == null || person.profileStatus == newStatus) {
      return;
    }

    person.profileStatus = newStatus;
    person.updatedAt = DateTime.now();
    await person.save();
    await _createNote(
      personId: id,
      text: 'סטטוס שונה ל-${newStatus.displayName}',
      createdAt: person.updatedAt,
      isAutomatic: true,
    );
    notifyListeners();
  }

  List<PersonNote> getNotesForPerson(String personId) {
    final Box<PersonNote>? noteBox = _noteBox;
    if (noteBox == null) {
      return const <PersonNote>[];
    }

    final List<PersonNote> notes = noteBox.values
        .where((PersonNote note) => note.personId == personId)
        .toList();
    notes.sort(
      (PersonNote a, PersonNote b) => a.createdAt.compareTo(b.createdAt),
    );
    return notes;
  }

  List<PersonNote> getAllNotes() {
    final Box<PersonNote>? noteBox = _noteBox;
    if (noteBox == null) {
      return const <PersonNote>[];
    }

    final List<PersonNote> notes = noteBox.values.toList();
    notes.sort(
      (PersonNote a, PersonNote b) => a.createdAt.compareTo(b.createdAt),
    );
    return notes;
  }

  bool containsNoteId(String id) {
    return _noteBox?.containsKey(id) ?? false;
  }

  Future<void> addNote(String personId, String text) async {
    final DateTime now = DateTime.now();
    await _createNote(
      personId: personId,
      text: text,
      createdAt: now,
      isAutomatic: false,
    );

    final Person? person = getById(personId);
    if (person != null) {
      person.updatedAt = now;
      await person.save();
    }

    notifyListeners();
  }

  Future<void> addImportedNote(PersonNote note) async {
    await _noteBox?.put(note.id, note);
  }

  List<Person> getBirthdaysToday() {
    final List<Person> people = _box.values.where((Person person) {
      final DateTime? birthDate = person.birthDate;
      return birthDate != null && AppDateUtils.isBirthdayToday(birthDate);
    }).toList();

    people.sort(_sortByFirstName);
    return people;
  }

  List<Person> getUpcomingBirthdays({int daysAhead = 7}) {
    final List<Person> people = _box.values.where((Person person) {
      final DateTime? birthDate = person.birthDate;
      return birthDate != null &&
          AppDateUtils.isBirthdaySoon(birthDate, daysAhead: daysAhead);
    }).toList();

    people.sort((Person a, Person b) {
      final int daysA = AppDateUtils.daysUntilBirthday(a.birthDate!) ?? 0;
      final int daysB = AppDateUtils.daysUntilBirthday(b.birthDate!) ?? 0;
      final int dayComparison = daysA.compareTo(daysB);
      if (dayComparison != 0) {
        return dayComparison;
      }

      return _sortByFirstName(a, b);
    });

    return people;
  }

  int _sortByFirstName(Person a, Person b) {
    return a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
  }

  Future<void> _refreshBirthdayNotifications() async {
    await NotificationService.scheduleBirthdayNotifications(getAll());
  }

  void _refreshBirthdayNotificationsInBackground() {
    unawaited(_refreshBirthdayNotifications());
  }

  Future<void> _createNote({
    required String personId,
    required String text,
    required DateTime createdAt,
    required bool isAutomatic,
  }) async {
    final Box<PersonNote>? noteBox = _noteBox;
    if (noteBox == null) {
      return;
    }

    final PersonNote note = PersonNote(
      id: _uuid.v4(),
      personId: personId,
      text: text,
      createdAt: createdAt,
      isAutomatic: isAutomatic,
    );
    await noteBox.put(note.id, note);
  }
}
