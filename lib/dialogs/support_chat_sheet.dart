import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// The conversation on one report, drawn the same way for both sides.
///
/// **One screen, two readers, and that is the point.** An administrator opens
/// it from the console or from a notification to ask "which screen was that
/// on?"; the person who sent the report opens it from the notifications page to
/// read the answer. Making them two screens would have meant two places to keep
/// the same conversation correct.
///
/// The report itself sits at the top, quoted and unchangeable, because a thread
/// with no subject is a thread neither side can place a week later.
abstract final class SupportChatSheet {
  static Future<void> show(
    BuildContext context,
    SupportReport report, {
    required bool asAdmin,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) =>
          _SupportChat(report: report, asAdmin: asAdmin),
    );
  }
}

class _SupportChat extends StatefulWidget {
  const _SupportChat({required this.report, required this.asAdmin});

  final SupportReport report;
  final bool asAdmin;

  @override
  State<_SupportChat> createState() => _SupportChatState();
}

class _SupportChatState extends State<_SupportChat> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final DateFormat _time = DateFormat('dd.MM · HH:mm');

  List<SupportMessage>? _messages;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<SupportMessage> messages = await SupportService.fetchMessages(
      widget.report.id,
    );
    if (!mounted) {
      return;
    }
    setState(() => _messages = messages);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  void _jumpToEnd() {
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  Future<void> _send() async {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    final bool ok = await SupportService.sendMessage(
      reportId: widget.report.id,
      text: text,
      fromAdmin: widget.asAdmin,
      authorName: widget.asAdmin
          ? ''
          : context.read<UserProfileProvider>().name ?? '',
    );
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    if (!ok) {
      AppNotice.show(
        context,
        'ההודעה לא נשלחה. כדאי לנסות שוב כשיש חיבור לאינטרנט.',
        isError: true,
      );
      return;
    }
    _controller.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<SupportMessage>? messages = _messages;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.support_agent_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.asAdmin
                          ? 'שיחה עם ${widget.report.authorName.isEmpty ? 'שולח הפנייה' : widget.report.authorName}'
                          : 'שיחה עם צוות שדכן',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _QuotedReport(report: widget.report),
            Expanded(
              child: messages == null
                  ? const Center(child: CircularProgressIndicator())
                  : messages.isEmpty
                  ? _Empty(asAdmin: widget.asAdmin, theme: theme)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                      itemCount: messages.length,
                      itemBuilder: (BuildContext context, int index) {
                        final SupportMessage message = messages[index];
                        return _MessageBubble(
                          message: message,
                          mine: message.fromAdmin == widget.asAdmin,
                          timestamp: _time.format(message.createdAt),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: SupportService.maxMessageLength,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: widget.asAdmin
                            ? 'מה לשאול או להשיב?'
                            : 'אפשר להוסיף פרטים או לענות',
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'שליחה',
                    onPressed: _sending || _controller.text.trim().isEmpty
                        ? null
                        : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The report the thread is about, quoted once at the top.
class _QuotedReport extends StatelessWidget {
  const _QuotedReport({required this.report});

  final SupportReport report;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.3 : 0.45,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            <String>[
              report.kind.label,
              AppDateUtils.formatDateShort(report.createdAt),
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            report.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.timestamp,
  });

  final SupportMessage message;
  final bool mine;
  final String timestamp;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: mine
                  ? theme.colorScheme.primaryContainer.withValues(
                      alpha: dark ? 0.45 : 0.7,
                    )
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: dark ? 0.5 : 0.75,
                    ),
              border: Border.all(
                color: mine
                    ? theme.colorScheme.primary.withValues(alpha: 0.28)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!mine && message.authorName.isNotEmpty) ...<Widget>[
                  Text(
                    message.authorName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(message.text),
                const SizedBox(height: 3),
                Text(
                  timestamp,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.asAdmin, required this.theme});

  final bool asAdmin;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          asAdmin
              ? 'עוד לא נכתב כאן כלום. אפשר לשאול את מי ששלח את הפנייה מה '
                    'בדיוק קרה — ההודעה תופיע אצלו בעמוד ההתראות.'
              : 'עוד לא נכתב כאן כלום. אם נצטרך פרטים נוספים נכתוב לכם כאן, '
                    'ואפשר גם להוסיף מיוזמתכם.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
