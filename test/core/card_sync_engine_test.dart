import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/card_sync_engine.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/utils/enums.dart';

Map<String, dynamic> _remote({
  String status = 'available',
  String description = 'אוהב טיולים',
  List<String> photos = const <String>[],
}) {
  final DateTime now = DateTime(2026, 1, 1);
  final Map<String, Object?> data = PersonalCardCodec.toRemote(
    Person(
      id: 'personal-card',
      firstName: 'דניאל',
      lastName: 'לוי',
      gender: Gender.male,
      birthDate: DateTime(1999, 4, 7),
      religiousLevel: ReligiousLevel.datiLeumi,
      description: description,
      region: Region.center,
      createdAt: now,
      updatedAt: now,
    ),
    ownerUid: 'owner',
    photoPaths: photos,
  );
  data['status'] = status;
  return Map<String, dynamic>.from(data);
}

Person _local({bool withOwnContent = true}) {
  final DateTime now = DateTime(2026, 1, 1);
  return Person(
    id: 'p1',
    firstName: 'דני',
    lastName: 'לוי',
    gender: Gender.male,
    manualAge: withOwnContent ? 30 : null,
    description: withOwnContent ? 'מה שאני כתבתי' : null,
    phone: '050-1234567',
    photosPaths: withOwnContent
        ? const <String>['/x/mine.jpg']
        : const <String>[],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('the first link keeps a snapshot of what the matchmaker wrote', () {
    final Person person = _local();
    final CardSyncResult result = CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>['/x/card_owner_a.jpg'],
    );
    expect(result.changed, isTrue);
    expect(result.updates, isEmpty);
    expect(person.cardOwnerUid, 'owner');
    expect(person.isCardSynced, isTrue);
    expect(person.preSyncSnapshot, isNotNull);
    expect(person.description, 'אוהב טיולים');
    expect(person.firstName, 'דניאל');
    expect(person.photosPaths, const <String>['/x/card_owner_a.jpg']);
    // The matchmaker's own number stays.
    expect(person.phone, '050-1234567');
  });

  test('no snapshot when there was nothing but a name', () {
    final Person person = _local(withOwnContent: false);
    CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    expect(person.preSyncSnapshot, isNull);
  });

  test('later changes are described in one line each', () {
    final Person person = _local();
    CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>['/x/card_owner_a.jpg'],
    );
    final CardSyncResult result = CardSyncEngine.apply(
      person,
      _remote(description: 'אוהב טיולים ומוזיקה'),
      ownerUid: 'owner',
      localPhotoPaths: const <String>['/x/card_owner_b.jpg'],
    );
    expect(result.updates, <String>['דניאל החליף תמונה']);
    // One word added to a short text is a correction, not news.
    expect(result.minorUpdates, <String>['דניאל תיקן את טקסט הכרטיס']);
  });

  test('a deleted photo reads as deleted, not replaced', () {
    final Person person = _local();
    CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[
        '/x/card_owner_a.jpg',
        '/x/card_owner_b.jpg',
      ],
    );
    final CardSyncResult result = CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>['/x/card_owner_a.jpg'],
    );
    expect(result.updates, <String>['דניאל מחק תמונה']);
    expect(result.minorUpdates, isEmpty);
  });

  test('a rewritten card text is news; a fixed word is not', () {
    const String long =
        'בחור רציני ושמח, עובד בהייטק ולומד בערבים. אוהב טיולים בטבע, '
        'מוזיקה ישראלית וערבי שבת עם חברים. מחפש בחורה חמה ושמחה.';
    final Person person = _local();
    CardSyncEngine.apply(
      person,
      _remote(description: long),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    final CardSyncResult small = CardSyncEngine.apply(
      person,
      _remote(description: long.replaceFirst('ישראלית', 'קלאסית')),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    expect(small.updates, isEmpty);
    expect(small.minorUpdates, <String>['דניאל תיקן את טקסט הכרטיס']);

    final CardSyncResult rewrite = CardSyncEngine.apply(
      person,
      _remote(description: 'סטודנט לרפואה בירושלים, מתנדב במד"א ומנגן בגיטרה.'),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    expect(rewrite.updates, <String>['דניאל עדכן את טקסט הכרטיס']);
  });

  test('photo change wording', () {
    expect(
      CardSyncEngine.describePhotoChange(
        const <String>['/a/1.jpg', '/a/2.jpg', '/a/3.jpg'],
        const <String>['/a/1.jpg'],
      ),
      (line: '{מחק|מחקה} 2 תמונות', major: true),
    );
    expect(
      CardSyncEngine.describePhotoChange(
        const <String>['/a/1.jpg'],
        const <String>['/a/1.jpg', '/a/2.jpg'],
      ),
      (line: '{הוסיף|הוסיפה} תמונה', major: true),
    );
    expect(
      CardSyncEngine.describePhotoChange(
        const <String>['/a/1.jpg', '/a/2.jpg', '/a/3.jpg'],
        const <String>['/a/1.jpg', '/a/3.jpg', '/a/2.jpg'],
      ).major,
      isFalse,
    );
    expect(
      CardSyncEngine.describePhotoChange(
        const <String>['/a/1.jpg', '/a/2.jpg'],
        const <String>['/a/2.jpg', '/a/1.jpg'],
      ),
      (line: '{החליף|החליפה} את התמונה הראשית', major: true),
    );
  });

  test('a local status stands until the owner changes theirs', () {
    final Person person = _local();
    CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    // The matchmaker marks them busy on this phone.
    person.profileStatus = ProfileStatus.busy;
    CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    expect(person.profileStatus, ProfileStatus.busy);

    final CardSyncResult result = CardSyncEngine.apply(
      person,
      _remote(status: 'onBreak'),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    expect(person.profileStatus, ProfileStatus.onBreak);
    expect(result.statusChanged, isTrue);
  });

  test('a detached record takes the status and nothing else', () {
    final Person person = _local();
    CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    person
      ..cardSyncDetached = true
      ..description = 'גרסה שלי';
    CardSyncEngine.apply(
      person,
      _remote(description: 'שינוי של הבעלים', status: 'mazelTov'),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    expect(person.description, 'גרסה שלי');
    expect(person.profileStatus, ProfileStatus.mazelTov);
  });

  test('withdrawn access puts the snapshot back and drops card photos', () {
    final Person person = _local();
    CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>['/x/card_owner_a.jpg'],
    );
    final List<String> toDelete = CardSyncEngine.unlink(person);
    expect(toDelete, const <String>['/x/card_owner_a.jpg']);
    expect(person.cardOwnerUid, isNull);
    expect(person.firstName, 'דני');
    expect(person.description, 'מה שאני כתבתי');
    expect(person.age, 30);
    expect(person.photosPaths, const <String>['/x/mine.jpg']);
  });

  test('with no snapshot, the owner’s details come off and the name stays', () {
    final Person person = _local(withOwnContent: false);
    CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>['/x/card_owner_a.jpg'],
    );
    CardSyncEngine.unlink(person);
    expect(person.firstName, 'דניאל');
    expect(person.description, isNull);
    expect(person.birthDate, isNull);
    expect(person.region, isNull);
    expect(person.photosPaths, isEmpty);
    expect(person.phone, '050-1234567');
  });

  test('withdrawn access leaves the friend in the database', () {
    final Person person = _local(withOwnContent: false)
      ..hidden = true
      ..needsReview = true;
    CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    // Whatever state the record was in, ending the link must not take the
    // friend out of המאגר שלי.
    person.hidden = true;
    CardSyncEngine.unlink(person);
    expect(person.hidden, isFalse);
    expect(person.needsReview, isFalse);
    expect(person.firstName, 'דניאל');
  });

  test('a detached record is kept as the matchmaker left it', () {
    final Person person = _local();
    CardSyncEngine.apply(
      person,
      _remote(),
      ownerUid: 'owner',
      localPhotoPaths: const <String>[],
    );
    person
      ..cardSyncDetached = true
      ..description = 'גרסה שלי';
    expect(CardSyncEngine.unlink(person), isEmpty);
    expect(person.description, 'גרסה שלי');
    expect(person.cardOwnerUid, isNull);
  });

  test('the print moves with a card edit and not with anything else', () {
    final Person person = _local();
    final String before = CardSyncEngine.printOf(person);
    person.isFavorite = true;
    expect(CardSyncEngine.printOf(person), before);
    person.description = 'שיניתי';
    expect(CardSyncEngine.printOf(person), isNot(before));
  });
}
