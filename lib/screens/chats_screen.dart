import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/models/matchmaker_connection.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/services/matchmaker_connections.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';

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
    unawaited(MatchmakerConnections.start());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('צ\'אטים')),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          ChatService.threads,
          MatchmakerConnections.connections,
        ]),
        builder: (BuildContext context, _) {
          final String? me = ChatService.uid ?? MatchmakerConnections.uid;
          final List<ChatThread> threads = ChatService.threads.value;
          // Connected matchmakers there is no chat with yet, so a chat can be
          // started from here too.
          final Set<String> withChat = <String>{
            if (me != null)
              for (final ChatThread t in threads) t.otherOf(me),
          };
          final List<MatchmakerConnection> fresh = <MatchmakerConnection>[
            if (me != null)
              for (final MatchmakerConnection c
                  in MatchmakerConnections.connections.value)
                if (c.isConnected && !withChat.contains(c.otherOf(me))) c,
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
                      'צ\'אט נפתח עם שדכנים שמחוברים אליך — שיחה אחת מתמשכת '
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
                    'שדכנים מחוברים',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                for (final MatchmakerConnection c in fresh)
                  ListTile(
                    leading: _Initial(name: c.names[c.otherOf(me!)] ?? ''),
                    title: Text(c.names[c.otherOf(me)] ?? 'שדכן/ית'),
                    subtitle: const Text('להתחיל שיחה'),
                    onTap: () async {
                      final String? id = await ChatService.openDirect(
                        otherUid: c.otherOf(me),
                        myName: c.names[me] ?? '',
                        theirName: c.names[c.otherOf(me)] ?? '',
                      );
                      if (id != null && context.mounted) {
                        await context.push('/chats/$id');
                      }
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

/// One conversation, WhatsApp-like: bubbles, day chips, a writing field at
/// the foot. A message can carry what it is about ([ChatRef]) — a card or an
/// idea — so one thread holds months of them.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId, this.initialRef});

  final String chatId;

  /// What the chat was opened about; sent with the next message.
  final ChatRef? initialRef;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _text = TextEditingController();
  late final Stream<List<ChatMessage>> _messages = ChatService.messages(
    widget.chatId,
  );
  ChatRef? _ref;
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _ref = widget.initialRef;
    ChatService.openChatId = widget.chatId;
    unawaited(ChatService.start());
    unawaited(ChatService.markRead(widget.chatId));
    _text.addListener(() {
      final bool can = _text.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
  }

  @override
  void dispose() {
    if (ChatService.openChatId == widget.chatId) ChatService.openChatId = null;
    unawaited(ChatService.markRead(widget.chatId));
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String body = _text.text.trim();
    if (body.isEmpty) return;
    if (!OfflineGuard.allow(context)) return;
    final bool ok = await ChatService.send(widget.chatId, body, ref: _ref);
    if (!ok || !mounted) return;
    _text.clear();
    setState(() => _ref = null);
  }

  void _openRef(ChatRef ref) {
    switch (ref.kind) {
      case 'card':
        final String? owner = ref.ownerUid;
        if (owner != null) context.push('/network/card/$owner/${ref.id}');
      case 'proposal':
      case 'idea':
        context.push('/network/proposals/${ref.id}');
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
        final String other = thread?.otherOf(me) ?? '';
        final String title = thread?.titleFor(me) ?? 'צ\'אט';
        final bool connected =
            thread == null ||
            thread.type != 'direct' ||
            MatchmakerNetwork.connectedNames.containsKey(other);
        return Scaffold(
          backgroundColor: dark
              ? theme.scaffoldBackgroundColor
              : const Color(0xFFF3EFE7),
          appBar: AppBar(
            titleSpacing: 0,
            title: InkWell(
              onTap: other.isEmpty
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
                child: StreamBuilder<List<ChatMessage>>(
                  stream: _messages,
                  builder: (BuildContext context, snap) {
                    final List<ChatMessage> list =
                        snap.data ?? const <ChatMessage>[];
                    if (snap.hasData) {
                      unawaited(ChatService.markRead(widget.chatId));
                    }
                    if (list.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            snap.hasData
                                ? 'זו תחילת השיחה. כל הכרטיסים והרעיונות ביניכם — '
                                      'כאן, בשיחה אחת.'
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
                      final DateTime d = DateTime(at.year, at.month, at.day);
                      if (day != d) {
                        day = d;
                        items.add(_DayChip(day: d));
                      }
                      items.add(
                        _Bubble(
                          message: m,
                          mine: m.fromUid == me,
                          onRef: _openRef,
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
              if (connected)
                _Composer(
                  controller: _text,
                  canSend: _canSend,
                  refLabel: _ref?.label,
                  onClearRef: () => setState(() => _ref = null),
                  onSend: _send,
                )
              else
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'החיבור ביניכם הסתיים — אפשר לקרוא את השיחה, לא לשלוח בה.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
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
  const _Bubble({
    required this.message,
    required this.mine,
    required this.onRef,
  });

  final ChatMessage message;
  final bool mine;
  final ValueChanged<ChatRef> onRef;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color fill = mine
        ? (dark ? const Color(0xFF2E4A57) : const Color(0xFFDCEBF2))
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
              if (ref != null)
                InkWell(
                  onTap: () => onRef(ref),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: BorderDirectional(
                        start: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      'לגבי: ${ref.label}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
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
  });

  final TextEditingController controller;
  final bool canSend;
  final String? refLabel;
  final VoidCallback onClearRef;
  final VoidCallback onSend;

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
