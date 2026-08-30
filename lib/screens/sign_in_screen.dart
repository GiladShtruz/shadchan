import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/account_service.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// The way in. Everybody comes through here, once.
///
/// **It used to be an invitation and it is a gate now.** The app was
/// local-first in the strongest sense: the database lived in Hive, an account
/// was optional, and this screen offered one with a way past it. That has a
/// cost nobody sees until it lands on them — a phone that is lost, replaced or
/// wiped takes years of a matchmaker's work with it, and there is nothing
/// anybody can do about it afterwards. It also makes "whose data is this?"
/// unanswerable, which is the other half of why this changed: with an account
/// behind every launch, everything in the app belongs to somebody, and the
/// somebody can change — see [AccountProvider.signOut] and the profile's own
/// account section.
///
/// **Three ways in, and no fourth.** Google and Apple where Apple's own flow
/// exists, and an address with a password for everybody who wants neither. The
/// third one matters more than it looks: a matchmaker with no Google account
/// and an Android phone had, before it, no way into the app at all.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  static const String headline = 'מתחילים בחשבון';

  static const String body =
      'החשבון שומר את המאגר שלך, מסנכרן אותו בין מכשירים ומחבר אותך לקהילת '
      'השדכנים. אפשר להתחבר בכל אחת מהדרכים האלה.';

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

/// Which question the address form is asking.
enum _EmailMode { register, signIn }

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  /// Registration first: this screen is on the path of somebody opening the app
  /// for the first time far more often than of somebody arriving on a second
  /// phone. The other question is one tap away and says so plainly.
  _EmailMode _mode = _EmailMode.register;

  bool _showPassword = false;

  /// Set once a button has been pressed with something missing, so nobody is
  /// scolded for a form they have not finished typing. Same rule as the
  /// onboarding form.
  bool _showErrors = false;

  bool _leaving = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Somebody who connected an account in an earlier version has already
    // answered this; they simply answered it before the question was
    // compulsory. Firebase resolves a moment after launch, so this runs on the
    // rebuild that follows rather than on the first frame.
    final AccountProvider account = context.watch<AccountProvider>();
    if (account.isSignedIn && !_leaving) {
      _leaving = true;
      SignInPromptStore.markSignedIn();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _leave();
        }
      });
    }
  }

  // --- The three ways in ---------------------------------------------------

  Future<void> _signIn(Future<AccountSignInResult> Function() attempt) async {
    final OverlayState? notices = AppNotice.capture(context);
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
        AppNotice.showOn(notices, result.message ?? 'לא הצלחנו להתחבר.');
        return;
      case AccountSignInOutcome.success:
        SignInPromptStore.markSignedIn();
        unawaited(_adoptLocalData());
        _leave();
    }
  }

  Future<void> _submitEmail(AccountProvider account) async {
    if (_emailProblem != null || _passwordProblem != null) {
      setState(() => _showErrors = true);
      FocusScope.of(context).unfocus();
      return;
    }
    setState(() => _showErrors = false);
    FocusScope.of(context).unfocus();

    final String email = _emailController.text.trim();
    final String password = _passwordController.text;
    await _signIn(() {
      return _mode == _EmailMode.register
          ? account.registerWithEmail(email: email, password: password)
          : account.signInWithEmail(email: email, password: password);
    });
  }

  /// The one thing an address-and-password account needs that the two provider
  /// buttons do not: a way back in after a forgotten password.
  Future<void> _resetPassword(AccountProvider account) async {
    if (_emailProblem != null) {
      setState(() => _showErrors = true);
      return;
    }
    final OverlayState? notices = AppNotice.capture(context);
    final AccountSignInResult result = await account.sendPasswordReset(
      _emailController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    AppNotice.showOn(
      notices,
      result.outcome == AccountSignInOutcome.success
          ? 'שלחנו מייל לאיפוס הסיסמה.'
          : result.message ?? 'לא הצלחנו לשלוח את המייל.',
    );
  }

  // --- Validation ----------------------------------------------------------

  String? get _emailProblem {
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      return 'צריך למלא כתובת מייל';
    }
    // Deliberately the loosest possible check. The address is verified by the
    // mail that either arrives or does not; a clever regular expression here
    // only ever refuses somebody's real address.
    if (!email.contains('@') || !email.contains('.')) {
      return 'כתובת המייל אינה תקינה';
    }
    return null;
  }

  String? get _passwordProblem {
    if (_passwordController.text.length < AccountService.minPasswordLength) {
      return 'צריך סיסמה של לפחות ${AccountService.minPasswordLength} תווים';
    }
    return null;
  }

  // --- Leaving -------------------------------------------------------------

  /// Back to wherever this was opened from.
  ///
  /// Popping when it can matters because this screen has two lives: the gate at
  /// the front of the app, which has nothing behind it, and the "התחברות"
  /// button on the community areas, which should return the reader to the
  /// screen they were reading.
  void _leave() {
    if (!mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    // `/home` rather than anywhere specific: the router decides what comes
    // next, and for a brand-new account that is the profile form.
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
  /// **And then the community, in the same breath.** Publishing used to wait
  /// for the next app open, which meant a matchmaker who had been using the app
  /// for months and signed in this morning appeared in the community with no
  /// history and nowhere on the board — the one moment they are most likely to
  /// go and look. The counts are recomputed from the local ledgers, so this
  /// publish carries everything they did before they had an account, and it is
  /// deliberately after the restore: a database that has just gained records
  /// from the account should be counted with them.
  ///
  /// Unawaited on purpose: this is a backup, and the matchmaker should be on
  /// the home screen while it happens rather than watching a spinner. Every
  /// provider is read *before* the first `await` for the same reason — this
  /// outlives the screen that started it.
  Future<void> _adoptLocalData() async {
    final SyncProvider sync = context.read<SyncProvider>();
    final PersonRepository people = context.read<PersonRepository>();
    final MatchRepository matches = context.read<MatchRepository>();
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final CommunityProvider community = context.read<CommunityProvider>();

    await sync.restore(
      personRepo: people,
      matchRepo: matches,
      profile: profile,
    );
    await sync.sync(personRepo: people, matchRepo: matches, profile: profile);
    await community.refresh(people: people, matches: matches, profile: profile);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AccountProvider account = context.watch<AccountProvider>();
    final bool registering = _mode == _EmailMode.register;

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
                    size: 52,
                    color: theme.brightness == Brightness.dark
                        ? theme.colorScheme.primary
                        : AppColors.primaryDark,
                  ),
                  const SizedBox(height: 20),
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
                  const SizedBox(height: 26),
                  // Apple only where Apple's own flow exists, and first when it
                  // does: an iPhone already has an Apple account signed in, so
                  // it is the one-tap answer there, and Apple's guidelines put
                  // their button above the alternatives. See
                  // `AccountService.isAppleAvailable`.
                  if (account.isAppleAvailable) ...<Widget>[
                    SignInWithAppleButton(
                      onPressed: account.isBusy
                          ? null
                          : () => _signIn(account.signInWithApple),
                      text: 'המשך עם Apple',
                      height: 52,
                      style: theme.brightness == Brightness.dark
                          ? SignInWithAppleButtonStyle.white
                          : SignInWithAppleButtonStyle.black,
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _ProviderButton(
                    icon: Icons.account_circle_outlined,
                    label: 'המשך עם Google',
                    busy: account.isBusy,
                    onPressed: () => _signIn(account.signIn),
                  ),
                  const SizedBox(height: 22),
                  const _OrRule(),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enabled: !account.isBusy,
                    decoration: InputDecoration(
                      labelText: 'מייל',
                      prefixIcon: const Icon(Icons.mail_outline_rounded),
                      errorText: _showErrors ? _emailProblem : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: !_showPassword,
                    enabled: !account.isBusy,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'סיסמה',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      // Shown rather than confirmed twice. A second box is one
                      // more field to fill for a mistake an eye catches faster.
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? 'הסתרה' : 'הצגה',
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                      helperText: registering
                          ? 'לפחות ${AccountService.minPasswordLength} תווים'
                          : null,
                      errorText: _showErrors ? _passwordProblem : null,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submitEmail(account),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: account.isBusy
                        ? null
                        : () => _submitEmail(account),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    child: account.isBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(registering ? 'הרשמה עם מייל' : 'התחברות'),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: account.isBusy
                        ? null
                        : () => setState(() {
                            _mode = registering
                                ? _EmailMode.signIn
                                : _EmailMode.register;
                            _showErrors = false;
                          }),
                    child: Text(
                      registering
                          ? 'כבר יש לי חשבון — התחברות'
                          : 'אין לי חשבון עדיין — הרשמה',
                    ),
                  ),
                  if (!registering)
                    TextButton(
                      onPressed: account.isBusy
                          ? null
                          : () => _resetPassword(account),
                      child: Text(
                        'שכחתי סיסמה',
                        style: theme.textTheme.bodySmall?.copyWith(
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

/// The Google provider button. Apple uses its guideline-compliant widget.
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

/// A hairline with "או" set into it, between the provider buttons and the
/// address form.
class _OrRule extends StatelessWidget {
  const _OrRule();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget rule = Expanded(
      child: Divider(color: theme.colorScheme.outlineVariant),
    );

    return Row(
      children: <Widget>[
        rule,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'או',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        rule,
      ],
    );
  }
}
