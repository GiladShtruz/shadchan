import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/tips_service.dart';
import 'package:shadchan/utils/app_colors.dart';

/// "הוספת טיפ" — where a matchmaker writes a tip for every other matchmaker.
///
/// Reached from the settings, never from the home screen: the home screen is
/// where tips are *read*, and putting a compose box there would turn a moment
/// of encouragement into another thing asking to be filled in.
///
/// Nothing published here goes live on its own. A tip is sent, the author sees
/// it sitting as "ממתין לאישור", and it joins the rotation only once the
/// administrator approves it.
class AddTipScreen extends StatefulWidget {
  const AddTipScreen({super.key});

  @override
  State<AddTipScreen> createState() => _AddTipScreenState();
}

class _AddTipScreenState extends State<AddTipScreen> {
  final TextEditingController _tip = TextEditingController();
  final TextEditingController _author = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    _author.text = profile.tipAuthorName ?? profile.name ?? '';
    _tip.addListener(() => setState(() {}));
    _author.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TipsProvider>().refreshMine();
      }
    });
  }

  @override
  void dispose() {
    _tip.dispose();
    _author.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending &&
      _tip.text.trim().length >= 10 &&
      _author.text.trim().length >= 2;

  Future<void> _send() async {
    final TipsProvider tips = context.read<TipsProvider>();
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() => _sending = true);
    await profile.setTipAuthorName(_author.text);
    final bool sent = await tips.submit(
      text: _tip.text,
      authorName: _author.text,
    );
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    if (sent) {
      _tip.clear();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('הטיפ נשלח לאישור. תודה!')),
        );
    } else {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('לא הצלחנו לשלוח את הטיפ. יש לבדוק חיבור לאינטרנט.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AccountProvider account = context.watch<AccountProvider>();
    final TipsProvider tips = context.watch<TipsProvider>();
    final bool canContribute = account.isSignedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('הוספת טיפ'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: <Widget>[
            _Intro(theme: theme),
            const SizedBox(height: 16),
            if (!canContribute)
              _SignInNotice(theme: theme)
            else ...<Widget>[
              TextField(
                controller: _author,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'שם פרטי ושם משפחה',
                  helperText: 'השם יופיע בקטן מתחת לטיפ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _tip,
                minLines: 4,
                maxLines: 8,
                maxLength: TipsService.maxLength,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'הטיפ שלך',
                  hintText: 'משהו קצר שלמדת ושיכול לעזור לשדכן אחר',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _canSend ? _send : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.brightness == Brightness.dark
                        ? theme.colorScheme.primary
                        : AppColors.primaryDark,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: const StadiumBorder(),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: const Text('שליחה לאישור'),
                ),
              ),
            ],
            if (tips.mine.isNotEmpty) ...<Widget>[
              const SizedBox(height: 26),
              Text(
                'הטיפים ששלחת',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              for (final CommunityTip tip in tips.mine) ...<Widget>[
                _MyTipRow(tip: tip),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bool dark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: dark
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : AppColors.primaryLight.withValues(alpha: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.lightbulb_rounded,
            color: dark ? theme.colorScheme.primary : AppColors.primaryDark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'הטיפים בעמוד הבית נכתבים על ידי שדכנים. אחרי שליחה הטיפ עובר '
              'אישור, ומשם הוא מצטרף לטיפים שכל השדכנים רואים.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInNotice extends StatelessWidget {
  const _SignInNotice({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.person_outline, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'כדי לשלוח טיפ יש להתחבר לחשבון מתוך "החשבון שלי" בפרופיל. '
              'החיבור הוא מה שמאפשר לזהות מי כתב את הטיפ.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _MyTipRow extends StatelessWidget {
  const _MyTipRow({required this.tip});

  final CommunityTip tip;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = switch (tip.status) {
      TipStatus.approved => const Color(0xFF2E9E5B),
      TipStatus.rejected => theme.colorScheme.onSurfaceVariant,
      TipStatus.pending => AppColors.secondary,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            tip.text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              tip.status.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
