import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.buttonText,
    this.onButtonPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? buttonText;
  final VoidCallback? onButtonPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color iconColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.primaryContainer
        : AppColors.primaryLight;

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 400),
        builder: (BuildContext context, double opacity, Widget? child) {
          return AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 400),
            child: child,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 80, color: iconColor),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (buttonText != null && onButtonPressed != null) ...<Widget>[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onButtonPressed,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(buttonText!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
