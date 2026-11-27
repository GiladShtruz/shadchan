import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/telemetry.dart';

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
  /// own — words only; the list draws the kind's own mark beside it
  /// (never an emoji).
  String get preview => switch (this) {
    ChatMessageType.voice => 'הודעה קולית',
    ChatMessageType.image => 'תמונה',
    ChatMessageType.card => 'כרטיס',
    ChatMessageType.idea => 'רעיון',
    ChatMessageType.ideaOffer => 'יש לי רעיון בשבילך',
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
    this.blockedBy = const <String>[],
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

  /// Members who blocked the conversation ("חסימה"): while anybody is here
  /// it takes no new message from either side; the history stays.
  final List<String> blockedBy;

  bool get isBlocked => blockedBy.isNotEmpty;
  bool blockedByMe(String me) => blockedBy.contains(me);

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
    if (lastFromUid == me) return 'אני: $body';
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
      blockedBy: <String>[
        if (data['blockedBy'] is List)
          for (final Object? b in data['blockedBy'] as List)
            if (b is String) b,
      ],
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

  /// How many conversations the list reads at most.
  static const int listLimit = 500;

  static String directId(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  /// Starts the list — once Firebase is up and somebody is signed in. Safe
  /// to call often; called again by itself when Firebase comes up later, and
  /// after a refused or dropped listener.
  ///
  /// **The query has no `orderBy`, on purpose.** Ordering by `lastAt` needed
  /// a composite index — until it is built every list read fails, and the
  /// screen waited on a spinner for good — and it silently left out every
  /// conversation that has no `lastAt` (those an earlier version wrote).
  /// `array-contains` alone needs no index and returns them all; the list is
  /// sorted on the phone, which for a few hundred conversations costs
  /// nothing.
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
      if (uid == null) {
        // Not signed in (yet): nothing to wait for on the list screen.
        loaded.value = true;
        return;
      }
      _uid = uid;
      await _sub?.cancel();
      _retry?.cancel();
      _sub = FirebaseFirestore.instance
          .collection('chats')
          .where('members', arrayContains: uid)
          .limit(listLimit)
          .snapshots()
          .listen(
            (QuerySnapshot<Map<String, dynamic>> snap) {
              if (_uid != uid) return;
              _failures = 0;
              _apply(uid, <ChatThread>[
                for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                    in snap.docs)
                  ?ChatThread.fromMap(d.id, d.data()),
              ]);
              if (!snap.metadata.isFromCache) loaded.value = true;
            },
            onError: (Object error) {
              _log(error);
              _sub = null;
              // The screen stops waiting — it shows what it has, or the
              // empty state — and the list is asked for again shortly.
              loaded.value = true;
              _scheduleRetry();
            },
          );
      // Offline with nothing cached the server never answers: stop showing
      // a spinner after a few seconds — the list (or the empty state with
      // people to write to) is drawn, and fills in when the server answers.
      Timer(const Duration(seconds: 6), () {
        if (_uid == uid) loaded.value = true;
      });
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      loaded.value = true;
      _scheduleRetry();
    } finally {
      _starting = false;
    }
  }

  /// Pull to refresh: asks the server for the list once, now. The live
  /// listener keeps running; this only stops waiting for its next push. A
  /// list that is not listened to (a failed start) is started again.
  static Future<void> refresh() async {
    final String? uid = _uid;
    if (uid == null || _sub == null) {
      _failures = 0;
      await start();
      return;
    }
    final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
        .instance
        .collection('chats')
        .where('members', arrayContains: uid)
        .limit(listLimit)
        .get(const GetOptions(source: Source.server));
    if (_uid != uid) return;
    _apply(uid, <ChatThread>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs)
        ?ChatThread.fromMap(d.id, d.data()),
    ]);
    loaded.value = true;
  }

  static Timer? _retry;
  static int _failures = 0;

  /// 5s, 10s, 20s … up to two minutes between attempts.
  static void _scheduleRetry() {
    _retry?.cancel();
    final int seconds = (5 << _failures.clamp(0, 5)).clamp(5, 120);
    _failures++;
    _retry = Timer(Duration(seconds: seconds), () {
      if (_sub == null) unawaited(start());
    });
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
          !mapEquals(x.photos, y.photos) ||
          !listEquals(x.blockedBy, y.blockedBy)) {
        return false;
      }
    }
    return true;
  }

  static Future<void> stop() async {
    _retry?.cancel();
    _retry = null;
    _failures = 0;
    await _sub?.cancel();
    _sub = null;
    _uid = null;
    openChatId = null;
    ChatOutbox.clear();
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
    // Without knowing who "me" is, either half could be the other side.
    if (me.isEmpty) return '';
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
    String? messageId,
    bool keepOnFailure = true,
  }) async {
    final String? uid = await me();
    final String body = text.trim();
    if (uid == null) return false;
    if (body.isEmpty && type == ChatMessageType.text) return false;
    final String other = otherOfId(chatId, uid);
    if (other.isEmpty || other == uid) return false;
    if (thread(chatId)?.isBlocked ?? false) return false;
    // The message's id is decided here, once, so a retry writes the same
    // message again instead of a second copy.
    final String id =
        messageId ??
        FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .doc()
            .id;
    void keep() {
      if (!keepOnFailure) return;
      ChatOutbox.fail(
        ChatOutboxItem(
          localId: id,
          chatId: chatId,
          type: type,
          text: body,
          ref: ref,
          media: media,
          offer: offer,
          at: DateTime.now(),
        ),
      );
    }

    try {
      final bool ok = await _commit(
        chatId: chatId,
        uid: uid,
        other: other,
        id: id,
        body: body,
        type: type,
        ref: ref,
        media: media,
        offer: offer,
        myName: myName,
        theirName: theirName,
        onLateFailure: keep,
      );
      if (ok) ChatOutbox.remove(id);
      return ok;
    } on FirebaseException catch (error) {
      // A first message to somebody this account is not tied to — a
      // matchmaker met on the board or in the community: the server opens
      // the conversation (after checking they are shown there), and the
      // message is then an ordinary one.
      if (error.code == 'permission-denied' &&
          thread(chatId) == null &&
          await _openCommunityChat(other)) {
        try {
          final bool ok = await _commit(
            chatId: chatId,
            uid: uid,
            other: other,
            id: id,
            body: body,
            type: type,
            ref: ref,
            media: media,
            offer: offer,
            myName: myName,
            theirName: theirName,
            onLateFailure: keep,
            forceAwait: true,
          );
          if (ok) ChatOutbox.remove(id);
          return ok;
        } catch (again, stackTrace) {
          _log(again, stackTrace);
        }
      } else {
        _log(error);
      }
      Telemetry.failed(AppFeature.chats, 'send_${type.name}', error);
      keep();
      return false;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      Telemetry.failed(AppFeature.chats, 'send_${type.name}', error);
      keep();
      return false;
    }
  }

  /// "צ'אט" with a matchmaker the app showed this account (the board, the
  /// community) and nothing else ties them to: the `openCommunityChat`
  /// function creates the conversation. False when the server said no.
  static Future<bool> _openCommunityChat(String other) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('openCommunityChat')
          .call<Object?>(<String, Object?>{'otherUid': other})
          .timeout(const Duration(seconds: 20));
      return true;
    } catch (error) {
      _log(error);
      return false;
    }
  }

  static Future<bool> _commit({
    required String chatId,
    required String uid,
    required String other,
    required String id,
    required String body,
    required ChatMessageType type,
    ChatRef? ref,
    ChatMedia? media,
    ChatOffer? offer,
    String? myName,
    String? theirName,
    required VoidCallback onLateFailure,
    bool forceAwait = false,
  }) async {
    {
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
      batch.set(chat.collection('messages').doc(id), <String, Object?>{
        'fromUid': uid,
        'type': type.name,
        'text': body.length > 4000 ? body.substring(0, 4000) : body,
        'at': FieldValue.serverTimestamp(),
        if (ref != null) 'ref': ref.toMap(),
        if (media != null) 'media': media.toMap(),
        if (offer != null) 'offer': offer.toMap(),
      });
      if (known == null || forceAwait) {
        // A first message (or one to a conversation the list has not shown
        // yet) is awaited: if the server says no, the screen says so instead
        // of showing a line that never arrives.
        await batch.commit().timeout(const Duration(seconds: 20));
        Telemetry.completed(AppFeature.chats, 'send_${type.name}');
        Telemetry.meter(writes: 2);
        return true;
      }
      // Not awaited past the local write: Firestore keeps the message queued
      // through a bad connection, like WhatsApp's clock. If the server
      // refuses it later, the line comes back as "לא נשלחה" with a retry.
      unawaited(
        batch.commit().catchError((Object error) {
          _log(error);
          onLateFailure();
        }),
      );
      Telemetry.completed(AppFeature.chats, 'send_${type.name}');
      Telemetry.meter(writes: 2);
      return true;
    }
  }

  /// Blocks the conversation from this side ("חסימה") — no new message from
  /// either side until unblocked — or unblocks it. The history stays, and
  /// ideas already opened go on in the ideas system.
  static Future<bool> setBlocked(String chatId, bool blocked) async {
    final String? uid = await me();
    if (uid == null) return false;
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update(
        <String, Object?>{
          'blockedBy': blocked
              ? FieldValue.arrayUnion(<String>[uid])
              : FieldValue.arrayRemove(<String>[uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      return true;
    } catch (error) {
      _log(error);
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
    // Drawn at once as "שולח…" in the conversation — the composer stays
    // free, so text can be sent while the file goes up.
    final String localId = 'upload_$id';
    ChatOutbox.add(
      ChatOutboxItem(
        localId: localId,
        chatId: chatId,
        type: type,
        text: caption.trim(),
        filePath: file.path,
        durationMs: durationMs,
        at: DateTime.now(),
        sending: true,
      ),
    );
    try {
      final int size = await file.length();
      await FirebaseStorage.instance
          .ref(path)
          .putFile(file, SettableMetadata(contentType: mime))
          .timeout(const Duration(minutes: 2));
      Telemetry.meter(uploads: 1, uploadBytes: size);
      // Kept beside the cache, so this phone never downloads its own file.
      await _cacheCopy(file, path);
      final bool sent = await send(
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
        keepOnFailure: false,
      );
      if (sent) {
        ChatOutbox.remove(localId);
      } else {
        ChatOutbox.markFailed(localId);
      }
      return sent;
    } catch (error, stackTrace) {
      _log(error, stackTrace);
      Telemetry.failed(AppFeature.chats, 'upload_${type.name}', error);
      ChatOutbox.markFailed(localId);
      return false;
    }
  }

  /// Sends a message that did not go — the same message (same id), or the
  /// same file uploaded again.
  static Future<bool> retry(
    ChatOutboxItem item, {
    String? myName,
    String? theirName,
  }) async {
    final String? file = item.filePath;
    if (file != null) {
      ChatOutbox.remove(item.localId);
      final File local = File(file);
      if (!local.existsSync()) return false;
      return sendFile(
        item.chatId,
        local,
        type: item.type,
        durationMs: item.durationMs,
        caption: item.text,
        myName: myName,
        theirName: theirName,
      );
    }
    ChatOutbox.markSending(item.localId);
    return send(
      item.chatId,
      item.text,
      type: item.type,
      ref: item.ref,
      media: item.media,
      offer: item.offer,
      myName: myName,
      theirName: theirName,
      messageId: item.localId,
    );
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
      // Opened before Firebase is up (a push tapped on a cold start): listen
      // as soon as it is, instead of leaving the conversation blank.
      loaded = true;
      refused = true;
      FirebaseBootstrap.readyListenable.addListener(_onFirebaseReady);
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

  void _onFirebaseReady() {
    if (!FirebaseBootstrap.isReady) return;
    FirebaseBootstrap.readyListenable.removeListener(_onFirebaseReady);
    if (!_disposed) _listen();
  }

  /// Listens again — after the first message created the conversation (from
  /// either side), or after the connection came back.
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
    FirebaseBootstrap.readyListenable.removeListener(_onFirebaseReady);
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}

/// A message written on this phone that the server has not got: an upload
/// still going ("שולח…"), or one that failed ("לא נשלחה · ניסיון חוזר").
/// Never thrown away by itself — the user retries or deletes it.
class ChatOutboxItem {
  const ChatOutboxItem({
    required this.localId,
    required this.chatId,
    required this.type,
    required this.text,
    required this.at,
    this.ref,
    this.media,
    this.offer,
    this.filePath,
    this.durationMs,
    this.sending = false,
  });

  /// The message's own id (a text) or the upload's (a file).
  final String localId;
  final String chatId;
  final ChatMessageType type;
  final String text;
  final DateTime at;
  final ChatRef? ref;
  final ChatMedia? media;
  final ChatOffer? offer;

  /// The local photo or recording, for an upload.
  final String? filePath;
  final int? durationMs;

  /// Still on its way; false once it failed.
  final bool sending;

  ChatOutboxItem copyWith({bool? sending}) => ChatOutboxItem(
    localId: localId,
    chatId: chatId,
    type: type,
    text: text,
    at: at,
    ref: ref,
    media: media,
    offer: offer,
    filePath: filePath,
    durationMs: durationMs,
    sending: sending ?? this.sending,
  );
}

/// The messages not on the server yet, for every conversation, in memory.
abstract final class ChatOutbox {
  static final ValueNotifier<List<ChatOutboxItem>> items =
      ValueNotifier<List<ChatOutboxItem>>(const <ChatOutboxItem>[]);

  static List<ChatOutboxItem> of(String chatId) => <ChatOutboxItem>[
    for (final ChatOutboxItem i in items.value)
      if (i.chatId == chatId) i,
  ];

  static void add(ChatOutboxItem item) {
    items.value = <ChatOutboxItem>[
      for (final ChatOutboxItem i in items.value)
        if (i.localId != item.localId) i,
      item,
    ];
  }

  /// [item] did not go: kept as failed.
  static void fail(ChatOutboxItem item) => add(item.copyWith(sending: false));

  static void markFailed(String localId) => _mark(localId, false);
  static void markSending(String localId) => _mark(localId, true);

  static void _mark(String localId, bool sending) {
    items.value = <ChatOutboxItem>[
      for (final ChatOutboxItem i in items.value)
        i.localId == localId ? i.copyWith(sending: sending) : i,
    ];
  }

  static void remove(String localId) {
    if (!items.value.any((ChatOutboxItem i) => i.localId == localId)) return;
    items.value = <ChatOutboxItem>[
      for (final ChatOutboxItem i in items.value)
        if (i.localId != localId) i,
    ];
  }

  static void clear() => items.value = const <ChatOutboxItem>[];
}

/// Conversations put away from the list ("העברה לארכיון") — on this
/// account, synced like any setting. A conversation comes back by itself
/// with its next message. Nothing is deleted, on either side.
abstract final class ChatArchive {
  static const String key = 'chats.archived';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Map<String, int>? _cache;

  static Map<String, int> get _all {
    final Map<String, int>? cached = _cache;
    if (cached != null) return cached;
    final Map<String, int> out = <String, int>{};
    final Object? raw = Hive.isBoxOpen('settings')
        ? Hive.box<dynamic>('settings').get(key)
        : null;
    if (raw is String && raw.isNotEmpty) {
      for (final String part in raw.split(',')) {
        final int cut = part.lastIndexOf(':');
        if (cut <= 0) continue;
        final int? at = int.tryParse(part.substring(cut + 1));
        if (at != null) out[part.substring(0, cut)] = at;
      }
    }
    return _cache = out;
  }

  /// Whether [t] is put away: archived after its last line.
  static bool isArchived(ChatThread t) {
    final int? at = _all[t.id];
    if (at == null) return false;
    final DateTime? last = t.lastAt;
    return last == null || last.millisecondsSinceEpoch <= at;
  }

  static void archive(String chatId, {DateTime? at}) => _write(<String, int>{
    ..._all,
    chatId: (at ?? DateTime.now()).millisecondsSinceEpoch,
  });

  static void restore(String chatId) =>
      _write(<String, int>{..._all}..remove(chatId));

  static void _write(Map<String, int> next) {
    _cache = next;
    persistHomeSetting(
      key,
      next.entries
          .map((MapEntry<String, int> e) => '${e.key}:${e.value}')
          .join(','),
    );
    revision.value++;
  }

  static void forgetCache() => _cache = null;
}
