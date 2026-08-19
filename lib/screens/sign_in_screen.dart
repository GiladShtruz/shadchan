import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/account_service.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The one-time invitation to connect an account.
///
/// **It is an invitation, not a gate.** Every matchmaker can walk past it, and
/// the app behind it works exactly as it did before — the database is local
/// either way. What signing in adds is a backup, a second device and the
/// community; what it must never add is a wall between somebody and the work
/// they opened the app to do.
///
/// **It is framed as keeping the database safe, not as registering.** "הרשמה"
/// asks somebody to give something; "שומרים על המאגר שלך" tells them what they
/// get. The difference is most of the reason people accept or refuse.
///
/// Shown once, to new matchmakers after onboarding and to existing ones on the
/// first launch after the update — see [SignInPromptStore] for why the gate is
/// a local flag rather than the account itself, and for how this screen gets
/// out of the way for somebody who is already signed in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  static const String headline = 'שומרים על המאגר שלך';

  static const String body =
      'התחברות מאפשרת לגבות את המאגר, לסנכרן אותו בין מכשירים ולהיות חלק '
      'מקהילת השדכנים.';

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Somebody who connected an account in an earlier version has already
    // answered this question; they simply answered it before the question
    // existed. Firebase resolves a moment after launch, so this runs on the
    // rebuild that follows rather than on the first frame.
    final AccountProvider account = context.watch<AccountProvider>();
    if (account.isSignedIn && !_leaving) {
      _leaving = true;
      SignInPromptStore.markAnswered();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _leave();
        }
      });
    }
  }

  Future<void> _signIn(Future<AccountSignInResult> Function() attempt) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AccountSignInResult result = await attempt();
    if (!mounted) {
      return;
    }

    switch (result.outcome) {
      case AccountSignInOutcome.canceled:
        // The account picker was closed. That is an answer to the picker, not
        // to this screen, so nothing is recorded and nothing is said.
        return;
      case AccountSignInOutcome.failure:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(result.message ?? 'לא הצלחנו להתחבר.')),
          );
        return;
      case AccountSignInOutcome.success:
        SignInPromptStore.markAnswered();
        unawaited(_adoptLocalData());
        _leave();
    }
  }

  /// Back to wherever this was opened from.
  ///
  /// Popping when it can matters because this screen has two lives: the
  /// one-time step in the entry flow, which has nothing behind it and must land
  /// on the home screen, and the "התחברות" button on the community areas, which
  /// should return the reader to the screen they were reading.
  void _leave() {
    if (!mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  /// Brings this device and the account into line, in the one order that can
  /// lose nothing.
  ///
  /// **Restore first, then sync.** `CloudSyncService.restore` only ever *adds*
  /// — an id that already exists locally is left alone, and the profile fills
  /// empty fields only — so it can never overwrite what is on this phone.
  /// `syncNow` then pushes the union upward against an empty fingerprint
  /// ledger, and an empty ledger means an empty `removed` list, so nothing that
  /// was already in the account is deleted either. A matchmaker who had a
  /// database here and a database there ends up with both.
  ///
  /// Unawaited on purpose: this is a backup, and the matchmaker should be on
  /// the home screen while it happens rather than watching a spinner.
  Future<void> _adoptLocalData() async {
    final SyncProvider sync = context.read<SyncProvider>();
    final PersonRepository people = context.read<PersonRepository>();
    final MatchRepository matches = context.read<MatchRepository>();
    final UserProfileProvider profile = context.read<UserProfileProvider>();

    await sync.restore(
      personRepo: people,
      matchRepo: matches,
      profile: profile,
    );
    await sync.sync(personRepo: people, matchRepo: matches, profile: profile);
  }

  Future<void> _continueWithout() async {
    final bool proceed = await ContinueWithoutAccountDialog.show(context);
    if (!mounted) {
      return;
    }
    if (!proceed) {
      return;
    }
    SignInPromptStore.markAnswered();
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AccountProvider account = context.watch<AccountProvider>();

    return Scaffold(
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
                    Icons.shield_outlined,
                    size: 56,
                    color: theme.brightness == Brightness.dark
                        ? theme.colorScheme.primary
                        : AppColors.primaryDark,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    SignInScreen.headline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    SignInScreen.body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Apple only where Apple's own flow exists, and first when it
                  // does: an iPhone already has an Apple account signed in, so
                  // it is the one-tap answer there, and Apple's guidelines put
                  // their button above the alternatives. See
                  // `AccountService.isAppleAvailable`.
                  if (account.isAppleAvailable) ...<Widget>[
                    _ProviderButton(
                      icon: Icons.apple,
                      label: 'המשך עם Apple',
                      busy: account.isBusy,
                      onPressed: () => _signIn(account.signInWithApple),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _ProviderButton(
                    icon: Icons.account_circle_outlined,
                    label: 'המשך עם Google',
                    busy: account.isBusy,
                    onPressed: () => _signIn(account.signIn),
                  ),
                  const SizedBox(height: 18),
                  // Quieter than the two above, and still a real, reachable
                  // way out. A skip that has to be hunted for is a dark
                  // pattern with extra steps.
                  TextButton(
                    onPressed: account.isBusy ? null : _continueWithout,
                    child: Text(
                      'המשך בלי להתחבר',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the two sign-in buttons, drawn identically so neither reads as the
/// recommended one.
class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 22),
      label: Text(label),
    );
  }
}

/// The second question, asked once, for somebody about to carry on locally.
///
/// **It says what is actually at stake and then lets them past.** The primary
/// button goes back to signing in because that is the recommendation; the
/// secondary one is not disguised, delayed or buried, because a matchmaker who
/// has now read the sentence and still wants to work locally has made an
/// informed decision and the app has no business arguing twice.
class ContinueWithoutAccountDialog extends StatelessWidget {
  const ContinueWithoutAccountDialog({super.key});

  static const String title = 'להמשיך בלי להתחבר?';

  static const String message =
      'המידע שלך נשמר כרגע רק במכשיר הזה. אם המכשיר יוחלף, יאבד או שהאפליקציה '
      'תימחק, המידע עלול ללכת לאיבוד. בנוסף, ללא התחברות לא ניתן לסנכרן את '
      'המאגר בין מכשירים או להשתתף בנתוני קהילת השדכנים.';

  /// True when the matchmaker chose to carry on without an account.
  static Future<bool> show(BuildContext context) async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => const ContinueWithoutAccountDialog(),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: const Text(title),
      content: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('התחברות ושמירת המאגר'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'בכל זאת להמשיך בלי להתחבר',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
