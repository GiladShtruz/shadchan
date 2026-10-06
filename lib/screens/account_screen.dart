import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/account_dialogs.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/services/account_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "החשבון שלי" — the account, said simply.
///
/// The address it is signed in with, the ways in that are linked to it,
/// the password, and at the foot the two ways out. Everything about the
/// database itself is absent on purpose: it is the account's, it is on every
/// phone signed in to it, and there is nothing to configure about that.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AccountProvider account = context.watch<AccountProvider>();
    final Set<String> providers = account.providerIds;
    final String? email = account.accountEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('החשבון שלי')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            SettingsGroup(
              title: 'מחובר כעת',
              accent: AppColors.primaryDark,
              children: <Widget>[
                SettingsRow(
                  icon: Icons.mail_outline_rounded,
                  leadingOverride: account.isBusy
                      ? const SettingsSpinner()
                      : null,
                  title: email ?? 'חשבון ללא כתובת מייל',
                  subtitle:
                      providers.contains('password') && !account.emailVerified
                      ? 'הכתובת עדיין לא אומתה'
                      : 'המאגר שלך שמור בחשבון הזה ומסונכרן בכל מכשיר '
                            'שמחובר אליו',
                ),
                if (providers.contains('password') && !account.emailVerified)
                  SettingsRow(
                    icon: Icons.mark_email_unread_outlined,
                    title: 'שליחת מייל לאימות הכתובת',
                    onTap: account.isBusy
                        ? null
                        : () => _resendVerification(context, account),
                  ),
              ],
            ),
            SettingsGroup(
              title: 'דרכי התחברות',
              accent: AppColors.secondary,
              children: <Widget>[
                _MethodRow(
                  icon: Icons.account_circle_outlined,
                  name: 'Google',
                  linked: providers.contains('google.com'),
                  onLink: () => _link(context, account.linkGoogle),
                ),
                if (providers.contains('apple.com') || account.isAppleAvailable)
                  _MethodRow(
                    icon: Icons.apple,
                    name: 'Apple',
                    linked: providers.contains('apple.com'),
                    onLink: account.isAppleAvailable
                        ? () => _link(context, account.linkApple)
                        : null,
                  ),
                _MethodRow(
                  icon: Icons.password_rounded,
                  name: 'מייל וסיסמה',
                  linked: providers.contains('password'),
                  onLink: email == null
                      ? null
                      : () => _addPassword(context, account),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                'אפשר להיכנס לאותו חשבון בכל אחת מהדרכים המקושרות. חשבון אחר, '
                'גם עם אותו אדם, הוא מאגר נפרד — חשבונות לא מתאחדים מעצמם.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
            if (providers.contains('password'))
              SettingsGroup(
                title: 'סיסמה',
                accent: AppColors.femaleAccent,
                children: <Widget>[
                  SettingsRow(
                    icon: Icons.lock_reset_rounded,
                    title: 'שינוי סיסמה',
                    onTap: account.isBusy
                        ? null
                        : () => _changePassword(context, account),
                  ),
                  if (email != null)
                    SettingsRow(
                      icon: Icons.forward_to_inbox_rounded,
                      title: 'שליחת מייל לאיפוס הסיסמה',
                      subtitle: email,
                      onTap: account.isBusy
                          ? null
                          : () => _sendReset(context, account, email),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Divider(color: theme.colorScheme.outlineVariant),
            _QuietAction(
              label: 'התנתקות',
              onPressed: account.isBusy
                  ? null
                  : () => AccountDialogs.confirmSignOut(context),
            ),
            _QuietAction(
              label: 'מחיקת החשבון',
              onPressed: account.isBusy
                  ? null
                  : () => AccountDialogs.confirmDeleteAccount(context),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _link(
    BuildContext context,
    Future<AccountSignInResult> Function() link,
  ) async {
    final OverlayState? notices = AppNotice.capture(context);
    final AccountSignInResult result = await link();
    if (result.outcome == AccountSignInOutcome.canceled) {
      return;
    }
    AppNotice.showOn(
      notices,
      result.outcome == AccountSignInOutcome.success
          ? 'דרך ההתחברות קושרה לחשבון.'
          : result.message ?? 'לא הצלחנו לקשר.',
    );
  }

  static Future<void> _addPassword(
    BuildContext context,
    AccountProvider account,
  ) async {
    final String? password = await AccountDialogs.askPassword(
      context,
      title: 'הוספת סיסמה',
      label: 'סיסמה חדשה (לפחות ${AccountService.minPasswordLength} תווים)',
      confirmLabel: 'הוספה',
    );
    if (password == null || !context.mounted) {
      return;
    }
    await _link(context, () => account.linkPassword(password));
  }

  static Future<void> _changePassword(
    BuildContext context,
    AccountProvider account,
  ) async {
    final String? current = await AccountDialogs.askPassword(
      context,
      title: 'שינוי סיסמה',
      label: 'הסיסמה הנוכחית',
      confirmLabel: 'המשך',
    );
    if (current == null || !context.mounted) {
      return;
    }
    final String? next = await AccountDialogs.askPassword(
      context,
      title: 'שינוי סיסמה',
      label: 'סיסמה חדשה (לפחות ${AccountService.minPasswordLength} תווים)',
      confirmLabel: 'שמירה',
    );
    if (next == null || !context.mounted) {
      return;
    }
    final OverlayState? notices = AppNotice.capture(context);
    final AccountSignInResult result = await account.changePassword(
      currentPassword: current,
      newPassword: next,
    );
    AppNotice.showOn(
      notices,
      result.outcome == AccountSignInOutcome.success
          ? 'הסיסמה שונתה.'
          : result.message ?? 'לא הצלחנו לשנות את הסיסמה.',
    );
  }

  static Future<void> _sendReset(
    BuildContext context,
    AccountProvider account,
    String email,
  ) async {
    final OverlayState? notices = AppNotice.capture(context);
    final AccountSignInResult result = await account.sendPasswordReset(email);
    AppNotice.showOn(
      notices,
      result.outcome == AccountSignInOutcome.success
          ? 'שלחנו ל־$email קישור לאיפוס הסיסמה.'
          : result.message ?? 'לא הצלחנו לשלוח את המייל.',
    );
  }

  static Future<void> _resendVerification(
    BuildContext context,
    AccountProvider account,
  ) async {
    final OverlayState? notices = AppNotice.capture(context);
    final AccountSignInResult result = await account.resendVerification();
    AppNotice.showOn(
      notices,
      result.outcome == AccountSignInOutcome.success
          ? 'שלחנו מייל עם קישור לאימות.'
          : result.message ?? 'לא הצלחנו לשלוח את המייל.',
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.icon,
    required this.name,
    required this.linked,
    required this.onLink,
  });

  final IconData icon;
  final String name;
  final bool linked;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SettingsRow(
      icon: icon,
      title: name,
      subtitle: linked ? 'מקושר' : 'לא מקושר',
      trailing: linked
          ? Icon(Icons.check_circle_rounded, color: AppColors.statusMarried)
          : onLink == null
          ? null
          : TextButton(
              onPressed: onLink,
              style: TextButton.styleFrom(
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('קישור'),
            ),
    );
  }
}

/// A small grey text button at the foot of the page — the ways out are there,
/// and nowhere near a tap made by mistake.
class _QuietAction extends StatelessWidget {
  const _QuietAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          visualDensity: VisualDensity.compact,
          textStyle: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
