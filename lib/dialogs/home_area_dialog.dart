import 'package:flutter/material.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

/// "איזה עמוד תרצה להגדיר כעמוד הבית?" — for somebody who has both the
/// matchmaker's area and a personal card of their own.
///
/// Two answers and nothing else: there is no "later", because a launch has to
/// open somewhere and the question is short. Dismissing it by Back keeps the
/// old behaviour (the area last used) and asks again next time.
abstract final class HomeAreaDialog {
  /// Asks, saves the answer and returns it (null when dismissed).
  static Future<WorkArea?> show(
    BuildContext context, {
    Gender? userGender,
  }) async {
    final WorkArea? current = WorkspaceStore.homeArea;
    final WorkArea? picked = await showDialog<WorkArea>(
      context: context,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return AlertDialog(
          title: Text(
            'איזה עמוד {תרצה|תרצי} להגדיר כעמוד הבית?'.forGender(userGender),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'האפליקציה תיפתח עליו בכל כניסה. אפשר לשנות בהגדרות.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              _AreaChoice(
                icon: Icons.person_outline_rounded,
                label: 'האזור האישי',
                accent: AppColors.femaleAccent,
                selected: current == WorkArea.personal,
                onTap: () => Navigator.of(context).pop(WorkArea.personal),
              ),
              const SizedBox(height: 10),
              _AreaChoice(
                icon: Icons.groups_2_outlined,
                label: 'אזור השדכן',
                accent: AppColors.primaryDark,
                selected: current == WorkArea.matchmaker,
                onTap: () => Navigator.of(context).pop(WorkArea.matchmaker),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      WorkspaceStore.setHomeArea(picked);
    }
    return picked;
  }
}

class _AreaChoice extends StatelessWidget {
  const _AreaChoice({
    required this.icon,
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: accent.withValues(alpha: selected ? 0.16 : 0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: accent.withValues(alpha: selected ? 0.7 : 0.35),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(icon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
