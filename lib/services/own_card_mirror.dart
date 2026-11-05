import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_utils.dart';

/// **A single who is also a matchmaker finds their own personal card in their
/// own database** — without adding themselves by hand, and without a second
/// copy of themselves.
///
/// The personal card lives apart from the database on purpose (the settings
/// key `personalCard.person`, never the people box): it is what the single
/// shares with *other* matchmakers. But a single who matchmakes too wants to
/// see themselves among their own friends, in התאמות and in ideas. So the card
/// is mirrored into the database as an ordinary friend:
///
/// - **One record, always the same one.** Its id is kept under
///   [mirrorIdKey] (a synced setting, so every phone of the account agrees),
///   and a new one is born with the fixed id [defaultId], so two phones that
///   both create it create the same record. Before creating, a friend the
///   matchmaker had already added for themselves — the same phone as "המספר
///   שלי", or exactly one visible friend with the card's full name and gender
///   — is adopted instead, so nobody ends up twice.
/// - **One way, from the card.** Every save of the personal card rewrites the
///   card's own fields on the record ([PersonalCardCodec.applyTo]) and its
///   status; the matchmaker's own notes, tags, reminders and ideas on it are
///   untouched. A card field edited on the record is the card's again at its
///   next save. The owner's "מה אני מחפש/ת" counts as their own wishes there
///   ([isMirror], used by `MatchSuggestionUtils.followsOwnerWishes`).
/// - **Photos are copies** (`own_<name>`), so trimming the photos of one never
///   deletes a file the other still shows.
/// - **Deleting it is an answer.** A matchmaker who deletes the record does
///   not get it back ([noteDeleted] → [declinedKey]).
abstract final class OwnCardMirror {
  static const String defaultId = 'own-personal-card';
  static const String mirrorIdKey = 'personalCard.mirrorId';
  static const String declinedKey = 'personalCard.mirrorDeclined';
  static const String _printKey = 'personalCard.mirrorPrint';
  static const String photoPrefix = 'own_';

  static final Map<String, String> _pending = <String, String>{};

  /// See `LocalSettingCaches.forgetAll`.
  static void forgetCache() => _pending.clear();

  static String? _read(String key) {
    final String? pending = _pending[key];
    if (pending != null) {
      return pending.isEmpty ? null : pending;
    }
    final Object? raw = Hive.isBoxOpen('settings')
        ? Hive.box<dynamic>('settings').get(key)
        : null;
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  static void _write(String key, String value) {
    _pending[key] = value;
    persistHomeSetting(key, value);
  }

  /// The id of the record that mirrors the personal card.
  static String get mirrorId => _read(mirrorIdKey) ?? defaultId;

  /// Whether [personId] is the matchmaker's own card in their database.
  static bool isMirror(String personId) =>
      personId == mirrorId || personId == defaultId;

  /// Called when the matchmaker deletes a friend: the mirror, deleted, stays
  /// deleted.
  static void noteDeleted(String personId) {
    if (isMirror(personId)) {
      _write(declinedKey, 'true');
      _write(_printKey, '');
    }
  }

  /// A stand-in for copying a photo file, for tests.
  @visibleForTesting
  static Future<String?> Function(String sourcePath)? copyPhotoOverride;

  /// Brings the mirror in step with [card]. Returns the record, or null when
  /// there is nothing to mirror (no live card, not a matchmaker, or the
  /// matchmaker deleted it).
  static Future<Person?> sync({
    required Person? card,
    required bool cardIsLive,
    required bool matchmakerEnabled,
    required PersonRepository people,
    String? myPhone,
  }) async {
    if (card == null || !cardIsLive || !matchmakerEnabled) {
      return null;
    }
    if (_read(declinedKey) == 'true') {
      return null;
    }

    Person? target = people.getById(mirrorId);
    if (target == null) {
      target = _findSelf(card, people, myPhone);
      if (target != null && target.id != mirrorId) {
        _write(mirrorIdKey, target.id);
      }
    }

    final String print = jsonEncode(<String, Object?>{
      ...PersonalCardCodec.cardValues(card),
      'status': card.profileStatus.name,
      'photos': card.photosPaths.map(PhotoPickerService.basenameOf).toList(),
      'phone': myPhone,
    });
    if (target != null && _read(_printKey) == print) {
      return target;
    }

    final DateTime now = DateTime.now();
    final Person record =
        target ??
        Person(
          id: defaultId,
          firstName: card.firstName,
          lastName: card.lastName,
          gender: card.gender,
          createdAt: now,
          updatedAt: now,
        );
    PersonalCardCodec.applyTo(
      record,
      Map<String, dynamic>.from(PersonalCardCodec.cardValues(card)),
    );
    record
      ..profileStatus = card.profileStatus
      ..photosPaths = await _copies(card.photosPaths, record.photosPaths)
      ..hidden = false
      ..needsReview = false
      ..updatedAt = now;
    final String phone = (myPhone ?? '').trim();
    if ((record.phone ?? '').trim().isEmpty && phone.isNotEmpty) {
      record.phone = phone;
    }
    await people.saveSynced(record);
    _write(_printKey, print);
    if (target == null) {
      _write(mirrorIdKey, record.id);
    }
    return record;
  }

  /// A friend the matchmaker already added for themselves, if there is
  /// exactly one way to read it.
  static Person? _findSelf(
    Person card,
    PersonRepository people,
    String? myPhone,
  ) {
    final List<Person> everyone = people
        .getAll()
        .where((Person p) => !p.hidden && !p.needsReview)
        .toList();
    final String? mine = _phoneKey(myPhone);
    if (mine != null) {
      final List<Person> byPhone = everyone
          .where((Person p) => _phoneKey(p.phone) == mine)
          .toList();
      if (byPhone.length == 1) {
        return byPhone.single;
      }
    }
    final String name = _nameKey(card.fullName);
    if (name.isEmpty) {
      return null;
    }
    final List<Person> byName = everyone
        .where(
          (Person p) =>
              _nameKey(p.fullName) == name &&
              (p.gender == card.gender || p.gender == Gender.unknown) &&
              !p.isCardSynced,
        )
        .toList();
    return byName.length == 1 ? byName.single : null;
  }

  static String? _phoneKey(String? phone) {
    if (phone == null) {
      return null;
    }
    final String? normalized = PhoneUtils.normalizeForComparison(phone);
    return normalized != null && normalized.length >= 9 ? normalized : null;
  }

  static String _nameKey(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// The card's photos as files of the mirror's own, in the card's order.
  /// A photo the matchmaker added to the record themselves (not one of these
  /// copies) is kept after them.
  static Future<List<String>> _copies(
    List<String> cardPhotos,
    List<String> current,
  ) async {
    final List<String> result = <String>[];
    for (final String source in cardPhotos) {
      final String? copy = await (copyPhotoOverride ?? _copy)(source);
      if (copy != null) {
        result.add(copy);
      }
    }
    for (final String path in current) {
      final String name = PhotoPickerService.basenameOf(path);
      if (!name.startsWith(photoPrefix) && !result.contains(path)) {
        result.add(path);
      }
    }
    return result;
  }

  static Future<String?> _copy(String sourcePath) async {
    try {
      final String name = PhotoPickerService.basenameOf(sourcePath);
      File source = File(sourcePath);
      if (!source.existsSync()) {
        source = await PhotoPickerService.fileFor(name);
      }
      final File target = await PhotoPickerService.fileFor('$photoPrefix$name');
      if (!target.existsSync()) {
        if (!source.existsSync()) {
          return null;
        }
        await source.copy(target.path);
      }
      return target.path;
    } catch (error) {
      debugPrint('OwnCardMirror: photo not copied ($error)');
      return null;
    }
  }
}
