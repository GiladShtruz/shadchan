import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/services/notification_service.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/models/person.dart';

class PersonRepository extends ChangeNotifier {
  PersonRepository(this._box);

  final Box<Person> _box;

  int get count => _box.length;

  List<Person> getAll() {
    final List<Person> people = _box.values.toList();
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
    String? city,
    bool? favoritesOnly,
  }) {
    final String? normalizedCity = city?.trim().toLowerCase();
    final bool shouldFilterByCity =
        normalizedCity != null && normalizedCity.isNotEmpty;
    final bool shouldFilterByReligiousLevel =
        religiousLevels != null && religiousLevels.isNotEmpty;
    final List<ReligiousLevel> selectedReligiousLevels =
        religiousLevels ?? const <ReligiousLevel>[];

    final List<Person> people = _box.values.where((Person person) {
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
    await person.save();
    notifyListeners();
    _refreshBirthdayNotificationsInBackground();
  }

  Future<void> delete(String id) async {
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
}
