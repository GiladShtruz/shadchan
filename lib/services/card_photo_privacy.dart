import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/home_board_store.dart';

/// "התמונה שלי לא ניתנת לשיתוף" — a single's choice that their card's photos
/// are for looking at inside שדכן only.
///
/// **The owner says it once, on their own card** (`PersonalCardProvider
/// .photosShareable`, published as `photosShareable: false` on
/// `personalCards/{uid}`). **The matchmaker's copy remembers it per friend**
/// here (`cardPhotosPrivate.{personId}`), written whenever the card is read
/// and forgotten when access ends. The photos still show on the friend's card
/// and profile; [shareable] is what every way a card leaves the app attaches —
/// the owner's photos are left out, a photo the matchmaker added themselves
/// is not the owner's to restrict.
abstract final class CardPhotoPrivacy {
  static const String _prefix = 'cardPhotosPrivate.';

  /// The field on the card document.
  static const String remoteField = 'photosShareable';

  static Box<dynamic>? get _settings =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// Written by the app this moment, ahead of the disk.
  static final Map<String, bool> _pending = <String, bool>{};

  /// Whether the friend [personId]'s own photos may not leave the app.
  static bool isPrivate(String personId) {
    final bool? pending = _pending[personId];
    if (pending != null) return pending;
    final Object? raw = _settings?.get('$_prefix$personId');
    return raw == true || raw == 'true';
  }

  static void set(String personId, {required bool private}) {
    if (isPrivate(personId) == private) return;
    _pending[personId] = private;
    persistHomeSetting('$_prefix$personId', private ? 'true' : 'false');
  }

  /// What a card document says: only an explicit `false` makes it private.
  static bool privateIn(Map<String, dynamic> data) =>
      data[remoteField] == false;

  /// A photo that came with the owner's card (`card_{ownerUid}_…`), as
  /// opposed to one the matchmaker added.
  static final RegExp _separators = RegExp(r'[\\/]');

  static bool isCardPhoto(String path) {
    final String name = path.split(_separators).last;
    return name.startsWith('card_');
  }

  /// [person]'s photos that may leave the app.
  static List<String> shareable(Person person) {
    if (!isPrivate(person.id)) return person.photosPaths;
    return <String>[
      for (final String path in person.photosPaths)
        if (!isCardPhoto(path)) path,
    ];
  }

  /// Whether some of [person]'s photos are held back from sharing.
  static bool holdsBack(Person person) =>
      isPrivate(person.id) && person.photosPaths.any(isCardPhoto);

  /// The account changed the settings box.
  static void forgetCache() => _pending.clear();
}
