import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/person_tags.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// A card another matchmaker shares with this one —
/// `networkCards/{ownerUid}_{personId}`, one published view naming its
/// `readers` (2026-11-20).
///
/// **View only, and only what a card is.** Photos, the card's own fields,
/// "מה מחפש" and tags. Never a phone number, a note, a go-between or a
/// reminder: [SharedCardCodec.toRemote] is the whitelist, and `firestore.rules`
/// refuses anything beyond it.
class SharedCard {
  SharedCard({
    required this.ownerUid,
    required this.ownerName,
    required this.personId,
    required this.person,
    required this.photoPaths,
    this.identity,
    this.cardOwnerUid,
    this.updatedAt,
  });

  /// The matchmaker who holds the card.
  final String ownerUid;
  final String ownerName;

  /// The friend's id in the owner's own database.
  final String personId;

  /// The card's fields as a transient [Person] — never saved, so it can be
  /// matched and drawn with the same code as the matchmaker's own friends.
  /// Its id is [key], so nothing can mistake it for a record.
  final Person person;

  /// Storage paths of the photos (`sharedCards/{owner}/{person}/{file}`).
  final List<String> photoPaths;

  /// The friend's phone, hashed (`PhoneIdentity`) — how two matchmakers
  /// holding the same person are recognised without either seeing a number.
  final String? identity;

  /// The single's own account, when the card is their personal card.
  final String? cardOwnerUid;

  final DateTime? updatedAt;

  /// One card across every matchmaker's pool.
  String get key => keyOf(ownerUid, personId);

  static String keyOf(String ownerUid, String personId) =>
      'shared:$ownerUid:$personId';

  /// The owner's first name, for "מהמאגר של יונתן".
  String get ownerFirstName {
    final String name = ownerName.trim();
    if (name.isEmpty) return 'שדכן/ית';
    return name.split(RegExp(r'\s+')).first;
  }

  static SharedCard? fromMap(Map<String, dynamic> data) {
    final Object? owner = data['ownerUid'];
    final Object? id = data['personId'];
    if (owner is! String || id is! String || owner.isEmpty || id.isEmpty) {
      return null;
    }
    final Person person = personFrom(data, key: keyOf(owner, id));
    final Object? stamp = data['updatedAt'];
    return SharedCard(
      ownerUid: owner,
      ownerName: (data['ownerName'] as String?)?.trim() ?? '',
      personId: id,
      person: person,
      photoPaths: <String>[
        for (final Object? p
            in (data['photoPaths'] as List?) ?? const <Object?>[])
          if (p is String && p.isNotEmpty) p,
      ],
      identity: _string(data['identity']),
      cardOwnerUid: _string(data['cardOwnerUid']),
      updatedAt: stamp is Timestamp ? stamp.toDate() : null,
    );
  }

  /// The card's fields as a transient [Person] with id [key]. Also used for a
  /// candidate offered in an idea, which carries the same fields.
  static Person personFrom(Map<String, dynamic> data, {required String key}) {
    final DateTime now = DateTime.now();
    final Person person = Person(
      id: key,
      firstName: '',
      lastName: '',
      gender: Gender.unknown,
      createdAt: now,
      updatedAt: now,
    );
    PersonalCardCodec.applyTo(person, data);
    final Object? age = data['age'];
    if (person.birthDate == null && age is num) {
      person.setManualAge(age.toInt());
    }
    person.tags = PersonalCardCodec.tagsOf(data);
    person.profileStatus =
        PersonalCardCodec.statusOf(data) ?? ProfileStatus.available;
    return person;
  }

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

/// The one mapping from a friend in the matchmaker's database to what other
/// matchmakers may see of them.
abstract final class SharedCardCodec {
  /// Where the published cards live — one document per shared friend.
  static const String collection = 'networkCards';

  static String docId(String ownerUid, String personId) =>
      '${ownerUid}_$personId';

  /// A name folded for a prefix search on the server: lower case, niqqud,
  /// punctuation and repeated spaces gone. The same fold for what is stored
  /// and what is typed.
  static String nameKey(String name) {
    final String folded = name
        .toLowerCase()
        .replaceAll(RegExp(r'[\u0591-\u05C7]'), '')
        .replaceAll(RegExp('[-_.,\'"׳״`]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return folded.length > 80 ? folded.substring(0, 80) : folded;
  }

  /// The most photos a shared card carries — also in `firestore.rules`.
  static const int maxPhotos = 6;

  /// The most tags — also in `firestore.rules`.
  static const int maxTags = 40;

  /// The card's fields, without photos or the server's time — what two
  /// versions of a card are compared by.
  static Map<String, Object?> values(
    Person person, {
    required String ownerUid,
    required String ownerName,
  }) {
    final String name = ownerName.trim();
    return <String, Object?>{
      'ownerUid': ownerUid,
      'ownerName': name.length > 80 ? name.substring(0, 80) : name,
      'personId': person.id,
      ...PersonalCardCodec.cardValues(person),
      'description': (person.description ?? '').trim(),
      'age': person.age,
      'tags': <String>[
        for (final String tag in person.tags.take(maxTags))
          if (PersonTags.normalize(tag).isNotEmpty) PersonTags.normalize(tag),
      ],
      'identity': PhoneIdentity.hash(person.phone),
      'cardOwnerUid': person.cardOwnerUid,
      'status': switch (person.profileStatus) {
        ProfileStatus.busy => 'busy',
        ProfileStatus.onBreak => 'onBreak',
        _ => 'available',
      },
    };
  }

  /// The document written to `networkCards/{ownerUid}_{personId}` — with
  /// [readers] — or, without them, a card sent to one matchmaker in a chat
  /// (`sentCards`).
  static Map<String, Object?> toRemote(
    Person person, {
    required String ownerUid,
    required String ownerName,
    required List<String> photoPaths,
    List<String>? readers,
  }) => <String, Object?>{
    ...values(person, ownerUid: ownerUid, ownerName: ownerName),
    'photoPaths': photoPaths,
    if (readers != null) 'readers': readers,
    if (readers != null)
      'nameKey': nameKey('${person.firstName} ${person.lastName}'),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Where a photo of [personId] lives in Storage.
  static String photoPath(String ownerUid, String personId, String basename) =>
      'sharedCards/$ownerUid/$personId/$basename';
}
