import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/matchmaker_share.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/services/card_photo_privacy.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/published_cards.dart';
import 'package:shadchan/services/read_throttle.dart';
import 'package:shadchan/services/sync_state_store.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/screen_perf.dart';

/// How much of the database one matchmaker shares with **one** other
/// matchmaker. Every pair is decided on its own: sharing everything with
/// יונתן says nothing about משה.
enum ShareMode {
  /// Nothing — the default. Sharing is always a decision.
  none,

  /// Every complete card.
  all,

  /// Only the friends picked one by one.
  selected,

  /// Every complete card except the friends picked one by one.
  allExcept;

  MatchmakerShareMode get remote => switch (this) {
    ShareMode.none => MatchmakerShareMode.none,
    ShareMode.all => MatchmakerShareMode.all,
    ShareMode.selected => MatchmakerShareMode.selected,
    ShareMode.allExcept => MatchmakerShareMode.allExcept,
  };

  static ShareMode byName(Object? name) {
    for (final ShareMode m in values) {
      if (m.name == name) return m;
    }
    return ShareMode.none;
  }
}

/// Whether a friend's card can go to another matchmaker at all.
enum ShareEligibility {
  /// A photo and card text — it can be shared.
  ready,

  /// No photo or no card text. **Only complete cards are ever shared**, even
  /// under "כל המאגר".
  incomplete,

  /// The friend keeps their own personal card, and has not said their
  /// matchmakers may show it to other matchmakers (`cardAccess.shareOnward`).
  awaitingConsent,

  /// Not a candidate to share: outside the database, a draft, married.
  notApplicable,
}

/// What this matchmaker shares with one other matchmaker.
@immutable
class ShareChoice {
  const ShareChoice(
    this.mode, {
    this.selected = const <String>{},
    this.excluded = const <String>{},
  });

  static const ShareChoice off = ShareChoice(ShareMode.none);

  final ShareMode mode;

  /// "אנשים נבחרים": the friends picked for this matchmaker.
  final Set<String> selected;

  /// "כל המאגר חוץ מ…": the friends kept out.
  final Set<String> excluded;

  bool get isOn => mode != ShareMode.none;

  /// Whether this choice includes [person] — eligibility aside. A single's
  /// own personal card is included like any card: under "כל המאגר", or when
  /// picked (their consent is checked by [NetworkSharing.eligibilityOf]).
  bool includes(Person person) => switch (mode) {
    ShareMode.none => false,
    ShareMode.all => true,
    ShareMode.selected => selected.contains(person.id),
    ShareMode.allExcept => !excluded.contains(person.id),
  };

  ShareChoice copyWith({
    ShareMode? mode,
    Set<String>? selected,
    Set<String>? excluded,
  }) => ShareChoice(
    mode ?? this.mode,
    selected: selected ?? this.selected,
    excluded: excluded ?? this.excluded,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'm': mode.name,
    if (selected.isNotEmpty) 's': (selected.toList()..sort()),
    if (excluded.isNotEmpty) 'x': (excluded.toList()..sort()),
  };

  static ShareChoice fromJson(Object? raw) {
    if (raw is! Map) return off;
    Set<String> ids(Object? list) => <String>{
      if (list is List)
        for (final Object? id in list)
          if (id is String) id,
    };
    return ShareChoice(
      ShareMode.byName(raw['m']),
      selected: ids(raw['s']),
      excluded: ids(raw['x']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShareChoice &&
      other.mode == mode &&
      setEquals(other.selected, selected) &&
      setEquals(other.excluded, excluded);

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAllUnordered(selected),
    Object.hashAllUnordered(excluded),
  );
}

/// Sharing cards with the matchmakers this matchmaker knows — **one decision
/// per matchmaker**, and the one place that writes the published cards to
/// `networkCards`.
///
/// **A card is published once, never copied per matchmaker.** Each shared
/// friend is one document, `networkCards/{me}_{personId}`, naming its
/// `readers` — the matchmakers whose choice includes it right now. Changing
/// what יונתן sees rewrites the `readers` of the cards that moved; nothing
/// is copied or deleted for him. A card nobody reads is removed.
///
/// **Never a public database.** Only the readers named read a card (the rules
/// check `readers`), view only, and without anything the matchmaker keeps for
/// themselves — no phone, no notes ([SharedCardCodec]).
///
/// The choices are a synced setting (every phone of the account agrees). The
/// publish remembers a print of what it last put on the server, so an app
/// open with nothing changed reads nothing at all.
abstract final class NetworkSharing {
  static const String choicesKey = 'network.shareChoices';
  static const String sentKey = 'network.sentCards';
  static const String onboardingKey = 'network.onboardingDone';
  static const String searchNetworkKey = 'people.searchNetwork';
  static const String _printKey = 'network.publishedPrint';
  static const String _legacyKey = 'network.legacyCleaned';

  /// This phone's record of the cards it holds on the server, per account
  /// (device-only: `network.held` in `AccountSyncCodec`).
  static const String _heldPrefix = 'network.held.';

  /// How often the record is checked against the server itself — which also
  /// catches a card the server removed on its own (a single withdrawing
  /// consent, a reader taken off).
  static const Duration heldVerifyEvery = PublishedCards.verifyEvery;

  /// Bumped whenever a choice changes, for screens that show it.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// How many cards the last publish left on the server (any reader).
  static final ValueNotifier<int?> publishedCount = ValueNotifier<int?>(null);

  static final Map<String, String> _pending = <String, String>{};
  static Map<String, ShareChoice>? _choices;

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

  /// Every matchmaker this one decided something for, reader uid → choice.
  static Map<String, ShareChoice> get choices {
    final Map<String, ShareChoice>? cached = _choices;
    if (cached != null) return cached;
    final Map<String, ShareChoice> out = <String, ShareChoice>{};
    final String? raw = _read(choicesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final MapEntry<Object?, Object?> e in decoded.entries) {
            if (e.key is String) {
              out[e.key! as String] = ShareChoice.fromJson(e.value);
            }
          }
        }
      } catch (_) {}
    }
    return _choices = Map<String, ShareChoice>.unmodifiable(out);
  }

  /// What this matchmaker shares with [readerUid].
  static ShareChoice choiceFor(String readerUid) =>
      choices[readerUid] ?? ShareChoice.off;

  /// The matchmakers this one shares something with now.
  static Iterable<String> get readers => <String>[
    for (final MapEntry<String, ShareChoice> e in choices.entries)
      if (e.value.isOn) e.key,
  ];

  /// Whether this matchmaker shares anything with anybody.
  static bool get sharesAnything => readers.isNotEmpty;

  /// Decides what [readerUid] sees — at once: the share row is written now
  /// (so a stop is a stop even before the cards are rewritten), and the cards
  /// follow on the next publish, which the [revision] bump triggers.
  static Future<bool> setChoice({
    required String readerUid,
    required ShareChoice choice,
    required String myName,
    required String theirName,
    required Iterable<Person> people,
    CardAccess? Function(String ownerUid)? accessTo,
  }) async {
    final Map<String, ShareChoice> next = Map<String, ShareChoice>.of(choices);
    if (choice.isOn) {
      next[readerUid] = choice;
    } else {
      next.remove(readerUid);
    }
    _choices = Map<String, ShareChoice>.unmodifiable(next);
    _write(
      choicesKey,
      jsonEncode(<String, Object?>{
        for (final MapEntry<String, ShareChoice> e in next.entries)
          e.key: e.value.toJson(),
      }),
    );
    final int count = choice.isOn
        ? sharedWith(readerUid, people, accessTo: accessTo).length
        : 0;
    // Only a row that exists or is worth writing: switching off a reader who
    // never had a share writes nothing.
    if (!choice.isOn && MatchmakerShares.mine(readerUid) == null) return true;
    return MatchmakerShares.setMine(
      readerUid: readerUid,
      mode: choice.mode.remote,
      count: count,
      myName: myName,
      theirName: theirName,
    );
  }

  /// Friends whose card was sent to a matchmaker one by one (chat) — their
  /// photos stay in Storage even when nobody else reads them.
  static Set<String> get sent => _readSet(sentKey);

  /// Whether the short "how sharing works" introduction was seen or closed.
  static bool get onboardingDone => _read(onboardingKey) == 'true';

  static void finishOnboarding() => _write(onboardingKey, 'true');

  /// "גם אצל השדכנים שלי" on the search of המאגר שלי — the last choice is
  /// kept as the default.
  static bool get alsoSearchNetwork => _read(searchNetworkKey) == 'true';

  static set alsoSearchNetwork(bool on) =>
      _write(searchNetworkKey, on ? 'true' : 'false');

  static void noteSent(String personId) {
    final Set<String> ids = sent;
    if (ids.add(personId)) _write(sentKey, jsonEncode(ids.toList()..sort()));
  }

  /// Test seam: every choice back to its default.
  @visibleForTesting
  static void debugReset() {
    for (final String key in <String>[
      choicesKey,
      sentKey,
      onboardingKey,
      _printKey,
    ]) {
      _pending[key] = '';
    }
    _choices = null;
    revision.value++;
  }

  /// Test seam: choices as if they had been made, without the server.
  @visibleForTesting
  static void debugSetChoices(Map<String, ShareChoice> choices) {
    _choices = Map<String, ShareChoice>.unmodifiable(choices);
    revision.value++;
  }

  /// The account changed the settings box.
  static void forgetCache() {
    _pending.clear();
    _choices = null;
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

  /// The matchmakers [person]'s card goes to right now (eligibility aside).
  static Set<String> readersOf(Person person) => <String>{
    for (final MapEntry<String, ShareChoice> e in choices.entries)
      if (e.value.includes(person)) e.key,
  };

  /// The friends [readerUid] sees right now: chosen for them and ready.
  static List<Person> sharedWith(
    String readerUid,
    Iterable<Person> people, {
    CardAccess? Function(String ownerUid)? accessTo,
  }) {
    final ShareChoice choice = choiceFor(readerUid);
    if (!choice.isOn) return <Person>[];
    return <Person>[
      for (final Person p in people)
        if (choice.includes(p) &&
            eligibilityOf(p, accessTo: accessTo) == ShareEligibility.ready)
          p,
    ];
  }

  /// Every friend shared with at least one matchmaker.
  static List<Person> sharedNow(
    Iterable<Person> people, {
    CardAccess? Function(String ownerUid)? accessTo,
  }) {
    final Map<String, ShareChoice> all = choices;
    if (all.values.every((ShareChoice c) => !c.isOn)) return <Person>[];
    return <Person>[
      for (final Person p in people)
        if (all.values.any((ShareChoice c) => c.includes(p)) &&
            eligibilityOf(p, accessTo: accessTo) == ShareEligibility.ready)
          p,
    ];
  }

  /// Complete cards that could be shared with [readerUid] and are not.
  static List<Person> addableFor(
    String readerUid,
    Iterable<Person> people, {
    CardAccess? Function(String ownerUid)? accessTo,
  }) {
    final ShareChoice choice = choiceFor(readerUid);
    return <Person>[
      for (final Person p in people)
        if (!choice.includes(p) &&
            eligibilityOf(p, accessTo: accessTo) == ShareEligibility.ready)
          p,
    ];
  }

  static bool _running = false;
  static bool _again = false;

  /// Brings `networkCards` to exactly what the choices say. Quiet on any
  /// failure — the next change or app open tries again.
  static Future<void> publish({
    required Iterable<Person> people,
    required String ownerName,
    CardAccess? Function(String ownerUid)? accessTo,
    bool force = false,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
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
          force: force,
        );
      } while (_again);
    } catch (error) {
      debugPrint('NetworkSharing: $error');
      // Forget the print so the next run reads the server again.
      _pending[_printKey] = '';
      persistHomeSetting(_printKey, '');
    } finally {
      _running = false;
    }
  }

  /// The search key a reader's query runs on: the full name, folded.
  static String nameKeyOf(Person person) =>
      SharedCardCodec.nameKey('${person.firstName} ${person.lastName}');

  static Future<void> _publishOnce({
    required List<Person> people,
    required String ownerName,
    CardAccess? Function(String ownerUid)? accessTo,
    required bool force,
  }) async {
    final String? uid = await PersonalCardService.durableUid();
    if (uid == null) return;
    await _cleanLegacy(uid);

    // What the server should hold: each shared friend, with its readers.
    final Map<String, ShareChoice> all = choices;
    final Map<String, (Person, List<String>)> desired =
        <String, (Person, List<String>)>{};
    final Map<String, int> perReader = <String, int>{
      for (final MapEntry<String, ShareChoice> e in all.entries)
        if (e.value.isOn) e.key: 0,
    };
    for (final Person p in people) {
      final List<String> readers = <String>[
        for (final MapEntry<String, ShareChoice> e in all.entries)
          if (e.value.includes(p)) e.key,
      ]..sort();
      if (readers.isEmpty) continue;
      if (eligibilityOf(p, accessTo: accessTo) != ShareEligibility.ready) {
        continue;
      }
      desired[p.id] = (p, readers);
      for (final String r in readers) {
        perReader[r] = (perReader[r] ?? 0) + 1;
      }
    }
    final String print = await SyncStateStore.fingerprintInBackground(
      <String, Object?>{
        'owner': ownerName,
        for (final MapEntry<String, (Person, List<String>)> e
            in desired.entries)
          e.key: <Object?>[
            SharedCardCodec.values(
              e.value.$1,
              ownerUid: uid,
              ownerName: ownerName,
            ),
            e.value.$2,
            CardPhotoPrivacy.shareable(e.value.$1),
          ],
      },
    );
    if (!force && _read(_printKey) == print) {
      publishedCount.value = desired.length;
      await _syncCounts(perReader);
      return;
    }

    final CollectionReference<Map<String, dynamic>> col = FirebaseFirestore
        .instance
        .collection(SharedCardCodec.collection);
    // What the server holds: this phone's own record of what it published
    // ([PublishedCard]), or — once a day, on a forced run, or with no record —
    // the server's answer itself. Reading every shared card on every edit
    // of any of them (hundreds, for somebody sharing "everything") was the
    // cost this replaces (2026-11-22).
    final String heldKey = '$_heldPrefix$uid';
    final String heldClock = 'networkHeld.$uid';
    final Map<String, PublishedCard>? recorded =
        force || ReadThrottle.due(heldClock, heldVerifyEvery)
        ? null
        : PublishedCards.decode(_read(heldKey));
    final Map<String, PublishedCard> held;
    if (recorded != null) {
      held = recorded;
    } else {
      ScreenPerf.noteQuery();
      final QuerySnapshot<Map<String, dynamic>> remote = await col
          .where('ownerUid', isEqualTo: uid)
          .get(const GetOptions(source: Source.server));
      held = <String, PublishedCard>{
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in remote.docs)
          (d.data()['personId'] as String?) ?? d.id: PublishedCard.fromServer(
            d.data(),
          ),
      };
      ReadThrottle.mark(heldClock);
    }
    final Map<String, PublishedCard> nowHeld = <String, PublishedCard>{};
    // A failure part-way leaves the record unknown: the next run asks the
    // server.
    _pending[heldKey] = '';
    persistHomeSetting(heldKey, '');

    // Whatever nobody reads any more leaves first. A card also sent to
    // somebody one by one keeps its photos for them.
    final Set<String> sentOnes = sent;
    for (final String id in held.keys) {
      if (!desired.containsKey(id)) {
        await col.doc(SharedCardCodec.docId(uid, id)).delete();
        if (!sentOnes.contains(id)) {
          await _deletePhotos(uid, id, keep: const <String>{});
        }
      }
    }

    int count = 0;
    for (final MapEntry<String, (Person, List<String>)> entry
        in desired.entries) {
      final Person person = entry.value.$1;
      final List<String> readers = entry.value.$2;
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
        final PublishedCard? there = held[person.id];
        if (there != null) nowHeld[person.id] = there.unknownValues();
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
      final PublishedCard? before = held[person.id];
      final List<Object?> heldPaths = before?.paths ?? const <Object?>[];
      final List<Object?> heldReaders = before?.readers ?? const <Object?>[];
      final String valuesPrint = SyncStateStore.fingerprint(values);
      nowHeld[person.id] = PublishedCard(
        paths: paths,
        readers: readers,
        valuesPrint: valuesPrint,
      );
      if (before != null &&
          before.sameValues(values, valuesPrint) &&
          listEquals(heldPaths, paths) &&
          listEquals(heldReaders, readers)) {
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
          .doc(SharedCardCodec.docId(uid, person.id))
          .set(
            SharedCardCodec.toRemote(
              person,
              ownerUid: uid,
              ownerName: ownerName,
              photoPaths: paths,
              readers: readers,
            ),
          );
      if (!sentOnes.contains(person.id)) {
        await _deletePhotos(uid, person.id, keep: paths.toSet());
      }
      count++;
    }
    publishedCount.value = count;
    _pending[_printKey] = print;
    persistHomeSetting(_printKey, print);
    final String heldJson = PublishedCards.encode(nowHeld);
    _pending[heldKey] = heldJson;
    persistHomeSetting(heldKey, heldJson);
    await _syncCounts(perReader);
  }

  /// Writes each reader's card count onto their share row, where it moved.
  static Future<void> _syncCounts(Map<String, int> perReader) async {
    for (final MapEntry<String, int> e in perReader.entries) {
      await MatchmakerShares.updateCount(e.key, e.value);
    }
  }

  /// The pre-2026-11-20 model kept one copy per card in
  /// `sharedCards/{me}/cards`, readable by every connected matchmaker. Those
  /// copies are removed once, by their owner — the old model is gone.
  static Future<void> _cleanLegacy(String uid) async {
    if (_read(_legacyKey) == 'true') return;
    try {
      ScreenPerf.noteQuery();
      final QuerySnapshot<Map<String, dynamic>> old = await FirebaseFirestore
          .instance
          .collection('sharedCards')
          .doc(uid)
          .collection('cards')
          .get();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in old.docs) {
        await d.reference.delete();
      }
      _pending[_legacyKey] = 'true';
      persistHomeSetting(_legacyKey, 'true');
    } catch (error) {
      debugPrint('NetworkSharing legacy: $error');
    }
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
}
