import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_card_service.dart';

/// What a message is about — a card or an idea — so a thread of months can
/// mention many of them without a chat per card.
class ChatRef {
  const ChatRef({
    required this.kind,
    required this.id,
    required this.label,
    this.ownerUid,
  });

  /// `card` (a shared card), `idea` (a shared idea's proposal), `proposal`.
  final String kind;
  final String id;
  final String label;

  /// For a card: the matchmaker who holds it.
  final String? ownerUid;

  Map<String, Object?> toMap() => <String, Object?>{
    'kind': kind,
    'id': id,
    'label': label.length > 120 ? label.substring(0, 120) : label,
    if (ownerUid != null) 'ownerUid': ownerUid,
  };

  static ChatRef? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Object? kind = raw['kind'];
    final Object? id = raw['id'];
    if (kind is! String || id is! String) return null;
    return ChatRef(
      kind: kind,
      id: id,
      label: (raw['label'] as String?) ?? '',
      ownerUid: raw['ownerUid'] as String?,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromUid,
    required this.text,
    this.at,
    this.ref,
    this.pending = false,
    this.system = false,
  });

  final String id;

  /// A small line the server wrote ("הרעיון אושר", "עבר להמתנה") — never a
  /// message from a person.
  final bool system;
  final String fromUid;
  final String text;
  final DateTime? at;
  final ChatRef? ref;

  /// Written on this phone and not yet on the server.
  final bool pending;
}

/// One conversation. Today: one continuing chat per pair of matchmakers.
/// Built so a group (`type: group`) or a chat with a single can join later.
class ChatThread {
  const ChatThread({
    required this.id,
    required this.members,
    required this.type,
    required this.names,
    this.lastText = '',
    this.lastFromUid,
    this.lastAt,
    this.readAt = const <String, DateTime>{},
  });

  final String id;
  final List<String> members;
  final String type;
  final Map<String, String> names;
  final String lastText;
  final String? lastFromUid;
  final DateTime? lastAt;
  final Map<String, DateTime> readAt;

  String otherOf(String me) =>
      members.firstWhere((String m) => m != me, orElse: () => me);

  /// What this thread is called from [me]'s side.
  String titleFor(String me) {
    final String name = (names[otherOf(me)] ?? '').trim();
    return name.isEmpty ? 'שדכן/ית' : name;
  }

  bool isUnreadFor(String me) {
    final DateTime? last = lastAt;
    if (last == null || lastFromUid == null || lastFromUid == me) return false;
    final DateTime? read = readAt[me];
    return read == null || read.isBefore(last);
  }

  static ChatThread? fromMap(String id, Map<String, dynamic> data) {
    final Object? members = data['members'];
    if (members is! List) return null;
    DateTime? time(Object? v) => v is Timestamp ? v.toDate() : null;
    final Object? names = data['names'];
    final Object? read = data['readAt'];
    return ChatThread(
      id: id,
      members: <String>[
        for (final Object? m in members)
          if (m is String) m,
      ],
      type: (data['type'] as String?) ?? 'direct',
      names: <String, String>{
        if (names is Map)
          for (final MapEntry<dynamic, dynamic> e in names.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      lastText: (data['lastText'] as String?) ?? '',
      lastFromUid: data['lastFromUid'] as String?,
      lastAt: time(data['lastAt']),
      readAt: <String, DateTime>{
        if (read is Map)
          for (final MapEntry<dynamic, dynamic> e in read.entries)
            if (e.key is String && time(e.value) != null)
              e.key as String: time(e.value)!,
      },
    );
  }
}

/// The app's chats, live — `chats/{id}` and their messages.
///
/// **One chat per pair of matchmakers** (`{a}_{b}`, uids sorted): every card
/// and idea between them is talked about in the same thread, the way people
/// already use WhatsApp. Only connected matchmakers can open one (the rules
/// check it); after a disconnect the history stays readable and takes no new
/// messages.
abstract final class ChatService {
  static final ValueNotifier<List<ChatThread>> threads =
      ValueNotifier<List<ChatThread>>(const <ChatThread>[]);

  /// Threads with a message this account has not read.
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  static String? _uid;
  static String? get uid => _uid;
  static bool _starting = false;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// The chat on the screen right now, so its own pushes are not announced.
  static String? openChatId;

  static String directId(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  static Future<void> start() async {
    if (_uid != null || _starting || !FirebaseBootstrap.isReady) return;
    _starting = true;
    try {
      final String? uid = await PersonalCardService.durableUid();
      if (uid == null) return;
      _uid = uid;
      _sub = FirebaseFirestore.instance
          .collection('chats')
          .where('members', arrayContains: uid)
          .snapshots()
          .listen((QuerySnapshot<Map<String, dynamic>> snap) {
            if (_uid != uid) return;
            final List<ChatThread> list =
                <ChatThread>[
                  for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                      in snap.docs)
                    ?ChatThread.fromMap(d.id, d.data()),
                ]..sort(
                  (ChatThread a, ChatThread b) => (b.lastAt ?? DateTime(2000))
                      .compareTo(a.lastAt ?? DateTime(2000)),
                );
            threads.value = list;
            unread.value = list
                .where((ChatThread t) => t.isUnreadFor(uid))
                .length;
          }, onError: _log);
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    } finally {
      _starting = false;
    }
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _uid = null;
    threads.value = const <ChatThread>[];
    unread.value = 0;
  }

  static ChatThread? thread(String id) {
    for (final ChatThread t in threads.value) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// The chat with [otherUid], created on first use. Null when it cannot be
  /// opened (not connected, offline on first use).
  static Future<String?> openDirect({
    required String otherUid,
    required String myName,
    required String theirName,
  }) async {
    final String? me = _uid ?? await PersonalCardService.durableUid();
    if (me == null || otherUid == me) return null;
    _uid ??= me;
    final String id = directId(me, otherUid);
    if (thread(id) != null) return id;
    final DocumentReference<Map<String, dynamic>> doc = FirebaseFirestore
        .instance
        .collection('chats')
        .doc(id);
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await doc.get();
      if (snap.exists) return id;
    } catch (_) {
      // Not readable: it does not exist yet (or the rules said no — the
      // create below will say the same).
    }
    try {
      await doc.set(<String, Object?>{
        'members': <String>[me, otherUid]..sort(),
        'type': 'direct',
        'kind': 'matchmakers',
        'names': <String, String>{
          me: _short(myName),
          otherUid: _short(theirName),
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return id;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return null;
    }
  }

  /// The messages of [chatId], oldest first, live.
  static Stream<List<ChatMessage>> messages(String chatId) {
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('at', descending: true)
        .limit(400)
        .snapshots(includeMetadataChanges: true)
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
          return <ChatMessage>[
            for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                in snap.docs.reversed)
              ChatMessage(
                id: d.id,
                fromUid: (d.data()['fromUid'] as String?) ?? '',
                text: (d.data()['text'] as String?) ?? '',
                at:
                    (d.data()['at'] as Timestamp?)?.toDate() ??
                    (d.metadata.hasPendingWrites ? DateTime.now() : null),
                ref: ChatRef.fromMap(d.data()['ref']),
                pending: d.metadata.hasPendingWrites,
                system: d.data()['system'] == true,
              ),
          ];
        });
  }

  /// Sends [text] (with what it is about, when there is something).
  static Future<bool> send(String chatId, String text, {ChatRef? ref}) async {
    final String? me = _uid;
    final String body = text.trim();
    if (me == null || body.isEmpty) return false;
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final DocumentReference<Map<String, dynamic>> chat = db
        .collection('chats')
        .doc(chatId);
    try {
      final WriteBatch batch = db.batch();
      batch.set(chat.collection('messages').doc(), <String, Object?>{
        'fromUid': me,
        'text': body.length > 4000 ? body.substring(0, 4000) : body,
        'at': FieldValue.serverTimestamp(),
        if (ref != null) 'ref': ref.toMap(),
      });
      batch.update(chat, <String, Object?>{
        'lastText': body.length > 200 ? body.substring(0, 200) : body,
        'lastFromUid': me,
        'lastAt': FieldValue.serverTimestamp(),
        'readAt.$me': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Not awaited past the local write: Firestore keeps the message
      // queued through a bad connection, like WhatsApp's clock.
      unawaited(batch.commit().catchError(_log));
      return true;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return false;
    }
  }

  /// This account read [chatId] up to now.
  static Future<void> markRead(String chatId) async {
    final String? me = _uid;
    if (me == null) return;
    final ChatThread? t = thread(chatId);
    if (t != null && !t.isUnreadFor(me)) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .update(<String, Object?>{
            'readAt.$me': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (error) {
      _log(error);
    }
  }

  static String _short(String name) {
    final String t = name.trim();
    return t.length > 80 ? t.substring(0, 80) : t;
  }

  static void _log(Object error, [StackTrace? stackTrace]) {
    debugPrint('ChatService: $error');
  }

  /// Test seam.
  @visibleForTesting
  static void debugSet(String uid, List<ChatThread> list) {
    _uid = uid;
    threads.value = list;
    unread.value = list.where((ChatThread t) => t.isUnreadFor(uid)).length;
  }
}
