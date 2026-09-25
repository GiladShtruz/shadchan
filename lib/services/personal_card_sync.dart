import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/sync_state_store.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// Brings the server up to date with this device: the owner's card, and the
/// phone identity other accounts find this one by.
///
/// **Only what changed, and only once Firebase is already up.** It never
/// starts Firebase itself — [CloudSyncScheduler] does that a frame after
/// launch — so it cannot drag Firebase onto the cold start, and under
/// `flutter test`, where Firebase is never ready, it does nothing at all.
/// What was last published is remembered as a fingerprint; a run that finds
/// nothing new costs no network.
abstract final class PersonalCardSync {
  static const String _cardPrintKey = 'personalCard.publishedPrint';
  static const String _identityPrintKey = 'personalCard.identityPrint';
  static const String _identityHashKey = 'personalCard.identityHash';

  static bool _running = false;
  static bool _again = false;

  static Box<dynamic>? get _settings =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  static Future<void> run({
    required PersonalCardProvider cards,
    required UserProfileProvider profile,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return;
    }
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        if (cards.isDeleted) {
          await _publishDeleted();
        } else {
          await _publishCard(cards.card);
        }
        await _publishIdentity(cards: cards, profile: profile);
      } while (_again);
    } catch (error, stackTrace) {
      debugPrint('PersonalCardSync failed: $error\n$stackTrace');
    } finally {
      _running = false;
    }
  }

  /// A deleted card stays on the server, flagged — which is what stops every
  /// matchmaker reading it at once, and what makes restoring possible.
  static Future<void> _publishDeleted() async {
    if (_settings?.get(_cardPrintKey) == 'deleted') {
      return;
    }
    if (await PersonalCardService.setCardDeleted(true)) {
      await _settings?.put(_cardPrintKey, 'deleted');
    }
  }

  /// Publishes [card] now, not on the next sync — deleting and restoring
  /// happen while the owner waits, and must have reached the server before
  /// anything else moves.
  static Future<bool> publishNow(Person card) async {
    final String print = SyncStateStore.fingerprint(
      BackupService.personToJson(card),
    );
    final bool ok = await PersonalCardService.publishCard(card);
    if (ok) {
      await _settings?.put(_cardPrintKey, print);
    }
    return ok;
  }

  /// Marks the card deleted on the server now; see [publishNow].
  static Future<bool> deleteNow() async {
    final bool ok = await PersonalCardService.setCardDeleted(true);
    if (ok) {
      await _settings?.put(_cardPrintKey, 'deleted');
    }
    return ok;
  }

  static Future<void> _publishCard(Person? card) async {
    if (card == null) {
      return;
    }
    final String print = SyncStateStore.fingerprint(
      BackupService.personToJson(card),
    );
    if (_settings?.get(_cardPrintKey) == print) {
      return;
    }
    if (await PersonalCardService.publishCard(card)) {
      await _settings?.put(_cardPrintKey, print);
    }
  }

  static Future<void> _publishIdentity({
    required PersonalCardProvider cards,
    required UserProfileProvider profile,
  }) async {
    final String? hash = PhoneIdentity.hash(profile.myPhone);
    if (hash == null) {
      return;
    }
    final String name = profile.fullName ?? '';
    final bool matchmaker = WorkspaceStore.matchmakerEnabled;
    final bool hasCard = cards.hasCard && profile.isSingle;
    final String print = '$hash|$name|$matchmaker|$hasCard';
    if (_settings?.get(_identityPrintKey) == print) {
      return;
    }
    final Object? previous = _settings?.get(_identityHashKey);
    final bool ok = await PersonalCardService.publishIdentity(
      phoneHash: hash,
      name: name,
      matchmaker: matchmaker,
      hasCard: hasCard,
      previousHash: previous is String ? previous : null,
    );
    if (ok) {
      await _settings?.put(_identityPrintKey, print);
      await _settings?.put(_identityHashKey, hash);
    }
  }

  /// Forgets what was published, for a sign-out: the next account on this
  /// phone publishes its own card and identity from scratch.
  static Future<void> forget() async {
    await _settings?.deleteAll(<String>[
      _cardPrintKey,
      _identityPrintKey,
      _identityHashKey,
      'personalCard.uploadedPhotos',
    ]);
  }
}
