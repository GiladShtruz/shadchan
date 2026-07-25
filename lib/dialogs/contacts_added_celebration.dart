import 'package:flutter/material.dart';

/// The confirmation shown after a batch of contacts was added to the database —
/// both at the end of a multi-add from the list and when leaving the swipe deck.
class ContactsAddedCelebration extends StatelessWidget {
  const ContactsAddedCelebration({
    super.key,
    required this.count,
    this.footnote,
  });

  final int count;

  /// Optional extra line under the headline (e.g. where to fill in details).
  final String? footnote;

  static Future<void> show(
    BuildContext context, {
    required int count,
    String? footnote,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'הוספה הושלמה',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, _, _) =>
          ContactsAddedCelebration(count: count, footnote: footnote),
      transitionBuilder: (_, Animation<double> animation, _, Widget child) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return Transform.scale(
          scale: curved.value,
          child: Opacity(
            opacity: animation.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String headline = count == 1
        ? 'מעולה, הוספת חבר אחד למאגר'
        : 'מעולה, הוספת $count חברים למאגר';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.elasticOut,
              builder: (BuildContext context, double value, Widget? child) {
                return Transform.scale(
                  scale: value,
                  child: Transform.rotate(
                    angle: (1 - value) * 0.6,
                    child: child,
                  ),
                );
              },
              child: const Text('🎉', style: TextStyle(fontSize: 64)),
            ),
            const SizedBox(height: 20),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (footnote != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                footnote!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('מעולה!'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
