import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/services/card_photo_privacy.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/enums.dart';

/// How much of the database the connected matchmakers see.
enum ShareMode {
  /// Nothing — the default. Sharing is always a decision.
  none,

  /// Every complete card.
  all,

  /// Only the friends picked one by one.
  selected,

  /// Every complete card except the friends picked one by one.
  allExcept;

  static ShareMode byName(Object? name) {
    for (final ShareMode m in values) {
      if (m.name == name) return m;
    }
    return ShareMode.none;
  }
}

/// Whether a friend's card can go to the connected matchmakers at all.
enum ShareEligibility {
  /// A photo and card text — it can be shared.
  ready,

  /// No photo or no card text. **Only complete cards are ever shared**, even
  /// under "שתף את כל המאגר".
  incomplete,

  /// The friend keeps their own personal card, and has not said this
  /// matchmaker may show it to other matchmakers (`cardAccess.shareOnward`).
  awaitingConsent,

  /// Not a candidate to share: outside the database, a draft, married.
  notApplicable,
}

/// "שיתוף כרטיסים עם שדכנים מחוברים" — which cards of this matchmaker's
/// database the matchmakers they are connected with may see, and the one
/// place that writes them to `sharedCards/{uid}/cards`.
///
/// **Never a public database.** A shared card is readable only by
/// matchmakers with an approved connection to this one (the rules check the
/// connection on every read), view only, and without anything the matchmaker
/// keeps for themselves — no phone, no notes ([SharedCardCodec]).
///
/// The choice is a synced setting (every phone of the account agrees), and
/// the publish is idempotent: it reads what the server holds and writes only
/// the difference, so two phones doing it at once cost nothing.
abstract final class NetworkSharing {
  static const String modeKey = 'network.shareMode';
  static const String selectedKey = 'network.shareSelected';
  static const String excludedKey = 'network.shareExcluded';
  static const String sinceKey = 'network.shareSince';
  static const String sentKey = 'network.sentCards';
  static const String onboardingKey = 'network.onboardingDone';
  static const String searchNetworkKey = 'people.searchNetwork';

  /// Bumped whenever the choice changes, for screens that show it.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// What the last publish left on the server, for the settings screen.
  static final ValueNotifier<int?> publishedCount = ValueNotifier<int?>(null);

  static final Map<String, String> _pending = <String, String>{};

  static String? _read(String key) {
    final String? pending = _pending[key];
    if (pending != null) return pending;
    if (!Hive.isBoxOpen('settings')) return null;
    final Object? raw = Hive.box<dynamic>('settings').get(key);
    return raw is String ? raw : null;
  }

  static void _write(String key, String value) {
    _pending[key] = value;
    persistHomeSetting(key, value);
    revision.value++;
  }

  static Set<String> _readSet(String key) {
    final String? raw = _read(key);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return <String>{
          for (final Object? id in decoded)
            if (id is String) id,
        };
      }
    } catch (_) {}
    return <String>{};
  }

  static ShareMode get mode => ShareMode.byName(_read(modeKey));

  /// Friends added to the share by hand — in every mode but [ShareMode.none].
  static Set<String> get selected => _readSet(selectedKey);

  /// Friends kept out by hand — they win over everything else.
  static Set<String> get excluded => _readSet(excludedKey);

  /// When this matchmaker first opened their database to the network.
  ///
  /// **Cards already in the database before that moment are never opened
  /// automatically**, even under "שתף הכל": they join only when the
  /// matchmaker adds them ([selected]). "שתף הכל" shares every card added
  /// from then on — and offers the earlier ones to add in one go.
  static DateTime? get since => DateTime.tryParse(_read(sinceKey) ?? '');

  /// Friends whose card was sent to a matchmaker one by one (chat) — their
  /// photos stay in Storage even when they are not in the shared pool.
  static Set<String> get sent => _readSet(sentKey);

  /// Whether the short "how sharing works" introduction was seen or closed.
  static bool get onboardingDone => _read(onboardingKey) == 'true';

  static void finishOnboarding() => _write(onboardingKey, 'true');

  /// "גם אצל השדכנים שלי" on the search of המאגר שלי — the last choice is
  /// kept as the default.
  static bool get alsoSearchNetwork => _read(searchNetworkKey) == 'true';

  static set alsoSearchNetwork(bool on) =>
      _write(searchNetworkKey, on ? 'true' : 'false');

  static void setMode(ShareMode mode) {
    if (mode != ShareMode.none && since == null) {
      _write(sinceKey, DateTime.now().toIso8601String());
    }
    _write(modeKey, mode.name);
  }

  static void setSelected(Set<String> ids) =>
      _write(selectedKey, jsonEncode(ids.toList()..sort()));
  static void setExcluded(Set<String> ids) =>
      _write(excludedKey, jsonEncode(ids.toList()..sort()));

  static void noteSent(String personId) {
    final Set<String> ids = sent;
    if (ids.add(personId)) _write(sentKey, jsonEncode(ids.toList()..sort()));
  }

  /// Adds [ids] to the share, in one go (the caller asked first — see
  /// `SharingSettingsScreen.confirmAdding`). Sharing that was off becomes
  /// "אנשים מסוימים".
  static void add(Iterable<String> ids) {
    final Set<String> add = ids.toSet();
    if (add.isEmpty) return;
    if (mode == ShareMode.none) setMode(ShareMode.selected);
    setSelected(selected..addAll(add));
    final Set<String> out = excluded;
    if (out.intersection(add).isNotEmpty) setExcluded(out..removeAll(add));
  }

  /// Takes [person] out of the share: whatever put them in.
  static void remove(Person person) {
    final Set<String> picked = selected;
    if (picked.remove(person.id)) setSelected(picked);
    if (chosen(person)) setExcluded(excluded..add(person.id));
  }

  /// Test seam: every choice back to its default, and a start of sharing.
  @visibleForTesting
  static void debugReset({DateTime? since}) {
    for (final String key in <String>[
      modeKey,
      selectedKey,
      excludedKey,
      sinceKey,
      sentKey,
      onboardingKey,
    ]) {
      _pending[key] = '';
    }
    if (since != null) _pending[sinceKey] = since.toIso8601String();
    revision.value++;
  }

  /// The account changed the settings box.
  static void forgetCache() {
    _pending.clear();
    revision.value++;
  }

  /// Whether [person] can be shared at all.
  static ShareEligibility eligibilityOf(
    Person person, {
    CardAccess? Function(String ownerUid)? accessTo,
  }) {
    if (person.hidden ||
        person.needsReview ||
        person.profileStatus == ProfileStatus.mazelTov ||
        (person.gender != Gender.male && person.gender != Gender.female)) {
      return ShareEligibility.notApplicable;
    }
    final String? cardOwner = person.cardOwnerUid;
    if (cardOwner != null && cardOwner.isNotEmpty) {
      final CardAccess? row = accessTo?.call(cardOwner);
      if (row == null || !row.canReadCard || !row.shareOnward) {
        return ShareEligibility.awaitingConsent;
      }
    }
    if (!isComplete(person)) {
      return ShareEligibility.incomplete;
    }
    return ShareEligibility.ready;
  }

  /// **A complete card is a photo and card text** — the only kind that is
  /// ever shared. A photo the single asked not to share does not count.
  static bool isComplete(Person person) {
    final bool hasText = (person.description ?? '').trim().isNotEmpty;
    final bool hasPhoto = CardPhotoPrivacy.shareable(
      person,
    ).any((String p) => p.trim().isNotEmpty);
    return hasText && hasPhoto;
  }

  /// Whether the matchmaker's choice includes [person]:
  ///
  ///  - nothing while sharing is off;
  ///  - never a friend kept out by hand;
  ///  - always a friend added by hand;
  ///  - **a single's own personal card, by default** — the single already
  ///    said their matchmakers may show it (eligibility checks that), and the
  ///    matchmaker can still keep it out;
  ///  - under "שתף הכל", every card added since sharing started ([since]) —
  ///    never the older ones by themselves.
  static bool chosen(Person person) {
    final ShareMode current = mode;
    if (current == ShareMode.none) return false;
    if (excluded.contains(person.id)) return false;
    if (selected.contains(person.id)) return true;
    if ((person.cardOwnerUid ?? '').isNotEmpty) return true;
    if (current == ShareMode.selected) return false;
    final DateTime? start = since;
    return start == null || !person.createdAt.isBefore(start);
  }

  /// The friends shared right now: chosen and [ShareEligibility.ready].
  static List<Person> sharedNow(
    Iterable<Person> people, {
    CardAccess? Function(String ownerUid)? accessTo,
  }) => <Person>[
    for (final Person p in people)
      if (chosen(p) &&
          eligibilityOf(p, accessTo: accessTo) == ShareEligibility.ready)
        p,
  ];

  /// Complete cards that could join the share and have not.
  static List<Person> addable(
    Iterable<Person> people, {
    CardAccess? Function(String ownerUid)? accessTo,
  }) => <Person>[
    for (final Person p in people)
      if (!chosen(p) &&
          eligibilityOf(p, accessTo: accessTo) == ShareEligibility.ready)
        p,
  ];

  /// Under "שתף הכל": the complete cards from before sharing started, which
  /// were deliberately not opened by themselves.
  static List<Person> earlierNotShared(
    Iterable<Person> people, {
    CardAccess? Function(String ownerUid)? accessTo,
  }) {
    final DateTime? start = since;
    if (start == null || mode == ShareMode.none || mode == ShareMode.selected) {
      return const <Person>[];
    }
    return <Person>[
      for (final Person p in addable(people, accessTo: accessTo))
        if (p.createdAt.isBefore(start) && !excluded.contains(p.id)) p,
    ];
  }

  static bool _running = false;
  static bool _again = false;

  /// Brings `sharedCards/{uid}/cards` to exactly [sharedNow]. Quiet on any
  /// failure — the next change or app open tries again.
  static Future<void> publish({
    required Iterable<Person> people,
    required String ownerName,
    CardAccess? Function(String ownerUid)? accessTo,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    // Sharing is off and the server holds nothing of it: nothing to read.
    if (mode == ShareMode.none && publishedCount.value == 0) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _publishOnce(
          people: people.toList(),
          ownerName: ownerName,
          accessTo: accessTo,
        );
      } while (_again);
    } catch (error) {
      debugPrint('NetworkSharing: $error');
    } finally {
      _running = false;
    }
  }

  static Future<void> _publishOnce({
    required List<Person> people,
    required String ownerName,
    CardAccess? Function(String ownerUid)? accessTo,
  }) async {
    final String? uid = await PersonalCardService.durableUid();
    if (uid == null) return;
    final CollectionReference<Map<String, dynamic>> col = FirebaseFirestore
        .instance
        .collection('sharedCards')
        .doc(uid)
        .collection('cards');
    final QuerySnapshot<Map<String, dynamic>> remote = await col.get(
      const GetOptions(source: Source.server),
    );
    final Map<String, Map<String, dynamic>> held =
        <String, Map<String, dynamic>>{
          for (final QueryDocumentSnapshot<Map<String, dynamic>> d
              in remote.docs)
            d.id: d.data(),
        };
    final Map<String, Person> desired = <String, Person>{
      for (final Person p in sharedNow(people, accessTo: accessTo)) p.id: p,
    };

    // Whatever is no longer chosen, complete or consented leaves first. A
    // card also sent to somebody one by one keeps its photos for them.
    final Set<String> sentOnes = sent;
    for (final String id in held.keys) {
      if (!desired.containsKey(id)) {
        await col.doc(id).delete();
        if (!sentOnes.contains(id)) {
          await _deletePhotos(uid, id, keep: const <String>{});
        }
      }
    }

    int count = 0;
    for (final Person person in desired.values) {
      final List<File> files = <File>[];
      for (final String path in CardPhotoPrivacy.shareable(person)) {
        if (files.length >= SharedCardCodec.maxPhotos) break;
        final File file = await PhotoPickerService.fileFor(
          PhotoPickerService.basenameOf(path),
        );
        if (await file.exists()) files.add(file);
      }
      if (files.isEmpty) {
        // The photos are not on this phone (yet); another phone, or the next
        // run, will publish it. Never a card without its face.
        continue;
      }
      final List<String> paths = <String>[
        for (final File f in files)
          SharedCardCodec.photoPath(
            uid,
            person.id,
            PhotoPickerService.basenameOf(f.path),
          ),
      ];
      final Map<String, Object?> values = SharedCardCodec.values(
        person,
        ownerUid: uid,
        ownerName: ownerName,
      );
      final Map<String, dynamic>? before = held[person.id];
      final List<Object?> heldPaths =
          (before?['photoPaths'] as List?) ?? const <Object?>[];
      if (before != null &&
          _sameValues(values, before) &&
          listEquals(heldPaths, paths)) {
        count++;
        continue;
      }
      for (int i = 0; i < files.length; i++) {
        if (heldPaths.contains(paths[i])) continue;
        await FirebaseStorage.instance
            .ref(paths[i])
            .putFile(files[i], SettableMetadata(contentType: 'image/jpeg'));
      }
      await col
          .doc(person.id)
          .set(
            SharedCardCodec.toRemote(
              person,
              ownerUid: uid,
              ownerName: ownerName,
              photoPaths: paths,
            ),
          );
      if (!sentOnes.contains(person.id)) {
        await _deletePhotos(uid, person.id, keep: paths.toSet());
      }
      count++;
    }
    publishedCount.value = count;
  }

  static bool _sameValues(
    Map<String, Object?> values,
    Map<String, dynamic> held,
  ) {
    for (final MapEntry<String, Object?> e in values.entries) {
      if (jsonEncode(e.value) != jsonEncode(held[e.key])) return false;
    }
    return true;
  }

  static Future<void> _deletePhotos(
    String uid,
    String personId, {
    required Set<String> keep,
  }) async {
    try {
      final ListResult list = await FirebaseStorage.instance
          .ref('sharedCards/$uid/$personId')
          .listAll();
      for (final Reference ref in list.items) {
        if (!keep.contains(ref.fullPath)) await ref.delete();
      }
    } catch (error) {
      debugPrint('NetworkSharing photos: $error');
    }
  }

  /// Stops sharing everything at once — "ביטול השיתוף".
  static void stopAll() => setMode(ShareMode.none);
}
