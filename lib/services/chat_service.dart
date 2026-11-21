import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_card_service.dart';

/// What a message is about — a card, an idea, an offer — so a thread of
/// months can mention many of them without a chat per card or per idea.
class ChatRef {
  const ChatRef({
    required this.kind,
    required this.id,
    required this.label,
    this.ownerUid,
  });

  /// `card` (a card sent or shared), `person` (a friend in my own database),
  /// `idea` / `proposal` (an idea between two matchmakers) or `ideaOffer`.
  final String kind;
  final String id;
  final String label;

  /// For a card: the account that holds it.
  final String? ownerUid;

  Map<String, Object?> toMap() => <String, Object?>{
    'kind': kind,
    'id': id.length > 300 ? id.substring(0, 300) : id,
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

/// The kinds of message a conversation holds.
enum ChatMessageType {
  text,
  voice,
  image,
  card,
  idea,

  /// "יש לי רעיון בשבילך" — a matchmaker offers a single somebody, and the
  /// single answers on the message itself.
  ideaOffer,

  /// A small line the server wrote ("הרעיון אושר") — never from a person.
  system;

  static ChatMessageType byName(Object? name) {
    for (final ChatMessageType t in ChatMessageType.values) {
      if (t.name == name) return t;
    }
    return ChatMessageType.text;
  }

  /// The last-line preview of a message of this kind with no words of its
  /// own.
  String get preview => switch (this) {
    ChatMessageType.voice => '🎤 הודעה קולית',
    ChatMessageType.image => '📷 תמונה',
    ChatMessageType.card => '🪪 כרטיס',
    ChatMessageType.idea => '💡 רעיון',
    ChatMessageType.ideaOffer => '💡 יש לי רעיון בשבילך',
    ChatMessageType.text || ChatMessageType.system => '',
  };
}

/// A photo or a recording in a conversation — the file lives in Storage
/// under `chats/{chatId}/`, and only the two members can read it.
class ChatMedia {
  const ChatMedia({
    required this.path,
    this.durationMs,
    this.width,
    this.height,
    this.size,
    this.mime,
  });

  final String path;
  final int? durationMs;
  final int? width;
  final int? height;
  final int? size;
  final String? mime;

  Map<String, Object?> toMap() => <String, Object?>{
    'path': path,
    if (durationMs != null) 'durationMs': durationMs,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (size != null) 'size': size,
    if (mime != null) 'mime': mime,
  };

  static ChatMedia? fromMap(Object? raw) {
    if (raw is! Map || raw['path'] is! String) return null;
    int? n(Object? v) => v is num ? v.toInt() : null;
    return ChatMedia(
      path: raw['path'] as String,
      durationMs: n(raw['durationMs']),
      width: n(raw['width']),
      height: n(raw['height']),
      size: n(raw['size']),
      mime: raw['mime'] as String?,
    );
  }
}

/// The candidate in "יש לי רעיון בשבילך": who, in a line, and the card that
/// was sent with it (`sentCards/{matchmaker}/to/{single}/cards/{personId}`).
class ChatOffer {
  const ChatOffer({
    required this.personId,
    required this.name,
    this.summary = '',
    this.matchId,
  });

  final String personId;
  final String name;
  final String summary;

  /// The idea this offer belongs to on the matchmaker's side, if any.
  final String? matchId;

  Map<String, Object?> toMap() => <String, Object?>{
    'personId': personId,
    'name': name.length > 120 ? name.substring(0, 120) : name,
    if (summary.isNotEmpty)
      'summary': summary.length > 300 ? summary.substring(0, 300) : summary,
    if (matchId != null) 'matchId': matchId,
  };

  static ChatOffer? fromMap(Object? raw) {
    if (raw is! Map || raw['personId'] is! String) return null;
    return ChatOffer(
      personId: raw['personId'] as String,
      name: (raw['name'] as String?) ?? '',
      summary: (raw['summary'] as String?) ?? '',
      matchId: raw['matchId'] as String?,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromUid,
    required this.text,
    this.type = ChatMessageType.text,
    this.at,
    this.ref,
    this.media,
    this.offer,
    this.answer,
    this.answerReason,
    this.pending = false,
    this.system = false,
  });

  final String id;
  final String fromUid;
  final ChatMessageType type;
  final String text;
  final DateTime? at;
  final ChatRef? ref;
  final ChatMedia? media;
  final ChatOffer? offer;

  /// The single's answer to an offer: `approved` or `declined`.
  final String? answer;

  /// Why it was declined, when the single said — only the matchmaker reads
  /// it (the candidate is never in this conversation).
  final String? answerReason;

  /// Written on this phone and not yet on the server.
  final bool pending;

  /// A small line the server wrote ("הרעיון אושר") — never from a person.
  final bool system;

  /// Whether the other member has read this message — derived from their
  /// `readAt` on the conversation, the same on every phone, rather than a
  /// write per message.
  bool readBy(ChatThread? thread, String other) {
    final DateTime? read = thread?.readAt[other];
    final DateTime? when = at;
    return read != null && when != null && !read.isBefore(when);
  }

  /// The words of a message, or what stands for them.
  String get preview => text.isNotEmpty ? text : type.preview;

  static ChatMessage fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final Map<String, dynamic> data = d.data() ?? const <String, dynamic>{};
    final bool system = data['system'] == true;
    return ChatMessage(
      id: d.id,
      fromUid: (data['fromUid'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      type: system
          ? ChatMessageType.system
          : ChatMessageType.byName(data['type']),
      at:
          (data['at'] as Timestamp?)?.toDate() ??
          (d.metadata.hasPendingWrites ? DateTime.now() : null),
      ref: ChatRef.fromMap(data['ref']),
      media: ChatMedia.fromMap(data['media']),
      offer: ChatOffer.fromMap(data['offer']),
      answer: data['answer'] as String?,
      answerReason: data['answerReason'] as String?,
      pending: d.metadata.hasPendingWrites,
      system: system,
    );
  }
}

/// One conversation between two accounts — **whatever either of them is**:
/// single, matchmaker, or both. Never one per idea, per card or per role.
class ChatThread {
  const ChatThread({
    required this.id,
    required this.members,
    required this.names,
    this.type = 'direct',
    this.photos = const <String, String>{},
    this.lastText = '',
    this.lastType = ChatMessageType.text,
    this.lastFromUid,
    this.lastAt,
    this.readAt = const <String, DateTime>{},
    this.unread = const <String, int>{},
  });

  final String id;
  final List<String> members;
  final String type;
  final Map<String, String> names;

  /// Each member's own picture (their community photo), when they have one.
  final Map<String, String> photos;
  final String lastText;
  final ChatMessageType lastType;
  final String? lastFromUid;
  final DateTime? lastAt;
  final Map<String, DateTime> readAt;

  /// Messages each member has not read yet.
  final Map<String, int> unread;

  String otherOf(String me) =>
      members.firstWhere((String m) => m != me, orElse: () => me);

  /// What this conversation is called from [me]'s side.
  String titleFor(String me) {
    final String name = (names[otherOf(me)] ?? '').trim();
    return name.isNotEmpty ? name : 'צ\'אט';
  }

  String? photoFor(String me) {
    final String? url = photos[otherOf(me)];
    return url == null || url.isEmpty ? null : url;
  }

  /// The last line as the list shows it.
  String previewFor(String me) {
    final String body = lastText.isNotEmpty ? lastText : lastType.preview;
    if (body.isEmpty) return 'שיחה חדשה';
    if (lastFromUid == me) return 'את/ה: $body';
    return body;
  }

  /// How many messages [me] has not read — at least one while the last line
  /// is somebody else's and newer than [me]'s read mark.
  int unreadCountFor(String me) {
    final int count = unread[me] ?? 0;
    if (count > 0) return count;
    return isUnreadFor(me) ? 1 : 0;
  }

  bool isUnreadFor(String me) {
    if ((unread[me] ?? 0) > 0) return true;
    final DateTime? last = lastAt;
    if (last == null || lastFromUid == null || lastFromUid == me) return false;
    if (lastType == ChatMessageType.system) return false;
    final DateTime? read = readAt[me];
    return read == null || read.isBefore(last);
  }

  static ChatThread? fromMap(String id, Map<String, dynamic> data) {
    final Object? members = data['members'];
    if (members is! List) return null;
    DateTime? time(Object? v) => v is Timestamp ? v.toDate() : null;
    Map<String, String> strings(Object? raw) => <String, String>{
      if (raw is Map)
        for (final MapEntry<dynamic, dynamic> e in raw.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
    };
    final Object? read = data['readAt'];
    final Object? unread = data['unread'];
    return ChatThread(
      id: id,
      members: <String>[
        for (final Object? m in members)
          if (m is String) m,
      ],
      type: (data['type'] as String?) ?? 'direct',
      names: strings(data['names']),
      photos: strings(data['photos']),
      lastText: (data['lastText'] as String?) ?? '',
      lastType: ChatMessageType.byName(data['lastType']),
      lastFromUid: data['lastFromUid'] as String?,
      lastAt: time(data['lastAt']) ?? time(data['updatedAt']),
      readAt: <String, DateTime>{
        if (read is Map)
          for (final MapEntry<dynamic, dynamic> e in read.entries)
            if (e.key is String && time(e.value) != null)
              e.key as String: time(e.value)!,
      },
      unread: <String, int>{
        if (unread is Map)
          for (final MapEntry<dynamic, dynamic> e in unread.entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toInt(),
      },
    );
  }
}

/// The app's one chat system — `chats/{a}_{b}` and their messages.
///
/// **One conversation per pair of accounts**, whatever either of them is.
/// Its id is the two uids, sorted, so the same two people always reach the
/// same conversation from anywhere — a profile, a card, an idea, a notice —
/// and a second one can never exist.
///
/// **Nothing is written by opening one.** The conversation is created by its
/// first message, in the same write: the chat document is written with a
/// merge, so the same write creates it the first time and updates it every
/// time after, with no read beforehand to decide which (the old read-first
/// path broke whenever that read failed — offline, Firebase not up yet, a
/// refused read — and from then on every message to an existing chat was
/// refused).
///
/// **Cheap by construction.** The list listens to the conversations' own
/// documents only (name, picture, last line, unread); messages are read only
/// while one conversation is open, a page at a time ([ChatMessagesController]).
abstract final class ChatService {
  static final ValueNotifier<List<ChatThread>> threads =
      ValueNotifier<List<ChatThread>>(const <ChatThread>[]);

  /// Conversations with something unread — the bar's badge, the same on
  /// every phone of the account.
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// Whether the server has answered the list once.
  static final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);

  static String? _uid;
  static String? get uid => _uid;
  static bool _starting = false;
  static bool _waitingForFirebase = false;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// The chat on the screen right now, so its own pushes are not announced.
  static String? openChatId;

  /// How many conversations the list holds at most.
  static const int listLimit = 200;

  static String directId(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  /// Starts the list — once Firebase is up and somebody is signed in. Safe
  /// to call often; called again by itself when Firebase comes up later.
  static Future<void> start() async {
    if (_uid != null && _sub != null) return;
    if (_starting) return;
    if (!FirebaseBootstrap.isReady) {
      if (!_waitingForFirebase) {
        _waitingForFirebase = true;
        FirebaseBootstrap.readyListenable.addListener(_onFirebaseReady);
      }
      return;
    }
    _starting = true;
    try {
      final String? uid = await PersonalCardService.durableUid();
      if (uid == null) return;
      _uid = uid;
      await _sub?.cancel();
      _sub = FirebaseFirestore.instance
          .collection('chats')
          .where('members', arrayContains: uid)
          .orderBy('lastAt', descending: true)
          .limit(listLimit)
          .snapshots()
          .listen(
            (QuerySnapshot<Map<String, dynamic>> snap) {
              if (_uid != uid) return;
              _apply(uid, <ChatThread>[
                for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                    in snap.docs)
                  ?ChatThread.fromMap(d.id, d.data()),
              ]);
              if (!snap.metadata.isFromCache) loaded.value = true;
            },
            onError: (Object error) {
              _log(error);
              // A dropped listener is started again on the next resume.
              _sub = null;
            },
          );
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    } finally {
      _starting = false;
    }
  }

  static void _onFirebaseReady() {
    if (!FirebaseBootstrap.isReady) return;
    FirebaseBootstrap.readyListenable.removeListener(_onFirebaseReady);
    _waitingForFirebase = false;
    unawaited(start());
  }

  static void _apply(String me, List<ChatThread> list) {
    list.sort(
      (ChatThread a, ChatThread b) =>
          (b.lastAt ?? DateTime(2000)).compareTo(a.lastAt ?? DateTime(2000)),
    );
    // Only notify when something a screen shows changed: a metadata-only
    // snapshot (pending → acknowledged) would otherwise redraw the list.
    if (!_sameList(threads.value, list)) threads.value = list;
    final int count = list.where((ChatThread t) => t.isUnreadFor(me)).length;
    if (unread.value != count) unread.value = count;
  }

  static bool _sameList(List<ChatThread> a, List<ChatThread> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final ChatThread x = a[i];
      final ChatThread y = b[i];
      if (x.id != y.id ||
          x.lastAt != y.lastAt ||
          x.lastText != y.lastText ||
          x.lastFromUid != y.lastFromUid ||
          !mapEquals(x.unread, y.unread) ||
          !mapEquals(x.readAt, y.readAt) ||
          !mapEquals(x.names, y.names) ||
          !mapEquals(x.photos, y.photos)) {
        return false;
      }
    }
    return true;
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _uid = null;
    openChatId = null;
    threads.value = const <ChatThread>[];
    unread.value = 0;
    loaded.value = false;
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

  /// The route of the conversation with [otherUid]. **Nothing is written by
  /// opening it**: the conversation is created by its first message, and
  /// from then on the same id always opens the same conversation.
  ///
  /// [ideaId] opens it with an idea as its context ("בנוגע לרעיון: …").
  static String routeTo({
    required String me,
    required String otherUid,
    String? theirName,
    String? ideaId,
  }) => Uri(
    path: '/chats/${directId(me, otherUid)}',
    queryParameters: <String, String>{
      if (theirName != null && theirName.trim().isNotEmpty)
        'name': theirName.trim(),
      if (ideaId != null && ideaId.isNotEmpty) 'idea': ideaId,
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

  /// What one send writes into the conversation's own document, as a merge.
  ///
  /// Pure, so the shape the rules expect is checked in a test: the members
  /// and type (unchanged on an existing chat), the last line, this member's
  /// read mark and zeroed counter, one more unread for the other member,
  /// and this member's own name and picture.
  @visibleForTesting
  static Map<String, Object?> chatWriteFor({
    required String me,
    required String other,
    required String lastText,
    required ChatMessageType type,
    String? myName,
    String? theirName,
    String? myPhotoUrl,
    Object? now,
  }) {
    final Object stamp = now ?? FieldValue.serverTimestamp();
    final String last = lastText.length > 200
        ? lastText.substring(0, 200)
        : lastText;
    return <String, Object?>{
      'members': <String>[me, other]..sort(),
      'type': 'direct',
      'names': <String, String>{
        if ((myName ?? '').trim().isNotEmpty) me: _short(myName!),
        if ((theirName ?? '').trim().isNotEmpty) other: _short(theirName!),
      },
      if ((myPhotoUrl ?? '').isNotEmpty)
        'photos': <String, String>{me: myPhotoUrl!},
      'lastText': last,
      'lastType': type.name,
      'lastFromUid': me,
      'lastAt': stamp,
      'readAt': <String, Object>{me: stamp},
      'unread': <String, Object>{
        me: 0,
        other: now == null ? FieldValue.increment(1) : 1,
      },
      'updatedAt': stamp,
    };
  }

  /// Sends one message. The first message of a conversation creates it, in
  /// the same write — the conversation and its first line arrive together
  /// or not at all.
  ///
  /// [theirName] is written only while this phone does not know the other
  /// side's name yet (it never overwrites the name they gave themselves).
  static Future<bool> send(
    String chatId,
    String text, {
    ChatMessageType type = ChatMessageType.text,
    ChatRef? ref,
    ChatMedia? media,
    ChatOffer? offer,
    String? myName,
    String? theirName,
  }) async {
    final String? uid = await me();
    final String body = text.trim();
    if (uid == null) return false;
    if (body.isEmpty && type == ChatMessageType.text) return false;
    final String other = otherOfId(chatId, uid);
    if (other.isEmpty || other == uid) return false;
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      final DocumentReference<Map<String, dynamic>> chat = db
          .collection('chats')
          .doc(chatId);
      final ChatThread? known = thread(chatId);
      final bool nameKnown = (known?.names[other] ?? '').trim().isNotEmpty;
      final WriteBatch batch = db.batch();
      batch.set(
        chat,
        chatWriteFor(
          me: uid,
          other: other,
          lastText: body.isNotEmpty ? body : type.preview,
          type: type,
          myName: myName,
          theirName: nameKnown ? null : theirName,
          myPhotoUrl: CommunityProfileStore.uploadedAvatarUrl,
        ),
        SetOptions(merge: true),
      );
      batch.set(chat.collection('messages').doc(), <String, Object?>{
        'fromUid': uid,
        'type': type.name,
        'text': body.length > 4000 ? body.substring(0, 4000) : body,
        'at': FieldValue.serverTimestamp(),
        if (ref != null) 'ref': ref.toMap(),
        if (media != null) 'media': media.toMap(),
        if (offer != null) 'offer': offer.toMap(),
      });
      if (known == null) {
        // A first message (or one to a conversation the list has not shown
        // yet) is awaited: if the server says no, the screen says so instead
        // of showing a line that never arrives.
        await batch.commit().timeout(const Duration(seconds: 20));
        return true;
      }
      // Not awaited past the local write: Firestore keeps the message queued
      // through a bad connection, like WhatsApp's clock.
      unawaited(batch.commit().catchError(_log));
      return true;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return false;
    }
  }

  /// Uploads [file] into the conversation and sends it as a photo or a
  /// voice message. False when the upload or the message failed.
  static Future<bool> sendFile(
    String chatId,
    File file, {
    required ChatMessageType type,
    int? durationMs,
    int? width,
    int? height,
    String caption = '',
    String? myName,
    String? theirName,
  }) async {
    assert(type == ChatMessageType.image || type == ChatMessageType.voice);
    final String? uid = await me();
    if (uid == null) return false;
    final String name = file.path.split(Platform.pathSeparator).last;
    final int dot = name.lastIndexOf('.');
    String ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (!RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) {
      ext = type == ChatMessageType.image ? 'jpg' : 'm4a';
    }
    final String mime = type == ChatMessageType.image
        ? (ext == 'png' ? 'image/png' : 'image/jpeg')
        : switch (ext) {
            'opus' || 'ogg' => 'audio/ogg',
            'mp3' => 'audio/mpeg',
            'aac' => 'audio/aac',
            _ => 'audio/mp4',
          };
    final String id =
        '${uid.substring(0, uid.length < 6 ? uid.length : 6)}'
        '${DateTime.now().microsecondsSinceEpoch}';
    final String path = 'chats/$chatId/$id.$ext';
    try {
      final int size = await file.length();
      await FirebaseStorage.instance
          .ref(path)
          .putFile(file, SettableMetadata(contentType: mime))
          .timeout(const Duration(minutes: 2));
      // Kept beside the cache, so this phone never downloads its own file.
      unawaited(_cacheCopy(file, path));
      return await send(
        chatId,
        caption,
        type: type,
        media: ChatMedia(
          path: path,
          durationMs: durationMs,
          width: width,
          height: height,
          size: size,
          mime: mime,
        ),
        myName: myName,
        theirName: theirName,
      );
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      return false;
    }
  }

  static Future<Directory> _cacheDir() async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory('${base.path}/chat_media');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String _cacheName(String path) => path.replaceAll('/', '__');

  static Future<void> _cacheCopy(File file, String path) async {
    try {
      final Directory dir = await _cacheDir();
      await file.copy('${dir.path}/${_cacheName(path)}');
    } catch (_) {}
  }

  static final Map<String, Future<File?>> _downloads =
      <String, Future<File?>>{};

  /// The local copy of a conversation's photo or recording — downloaded once
  /// and kept, so the history opens offline and scrolls without fetching.
  static Future<File?> mediaFile(String path) {
    return _downloads.putIfAbsent(path, () async {
      try {
        final Directory dir = await _cacheDir();
        final File file = File('${dir.path}/${_cacheName(path)}');
        if (file.existsSync() && file.lengthSync() > 0) return file;
        final File partial = File('${file.path}.part');
        await FirebaseStorage.instance
            .ref(path)
            .writeToFile(partial)
            .timeout(const Duration(minutes: 2));
        await partial.rename(file.path);
        return file;
      } catch (error) {
        _log(error);
        // Not remembered: the next look tries again.
        unawaited(Future<void>(() => _downloads.remove(path)));
        return null;
      }
    });
  }

  /// This account read [chatId] up to now — on every phone of the account.
  static Future<void> markRead(String chatId) async {
    final String? me = _uid;
    if (me == null) return;
    final ChatThread? t = thread(chatId);
    // A chat with no message yet has nothing to mark.
    if (t == null || !t.isUnreadFor(me)) return;
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).set(
        <String, Object?>{
          'readAt': <String, Object>{me: FieldValue.serverTimestamp()},
          'unread': <String, Object>{me: 0},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (error) {
      _log(error);
    }
  }

  /// The single's answer to "יש לי רעיון בשבילך" — once. [reason] is
  /// optional and only the matchmaker reads it.
  static Future<bool> answerOffer(
    String chatId,
    String messageId, {
    required bool approve,
    String? reason,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update(<String, Object?>{
            'answer': approve ? 'approved' : 'declined',
            if ((reason ?? '').trim().isNotEmpty)
              'answerReason': reason!.trim().length > 500
                  ? reason.trim().substring(0, 500)
                  : reason.trim(),
            'answeredAt': FieldValue.serverTimestamp(),
          });
      return true;
    } catch (error) {
      _log(error);
      return false;
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

/// The messages of one open conversation: the newest page live, older pages
/// read once as the reader scrolls back, and nothing at all for the
/// conversations that are not open.
///
/// A conversation with no message yet cannot be read (it does not exist), and
/// Firestore closes a refused listener for good — so a refusal is not an
/// error here: the controller waits, and [resubscribe] after the first
/// message listens again.
class ChatMessagesController extends ChangeNotifier {
  ChatMessagesController(this.chatId, {this.pageSize = 30}) {
    _listen();
  }

  final String chatId;
  final int pageSize;

  List<ChatMessage> _live = const <ChatMessage>[];
  final List<ChatMessage> _older = <ChatMessage>[];
  DocumentSnapshot<Map<String, dynamic>>? _oldestLive;
  DocumentSnapshot<Map<String, dynamic>>? _oldestLoaded;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _disposed = false;

  /// Whether the newest page has arrived (from the cache or the server).
  bool loaded = false;

  /// Whether a page older than the ones held may exist.
  bool hasMore = true;
  bool loadingOlder = false;

  /// The listener was refused — usually a conversation that does not exist
  /// yet.
  bool refused = false;

  /// Oldest first.
  List<ChatMessage> get messages {
    final Set<String> seen = <String>{};
    final List<ChatMessage> all = <ChatMessage>[];
    for (final ChatMessage m in <ChatMessage>[..._older.reversed, ..._live]) {
      if (seen.add(m.id)) all.add(m);
    }
    return all;
  }

  CollectionReference<Map<String, dynamic>> get _collection => FirebaseFirestore
      .instance
      .collection('chats')
      .doc(chatId)
      .collection('messages');

  void _listen() {
    if (!FirebaseBootstrap.isReady) {
      loaded = true;
      refused = true;
      return;
    }
    unawaited(_sub?.cancel());
    refused = false;
    _sub = _collection
        .orderBy('at', descending: true)
        .limit(pageSize)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (QuerySnapshot<Map<String, dynamic>> snap) {
            _live = <ChatMessage>[
              for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                  in snap.docs.reversed)
                ChatMessage.fromDoc(d),
            ];
            _oldestLive = snap.docs.isEmpty ? null : snap.docs.last;
            if (snap.docs.length < pageSize && _older.isEmpty) hasMore = false;
            loaded = true;
            _notify();
          },
          onError: (Object error) {
            ChatService._log(error);
            refused = true;
            loaded = true;
            _sub = null;
            _notify();
          },
        );
  }

  /// Listens again — after the first message created the conversation, or
  /// after the connection came back.
  void resubscribe() {
    if (_disposed) return;
    if (_sub != null && !refused) return;
    _listen();
  }

  /// Reads the next older page, once.
  Future<void> loadOlder() async {
    if (loadingOlder || !hasMore || _disposed) return;
    final DocumentSnapshot<Map<String, dynamic>>? after =
        _oldestLoaded ?? _oldestLive;
    if (after == null) return;
    loadingOlder = true;
    _notify();
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await _collection
          .orderBy('at', descending: true)
          .startAfterDocument(after)
          .limit(pageSize)
          .get();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
        _older.add(ChatMessage.fromDoc(d));
      }
      if (snap.docs.isNotEmpty) _oldestLoaded = snap.docs.last;
      if (snap.docs.length < pageSize) hasMore = false;
    } catch (error) {
      ChatService._log(error);
    } finally {
      loadingOlder = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
