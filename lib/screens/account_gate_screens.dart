import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/account_dialogs.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/services/account_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// The shape the three account gates share: an icon, a heading, a sentence
/// and the buttons, centred on paper.
class _GateScaffold extends StatelessWidget {
  const _GateScaffold({
    required this.icon,
    required this.title,
    required this.body,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Icon(
                      icon,
                      size: 52,
                      color: theme.brightness == Brightness.dark
                          ? theme.colorScheme.primary
                          : AppColors.primaryDark,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 26),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _quiet(BuildContext context, String label, VoidCallback? onPressed) {
  final ThemeData theme = Theme.of(context);
  return TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: theme.colorScheme.onSurfaceVariant,
    ),
    child: Text(label),
  );
}

/// "טוענים את המאגר שלך" — a phone signed in to an account it has never read.
///
/// Without this, the first thing a second phone showed was an empty database
/// and a request to introduce yourself — the profile is part of the account
/// too, and it had not arrived yet. It waits for the account to be read once;
/// after that every launch opens straight away, offline included.
class AccountLoadingScreen extends StatefulWidget {
  const AccountLoadingScreen({super.key});

  /// Set when the matchmaker chose to go on without waiting, for this launch.
  static bool skipped = false;

  @override
  State<AccountLoadingScreen> createState() => _AccountLoadingScreenState();
}

class _AccountLoadingScreenState extends State<AccountLoadingScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() => _failed = false);
    final SyncProvider sync = context.read<SyncProvider>();
    await sync.start();
    if (!mounted) {
      return;
    }
    if (sync.initialPullDone) {
      context.go('/home');
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_failed) {
      return const _GateScaffold(
        icon: Icons.cloud_download_outlined,
        title: 'טוענים את המאגר שלך',
        body: 'רק בפעם הראשונה במכשיר הזה. אחר כך הכול נפתח מיד, גם בלי חיבור.',
        children: <Widget>[Center(child: CircularProgressIndicator())],
      );
    }
    return _GateScaffold(
      icon: Icons.cloud_off_outlined,
      title: 'לא הצלחנו לטעון את המאגר',
      body: 'כדאי לוודא שיש חיבור לאינטרנט ולנסות שוב.',
      children: <Widget>[
        FilledButton(
          onPressed: _load,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('ניסיון חוזר'),
        ),
        const SizedBox(height: 6),
        _quiet(context, 'להמשיך בלי לחכות', () {
          AccountLoadingScreen.skipped = true;
          context.go('/home');
        }),
        _quiet(
          context,
          'התנתקות',
          () => AccountDialogs.confirmSignOut(context),
        ),
      ],
    );
  }
}

/// "אימות כתובת המייל" — an account made with an address and a password,
/// until the address is shown to belong to whoever typed it.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The link is opened in a mail app or a browser; coming back is the moment
  /// to ask whether it worked.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_check(quiet: true));
    }
  }

  Future<void> _check({bool quiet = false}) async {
    if (_checking) {
      return;
    }
    final OverlayState? notices = AppNotice.capture(context);
    setState(() => _checking = true);
    final bool verified = await context
        .read<AccountProvider>()
        .refreshVerification();
    if (!mounted) {
      return;
    }
    setState(() => _checking = false);
    if (verified) {
      context.go('/home');
    } else if (!quiet) {
      AppNotice.showOn(
        notices,
        'הכתובת עדיין לא אומתה. כדאי לבדוק גם בתיקיית הספאם.',
      );
    }
  }

  Future<void> _resend() async {
    final OverlayState? notices = AppNotice.capture(context);
    final AccountSignInResult result = await context
        .read<AccountProvider>()
        .resendVerification();
    AppNotice.showOn(
      notices,
      result.outcome == AccountSignInOutcome.success
          ? 'שלחנו שוב.'
          : result.message ?? 'לא הצלחנו לשלוח את המייל.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final AccountProvider account = context.watch<AccountProvider>();
    final String email = account.accountEmail ?? 'הכתובת שלך';
    return _GateScaffold(
      icon: Icons.mark_email_unread_outlined,
      title: 'אימות כתובת המייל',
      body:
          'שלחנו קישור לאימות אל $email. אחרי הלחיצה עליו אפשר לחזור לכאן '
          'ולהמשיך.',
      children: <Widget>[
        FilledButton(
          onPressed: _checking ? null : () => _check(),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('אימתתי — להמשיך'),
        ),
        const SizedBox(height: 6),
        _quiet(context, 'שליחת המייל שוב', account.isBusy ? null : _resend),
        _quiet(
          context,
          'התנתקות',
          () => AccountDialogs.confirmSignOut(context),
        ),
      ],
    );
  }
}

/// "החשבון מתוזמן למחיקה" — signing in to an account inside its 30 days of
/// grace. Restoring takes it out of deletion and opens it as it was.
class AccountRecoveryScreen extends StatefulWidget {
  const AccountRecoveryScreen({super.key});

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  bool _restoring = false;

  Future<void> _restore() async {
    final OverlayState? notices = AppNotice.capture(context);
    setState(() => _restoring = true);
    final bool done = await context.read<AccountProvider>().cancelDeletion();
    if (!mounted) {
      return;
    }
    setState(() => _restoring = false);
    if (!done) {
      AppNotice.showOn(
        notices,
        'לא הצלחנו לשחזר כרגע. כדאי לבדוק את החיבור לאינטרנט ולנסות שוב.',
      );
      return;
    }
    unawaited(context.read<SyncProvider>().start());
    context.go('/home');
    AppNotice.showOn(notices, 'החשבון שוחזר. ברוך שובך!');
  }

  @override
  Widget build(BuildContext context) {
    final AccountProvider account = context.watch<AccountProvider>();
    final DateTime? due = account.deletionDue;
    return _GateScaffold(
      icon: Icons.restore_rounded,
      title: 'החשבון מתוזמן למחיקה',
      body: due == null
          ? 'ביקשת למחוק את החשבון. אפשר לשחזר אותו עכשיו, וכל המאגר יחזור.'
          : 'ביקשת למחוק את החשבון, והוא יימחק לצמיתות ב־'
                '${AccountDialogs.dueLabel(due)}. אפשר לשחזר אותו עכשיו, וכל '
                'המאגר יחזור.',
      children: <Widget>[
        FilledButton(
          onPressed: _restoring ? null : _restore,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _restoring
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('שחזור החשבון'),
        ),
        const SizedBox(height: 6),
        _quiet(
          context,
          'התנתקות',
          () => AccountDialogs.confirmSignOut(context),
        ),
        _quiet(
          context,
          'מחיקה לצמיתות עכשיו',
          () => AccountDialogs.confirmDeleteNow(context),
        ),
      ],
    );
  }
}
