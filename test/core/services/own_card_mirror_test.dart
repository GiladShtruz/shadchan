import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/own_card_mirror.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';

/// A single who matchmakes too finds their own personal card among their
/// friends: one record, kept in step with the card, never a duplicate.
void main() {
  late Directory directory;
  late Box<Person> people;
  late PersonRepository repository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('own_card_mirror_');
    Hive.init(directory.path);
    Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
    }
    Hive.registerAdapter(GenderAdapter());
    Hive.registerAdapter(ReligiousLevelAdapter());
    Hive.registerAdapter(ProfileStatusAdapter());
    Hive.registerAdapter(MaritalStatusAdapter());
    Hive.registerAdapter(MatchContactAdapter());
    await Hive.openBox<dynamic>('settings');
    // Photo copies are files in the app's documents folder; the test only
    // needs to know which names the record ends up with.
    OwnCardMirror.copyPhotoOverride = (String source) async =>
        '/photos/${OwnCardMirror.photoPrefix}${source.split('/').last}';
  });

  setUp(() async {
    await Future<void>.delayed(Duration.zero);
    people = await Hive.openBox<Person>('people');
    await people.clear();
    await Hive.box<dynamic>('settings').clear();
    OwnCardMirror.forgetCache();
    repository = PersonRepository(people);
  });

  tearDownAll(() async {
    OwnCardMirror.copyPhotoOverride = null;
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  final DateTime now = DateTime(2026, 1, 1);

  Person card({
    String description = 'בחורה שמחה, אוהבת טיולים ואנשים, מחפשת בית חם',
    ProfileStatus status = ProfileStatus.available,
    List<String> photos = const <String>['/photos/card_1.jpg'],
    int? prefMinAge,
  }) => Person(
    id: 'personal-card',
    firstName: 'נועה',
    lastName: 'לוי',
    gender: Gender.female,
    religiousLevel: ReligiousLevel.datiLeumi,
    city: 'ירושלים',
    description: description,
    profileStatus: status,
    photosPaths: photos,
    preferredMinAge: prefMinAge,
    createdAt: now,
    updatedAt: now,
  );

  Future<Person?> sync(
    Person c, {
    bool matchmaker = true,
    String? phone = '050-1234567',
  }) => OwnCardMirror.sync(
    card: c,
    cardIsLive: true,
    matchmakerEnabled: matchmaker,
    people: repository,
    myPhone: phone,
  );

  test('the card lands in the database once, with its details', () async {
    final Person? mirror = await sync(card());
    expect(mirror, isNotNull);
    expect(repository.getAll().length, 1);
    final Person saved = repository.getById(OwnCardMirror.defaultId)!;
    expect(saved.fullName, 'נועה לוי');
    expect(saved.gender, Gender.female);
    expect(saved.city, 'ירושלים');
    expect(saved.description, startsWith('בחורה שמחה'));
    expect(saved.phone, '050-1234567');
    expect(saved.hidden, isFalse);
    // Its photos are copies of its own.
    expect(saved.photosPaths, <String>['/photos/own_card_1.jpg']);

    await sync(card());
    expect(repository.getAll().length, 1);
  });

  test(
    'a change to the card follows; the matchmaker\'s own notes stay',
    () async {
      await sync(card());
      final Person mine = repository.getById(OwnCardMirror.defaultId)!
        ..tags = <String>['חברה מהעבודה'];
      await repository.update(mine);

      await sync(
        card(
          description: 'כרטיס חדש לגמרי, עם עוד כמה מילים טובות עליי',
          status: ProfileStatus.onBreak,
          photos: <String>['/photos/card_2.jpg', '/photos/card_1.jpg'],
        ),
      );
      final Person saved = repository.getById(OwnCardMirror.defaultId)!;
      expect(saved.description, startsWith('כרטיס חדש'));
      expect(saved.profileStatus, ProfileStatus.onBreak);
      expect(saved.photosPaths, <String>[
        '/photos/own_card_2.jpg',
        '/photos/own_card_1.jpg',
      ]);
      expect(saved.tags, <String>['חברה מהעבודה']);
    },
  );

  test('a friend already added for oneself is adopted, not doubled', () async {
    await repository.add(
      Person(
        id: 'manual-me',
        firstName: 'נועה',
        lastName: 'לוי',
        gender: Gender.female,
        phone: '0501234567',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final Person? mirror = await sync(card());
    expect(mirror!.id, 'manual-me');
    expect(repository.getAll().length, 1);
    expect(repository.getById('manual-me')!.description, startsWith('בחורה'));
    expect(OwnCardMirror.mirrorId, 'manual-me');
    expect(OwnCardMirror.isMirror('manual-me'), isTrue);
  });

  test('nothing for a single who is not a matchmaker', () async {
    expect(await sync(card(), matchmaker: false), isNull);
    expect(repository.getAll(), isEmpty);
  });

  test('deleted from the database, it stays deleted', () async {
    await sync(card());
    await repository.delete(OwnCardMirror.defaultId);
    expect(
      await sync(card(description: 'שוב משהו חדש לגמרי בכרטיס שלי כאן')),
      isNull,
    );
    expect(repository.getAll(), isEmpty);
  });

  test('the single\'s own "מה אני מחפש/ת" are their wishes here too', () async {
    await sync(card(prefMinAge: 26));
    final Person mirror = repository.getById(OwnCardMirror.defaultId)!;
    expect(MatchSuggestionUtils.followsOwnerWishes(mirror), isTrue);
  });
}
