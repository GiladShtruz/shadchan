import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/network_screen.dart';
import 'package:shadchan/screens/partner_space_screen.dart';
import 'package:shadchan/services/partner_space.dart';
import 'package:shadchan/services/ai_chat_command.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/utils/chat_idea_command.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/chat_objects.dart';

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

/// "צ'אטים" — every conversation of this account, newest first, the way a
/// messaging app lists them: a face, a name, the last line, its time, and a
/// mark when something is unread.
///
/// Today that is the matchmakers this one is connected with — one continuing
/// chat each. The list is built for more kinds (a group of matchmakers, a
/// single) without changing shape.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  static const String route = '/chats';

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ChatService.start());
    unawaited(MatchmakerNetwork.start());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('צ\'אטים')),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          ChatService.threads,
          MatchmakerShares.rows,
        ]),
        builder: (BuildContext context, _) {
          final String? me = ChatService.uid ?? MatchmakerShares.uid;
          final List<ChatThread> threads = ChatService.threads.value;
          // Matchmakers who share with this one (either way) there is no
          // chat with yet, so a chat can be started from here too.
          final Set<String> withChat = <String>{
            if (me != null)
              for (final ChatThread t in threads) t.otherOf(me),
          };
          final List<MapEntry<String, String>> fresh =
              <MapEntry<String, String>>[
                if (me != null)
                  for (final MapEntry<String, String> c
                      in MatchmakerShares.connectedNames.entries)
                    if (!withChat.contains(c.key)) c,
              ];
          if (threads.isEmpty && fresh.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'צ\'אט נפתח עם שדכנים שאת/ה מכיר/ה — שיחה אחת מתמשכת '
                      'לכל הכרטיסים והרעיונות ביניכם.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => context.push('/known-matchmakers'),
                      child: const Text('לשדכנים שאני מכיר'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            children: <Widget>[
              for (final ChatThread t in threads)
                _ThreadRow(thread: t, me: me ?? ''),
              if (fresh.isNotEmpty) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'שדכנים שמשתפים',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                for (final MapEntry<String, String> c in fresh)
                  ListTile(
                    leading: _Initial(name: c.value),
                    title: Text(c.value.isEmpty ? 'שדכן/ית' : c.value),
                    subtitle: const Text('להתחיל שיחה'),
                    onTap: () async {
                      await context.push(
                        ChatService.routeTo(
                          me: me!,
                          otherUid: c.key,
                          theirName: c.value,
                        ),
                      );
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name, this.radius = 24});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String n = name.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.softBlue,
      child: Text(
        n.isEmpty ? '?' : n.characters.first,
        style: TextStyle(
          color: AppColors.primaryInk,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread, required this.me});

  final ChatThread thread;
  final String me;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool unread = thread.isUnreadFor(me);
    final DateTime? at = thread.lastAt;
    return ListTile(
      leading: _Initial(name: thread.titleFor(me)),
      title: Text(
        thread.titleFor(me),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      subtitle: Text(
        thread.lastText.isEmpty
            ? 'שיחה חדשה'
            : '${thread.lastFromUid == me ? 'את/ה: ' : ''}${thread.lastText}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (at != null)
            Text(
              AppDateUtils.notificationTime(at),
              style: theme.textTheme.labelSmall?.copyWith(
                color: unread ? theme.colorScheme.primary : null,
              ),
            ),
          if (unread) ...<Widget>[
            const SizedBox(height: 4),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
      onTap: () => context.push('/chats/${thread.id}'),
    );
  }
}

/// Opens the one continuing chat with [otherUid] — from a profile, a list of
/// matchmakers or a list of singles. Nothing is written until the first
/// message; the same pair always reaches the same conversation.
abstract final class ChatLauncher {
  static Future<void> open(
    BuildContext context, {
    required String otherUid,
    required String otherName,
    String kind = 'matchmakers',
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
        kind: kind,
      ),
    );
  }
}

/// One conversation, WhatsApp-like: bubbles, day chips, a writing field at
/// the foot. A message can carry what it is about ([ChatRef]) — a card or an
/// idea — so one thread holds months of them.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    this.initialRef,
    this.otherName,
    this.kind = 'matchmakers',
  });

  final String chatId;

  /// The other side's name, for a chat that has no message yet (and so no
  /// document to read it from).
  final String? otherName;

  /// `matchmakers`, `single` or `partners` — written when the first message
  /// creates the chat.
  final String kind;

  /// What the chat was opened about; sent with the next message.
  final ChatRef? initialRef;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _text = TextEditingController();

  /// Listened to only once the chat exists: a chat with no message yet
  /// cannot be read, and a refused listener would never recover.
  Stream<List<ChatMessage>>? _messages;
  ChatRef? _ref;
  bool _canSend = false;
  bool _sending = false;

  /// Whether the server answered whether this chat exists yet.
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _ref = widget.initialRef;
    ChatService.openChatId = widget.chatId;
    unawaited(ChatService.start());
    unawaited(_load());
    unawaited(_loadTheirCards());
    _text.addListener(() {
      final bool can = _text.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
  }

  VoidCallback? _releaseProposals;

  /// While this chat is open, and only then: the ideas live, the cards the
  /// other matchmaker sent here, and a first page of what they share — so
  /// the "+" and a sentence like "פתח רעיון בין יעל לאורי" can find them.
  Future<void> _loadTheirCards() async {
    await MatchmakerNetwork.start();
    if (!mounted) return;
    _releaseProposals = MatchmakerNetwork.watchProposals();
    final String other = _other;
    if (other.isEmpty || PartnerSpace.isPartner(other)) return;
    await MatchmakerNetwork.loadSentFrom(other);
    if (MatchmakerShares.sharesWithMe(other)) {
      try {
        await MatchmakerNetwork.page(ownerUid: other, limit: 60);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _releaseProposals?.call();
    if (ChatService.openChatId == widget.chatId) ChatService.openChatId = null;
    unawaited(ChatService.markRead(widget.chatId));
    _text.dispose();
    super.dispose();
  }

  /// Finds out whether the chat exists — opening an existing one at once,
  /// and a new one as an empty conversation ready for its first message.
  Future<void> _load() async {
    await ChatService.me();
    final bool exists = await ChatService.exists(widget.chatId);
    if (!mounted) return;
    setState(() {
      _checked = true;
      if (exists) _messages = ChatService.messages(widget.chatId);
    });
    if (exists) unawaited(ChatService.markRead(widget.chatId));
  }

  Future<void> _send() async {
    final String body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    if (!OfflineGuard.allow(context)) return;
    // "פתח רעיון בין יעל כהן לאורי לוי": done, not sent as words.
    if (ChatIdeaCommand.looksLike(body)) {
      final bool handled = await _ideaFromText(body);
      if (handled) {
        if (mounted) _text.clear();
        return;
      }
    }
    await _deliver(body, ref: _ref);
  }

  /// Sends one line — creating the chat when this is its first message.
  Future<bool> _deliver(String body, {ChatRef? ref}) async {
    final bool first = _messages == null;
    setState(() => _sending = true);
    final bool ok = await ChatService.send(
      widget.chatId,
      body,
      ref: ref,
      kind: widget.kind,
      myName: _maybeRead<UserProfileProvider>(context)?.fullName,
      theirName: _otherName,
    );
    if (!mounted) return ok;
    setState(() => _sending = false);
    if (!ok) {
      AppNotice.show(
        context,
        'ההודעה לא נשלחה. אפשר לבדוק את החיבור ולנסות שוב.',
        isError: true,
      );
      return false;
    }
    _text.clear();
    setState(() {
      _ref = null;
      if (first) _messages = ChatService.messages(widget.chatId);
    });
    return true;
  }

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

  /// The "+" beside the field: send one of my cards here, or offer an idea
  /// for one of theirs — without leaving the conversation.
  Future<void> _attach() async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('שליחת כרטיס מהמאגר שלי'),
              onTap: () => Navigator.pop(context, 'card'),
            ),
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
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'card') {
      final Person? person = await PersonPickerSheet.show(
        context,
        title: 'איזה כרטיס לשלוח ל$_otherName?',
        candidatePredicate: (Person p) =>
            !p.hidden && !SharedIdeas.isPartnersPerson(p.id),
      );
      if (person == null || !mounted) return;
      final bool sent = await MatchmakerNetwork.sendCard(
        person: person,
        toUid: _other,
        myName: context.read<UserProfileProvider>().fullName ?? '',
      );
      if (!mounted) return;
      if (!sent) {
        AppNotice.show(
          context,
          'אפשר לשלוח רק כרטיס מלא — תמונה וטקסט — שמותר לשתף.',
          isError: true,
        );
        return;
      }
      NetworkSharing.noteSent(person.id);
      await _deliver(
        'שלחתי לך את הכרטיס של ${person.fullName}',
        ref: ChatRef(
          kind: 'card',
          id: person.id,
          ownerUid: ChatService.uid,
          label: person.fullName,
        ),
      );
      return;
    }
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

  void _openRef(ChatRef ref) {
    final String me = ChatService.uid ?? '';
    switch (ref.kind) {
      case 'card':
        final String? owner = ref.ownerUid;
        if (owner == null || owner == me) {
          context.push('/people/${ref.id}');
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
        final String kind = thread?.kind ?? widget.kind;
        // The composer is always there: whether a message may be sent is the
        // server's answer (connected matchmakers, a single and a matchmaker
        // who keeps or asked for their card, partners), and a refusal is said
        // in words rather than by a field that silently vanished.
        return Scaffold(
          backgroundColor: dark
              ? theme.scaffoldBackgroundColor
              : AppColors.page,
          appBar: AppBar(
            titleSpacing: 0,
            title: InkWell(
              onTap: other.isEmpty || kind != 'matchmakers'
                  ? null
                  : () => context.push('/known-matchmakers/$other'),
              child: Row(
                children: <Widget>[
                  _Initial(name: title, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
          body: Column(
            children: <Widget>[
              Expanded(
                child: !_checked
                    ? const Center(child: CircularProgressIndicator())
                    : StreamBuilder<List<ChatMessage>>(
                        stream:
                            _messages ??
                            Stream<List<ChatMessage>>.value(
                              const <ChatMessage>[],
                            ),
                        builder: (BuildContext context, snap) {
                          final List<ChatMessage> list =
                              snap.data ?? const <ChatMessage>[];
                          if (snap.hasData && _messages != null) {
                            unawaited(ChatService.markRead(widget.chatId));
                          }
                          if (list.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  snap.hasData
                                      ? (_messages == null
                                            ? 'עוד אין הודעות. השיחה תיפתח עם ההודעה '
                                                  'הראשונה — ותישאר אותה שיחה גם '
                                                  'בהמשך.'
                                            : 'זו תחילת השיחה. כל הכרטיסים והרעיונות '
                                                  'ביניכם — כאן, בשיחה אחת.')
                                      : '',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            );
                          }
                          final List<Widget> items = <Widget>[];
                          DateTime? day;
                          for (final ChatMessage m in list) {
                            final DateTime at = m.at ?? DateTime.now();
                            final DateTime d = DateTime(
                              at.year,
                              at.month,
                              at.day,
                            );
                            if (day != d) {
                              day = d;
                              items.add(_DayChip(day: d));
                            }
                            if (m.system) {
                              final ChatRef? ref = m.ref;
                              items.add(
                                ChatSystemLine(
                                  text: m.text,
                                  onTap: ref == null
                                      ? null
                                      : () => _openRef(ref),
                                ),
                              );
                              continue;
                            }
                            items.add(
                              _Bubble(
                                message: m,
                                mine: m.fromUid == me,
                                me: me,
                              ),
                            );
                          }
                          return ListView(
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                            children: items.reversed.toList(),
                          );
                        },
                      ),
              ),
              _Composer(
                controller: _text,
                canSend: _canSend && !_sending,
                refLabel: _ref?.label,
                onClearRef: () => setState(() => _ref = null),
                onSend: _send,
                onAttach: _attach,
              ),
            ],
          ),
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
  const _Bubble({required this.message, required this.mine, required this.me});

  final ChatMessage message;
  final bool mine;
  final String me;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color fill = mine
        ? (dark ? AppColors.primaryLightDarkDm : AppColors.primaryLight)
        : theme.colorScheme.surface;
    final DateTime? at = message.at;
    final ChatRef? ref = message.ref;
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
              if (ref != null) ChatObject(chatRef: ref, me: me),
              Text(message.text, style: theme.textTheme.bodyLarge),
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
                          : Icons.done_rounded,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.canSend,
    required this.refLabel,
    required this.onClearRef,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool canSend;
  final String? refLabel;
  final VoidCallback onClearRef;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            IconButton(
              tooltip: 'כרטיס או רעיון',
              onPressed: onAttach,
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
                                'לגבי: $refLabel',
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
