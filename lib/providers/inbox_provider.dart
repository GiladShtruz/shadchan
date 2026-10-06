import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_card_service.dart';

/// One notice the server wrote for this account.
class InboxItem {
  const InboxItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.route,
    required this.read,
    this.ownerUid,
    this.ownerPhoneHash,
    this.createdAt,
  });

  final String id;

  /// `accessRequest`, `accessApproved`, `accessDeclined`, `cardCreated`,
  /// `mazelTov`, `birthday`, `statusReport`.
  final String kind;
  final String title;
  final String body;
  final String route;
  final bool read;

  /// The card owner the notice is about, when it is about one.
  final String? ownerUid;

  /// The owner's phone identity, when the notice is about a friend the
  /// matchmaker may already have in the database under their number.
  final String? ownerPhoneHash;
  final DateTime? createdAt;

  /// The two notices that carry a "send on WhatsApp" action.
  bool get offersWhatsApp => kind == 'mazelTov' || kind == 'birthday';

  InboxItem asRead() => InboxItem(
    id: id,
    kind: kind,
    title: title,
    body: body,
    route: route,
    read: true,
    ownerUid: ownerUid,
    ownerPhoneHash: ownerPhoneHash,
    createdAt: createdAt,
  );
}

/// The server's notices to this account — `users/{uid}/inbox` — live.
///
/// This is the record; a push is only the courtesy that points at it. So the
/// list is shown on the notifications page whether or not any push arrived.
class InboxProvider extends ChangeNotifier {
  InboxProvider({bool enabled = true}) : _enabled = enabled;

  final bool _enabled;
  String? _uid;
  bool _starting = false;
  StreamSubscription<Object?>? _subscription;
  List<InboxItem> _items = <InboxItem>[];

  /// Read and removed ahead of the server's answer, so the page and the bell
  /// change the moment the matchmaker acts rather than a round trip later.
  final Set<String> _readLocally = <String>{};
  final Set<String> _removedLocally = <String>{};

  /// Read before the account was connected — a push tapped on a cold start.
  /// Written to the server once [start] knows whose inbox this is.
  final Set<String> _pendingRead = <String>{};

  List<InboxItem> get items => <InboxItem>[
    for (final InboxItem i in _items)
      if (!_removedLocally.contains(i.id))
        _readLocally.contains(i.id) && !i.read ? i.asRead() : i,
  ];
  int get unreadCount => items.where((InboxItem i) => !i.read).length;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('inbox');

  Future<void> start() async {
    if (!_enabled || _uid != null || _starting || !FirebaseBootstrap.isReady) {
      return;
    }
    _starting = true;
    try {
      final String? uid = await PersonalCardService.durableUid();
      if (uid == null) {
        return;
      }
      _uid = uid;
      for (final String id in _pendingRead.toList()) {
        _pendingRead.remove(id);
        unawaited(_writeRead(uid, id));
      }
      _subscription = _collection(uid)
          .orderBy('createdAt', descending: true)
          .limit(300)
          .snapshots()
          .listen((QuerySnapshot<Map<String, dynamic>> snap) {
            _items = <InboxItem>[
              for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                  in snap.docs)
                InboxItem(
                  id: doc.id,
                  kind: (doc.data()['kind'] as String?) ?? '',
                  title: (doc.data()['title'] as String?) ?? '',
                  body: (doc.data()['body'] as String?) ?? '',
                  route: (doc.data()['route'] as String?) ?? '',
                  read: doc.data()['read'] == true,
                  ownerUid: doc.data()['ownerUid'] as String?,
                  ownerPhoneHash: doc.data()['ownerPhoneHash'] as String?,
                  createdAt: (doc.data()['createdAt'] as Timestamp?)?.toDate(),
                ),
            ];
            notifyListeners();
          }, onError: (Object error) => debugPrint('InboxProvider: $error'));
    } finally {
      _starting = false;
    }
  }

  /// A list to draw without a server — widget tests only.
  @visibleForTesting
  void debugSetItems(List<InboxItem> items) {
    _items = items;
    notifyListeners();
  }

  /// Marks a notice read by its id alone — the tapped push carries no more
  /// than that, and on a cold start the list may not be here yet.
  Future<void> markReadById(String id) async {
    if (id.isEmpty || !_readLocally.add(id)) {
      return;
    }
    notifyListeners();
    final String? uid = _uid;
    if (uid == null) {
      _pendingRead.add(id);
      return;
    }
    await _writeRead(uid, id);
  }

  Future<void> _writeRead(String uid, String id) async {
    try {
      await _collection(uid).doc(id).update(<String, Object?>{'read': true});
    } catch (error) {
      debugPrint('InboxProvider.markReadById: $error');
    }
  }

  Future<void> markRead(InboxItem item) async {
    final String? uid = _uid;
    if (item.read || !_readLocally.add(item.id)) {
      return;
    }
    notifyListeners();
    if (uid == null) {
      return;
    }
    try {
      await _collection(
        uid,
      ).doc(item.id).update(<String, Object?>{'read': true});
    } catch (error) {
      debugPrint('InboxProvider.markRead: $error');
    }
  }

  /// Everything unread, read — "סמן הכל כנקרא", and opening the page.
  Future<void> markAllRead() async {
    final List<InboxItem> unread = items
        .where((InboxItem i) => !i.read)
        .toList();
    if (unread.isEmpty) {
      return;
    }
    _readLocally.addAll(unread.map((InboxItem i) => i.id));
    notifyListeners();
    final String? uid = _uid;
    if (uid == null) {
      return;
    }
    try {
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final InboxItem item in unread) {
        batch.update(_collection(uid).doc(item.id), <String, Object?>{
          'read': true,
        });
      }
      await batch.commit();
    } catch (error) {
      debugPrint('InboxProvider.markAllRead: $error');
    }
  }

  Future<void> remove(InboxItem item) async {
    final String? uid = _uid;
    _removedLocally.add(item.id);
    notifyListeners();
    if (uid == null) {
      return;
    }
    try {
      await _collection(uid).doc(item.id).delete();
    } catch (error) {
      debugPrint('InboxProvider.remove: $error');
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _uid = null;
    _items = <InboxItem>[];
    _readLocally.clear();
    _removedLocally.clear();
    _pendingRead.clear();
    notifyListeners();
  }
}
