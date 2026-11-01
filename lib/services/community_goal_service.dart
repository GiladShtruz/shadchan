import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/utils/community_challenge.dart';

/// One public configuration document. Writes are administrator-only in rules.
abstract final class CommunityGoalService {
  static DocumentReference<Map<String, dynamic>> get _document =>
      FirebaseFirestore.instance.collection('communityGoals').doc('weekly');

  static bool get _available =>
      FirebaseBootstrap.isReady && FirebaseAuth.instance.currentUser != null;

  static Future<WeeklyCommunityGoal?> fetch() async {
    if (!_available) throw StateError('Firebase is not ready');
    final snapshot = await _document.get(
      const GetOptions(source: Source.server),
    );
    final data = snapshot.data();
    final goal = WeeklyCommunityGoal.fromJson(data);
    if (data != null && goal == null) throw StateError('Invalid weekly goal');
    return goal;
  }

  static Stream<WeeklyCommunityGoal?> watch() {
    if (!_available) return const Stream<WeeklyCommunityGoal?>.empty();
    return _document.snapshots().map(
      (snapshot) => WeeklyCommunityGoal.fromJson(snapshot.data()),
    );
  }

  static Future<void> save(WeeklyCommunityGoal goal) async {
    if (!_available) throw StateError('Firebase is not ready');
    if (!goal.isValid) throw ArgumentError('Invalid weekly goal');
    await _document.set(<String, dynamic>{
      ...goal.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
