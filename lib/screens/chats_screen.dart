import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/widgets/app_refresh.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/dialogs/voice_recorder_sheet.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/idea_proposal.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/network_screen.dart';
import 'package:shadchan/screens/partner_space_screen.dart';
import 'package:shadchan/services/ai_chat_command.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/services/partner_space.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/avatar_image.dart';
import 'package:shadchan/utils/chat_idea_command.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/chat_objects.dart';
import 'package:shadchan/widgets/personal_home_sections.dart';

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

/// "צ'אטים" — **one list of every conversation of this account**, whoever it
/// is with: a single, a matchmaker, somebody who is both. Newest first, the
/// way a messaging app lists them: a face, a name, the last line, its time,
/// and how many messages are waiting. No tabs by role — a person is a
/// person.
///
/// The list reads only the conversations' own documents; no message is
/// loaded until a conversation is opened.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  static const String route = '/chats';

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(ChatService.start());
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Whether [t] answers the search — by the other side's name or the last
  /// line.
  static bool matches(ChatThread t, String me, String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.titleFor(me).toLowerCase().contains(q) ||
        t.lastText.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('צ\'אטים'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                hintText: 'חיפוש בצ\'אטים',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'ניקוי',
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'new-chat',
        tooltip: 'שיחה חדשה',
        onPressed: () => NewChatSheet.show(context),
        child: const Icon(Icons.edit_square),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          ChatService.threads,
          ChatService.loaded,
        ]),
        builder: (BuildContext context, _) {
          final String me = ChatService.uid ?? '';
          final List<ChatThread> all = ChatService.threads.value;
          final List<ChatThread> shown = <ChatThread>[
            for (final ChatThread t in all)
              if (matches(t, me, _search.text)) t,
          ];
          if (all.isEmpty) {
            if (!ChatService.loaded.value && ChatService.uid != null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _EmptyChats(candidates: NewChatSheet.candidatesOf(context));
          }
          if (shown.isEmpty) {
            return const Center(child: Text('לא נמצאו שיחות'));
          }
          return AppRefreshIndicator(
            scope: RefreshScope.chats,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: shown.length,
              itemBuilder: (BuildContext context, int i) => _ThreadRow(
                key: ValueKey<String>(shown[i].id),
                thread: shown[i],
                me: me,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A face for a conversation: their picture, else a plain figure.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 26,
  });

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String? url = photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.softBlue,
      foregroundImage: url == null
          ? null
          : avatarImage(context, url, diameter: radius * 2),
      // No picture: a plain flat figure of a person, the same everywhere a
      // matchmaker or a friend has no photo.
      child: Icon(
        Icons.person_rounded,
        size: radius * 1.3,
        color: AppColors.white,
      ),
    );
  }
}

/// No conversation yet: what the list is for, and the people a first one can
/// be started with right here — a tap opens the conversation, ready to
/// write; nothing is created until the first message is sent.
class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.candidates});

  final List<ChatCandidate> candidates;

  static const int shown = 8;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ChatCandidate> first = candidates.take(shown).toList();
    return AppRefreshIndicator(
      scope: RefreshScope.chats,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 96),
        children: <Widget>[
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 44,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 10),
          Text(
            'עדיין אין שיחות',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'כאן יופיעו כל השיחות שלך — עם שדכנים ועם חברים שמנהלים כרטיס. '
            'שיחה אחת קבועה עם כל אחד.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (first.isNotEmpty) ...<Widget>[
            Text(
              'אפשר להתחיל שיחה עם',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            for (final ChatCandidate c in first)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ChatAvatar(name: c.name, radius: 22),
                title: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(c.why),
                trailing: const Icon(Icons.chat_bubble_outline_rounded),
                onTap: () => ChatLauncher.open(
                  context,
                  otherUid: c.uid,
                  otherName: c.name,
                ),
              ),
            if (candidates.length > shown)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => NewChatSheet.show(context),
                  child: Text('לכל ${candidates.length} האנשים'),
                ),
              ),
          ] else
            Text(
              'אפשר לפתוח שיחה עם השדכנים שרואים את הכרטיס שלך, עם חברים '
              'שהכרטיס האישי שלהם אצלך, ועם שדכנים שמורים אצלך באנשי הקשר.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({super.key, required this.thread, required this.me});

  final ChatThread thread;
  final String me;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool unread = thread.isUnreadFor(me);
    final int count = thread.unreadCountFor(me);
    final DateTime? at = thread.lastAt;
    final String title = thread.titleFor(me);
    return ListTile(
      leading: ChatAvatar(name: title, photoUrl: thread.photoFor(me)),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      subtitle: Text(
        thread.previewFor(me),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unread
            ? theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              )
            : null,
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (at != null)
            Text(
              AppDateUtils.notificationTime(at),
              style: theme.textTheme.labelSmall?.copyWith(
                color: unread ? theme.colorScheme.secondary : null,
                fontWeight: unread ? FontWeight.w800 : null,
              ),
            ),
          if (unread) ...<Widget>[
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: () => context.push(
        ChatService.routeTo(
          me: me,
          otherUid: thread.otherOf(me),
          theirName: title,
        ),
      ),
    );
  }
}

/// Somebody a conversation can be started with.
class ChatCandidate {
  const ChatCandidate({
    required this.uid,
    required this.name,
    required this.why,
  });

  final String uid;
  final String name;

  /// What ties the two of them: "השדכן/ית שלך", "כרטיס אישי", "שדכן/ית".
  final String why;
}

/// "שיחה חדשה" — the people a conversation can be started with, from every
/// tie this account has: the matchmakers who see (or asked for) the user's
/// own card, the friends whose personal card the user follows, and the
/// matchmakers they share with. Nothing is written until the first message.
abstract final class NewChatSheet {
  static List<ChatCandidate> candidatesOf(BuildContext context) {
    final Map<String, ChatCandidate> out = <String, ChatCandidate>{};
    void add(String uid, String name, String why) {
      if (uid.isEmpty || uid == ChatService.uid) return;
      out.putIfAbsent(uid, () => ChatCandidate(uid: uid, name: name, why: why));
    }

    final CardAccessProvider? access = _maybeRead<CardAccessProvider>(context);
    if (access != null) {
      for (final friend in matchmakerFriendsOf(access)) {
        final CardAccess? row = friend.row;
        if (row == null ||
            row.status == CardAccessStatus.blocked ||
            row.granteeUids.length > 1) {
          continue;
        }
        add(row.matchmakerUid, friend.name, 'משדכ/ת · הכרטיס שלך');
      }
    }
    final String? partner = PartnerSpace.partnerUid;
    if (partner != null)
      add(partner, PartnerSpace.partnerFirstName, 'מרחב זוגי');
    if (WorkspaceStore.matchmakerEnabled) {
      final PersonRepository? people = _maybeRead<PersonRepository>(context);
      for (final Person p in people?.getAll() ?? const <Person>[]) {
        final String? owner = p.cardOwnerUid;
        if (owner != null && !p.hidden) {
          add(owner, p.fullName, 'כרטיס אישי');
        }
      }
      for (final MapEntry<String, String> c
          in MatchmakerShares.connectedNames.entries) {
        add(c.key, c.value, 'שדכן/ית');
      }
    }
    // Matchmakers saved in this phone who use the app — for a single as
    // much as for a matchmaker: one conversation with each, whoever writes
    // first.
    if (access != null) {
      for (final CardHelper h in access.knownHelpers) {
        if (h.granteeUids.length > 1) continue;
        add(h.uid, access.nameInContacts(h.uid, h.name), 'שדכן/ית מאנשי הקשר');
      }
    }
    final List<ChatCandidate> list = out.values.toList()
      ..sort((ChatCandidate a, ChatCandidate b) => a.name.compareTo(b.name));
    return list;
  }

  static Future<void> show(BuildContext context) async {
    final List<ChatCandidate> list = candidatesOf(context);
    final ChatCandidate? picked = await showModalBottomSheet<ChatCandidate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (BuildContext sheet, ScrollController controller) =>
            list.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'אפשר לפתוח שיחה עם השדכנים שרואים את הכרטיס שלך, עם חברים '
                  'שהכרטיס האישי שלהם אצלך, ועם שדכנים שמורים אצלך באנשי הקשר.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.builder(
                controller: controller,
                itemCount: list.length + 1,
                itemBuilder: (BuildContext sheet, int i) => i == 0
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          'שיחה חדשה',
                          style: Theme.of(sheet).textTheme.titleMedium,
                        ),
                      )
                    : ListTile(
                        leading: ChatAvatar(name: list[i - 1].name, radius: 20),
                        title: Text(list[i - 1].name),
                        subtitle: Text(list[i - 1].why),
                        onTap: () => Navigator.of(sheet).pop(list[i - 1]),
                      ),
              ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await ChatLauncher.open(
      context,
      otherUid: picked.uid,
      otherName: picked.name,
    );
  }
}

/// Opens the one continuing conversation with [otherUid] — from a profile, a
/// card, an idea, a notice or the list of matchmakers. Nothing is written
/// until the first message; the same two accounts always reach the same
/// conversation.
abstract final class ChatLauncher {
  static Future<void> open(
    BuildContext context, {
    required String otherUid,
    required String otherName,
    String? ideaId,
  }) async {
    final String? me = await ChatService.me();
    if (!context.mounted) return;
    if (me == null || otherUid.isEmpty || otherUid == me) {
      AppNotice.show(
        context,
        'אפשר לפתוח צ\'אט אחרי ההתחברות לחשבון.',
        isError: true,
      );
      return;
    }
    await context.push(
      ChatService.routeTo(
        me: me,
        otherUid: otherUid,
        theirName: otherName,
        ideaId: ideaId,
      ),
    );
  }
}

/// One conversation, WhatsApp-like: bubbles, day chips, read marks, photos
/// and voice messages, cards and ideas as objects in the thread, and a
/// writing field at the foot. Opened about an idea, the composer carries its
/// context ("בנוגע לרעיון: יעל × אורי") — still the same conversation.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    this.initialRef,
    this.otherName,
    this.contextIdeaId,
  });

  final String chatId;

  /// The other side's name, for a chat that has no message yet (and so no
  /// document to read it from).
  final String? otherName;

  /// What the chat was opened about; sent with the next message.
  final ChatRef? initialRef;

  /// The shared idea the chat was opened from — its small context line.
  final String? contextIdeaId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  late final ChatMessagesController _messages = ChatMessagesController(
    widget.chatId,
  );
  ChatRef? _ref;
  bool _canSend = false;
  bool _sending = false;
  VoidCallback? _releaseProposals;

  @override
  void initState() {
    super.initState();
    _ref = widget.initialRef ?? _ideaRef(widget.contextIdeaId);
    ChatService.openChatId = widget.chatId;
    unawaited(_startService());
    _messages.addListener(_onMessages);
    ChatService.threads.addListener(_onThreads);
    _scroll.addListener(_onScroll);
    _text.addListener(() {
      final bool can = _text.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
  }

  /// "בנוגע לרעיון: יעל × אורי" for a shared idea opened from its card.
  static ChatRef? _ideaRef(String? id) {
    if (id == null || id.isEmpty) return null;
    final IdeaProposal? p = MatchmakerNetwork.proposal(id);
    final String label = p == null
        ? 'רעיון משותף'
        : '${p.candidateFirstName} × ${p.targetFirstName}';
    return ChatRef(kind: 'proposal', id: id, label: label);
  }

  /// The account is known before anything about the other side is read
  /// (a conversation opened from a push on a cold start comes here before
  /// the chat service has started).
  Future<void> _startService() async {
    await ChatService.me();
    unawaited(ChatService.start());
    if (!mounted) return;
    setState(() {});
    unawaited(_loadTheirCards());
  }

  /// A conversation opened before it existed — its listener was refused —
  /// starts listening the moment the list shows it exists: the other side
  /// wrote first while this one was open, and their message must arrive at
  /// once, not on the next visit.
  void _onThreads() {
    if (_messages.refused && ChatService.thread(widget.chatId) != null) {
      _messages.resubscribe();
    }
    if (mounted) setState(() {});
  }

  void _onMessages() {
    if (!mounted) return;
    setState(() {});
    if (_messages.messages.isNotEmpty) {
      unawaited(ChatService.markRead(widget.chatId));
    }
  }

  /// Near the top of what is loaded: the next older page.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      unawaited(_messages.loadOlder());
    }
  }

  /// While this chat is open, and only then: the ideas live, the cards the
  /// other side sent here, and a first page of what they share — so the "+"
  /// and a sentence like "פתח רעיון בין יעל לאורי" can find them.
  Future<void> _loadTheirCards() async {
    await MatchmakerNetwork.start();
    if (!mounted) return;
    _releaseProposals = MatchmakerNetwork.watchProposals();
    if (_ref?.kind == 'proposal' && _ref?.label == 'רעיון משותף') {
      final ChatRef? better = _ideaRef(_ref!.id);
      if (better != null && mounted) setState(() => _ref = better);
    }
    final String other = _other;
    if (other.isEmpty || PartnerSpace.isPartner(other)) return;
    await MatchmakerNetwork.loadSentFrom(other);
    if (WorkspaceStore.matchmakerEnabled &&
        MatchmakerShares.sharesWithMe(other)) {
      try {
        await MatchmakerNetwork.page(ownerUid: other, limit: 60);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _releaseProposals?.call();
    ChatService.threads.removeListener(_onThreads);
    if (ChatService.openChatId == widget.chatId) ChatService.openChatId = null;
    unawaited(ChatService.markRead(widget.chatId));
    _messages.removeListener(_onMessages);
    _messages.dispose();
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    if (!OfflineGuard.allow(context)) return;
    // "פתח רעיון בין יעל כהן לאורי לוי": done, not sent as words.
    if (WorkspaceStore.matchmakerEnabled && ChatIdeaCommand.looksLike(body)) {
      final bool handled = await _ideaFromText(body);
      if (handled) {
        if (mounted) _text.clear();
        return;
      }
    }
    await _deliver(body, ref: _ref);
  }

  String? get _myName => _maybeRead<UserProfileProvider>(context)?.fullName;

  /// Sends one line — creating the chat when this is its first message.
  Future<bool> _deliver(
    String body, {
    ChatRef? ref,
    ChatMessageType type = ChatMessageType.text,
    ChatOffer? offer,
  }) async {
    setState(() => _sending = true);
    final bool ok = await ChatService.send(
      widget.chatId,
      body,
      type: type,
      ref: ref,
      offer: offer,
      myName: _myName,
      theirName: _otherName,
    );
    if (!mounted) return ok;
    setState(() => _sending = false);
    if (!ok) {
      _failed();
      return false;
    }
    if (type == ChatMessageType.text) _text.clear();
    setState(() => _ref = null);
    _messages.resubscribe();
    return true;
  }

  void _failed() => AppNotice.show(
    context,
    'ההודעה לא נשלחה. אפשר לבדוק את החיבור ולנסות שוב.',
    isError: true,
  );

  /// The other side, read off the chat's id — known before the chat exists.
  String get _other =>
      ChatService.otherOfId(widget.chatId, ChatService.uid ?? '');

  String get _otherName {
    final String me = ChatService.uid ?? '';
    final ChatThread? t = ChatService.thread(widget.chatId);
    final String fromThread = (t?.names[t.otherOf(me)] ?? '').trim();
    if (fromThread.isNotEmpty) return fromThread;
    final String given = (widget.otherName ?? '').trim();
    if (given.isNotEmpty) return given;
    return MatchmakerNetwork.connectedNames[_other] ?? '';
  }

  /// Whether the other side keeps a personal card this account follows —
  /// the conversation can then carry "יש לי רעיון בשבילך".
  bool get _otherIsSingle {
    final CardAccessProvider? access = _maybeRead<CardAccessProvider>(context);
    if (access == null) return false;
    final PersonRepository? people = _maybeRead<PersonRepository>(context);
    return (people?.getAll() ?? const <Person>[]).any(
      (Person p) => p.cardOwnerUid == _other,
    );
  }

  /// The cards the other matchmaker shares with this one, or sent in here.
  List<SharedCard> get _theirCards {
    final String other = _other;
    // A partner's whole database is open in a couple space.
    if (PartnerSpace.isPartner(other)) return PartnerSpace.partnerCards.value;
    return <SharedCard>[
      for (final SharedCard c in <SharedCard>[
        ...MatchmakerNetwork.cards.value,
        ...MatchmakerNetwork.sentToMe.value,
      ])
        if (c.ownerUid == other) c,
    ];
  }

  /// An idea for [target]: between partners it opens at once on both phones;
  /// otherwise it is offered to the matchmaker who holds the card.
  Future<void> _ideaFor(SharedCard target, {Person? candidate}) async {
    if (PartnerSpace.isPartner(target.ownerUid)) {
      if (candidate == null) {
        await PartnerCardSheet.openIdea(context, target);
      } else {
        await PartnerCardSheet.openIdeaWith(
          context,
          mine: candidate,
          card: target,
        );
      }
      return;
    }
    await NetworkActions.propose(context, target, candidate: candidate);
  }

  /// Reads a free sentence as "open an idea between these two": the local
  /// reading first, Gemini only when it found nothing; then the names are
  /// resolved against real cards — one of mine, one the other matchmaker
  /// shares — asking whenever more than one card answers. Ends in the same
  /// preview every idea goes through before it is sent. False when the
  /// sentence was not such a request after all (it is sent as words).
  Future<bool> _ideaFromText(String body) async {
    final PersonRepository repo = context.read<PersonRepository>();
    List<NamePair> pairs = ChatIdeaCommand.parse(body);
    if (pairs.isEmpty) {
      final NamePair? ai = await AiChatCommand.extract(body);
      if (ai != null) pairs = <NamePair>[ai];
    }
    if (!mounted) return true;
    if (pairs.isEmpty) return false;
    final List<Person> mine = <Person>[
      for (final Person p in repo.getAll())
        if (!p.hidden && !SharedIdeas.isPartnersPerson(p.id)) p,
    ];
    final List<SharedCard> theirs = _theirCards;
    final Map<String, SharedCard> byKey = <String, SharedCard>{
      for (final SharedCard c in theirs) c.person.id: c,
    };
    List<Person> myMatches = const <Person>[];
    List<SharedCard> theirMatches = const <SharedCard>[];
    for (final NamePair pair in pairs) {
      for (final NamePair o in <NamePair>[pair, (pair.$2, pair.$1)]) {
        final List<Person> a = ChatIdeaCommand.resolve(o.$1, mine);
        final List<SharedCard> b = <SharedCard>[
          for (final Person p in ChatIdeaCommand.resolve(
            o.$2,
            theirs.map((SharedCard c) => c.person),
          ))
            byKey[p.id]!,
        ];
        if (a.isNotEmpty && b.isNotEmpty) {
          myMatches = a;
          theirMatches = b;
          break;
        }
      }
      if (myMatches.isNotEmpty) break;
    }
    if (myMatches.isEmpty) {
      final NamePair first = pairs.first;
      AppNotice.show(
        context,
        'לא מצאתי את "${first.$1}" ואת "${first.$2}" — אחד מהמאגר שלך ואחד '
        'מהכרטיסים ש$_otherName שיתף/ה איתך. אפשר לבדוק את השמות ולנסות שוב.',
        isError: true,
      );
      return true;
    }
    final Person? me = myMatches.length == 1
        ? myMatches.single
        : await _choose<Person>(
            'למי מהמאגר שלך התכוונת?',
            myMatches,
            (Person p) => p.fullName,
            (Person p) => sharedSummaryOf(p),
          );
    if (me == null || !mounted) return true;
    final SharedCard? target = theirMatches.length == 1
        ? theirMatches.single
        : await _choose<SharedCard>(
            'למי מהכרטיסים של $_otherName התכוונת?',
            theirMatches,
            (SharedCard c) => c.person.fullName,
            (SharedCard c) => sharedSummaryOf(c.person),
          );
    if (target == null || !mounted) return true;
    if (me.gender == target.person.gender) {
      AppNotice.show(
        context,
        '${me.firstName} ו${target.person.firstName} מאותו מגדר — לא נפתח רעיון.',
        isError: true,
      );
      return true;
    }
    await _ideaFor(target, candidate: me);
    return true;
  }

  Future<T?> _choose<T>(
    String title,
    List<T> options,
    String Function(T) name,
    String Function(T) details,
  ) => showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final T o in options)
            ListTile(
              title: Text(name(o)),
              subtitle: details(o).isEmpty ? null : Text(details(o)),
              onTap: () => Navigator.pop(context, o),
            ),
        ],
      ),
    ),
  );

  /// The "+" beside the field: a photo, a card from my database, an idea —
  /// without leaving the conversation.
  Future<void> _attach() async {
    final bool matchmaker = WorkspaceStore.matchmakerEnabled;
    final bool single = matchmaker && _otherIsSingle;
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('תמונה מהגלריה'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            if (single)
              ListTile(
                leading: const Icon(Icons.lightbulb_outline_rounded),
                title: Text('יש לי רעיון בשביל $_otherName'),
                subtitle: const Text('כרטיס של מועמד/ת מהמאגר שלך'),
                onTap: () => Navigator.pop(context, 'offer'),
              ),
            if (matchmaker) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('שליחת כרטיס מהמאגר שלי'),
                onTap: () => Navigator.pop(context, 'card'),
              ),
              if (!single)
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline_rounded),
                  title: Text('הצעת רעיון לכרטיס של $_otherName'),
                  onTap: () => Navigator.pop(context, 'idea'),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'אפשר גם לכתוב, למשל: "פתח רעיון בין יעל כהן לאורי לוי".',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'image':
        await _sendImage();
      case 'card':
        await _sendCard(offer: false);
      case 'offer':
        await _sendCard(offer: true);
      case 'idea':
        await _offerIdeaForTheirCard();
    }
  }

  Future<void> _sendImage() async {
    if (!OfflineGuard.allow(context)) return;
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    final bool ok = await ChatService.sendFile(
      widget.chatId,
      File(picked.path),
      type: ChatMessageType.image,
      myName: _myName,
      theirName: _otherName,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      _failed();
      return;
    }
    _messages.resubscribe();
  }

  Future<void> _recordVoice() async {
    if (!OfflineGuard.allow(context)) return;
    final VoiceRecording? recording = await VoiceRecorderSheet.record(
      context,
      maxDuration: const Duration(minutes: 5),
    );
    if (recording == null || !mounted) return;
    final File file = await VoiceNoteStore.fileFor(recording.fileName);
    if (!mounted) return;
    setState(() => _sending = true);
    final bool ok = await ChatService.sendFile(
      widget.chatId,
      file,
      type: ChatMessageType.voice,
      durationMs: recording.durationMs,
      myName: _myName,
      theirName: _otherName,
    );
    // The recording was made for this message only; the conversation keeps
    // its own copy.
    unawaited(VoiceNoteStore.delete(recording.fileName));
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      _failed();
      return;
    }
    _messages.resubscribe();
  }

  /// A card from my database, as an object in the conversation — or, to a
  /// single, "יש לי רעיון בשבילך" with the candidate's card.
  Future<void> _sendCard({required bool offer}) async {
    final Person? person = await PersonPickerSheet.show(
      context,
      title: offer
          ? 'איזה רעיון יש לך בשביל $_otherName?'
          : 'איזה כרטיס לשלוח ל$_otherName?',
      candidatePredicate: (Person p) =>
          !p.hidden &&
          !SharedIdeas.isPartnersPerson(p.id) &&
          p.cardOwnerUid != _other,
    );
    if (person == null || !mounted) return;
    if (!OfflineGuard.allow(context)) return;
    setState(() => _sending = true);
    final bool sent = await MatchmakerNetwork.sendCard(
      person: person,
      toUid: _other,
      myName: context.read<UserProfileProvider>().fullName ?? '',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (!sent) {
      AppNotice.show(
        context,
        'אפשר לשלוח רק כרטיס מלא — תמונה וטקסט — שמותר לשתף.',
        isError: true,
      );
      return;
    }
    NetworkSharing.noteSent(person.id);
    final ChatRef ref = ChatRef(
      kind: 'card',
      id: person.id,
      ownerUid: ChatService.uid,
      label: person.fullName,
    );
    if (offer) {
      await _deliver(
        'יש לי רעיון בשבילך',
        ref: ref,
        type: ChatMessageType.ideaOffer,
        offer: ChatOffer(
          personId: person.id,
          name: person.fullName,
          summary: sharedSummaryOf(person),
        ),
      );
      return;
    }
    await _deliver(
      'שלחתי לך את הכרטיס של ${person.fullName}',
      ref: ref,
      type: ChatMessageType.card,
    );
  }

  Future<void> _offerIdeaForTheirCard() async {
    final List<SharedCard> theirs = _theirCards;
    if (theirs.isEmpty) {
      AppNotice.show(context, '$_otherName עוד לא שיתף/ה איתך כרטיסים.');
      return;
    }
    final SharedCard? target = await _choose<SharedCard>(
      'לאיזה כרטיס של $_otherName?',
      theirs,
      (SharedCard c) => c.person.fullName,
      (SharedCard c) => sharedSummaryOf(c.person),
    );
    if (target == null || !mounted) return;
    await _ideaFor(target);
  }

  /// The single's answer to "יש לי רעיון בשבילך": approve, decline — with a
  /// reason only the matchmaker reads, or "דלג" — or ask the matchmaker in
  /// the ordinary composer.
  Future<void> _answerOffer(ChatMessage m, String answer) async {
    if (answer == 'ask') {
      setState(
        () => _ref = ChatRef(
          kind: 'ideaOffer',
          id: m.id,
          label: m.offer?.name ?? 'הרעיון',
        ),
      );
      _focus.requestFocus();
      return;
    }
    if (!OfflineGuard.allow(context)) return;
    String? reason;
    if (answer == 'declined') {
      reason = await _DeclineReasonDialog.ask(context);
      if (reason == null || !mounted) return; // dismissed: nothing sent
    }
    final bool ok = await ChatService.answerOffer(
      widget.chatId,
      m.id,
      approve: answer == 'approved',
      reason: reason,
    );
    if (!ok && mounted) _failed();
  }

  void _openRef(ChatRef ref) {
    final String me = ChatService.uid ?? '';
    switch (ref.kind) {
      case 'card':
      case 'person':
        final String? owner = ref.ownerUid;
        if (owner == null || owner == me) {
          if (WorkspaceStore.matchmakerEnabled) {
            context.push('/people/${ref.id}');
          }
        } else {
          SharedCardScreen.showSheet(
            context,
            ownerUid: owner,
            personId: ref.id,
          );
        }
      case 'proposal':
      case 'idea':
        ProposalScreen.showSheet(context, ref.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return ValueListenableBuilder<List<ChatThread>>(
      valueListenable: ChatService.threads,
      builder: (BuildContext context, _, _) {
        final String me = ChatService.uid ?? '';
        final ChatThread? thread = ChatService.thread(widget.chatId);
        final String other = _other;
        final String title = _otherName.isEmpty ? 'צ\'אט' : _otherName;
        final List<ChatMessage> list = _messages.messages;
        return Scaffold(
          backgroundColor: dark
              ? theme.scaffoldBackgroundColor
              : AppColors.page,
          appBar: AppBar(
            titleSpacing: 0,
            title: InkWell(
              onTap: other.isEmpty || !WorkspaceStore.matchmakerEnabled
                  ? null
                  : () => context.push('/known-matchmakers/$other'),
              child: Row(
                children: <Widget>[
                  ChatAvatar(
                    name: title,
                    photoUrl: thread?.photoFor(me),
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
          body: Column(
            children: <Widget>[
              Expanded(
                child: !_messages.loaded
                    ? const Center(child: CircularProgressIndicator())
                    : list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'עוד אין הודעות. השיחה תיפתח עם ההודעה הראשונה — '
                            'ותישאר אותה שיחה גם בהמשך.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      )
                    : _MessageList(
                        controller: _scroll,
                        messages: list,
                        me: me,
                        other: other,
                        thread: thread,
                        loadingOlder: _messages.loadingOlder,
                        onOpenRef: _openRef,
                        onAnswer: _answerOffer,
                      ),
              ),
              _Composer(
                controller: _text,
                focusNode: _focus,
                canSend: _canSend && !_sending,
                busy: _sending,
                refLabel: _ref == null
                    ? null
                    : _ref!.kind == 'proposal' || _ref!.kind == 'idea'
                    ? 'בנוגע לרעיון: ${_ref!.label}'
                    : 'לגבי: ${_ref!.label}',
                onClearRef: () => setState(() => _ref = null),
                onSend: _send,
                onAttach: _attach,
                onRecord: _recordVoice,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The thread itself: newest at the bottom, built lazily — only the bubbles
/// on screen exist — with a day chip wherever the day changes.
class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.controller,
    required this.messages,
    required this.me,
    required this.other,
    required this.thread,
    required this.loadingOlder,
    required this.onOpenRef,
    required this.onAnswer,
  });

  final ScrollController controller;

  /// Oldest first.
  final List<ChatMessage> messages;
  final String me;
  final String other;
  final ChatThread? thread;
  final bool loadingOlder;
  final ValueChanged<ChatRef> onOpenRef;
  final void Function(ChatMessage, String) onAnswer;

  static DateTime _day(ChatMessage m) {
    final DateTime at = m.at ?? DateTime.now();
    return DateTime(at.year, at.month, at.day);
  }

  @override
  Widget build(BuildContext context) {
    final int n = messages.length;
    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      itemCount: n + (loadingOlder ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (i == n) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        // Reversed: index 0 is the newest.
        final ChatMessage m = messages[n - 1 - i];
        final bool firstOfDay =
            i == n - 1 || _day(messages[n - 2 - i]) != _day(m);
        final Widget body = m.system
            ? ChatSystemLine(
                text: m.text,
                onTap: m.ref == null ? null : () => onOpenRef(m.ref!),
              )
            : _Bubble(
                message: m,
                mine: m.fromUid == me,
                me: me,
                read: m.fromUid == me && m.readBy(thread, other),
                onOpenRef: onOpenRef,
                onAnswer: (String a) => onAnswer(m, a),
              );
        return KeyedSubtree(
          key: ValueKey<String>(m.id),
          child: firstOfDay
              ? Column(
                  children: <Widget>[
                    _DayChip(day: _day(m)),
                    body,
                  ],
                )
              : body,
        );
      },
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int diff = today.difference(day).inDays;
    final String label = diff == 0
        ? 'היום'
        : diff == 1
        ? 'אתמול'
        : '${day.day}.${day.month}.${day.year}';
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.me,
    required this.read,
    required this.onOpenRef,
    required this.onAnswer,
  });

  final ChatMessage message;
  final bool mine;
  final String me;
  final bool read;
  final ValueChanged<ChatRef> onOpenRef;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color fill = mine
        ? (dark ? AppColors.primaryLightDarkDm : AppColors.primaryLight)
        : theme.colorScheme.surface;
    final DateTime? at = message.at;
    final ChatRef? ref = message.ref;
    final ChatMedia? media = message.media;
    final bool offer = message.type == ChatMessageType.ideaOffer;
    return Align(
      // As in WhatsApp in Hebrew: what I wrote on the left (the end), what I
      // received on the right (the start).
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(14),
              topEnd: const Radius.circular(14),
              bottomStart: Radius.circular(mine ? 14 : 4),
              bottomEnd: Radius.circular(mine ? 4 : 14),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (offer)
                _OfferBlock(
                  message: message,
                  mine: mine,
                  onOpenRef: onOpenRef,
                  onAnswer: onAnswer,
                )
              else ...<Widget>[
                if (ref != null &&
                    (ref.kind == 'ideaOffer' ||
                        ref.kind == 'proposal' &&
                            message.type == ChatMessageType.text))
                  _ContextLine(ref: ref, onTap: () => onOpenRef(ref))
                else if (ref != null)
                  ChatObject(chatRef: ref, me: me),
                if (media != null && message.type == ChatMessageType.image)
                  _ChatImage(media: media),
                if (media != null && message.type == ChatMessageType.voice)
                  _ChatVoice(media: media),
                if (message.text.isNotEmpty)
                  Text(message.text, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (at != null)
                    Text(
                      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                    ),
                  if (mine) ...<Widget>[
                    const SizedBox(width: 3),
                    Icon(
                      message.pending
                          ? Icons.schedule_rounded
                          : read
                          ? Icons.done_all_rounded
                          : Icons.done_rounded,
                      size: 13,
                      color: read
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small line over a message that answers something: "בנוגע לרעיון: …".
class _ContextLine extends StatelessWidget {
  const _ContextLine({required this.ref, required this.onTap});

  final ChatRef ref;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: ref.kind == 'ideaOffer' ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: BorderDirectional(
            start: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        child: Text(
          'בנוגע לרעיון: ${ref.label}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// "יש לי רעיון בשבילך": the candidate's card (opened inside the app, never
/// passed on), and — for the single, once — אשר | דחה | שאל את השדכן.
class _OfferBlock extends StatelessWidget {
  const _OfferBlock({
    required this.message,
    required this.mine,
    required this.onOpenRef,
    required this.onAnswer,
  });

  final ChatMessage message;
  final bool mine;
  final ValueChanged<ChatRef> onOpenRef;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChatOffer? offer = message.offer;
    final ChatRef? ref = message.ref;
    final String? answer = message.answer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.lightbulb_rounded,
              color: theme.colorScheme.secondary,
              size: 20,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message.text.isEmpty ? 'יש לי רעיון בשבילך' : message.text,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          ),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: ref == null ? null : () => onOpenRef(ref),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.badge_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          offer?.name ?? '',
                          style: theme.textTheme.titleSmall,
                        ),
                        if ((offer?.summary ?? '').isNotEmpty)
                          Text(
                            offer!.summary,
                            style: theme.textTheme.bodySmall,
                          ),
                        Text(
                          'לצפייה בכרטיס',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (answer == 'approved')
          Text(
            mine ? '✓ אישר/ה את הרעיון' : '✓ אישרת את הרעיון',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.primaryDark,
            ),
          )
        else if (answer == 'declined') ...<Widget>[
          Text(
            mine ? 'לא מתאים/ה לרעיון הזה' : 'דחית את הרעיון',
            style: theme.textTheme.labelLarge,
          ),
          if (mine && (message.answerReason ?? '').isNotEmpty)
            Text(
              'הסיבה: ${message.answerReason}',
              style: theme.textTheme.bodySmall,
            ),
        ] else if (mine)
          Text('ממתין לתשובה', style: theme.textTheme.labelMedium)
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              FilledButton(
                onPressed: () => onAnswer('approved'),
                child: const Text('אשר'),
              ),
              OutlinedButton(
                onPressed: () => onAnswer('declined'),
                child: const Text('דחה'),
              ),
              TextButton(
                onPressed: () => onAnswer('ask'),
                child: const Text('שאל את השדכן'),
              ),
            ],
          ),
      ],
    );
  }
}

/// "למה לא?" — optional, only the matchmaker reads it, and "דלג" is an
/// answer too: asked once, never again for the same idea. Null when
/// dismissed (nothing is sent).
class _DeclineReasonDialog extends StatefulWidget {
  const _DeclineReasonDialog();

  static Future<String?> ask(BuildContext context) => showDialog<String>(
    context: context,
    builder: (_) => const _DeclineReasonDialog(),
  );

  @override
  State<_DeclineReasonDialog> createState() => _DeclineReasonDialogState();
}

class _DeclineReasonDialogState extends State<_DeclineReasonDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('רוצה לכתוב למה?'),
    content: TextField(
      controller: _c,
      autofocus: true,
      minLines: 2,
      maxLines: 4,
      maxLength: 500,
      decoration: const InputDecoration(hintText: 'לא חובה — רק השדכן/ית יראו'),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(''),
        child: const Text('דלג'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_c.text.trim()),
        child: const Text('שליחה'),
      ),
    ],
  );
}

/// A photo in the conversation: a small thumbnail from the local copy, the
/// whole picture on a tap.
class _ChatImage extends StatelessWidget {
  const _ChatImage({required this.media});

  final ChatMedia media;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width * 0.6;
    final int px = (width * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: FutureBuilder<File?>(
        future: ChatService.mediaFile(media.path),
        builder: (BuildContext context, AsyncSnapshot<File?> snap) {
          final File? file = snap.data;
          if (file == null) {
            return SizedBox(
              width: width,
              height: width * 0.75,
              child: Center(
                child: snap.connectionState == ConnectionState.done
                    ? const Icon(Icons.broken_image_outlined)
                    : const CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  body: Center(
                    child: InteractiveViewer(child: Image.file(file)),
                  ),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                file,
                width: width,
                fit: BoxFit.cover,
                cacheWidth: px,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A voice message: play/pause and its length — the file downloaded once.
class _ChatVoice extends StatefulWidget {
  const _ChatVoice({required this.media});

  final ChatMedia media;

  @override
  State<_ChatVoice> createState() => _ChatVoiceState();
}

class _ChatVoiceState extends State<_ChatVoice> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _state;
  StreamSubscription<Duration>? _position;
  bool _playing = false;
  bool _loading = false;
  Duration _at = Duration.zero;

  @override
  void dispose() {
    unawaited(_state?.cancel());
    unawaited(_position?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player?.pause();
      return;
    }
    if (_player == null) {
      setState(() => _loading = true);
      final File? file = await ChatService.mediaFile(widget.media.path);
      if (!mounted) return;
      if (file == null) {
        setState(() => _loading = false);
        AppNotice.show(context, 'לא הצלחנו לטעון את ההקלטה', isError: true);
        return;
      }
      final AudioPlayer player = AudioPlayer();
      try {
        await player.setFilePath(file.path);
      } catch (_) {
        await player.dispose();
        if (mounted) {
          setState(() => _loading = false);
          AppNotice.show(context, 'לא ניתן לנגן את ההקלטה', isError: true);
        }
        return;
      }
      _player = player;
      _state = player.playerStateStream.listen((PlayerState s) {
        if (!mounted) return;
        if (s.processingState == ProcessingState.completed) {
          unawaited(player.pause());
          unawaited(player.seek(Duration.zero));
        }
        setState(() {
          _playing =
              s.playing && s.processingState != ProcessingState.completed;
        });
      });
      _position = player.positionStream.listen((Duration d) {
        if (mounted) setState(() => _at = d);
      });
      setState(() => _loading = false);
    }
    unawaited(_player!.play());
  }

  static String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Duration total = Duration(milliseconds: widget.media.durationMs ?? 0);
    final double progress = total.inMilliseconds == 0
        ? 0
        : (_at.inMilliseconds / total.inMilliseconds).clamp(0, 1).toDouble();
    return SizedBox(
      width: 220,
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: _playing ? 'השהיה' : 'השמעה',
            onPressed: _loading ? null : _toggle,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _clock(_playing || _at > Duration.zero ? _at : total),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.busy,
    required this.refLabel,
    required this.onClearRef,
    required this.onSend,
    required this.onAttach,
    required this.onRecord,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final bool busy;
  final String? refLabel;
  final VoidCallback onClearRef;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool empty = controller.text.trim().isEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            IconButton(
              tooltip: 'צירוף',
              onPressed: busy ? null : onAttach,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (refLabel != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.reply_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                refLabel!,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'בלי',
                              onPressed: onClearRef,
                              icon: const Icon(Icons.close_rounded, size: 16),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'הודעה',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (empty)
              IconButton.filledTonal(
                tooltip: 'הודעה קולית',
                onPressed: busy ? null : onRecord,
                icon: const Icon(Icons.mic_rounded),
              )
            else
              IconButton.filled(
                tooltip: 'שליחה',
                onPressed: canSend ? onSend : null,
                icon: const Icon(Icons.send_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
