import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/services/tips_service.dart';

/// The approval queue for community tips, as a panel.
///
/// A tip written by a matchmaker is **never** shown to anybody else until it is
/// approved here: it is created `pending`, the rotation only ever queries
/// approved tips, and `firestore.rules` refuses a client that tries to publish
/// straight into it. So this queue is the one gate between "somebody wrote a
/// tip" and "every matchmaker reads it", and it lives inside the feedback
/// console beside the reports rather than on a screen of its own.
///
/// Deliberately plain: approve or reject, nothing else. There is no reason
/// field, no editing and no version history, because a tip is two sentences —
/// a rejected one is rewritten, not negotiated.
///
/// The panel is only *drawn* for an administrator; every write it makes is
/// separately checked in `firestore.rules` against the same verified address,
/// so reaching it some other way produces a list of buttons that all fail.
class PendingTipsReview extends StatefulWidget {
  const PendingTipsReview({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 28),
  });

  final EdgeInsetsGeometry padding;

  @override
  State<PendingTipsReview> createState() => _PendingTipsReviewState();
}

class _PendingTipsReviewState extends State<PendingTipsReview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TipsProvider>().refreshPending();
      }
    });
  }

  Future<void> _review(CommunityTip tip, TipStatus status) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool done = await context.read<TipsProvider>().review(tip.id, status);
    if (!mounted || done) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('הפעולה נכשלה')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TipsProvider tips = context.watch<TipsProvider>();
    final AccountProvider account = context.watch<AccountProvider>();

    if (!account.isTipsAdmin) {
      return const _Message(text: 'החשבון המחובר אינו חשבון הניהול.');
    }
    if (tips.pending.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<TipsProvider>().refreshPending(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            _Message(
              text: tips.isBusy ? 'טוען…' : 'אין כרגע טיפים שממתינים לאישור.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<TipsProvider>().refreshPending(),
      child: ListView.separated(
        padding: widget.padding,
        itemCount: tips.pending.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return _WaitingBanner(count: tips.pending.length, theme: theme);
          }
          final CommunityTip tip = tips.pending[index - 1];
          return _PendingTipCard(
            tip: tip,
            onApprove: () => _review(tip, TipStatus.approved),
            onReject: () => _review(tip, TipStatus.rejected),
          );
        },
      ),
    );
  }
}

/// The standalone screen, kept for the settings row and the old route. It is
/// the same panel with a bar over it.
class TipsAdminScreen extends StatelessWidget {
  const TipsAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TipsProvider tips = context.watch<TipsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('אישור טיפים'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            tooltip: 'רענון',
            onPressed: tips.isBusy ? null : tips.refreshPending,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: const SafeArea(child: PendingTipsReview()),
    );
  }
}

/// "יש טיפים שממתינים לאישור" — the alert the queue raises the moment somebody
/// sends one, so the console says what is waiting before it is scrolled.
class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner({required this.count, required this.theme});

  final int count;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.notifications_active_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? 'טיפ אחד ממתין לאישור. עד שיאושר הוא לא מוצג לאף שדכן.'
                  : '$count טיפים ממתינים לאישור. עד שיאושרו הם לא מוצגים '
                        'לאף שדכן.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingTipCard extends StatelessWidget {
  const _PendingTipCard({
    required this.tip,
    required this.onApprove,
    required this.onReject,
  });

  final CommunityTip tip;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            tip.text,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 8),
          Text(
            tip.authorName.isEmpty ? 'ללא שם' : tip.authorName,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('אישור'),
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onReject,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                child: const Text('דחייה'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
