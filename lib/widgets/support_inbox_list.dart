import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/support_chat_sheet.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/support_inbox_provider.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';

/// Reports and answers, on the notifications page above the reminders.
///
/// **Support news is notification news.** A reply from the app is exactly the
/// kind of thing the bell already stands for — something that happened, that
/// somebody should look at, that is not on any screen they were going to visit
/// anyway. Putting it anywhere else would have meant a second inbox nobody
/// checks; there is only one bell in this app, and this is now under it.
///
/// It draws nothing at all for the ordinary case: a matchmaker who has never
/// sent a report, and an administrator with an empty console, both see the
/// reminders exactly as before.
class SupportInboxList extends StatefulWidget {
  const SupportInboxList({super.key, this.onOpen});

  /// Runs before the sheet opens — the panel uses it to close itself first.
  final VoidCallback? onOpen;

  @override
  State<SupportInboxList> createState() => _SupportInboxListState();
}

class _SupportInboxListState extends State<SupportInboxList> {
  @override
  void initState() {
    super.initState();
    // Drawn is read. This list only ever appears on the notifications page and
    // in the panel behind the bell, and both of those are somebody looking —
    // so the badge clears here rather than asking for a second gesture that
    // means "yes, I did look at the thing I am looking at".
    //
    // After the frame, because it notifies listeners and this is one of them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SupportInboxProvider>().markAllSeen();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SupportInboxProvider inbox = context.watch<SupportInboxProvider>();
    final bool isAdmin = context.watch<AccountProvider>().isSupportAdmin;

    final List<SupportReport> unanswered = isAdmin
        ? inbox.newReports
              .where((SupportReport report) => !report.hasConversation)
              .toList()
        : const <SupportReport>[];
    if (unanswered.isEmpty && inbox.threads.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            isAdmin ? 'פניות שהגיעו' : 'פניות ותשובות',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final SupportReport report in unanswered)
          _SupportRow(
            report: report,
            unread: true,
            isAdmin: isAdmin,
            onOpen: widget.onOpen,
          ),
        for (final SupportThread thread in inbox.threads)
          _SupportRow(
            report: thread.report,
            unread: thread.unread,
            isAdmin: isAdmin,
            onOpen: widget.onOpen,
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({
    required this.report,
    required this.unread,
    required this.isAdmin,
    required this.onOpen,
  });

  final SupportReport report;
  final bool unread;
  final bool isAdmin;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime when = report.lastMessageAt ?? report.createdAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: unread
            ? AppColors.secondary.withValues(alpha: 0.12)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            onOpen?.call();
            SupportChatSheet.show(context, report, asAdmin: isAdmin);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: unread
                    ? AppColors.secondary.withValues(alpha: 0.4)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  report.hasConversation
                      ? Icons.forum_outlined
                      : Icons.mark_email_unread_outlined,
                  size: 20,
                  color: unread
                      ? AppColors.secondary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _title(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        report.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppDateUtils.formatDateShort(when),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
    );
  }

  String _title() {
    if (isAdmin) {
      final String name = report.authorName.trim();
      final String who = name.isEmpty ? 'שולח לא מזוהה' : name;
      return report.hasConversation ? 'שיחה עם $who' : 'פנייה חדשה מ$who';
    }
    return report.lastMessageFromAdmin
        ? 'תשובה מצוות שדכן'
        : 'הפנייה שלך — שיחה פתוחה';
  }
}
