import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';

void main() {
  late Directory hiveDirectory;
  late int boxCounter;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    hiveDirectory = await Directory.systemTemp.createTemp(
      'shadchan_contacts_test_',
    );
    Hive.init(hiveDirectory.path);
    boxCounter = 0;

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PersonAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(GenderAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ReligiousLevelAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ProfileStatusAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('normalizeForComparison unifies Israeli phone formats', () {
    expect(PhoneUtils.normalizeForComparison('+972-52-123-4567'), '0521234567');
    expect(PhoneUtils.normalizeForComparison('052 123 4567'), '0521234567');
  });

  test('buildCandidate keeps first valid phone and marks existing numbers', () {
    final ContactImportCandidate? candidate =
        ContactsImportService.buildCandidate(
          deviceContactId: 'contact_1',
          displayName: 'יוסי כהן',
          phones: const <String>['', '+972 52 123 4567', '03-5555555'],
          existingPhones: const <String>{'0521234567'},
        );

    expect(candidate, isNotNull);
    expect(candidate!.phone, '+972 52 123 4567');
    expect(candidate.normalizedPhone, '0521234567');
    expect(candidate.alreadyExists, isTrue);
    expect(candidate.hasAdditionalPhones, isTrue);
  });

  test('buildCandidate only accepts Israeli mobile phone prefixes', () {
    final ContactImportCandidate? landlineCandidate =
        ContactsImportService.buildCandidate(
          deviceContactId: 'contact_1',
          displayName: 'מוקד עירוני',
          phones: const <String>['02-6751234'],
          existingPhones: const <String>{},
        );
    final ContactImportCandidate? shortCodeCandidate =
        ContactsImportService.buildCandidate(
          deviceContactId: 'contact_2',
          displayName: 'שירות קצר',
          phones: const <String>['100'],
          existingPhones: const <String>{},
        );
    final ContactImportCandidate? mobileCandidate =
        ContactsImportService.buildCandidate(
          deviceContactId: 'contact_3',
          displayName: 'יוסי כהן',
          phones: const <String>['+972 52 123 4567'],
          existingPhones: const <String>{},
        );

    expect(landlineCandidate, isNull);
    expect(shortCodeCandidate, isNull);
    expect(mobileCandidate, isNotNull);
  });

  test('buildCandidate marks names that match blocked keywords', () {
    final ContactImportCandidate? candidate =
        ContactsImportService.buildCandidate(
          deviceContactId: 'contact_1',
          displayName: 'יוסי אבא של גלעד',
          phones: const <String>['0521234567'],
          existingPhones: const <String>{},
        );

    expect(candidate, isNotNull);
    expect(candidate!.isFilteredByName, isTrue);
  });

  test('splitDisplayName supports single-word names', () {
    final ({String firstName, String lastName}) parsedName =
        ContactsImportService.splitDisplayName('שרה');

    expect(parsedName.firstName, 'שרה');
    expect(parsedName.lastName, isEmpty);
  });

  test('matchesQuery finds by partial name and ignores formatting marks', () {
    const ContactImportCandidate candidate = ContactImportCandidate(
      deviceContactId: 'contact_1',
      displayName: 'דוד\u200f כהן',
      phone: '052-1234567',
      normalizedPhone: '0521234567',
      alreadyExists: false,
      hasAdditionalPhones: false,
      isFilteredByName: false,
    );

    expect(candidate.matchesQuery('דוד'), isTrue);
    expect(candidate.matchesQuery('כהן'), isTrue);
    expect(candidate.matchesQuery('דוד כהן'), isTrue);
    expect(candidate.matchesQuery('1234'), isTrue);
    expect(candidate.matchesQuery('משה'), isFalse);
  });

  test('importSelections skips existing and repeated phone numbers', () async {
    final String suffix =
        '${DateTime.now().microsecondsSinceEpoch}_${boxCounter++}';
    final Box<Person> peopleBox = await Hive.openBox<Person>('people_$suffix');
    final PersonRepository personRepository = PersonRepository(peopleBox);

    final DateTime now = DateTime.now();
    await personRepository.addImported(
      Person(
        id: 'existing_person',
        firstName: 'דני',
        lastName: 'לוי',
        gender: Gender.male,
        phone: '0521234567',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final ContactImportResult result =
        await ContactsImportService.importSelections(
          const <ContactImportSelection>[
            ContactImportSelection(
              candidate: ContactImportCandidate(
                deviceContactId: 'contact_1',
                displayName: 'שרה כהן',
                phone: '054-1111111',
                normalizedPhone: '0541111111',
                alreadyExists: false,
                hasAdditionalPhones: false,
                isFilteredByName: false,
              ),
            ),
            ContactImportSelection(
              candidate: ContactImportCandidate(
                deviceContactId: 'contact_2',
                displayName: 'משה ישראלי',
                phone: '+972521234567',
                normalizedPhone: '0521234567',
                alreadyExists: true,
                hasAdditionalPhones: false,
                isFilteredByName: false,
              ),
              gender: Gender.male,
            ),
            ContactImportSelection(
              candidate: ContactImportCandidate(
                deviceContactId: 'contact_3',
                displayName: 'שרה נוספת',
                phone: '0541111111',
                normalizedPhone: '0541111111',
                alreadyExists: false,
                hasAdditionalPhones: false,
                isFilteredByName: false,
              ),
              gender: Gender.female,
            ),
          ],
          personRepository,
        );

    final List<Person> people = personRepository.getAll();

    expect(result.addedCount, 1);
    expect(result.skippedExistingCount, 2);
    expect(people, hasLength(2));
    expect(
      people.any(
        (Person person) =>
            person.phone == '054-1111111' &&
            person.source == 'אנשי קשר' &&
            person.gender == Gender.unknown,
      ),
      isTrue,
    );

    await peopleBox.deleteFromDisk();
  });
}
