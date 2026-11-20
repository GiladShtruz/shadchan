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
    this.kind = 'matchmakers',
    this.lastText = '',
    this.lastFromUid,
    this.lastAt,
    this.readAt = const <String, DateTime>{},
  });

  final String id;
  final List<String> members;
  final String type;

  /// Who the chat is between: `matchmakers`, `single` (a single and a
  /// matchmaker who keeps or asked for their card) or `partners` (a couple
  /// space).
  final String kind;
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
    if (name.isNotEmpty) return name;
    return kind == 'single' ? 'צ\'אט' : 'שדכן/ית';
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
      kind: (data['kind'] as String?) ?? 'matchmakers',
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

  /// The other member of a direct chat, read off its id (`{a}_{b}`, sorted).
  static String otherOfId(String chatId, String me) {
    final int cut = chatId.indexOf('_');
    if (cut <= 0) return '';
    final String a = chatId.substring(0, cut);
    final String b = chatId.substring(cut + 1);
    return a == me ? b : a;
  }

  /// The route of the chat with [otherUid]. **Nothing is written by opening
  /// it**: the chat is created by its first message, and from then on the
  /// same id always opens the same conversation — never a second one.
  static String routeTo({
    required String me,
    required String otherUid,
    String? theirName,
    String kind = 'matchmakers',
  }) => Uri(
    path: '/chats/${directId(me, otherUid)}',
    queryParameters: <String, String>{
      if (theirName != null && theirName.trim().isNotEmpty)
        'name': theirName.trim(),
      if (kind != 'matchmakers') 'kind': kind,
    },
  ).toString();

  /// The account's uid, waiting for the sign-in to settle when the service
  /// has not started yet — a message typed in the first second must not be
  /// dropped because `start()` was still on its way.
  static Future<String?> me() async =>
      _uid ?? (_uid = await PersonalCardService.durableUid());

  /// Kept for older callers: the id of the chat with [otherUid]. Writes
  /// nothing — see [routeTo].
  static Future<String?> openDirect({
    required String otherUid,
    required String myName,
    required String theirName,
  }) async {
    final String? uid = await me();
    if (uid == null || otherUid == uid || otherUid.isEmpty) return null;
    return directId(uid, otherUid);
  }

  /// Whether the chat document exists on the server. False for a chat with
  /// no message yet — which is also what a refused read looks like, and
  /// either way the screen shows an empty conversation ready for a first
  /// message.
  static Future<bool> exists(String chatId) async {
    if (thread(chatId) != null) return true;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  /// The messages of [chatId], oldest first, live. A chat that cannot be read
  /// (not created yet) is an empty conversation, not an error.
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
        })
        .handleError((Object error) => _log(error));
  }

  /// Sends [text] (with what it is about, when there is something).
  ///
  /// The first message of a chat creates it, in the same write: the chat and
  /// its first line arrive together or not at all. [kind], [myName] and
  /// [theirName] are only used then.
  static Future<bool> send(
    String chatId,
    String text, {
    ChatRef? ref,
    String? myName,
    String? theirName,
    String kind = 'matchmakers',
  }) async {
    final String? uid = await me();
    final String body = text.trim();
    if (uid == null || body.isEmpty) return false;
    final String other = otherOfId(chatId, uid);
    if (other.isEmpty || other == uid) return false;
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final DocumentReference<Map<String, dynamic>> chat = db
        .collection('chats')
        .doc(chatId);
    final String last = body.length > 200 ? body.substring(0, 200) : body;
    try {
      final bool known = await exists(chatId);
      final WriteBatch batch = db.batch();
      if (!known) {
        batch.set(chat, <String, Object?>{
          'members': <String>[uid, other]..sort(),
          'type': 'direct',
          'kind': kind,
          'names': <String, String>{
            if ((myName ?? '').trim().isNotEmpty) uid: _short(myName!),
            if ((theirName ?? '').trim().isNotEmpty) other: _short(theirName!),
          },
          'lastText': last,
          'lastFromUid': uid,
          'lastAt': FieldValue.serverTimestamp(),
          'readAt': <String, Object?>{uid: FieldValue.serverTimestamp()},
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      batch.set(chat.collection('messages').doc(), <String, Object?>{
        'fromUid': uid,
        'text': body.length > 4000 ? body.substring(0, 4000) : body,
        'at': FieldValue.serverTimestamp(),
        if (ref != null) 'ref': ref.toMap(),
      });
      if (known) {
        batch.update(chat, <String, Object?>{
          'lastText': last,
          'lastFromUid': uid,
          'lastAt': FieldValue.serverTimestamp(),
          'readAt.$uid': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (!known) {
        // The first message is awaited: if the rules say no, the screen
        // must say so instead of showing a line that never arrives.
        await batch.commit();
        return true;
      }
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
    // A chat with no message yet has nothing to mark.
    if (t == null || !t.isUnreadFor(me)) return;
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
