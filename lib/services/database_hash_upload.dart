import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/sync_state_store.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/phone_identity.dart';

/// Publishes which phone numbers a matchmaker keeps in their database — as
/// [PhoneIdentity] hashes, never names or numbers — to
/// `databaseHashes/{uid}`, which only the server reads.
///
/// It is what lets the server say "X הוסיף/ה כרטיס אישי" to exactly the
/// matchmakers who have X among their friends, the moment X writes a card:
/// the database lives on the phone, and nothing else on the server knows who
/// is in it. The cloud backup already holds these numbers in full; this is
/// the same fact in the one shape the server can search.
///
/// Only what changed is sent, and never starts Firebase itself.
abstract final class DatabaseHashUpload {
  static const String collection = 'databaseHashes';
  static const String _printKey = 'databaseHashes.print';

  /// A database is a phone's worth of friends; this keeps one document well
  /// inside Firestore's size limit whatever somebody imports.
  static const int _max = 20000;

  static Box<dynamic>? get _settings =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// The hashes of every friend in [people] with a usable number — hidden
  /// drafts and names on an idea left out: they are not the database.
  static List<String> hashesOf(Iterable<Person> people) {
    final Set<String> hashes = <String>{
      for (final Person person in people)
        if (!person.hidden) ?PhoneIdentity.hash(person.phone),
    };
    final List<String> sorted = hashes.toList()..sort();
    return sorted.length > _max ? sorted.sublist(0, _max) : sorted;
  }

  static Future<void> publishFrom(Iterable<Person> people) async {
    if (!FirebaseBootstrap.isReady || !WorkspaceStore.matchmakerEnabled) {
      return;
    }
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return;
    }
    final List<String> hashes = hashesOf(people);
    final String print =
        '${user.uid}:${SyncStateStore.fingerprint(<String, Object?>{'hashes': hashes})}';
    if (_settings?.get(_printKey) == print) {
      return;
    }
    try {
      await FirebaseFirestore.instance.collection(collection).doc(user.uid).set(
        <String, Object?>{
          'hashes': hashes,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      await _settings?.put(_printKey, print);
    } catch (error) {
      debugPrint('DatabaseHashUpload failed: $error');
    }
  }

  /// Forgets what was published, for a sign-out.
  static Future<void> forget() async {
    await _settings?.delete(_printKey);
  }
}
