import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/services/tips_service.dart';

/// The approval queue for community tips.
///
/// Deliberately plain: approve or reject, nothing else. There is no reason
/// field, no editing and no version history, because a tip is two sentences —
/// a rejected one is rewritten, not negotiated.
///
/// The screen is only *offered* to the administrator's account; every write it
/// makes is separately checked in `firestore.rules` against the same verified
/// address, so reaching this page some other way produces a list of buttons
/// that all fail.
class TipsAdminScreen extends StatefulWidget {
  const TipsAdminScreen({super.key});

  @override
  State<TipsAdminScreen> createState() => _TipsAdminScreenState();
}

class _TipsAdminScreenState extends State<TipsAdminScreen> {
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
      body: SafeArea(
        child: !account.isTipsAdmin
            ? _Message(theme: theme, text: 'החשבון המחובר אינו חשבון הניהול.')
            : tips.pending.isEmpty
            ? _Message(
                theme: theme,
                text: tips.isBusy ? 'טוען…' : 'אין כרגע טיפים שממתינים לאישור.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                itemCount: tips.pending.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (BuildContext context, int index) {
                  final CommunityTip tip = tips.pending[index];
                  return _PendingTipCard(
                    tip: tip,
                    onApprove: () => _review(tip, TipStatus.approved),
                    onReject: () => _review(tip, TipStatus.rejected),
                  );
                },
              ),
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
  const _Message({required this.theme, required this.text});

  final ThemeData theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
