import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';

class PersonalNews {
  const PersonalNews({
    required this.id,
    required this.title,
    required this.text,
    this.imagePath,
  });
  final String id, title, text;
  final String? imagePath;
  factory PersonalNews.fromMap(String id, Map<String, dynamic> data) =>
      PersonalNews(
        id: id,
        title: data['title'] as String? ?? '',
        text: data['text'] as String? ?? '',
        imagePath: data['imagePath'] as String?,
      );
}

/// Private account activity plus anonymous, server-calculated community totals.
class PersonalAreaProvider extends ChangeNotifier {
  PersonalAreaProvider({bool enabled = true}) : _enabled = enabled {
    if (_enabled) {
      FirebaseBootstrap.readyListenable.addListener(_ready);
      _ready();
    }
  }
  final bool _enabled;
  bool _disposed = false;
  StreamSubscription<User?>? _auth;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  String? _uid;
  Map<String, dynamic> stats = {};
  Map<String, dynamic> activity = {};
  List<PersonalNews> news = [];
  String? error;
  bool get connected => _uid != null;
  DateTime? date(String key) => (activity[key] as Timestamp?)?.toDate();
  bool get canNudge =>
      date('nudgedAt') == null ||
      DateTime.now().difference(date('nudgedAt')!).inDays >= 30;
  static bool reviewDue(DateTime last, [DateTime? now]) {
    final at = now ?? DateTime.now();
    final month = last.month + 3;
    final lastDay = DateTime(last.year, month + 1, 0).day;
    final due = DateTime(
      last.year,
      month,
      last.day > lastDay ? lastDay : last.day,
      last.hour,
      last.minute,
    );
    return !at.isBefore(due);
  }

  void _ready() {
    if (_disposed || !_enabled || !FirebaseBootstrap.isReady || _auth != null) {
      return;
    }
    _auth = FirebaseAuth.instance.authStateChanges().listen(
      (user) => _connect(user?.isAnonymous == false ? user!.uid : null),
    );
  }

  void _connect(String? uid) {
    if (_disposed || _uid == uid) return;
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
    _uid = uid;
    stats = {};
    activity = {};
    news = [];
    error = null;
    if (uid != null) {
      final db = FirebaseFirestore.instance;
      _subscriptions.add(
        db.doc('users/$uid/private/cardActivity').snapshots().listen((doc) {
          if (_uid != uid || _disposed) return;
          activity = doc.data() ?? {};
          notifyListeners();
        }, onError: _failed),
      );
      _subscriptions.add(
        db.doc('publicStats/personalArea').snapshots().listen((doc) {
          if (_uid != uid || _disposed) return;
          stats = doc.data() ?? {};
          notifyListeners();
        }, onError: _failed),
      );
      _subscriptions.add(
        db
            .collection('personalNews')
            .where('published', isEqualTo: true)
            .orderBy('updatedAt', descending: true)
            .limit(30)
            .snapshots()
            .listen((snap) {
              if (_uid != uid || _disposed) return;
              news = snap.docs
                  .map((d) => PersonalNews.fromMap(d.id, d.data()))
                  .toList();
              notifyListeners();
            }, onError: _failed),
      );
    }
    notifyListeners();
  }

  void _failed(Object failure) {
    if (!_disposed) {
      error = 'לא ניתן לרענן כרגע';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    FirebaseBootstrap.readyListenable.removeListener(_ready);
    unawaited(_auth?.cancel());
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}
