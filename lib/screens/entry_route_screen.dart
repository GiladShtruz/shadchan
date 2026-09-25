import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/home_section.dart';

/// "ברוך הבא!" — the first screen of a fresh install, before signing in.
///
/// Two ways in, one account either way. A matchmaker goes on to the sign-up
/// the app always had, introduction included. Somebody who came to manage
/// their own card signs in the same way and then goes straight to writing it,
/// without being walked through a matchmaker's database they may never use.
class EntryRouteScreen extends StatelessWidget {
  const EntryRouteScreen({super.key});

  void _choose(BuildContext context, EntryRoute route) {
    WorkspaceStore.chooseEntry(route);
    context.go('/sign-in');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(
                    Icons.favorite,
                    size: 52,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'ברוך הבא!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'איך נכנסים היום?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  _RouteCard(
                    icon: Icons.diversity_1_outlined,
                    title: 'כניסה לשדכן',
                    subtitle: 'לנהל את החברים שלך ולחשוב על רעיונות לשידוכים',
                    accent: AppColors.primary,
                    onTap: () => _choose(context, EntryRoute.matchmaker),
                  ),
                  const SizedBox(height: 14),
                  _RouteCard(
                    icon: Icons.badge_outlined,
                    title: 'כניסה לרווק/ה',
                    subtitle:
                        'לנהל בעצמך כרטיס אישי ולתת לחברים שמשדכים גישה אליו',
                    accent: AppColors.secondary,
                    onTap: () => _choose(context, EntryRoute.cardOwner),
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

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return HomePaperCard(
      stripe: accent,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
