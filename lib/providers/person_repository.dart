import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/notification_service.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/models/person.dart';
import 'package:uuid/uuid.dart';

class PersonRepository extends ChangeNotifier {
  PersonRepository(this._box, [this._noteBox, this._eventBox]) {
    // Pending notifications do not survive a reinstall or a device restart on
    // every Android build, so the whole set is re-scheduled on startup.
    _refreshPersonRemindersInBackground();
  }

  final Box<Person> _box;
  final Box<PersonNote>? _noteBox;
  final Box<PersonEvent>? _eventBox;
  final Uuid _uuid = const Uuid();

  /// Invoked with a person id whenever that person's availability changes, so
  /// their proposals can move to "בהמתנה" (when someone is busy / on a break)
  /// or back to "רעיון" (once both sides are free again). Wired to
  /// [MatchRepository] in `main.dart` to avoid a hard dependency between the
  /// two repositories.
  Future<void> Function(String personId)? onPersonStatusChanged;

  int get count => _box.length;

  int get pendingCount {
    int total = 0;
    for (final Person person in _box.values) {
      if (person.needsReview) total++;
    }
    return total;
  }

  int get activeCount => count - pendingCount;

  /// People actually in the matchmaker's database, ignoring the soft-deleted
  /// ones. This is the number the add-contacts screens count up.
  int get databaseCount {
    int total = 0;
    for (final Person person in _box.values) {
      if (!person.hidden) total++;
    }
    return total;
  }

  ({int min, int max})? get activeAgeBounds {
    int? min;
    int? max;
    for (final Person person in _box.values) {
      if (person.needsReview || person.profileStatus.isArchived) {
        continue;
      }
      final int? age = person.age;
      if (age == null) {
        continue;
      }
      if (min == null || age < min) {
        min = age;
      }
      if (max == null || age > max) {
        max = age;
      }
    }
    if (min == null || max == null) {
      return null;
    }
    return (min: min, max: max);
  }

  List<Person> getAll() {
    final List<Person> people = _box.values.toList();
    people.sort(_sortByFirstName);
    return people;
  }

  List<Person> getPending() {
    final List<Person> people = _box.values
        .where((Person person) => person.needsReview && !person.hidden)
        .toList();
    people.sort(_sortByFirstName);
    return people;
  }

  /// Contact-import drafts that are not part of the visible database yet.
  List<Person> getPendingContactDrafts() {
    final List<Person> people = _box.values
        .where(
          (Person person) =>
              person.needsReview &&
              person.hidden &&
              (person.source == 'סריקה' || person.source == 'אנשי קשר'),
        )
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
    List<String>? religiousLevelOtherLabels,
    List<ProfileStatus>? profileStatuses,
    String? city,
    bool includePending = false,
  }) {
    final String? normalizedCity = city?.trim().toLowerCase();
    final bool shouldFilterByCity =
        normalizedCity != null && normalizedCity.isNotEmpty;
    final List<String> selectedReligiousLevelOtherLabels =
        religiousLevelOtherLabels ?? const <String>[];
    final List<ReligiousLevel> selectedReligiousLevels =
        religiousLevels ?? const <ReligiousLevel>[];
    final bool shouldFilterByReligiousLevel =
        selectedReligiousLevels.isNotEmpty ||
        selectedReligiousLevelOtherLabels.isNotEmpty;
    final bool shouldFilterByProfileStatus =
        profileStatuses != null && profileStatuses.isNotEmpty;
    final List<ProfileStatus> selectedProfileStatuses =
        profileStatuses ?? const <ProfileStatus>[];

    final List<Person> people = _box.values.where((Person person) {
      if (person.hidden) {
        return false;
      }

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
          !selectedReligiousLevels.contains(person.religiousLevel) &&
          !(person.religiousLevel == ReligiousLevel.other &&
              selectedReligiousLevelOtherLabels.contains(
                person.religiousLevelOther?.trim(),
              ))) {
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

  /// Phones of active (non-hidden) people. Used to decide which device
  /// contacts are already imported. Hidden people are excluded so their device
  /// contacts can resurface in the import list (where they appear only while
  /// searching).
  Set<String> getNormalizedPhones() {
    return _box.values
        .where((Person person) => !person.hidden)
        .map((Person person) => PhoneUtils.normalizeForComparison(person.phone))
        .whereType<String>()
        .toSet();
  }

  /// Phones of hidden (soft-deleted) people.
  Set<String> getHiddenNormalizedPhones() {
    return _box.values
        .where((Person person) => person.hidden)
        .map((Person person) => PhoneUtils.normalizeForComparison(person.phone))
        .whereType<String>()
        .toSet();
  }

  Future<void> setHidden(String id, bool hidden) async {
    final Person? person = getById(id);
    if (person == null || person.hidden == hidden) {
      return;
    }

    person.hidden = hidden;
    person.updatedAt = DateTime.now();
    await person.save();
    notifyListeners();
    _refreshBirthdayNotificationsInBackground();
  }

  /// Restores a previously hidden person back into the import queue so the user
  /// can fill in their details again. Returns the restored person.
  Future<Person?> restoreHidden(String id) async {
    final Person? person = getById(id);
    if (person == null) {
      return null;
    }

    person.hidden = false;
    person.needsReview = true;
    person.updatedAt = DateTime.now();
    await person.save();
    notifyListeners();
    _refreshBirthdayNotificationsInBackground();
    return person;
  }

  Future<void> add(Person person) async {
    await _box.put(person.id, person);
    notifyListeners();
    _refreshBirthdayNotificationsInBackground();
  }

  Future<void> addImported(Person person) async {
    await _box.put(person.id, person);
  }

  Future<void> savePendingContactDraft(Person person) async {
    person
      ..hidden = true
      ..needsReview = true
      ..updatedAt = DateTime.now();
    await _box.put(person.id, person);
    notifyListeners();
  }

  Future<void> activatePendingContactDraft(Person person) async {
    person.hidden = false;
    await update(person);
  }

  Future<void> update(Person person) async {
    person.updatedAt = DateTime.now();
    person.needsReview = false;
    await person.save();
    _recordActivity(person.id, HomeActivityAction.editedDetails);
    if (!person.profileStatus.pausesMatches) {
      await PersonReminders.clear(person.id);
    }
    notifyListeners();
    await onPersonStatusChanged?.call(person.id);
    _refreshBirthdayNotificationsInBackground();
    _refreshPersonRemindersInBackground();
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

    final Box<PersonEvent>? eventBox = _eventBox;
    if (eventBox != null) {
      final List<dynamic> eventKeys = eventBox.keys.where((dynamic key) {
        return eventBox.get(key)?.personId == id;
      }).toList();
      if (eventKeys.isNotEmpty) {
        await eventBox.deleteAll(eventKeys);
      }
    }

    await _box.delete(id);
    HomeBoardStore.instance.forget(HomeItemKind.person, id);
    RecentActivityStore.instance.forget(HomeItemKind.person, id);
    notifyListeners();
    _refreshBirthdayNotificationsInBackground();
    _refreshPersonRemindersInBackground();
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
    final String? normalized = (newCity == null || newCity.trim().isEmpty)
        ? null
        : newCity.trim();
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
    if (person == null) {
      return;
    }
    if (person.profileStatus == newStatus) {
      if (!newStatus.pausesMatches) {
        await PersonReminders.clear(id);
        notifyListeners();
        _refreshPersonRemindersInBackground();
      }
      return;
    }

    person.profileStatus = newStatus;
    person.updatedAt = DateTime.now();
    await person.save();
    if (!newStatus.pausesMatches) {
      await PersonReminders.clear(id);
    }
    // Status changes stay out of the personal-notes timeline (which is for the
    // matchmaker's own notes), but they are meaningful history, so they are
    // recorded in the dedicated event log.
    await logEvent(
      id,
      PersonEventType.statusChanged,
      'הסטטוס שונה ל־${newStatus.displayName}',
    );
    _recordActivity(id, HomeActivityAction.changedStatus);
    notifyListeners();
    await onPersonStatusChanged?.call(id);
    _refreshPersonRemindersInBackground();
  }

  /// The history events for a person, newest first. Backs the profile's
  /// "היסטוריה אחרונה" feed and the full history screen.
  List<PersonEvent> getEventsForPerson(String personId) {
    final Box<PersonEvent>? eventBox = _eventBox;
    if (eventBox == null) {
      return const <PersonEvent>[];
    }
    final List<PersonEvent> events = eventBox.values
        .where((PersonEvent event) => event.personId == personId)
        .toList();
    events.sort(
      (PersonEvent a, PersonEvent b) => b.createdAt.compareTo(a.createdAt),
    );
    return events;
  }

  /// Records a meaningful history event for a person. Wired to
  /// [MatchRepository.logPersonEvent] in `main.dart` so proposal-driven events
  /// land here without that repository depending on the person store.
  Future<void> logEvent(
    String personId,
    PersonEventType type,
    String text, {
    String? relatedPersonId,
    String? relatedMatchId,
  }) async {
    final Box<PersonEvent>? eventBox = _eventBox;
    if (eventBox == null) {
      return;
    }
    final PersonEvent event = PersonEvent(
      id: _uuid.v4(),
      personId: personId,
      type: type,
      text: text,
      createdAt: DateTime.now(),
      relatedPersonId: relatedPersonId,
      relatedMatchId: relatedMatchId,
    );
    await eventBox.put(event.id, event);
    notifyListeners();
  }

  /// The "check on them again" reminder date for a person, or null when none.
  DateTime? personReminderFor(String id) => PersonReminders.forPerson(id);

  /// Sets a per-person reminder (used when someone goes on a break) and bumps
  /// [Person.updatedAt] since setting it is a meaningful action.
  Future<void> setPersonReminder(String id, DateTime date) async {
    await PersonReminders.set(id, date);
    final Person? person = getById(id);
    if (person != null) {
      person.updatedAt = DateTime.now();
      await person.save();
    }
    notifyListeners();
    _refreshPersonRemindersInBackground();
  }

  Future<void> clearPersonReminder(String id) async {
    await PersonReminders.clear(id);
    notifyListeners();
    _refreshPersonRemindersInBackground();
  }

  /// Bumps [Person.updatedAt] for a meaningful action that doesn't otherwise
  /// change the record — e.g. reaching out over WhatsApp from the profile.
  Future<void> touch(String id) async {
    final Person? person = getById(id);
    if (person == null) {
      return;
    }
    person.updatedAt = DateTime.now();
    await person.save();
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

  Future<void> addNote(
    String personId,
    String text, {
    bool isAutomatic = false,
  }) async {
    final DateTime now = DateTime.now();
    await _createNote(
      personId: personId,
      text: text,
      createdAt: now,
      isAutomatic: isAutomatic,
    );

    final Person? person = getById(personId);
    if (person != null) {
      person.updatedAt = now;
      await person.save();
    }

    // A note the matchmaker wrote is history worth surfacing; the automatic
    // history lines that other flows create are logged as events directly.
    if (!isAutomatic) {
      await logEvent(personId, PersonEventType.note, text);
      _recordActivity(personId, HomeActivityAction.addedNote);
    }

    notifyListeners();
  }

  Future<void> updateNote(String noteId, String text) async {
    final Box<PersonNote>? noteBox = _noteBox;
    final PersonNote? note = noteBox?.get(noteId);
    if (note == null) {
      return;
    }

    note.text = text;
    await noteBox!.put(note.id, note);
    await _touchPerson(note.personId);
    notifyListeners();
  }

  Future<void> deleteNote(String noteId) async {
    final Box<PersonNote>? noteBox = _noteBox;
    if (noteBox == null || !noteBox.containsKey(noteId)) {
      return;
    }

    final String? personId = noteBox.get(noteId)?.personId;
    await noteBox.delete(noteId);
    if (personId != null) {
      await _touchPerson(personId);
    }
    notifyListeners();
  }

  Future<void> _touchPerson(String personId) async {
    final Person? person = getById(personId);
    if (person != null) {
      person.updatedAt = DateTime.now();
      await person.save();
    }
  }

  Future<void> addImportedNote(PersonNote note) async {
    await _noteBox?.put(note.id, note);
  }

  int _sortByFirstName(Person a, Person b) {
    return a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
  }

  Future<void> _refreshBirthdayNotifications() async {
    await NotificationService.cancelBirthdayNotifications();
  }

  void _refreshBirthdayNotificationsInBackground() {
    unawaited(_refreshBirthdayNotifications());
  }

  /// Hands the current set of "check on them again" reminders to the
  /// notification service, so the matchmaker gets a push on the day instead of
  /// having to remember to open the reminders panel. Reminders for people who
  /// no longer exist are skipped.
  Future<void> _refreshPersonReminders() async {
    final List<PersonReminderNotification> reminders =
        <PersonReminderNotification>[];
    for (final MapEntry<String, DateTime> entry
        in PersonReminders.all().entries) {
      final Person? person = getById(entry.key);
      if (person == null) {
        continue;
      }
      final String name = person.fullName.trim();
      reminders.add(
        PersonReminderNotification(
          name: name.isEmpty ? 'חבר/ה מהמאגר' : name,
          date: entry.value,
        ),
      );
    }

    await NotificationService.schedulePersonReminders(reminders);
  }

  void _refreshPersonRemindersInBackground() {
    unawaited(_refreshPersonReminders());
  }

  /// Feeds the home screen's "חזרה מהירה" strip. Recorded here rather than at
  /// the call sites so every path that really changes a person shows up, with
  /// no extra bookkeeping asked of the matchmaker.
  void _recordActivity(String personId, HomeActivityAction action) {
    RecentActivityStore.instance.record(
      kind: HomeItemKind.person,
      targetId: personId,
      action: action,
    );
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
