import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/enums.dart';

/// The signed-in user's own shidduch card, which they manage themselves.
///
/// **It is a [Person], on purpose.** The card owner edits it with the same
/// page a matchmaker uses for a friend, and the matchmakers they approve will
/// receive it into their own database as a `Person` — one shape end to end
/// means nothing has to be translated, and nothing can be lost in the
/// translation.
///
/// It is kept out of the people box. That box *is* the matchmaker's
/// database; the owner's own card sitting in it would count in their figures,
/// turn up in their searches and be offered as a match for their friends.
///
/// Stored as the backup JSON of the person, in the settings box, written
/// through [persistHomeSetting] like every store the first frame reads.
class PersonalCardProvider extends ChangeNotifier {
  PersonalCardProvider(this._box) {
    _card = _decode(_box.get(_cardKey));
    final Object? deleted = _box.get(_deletedKey);
    _deleted = deleted == true || deleted == 'true';
    final Object? accepts = _box.get(_acceptsRequestsKey);
    _acceptsRequests = !(accepts == false || accepts == 'false');
  }

  static const String cardId = 'personal-card';
  static const String _cardKey = 'personalCard.person';
  static const String _deletedKey = 'personalCard.deleted';
  static const String _acceptsRequestsKey = 'personalCard.acceptsRequests';

  final Box<dynamic> _box;
  Person? _card;
  bool _deleted = false;
  bool _acceptsRequests = true;

  /// Whether matchmakers may ask for access to the card at all.
  ///
  /// **One answer for everybody.** Off, no matchmaker can send a request, and
  /// to every one of them the card looks like no card: they write to the
  /// friend in WhatsApp as they would to anybody. The owner can still give a
  /// friend access on their own initiative, from "החברים שלי שמשדכים בשדכן".
  /// Published beside the phone identity — see `PersonalCardSync`.
  bool get acceptsRequests => _acceptsRequests;

  Future<void> setAcceptsRequests(bool value) async {
    if (_acceptsRequests == value) {
      return;
    }
    _acceptsRequests = value;
    persistHomeSetting(_acceptsRequestsKey, value ? 'true' : 'false');
    notifyListeners();
  }

  /// The card as last saved — kept even while deleted, because deleting a
  /// card never erases it: it can always be restored.
  Person? get card => _card;

  /// A live card: written, and not deleted.
  bool get hasCard => _card != null && !_deleted;

  /// A card that was written and then deleted — the personal area offers
  /// "שחזור הכרטיס שלי" instead of an empty page.
  bool get isDeleted => _card != null && _deleted;

  /// Marks the card deleted on this device. The caller has already told the
  /// server; see [PersonalCardService.setCardDeleted].
  Future<void> markDeleted() async {
    _deleted = true;
    persistHomeSetting(_deletedKey, 'true');
    notifyListeners();
  }

  /// Brings a deleted card back, as "פנוי" — whatever it said when it was
  /// deleted, a restored card starts again as available.
  Future<Person?> restore() async {
    final Person? current = _card;
    if (current == null) {
      return null;
    }
    _deleted = false;
    persistHomeSetting(_deletedKey, 'false');
    await save(current.copyWith(profileStatus: ProfileStatus.available));
    return _card;
  }

  static Person? _decode(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    try {
      final Object? json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return BackupService.personFromJson(json);
      }
    } catch (error) {
      debugPrint('PersonalCardProvider: unreadable card ($error)');
    }
    return null;
  }

  /// A first draft for somebody who has no card yet, filled from what the app
  /// already knows about them — their name and gender, and the short card and
  /// photos the old "כרטיס השידוכים שלי" kept, so nothing written there is
  /// lost when the full card replaces it.
  Person draftFrom(UserProfileProvider profile) {
    final DateTime now = DateTime.now();
    return Person(
      id: cardId,
      firstName: profile.firstName ?? '',
      lastName: profile.lastName ?? '',
      gender: profile.gender ?? Gender.unknown,
      description: profile.personalCard,
      photosPaths: profile.personalCardPhotos,
      maritalStatus: MaritalStatus.single,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Saves [person] as the card. The owner is the only one who ever edits it,
  /// so there is nothing to merge: the latest save is the card.
  Future<void> save(Person person) async {
    final Person saved = person.copyWith(
      id: cardId,
      updatedAt: DateTime.now(),
      // A card owner's card is never a hidden draft, and never waits for
      // review — it is theirs, finished whenever they say so.
      hidden: false,
      needsReview: false,
    );
    _card = saved;
    persistHomeSetting(_cardKey, jsonEncode(BackupService.personToJson(saved)));
    notifyListeners();
  }

  /// The owner's own availability — פנוי, בהפסקה, תפוס, מזל טוב.
  Future<void> setStatus(ProfileStatus status) async {
    final Person? current = _card;
    if (current == null || current.profileStatus == status) {
      return;
    }
    await save(current.copyWith(profileStatus: status));
  }

  /// Forgets the card on this device, for a sign-out.
  Future<void> clear() async {
    _card = null;
    _deleted = false;
    _acceptsRequests = true;
    await _box.deleteAll(<String>[_cardKey, _deletedKey, _acceptsRequestsKey]);
    notifyListeners();
  }
}
