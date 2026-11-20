import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/utils/app_colors.dart';

/// "הוספת חברים": straight to the contacts page.
///
/// **The fast way is the default.** It used to ask first — contacts, by hand
/// or AI — in a dialog of its own; now the contacts page opens at once, and
/// carries "הוספה ידנית" and "הוספה מרוכזת באמצעות AI" at its top.
abstract final class AddPeopleDialog {
  static Future<void> show(BuildContext context) async {
    if (!OfflineGuard.allow(context)) {
      return;
    }
    unawaited(ContactsImportService.prewarmCache());
    await context.push<Object?>('/people/import');
  }
}

/// One selectable route into the add flow: a soft slate icon badge, its name,
/// and a chevron. No explanation under it — the three names say it.
class AddMethodCard extends StatelessWidget {
  const AddMethodCard({
    super.key,
    required this.icon,
    required this.title,
    required this.slate,
    required this.dark,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color slate;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: dark ? theme.colorScheme.surface : AppColors.cardCream,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                _IconBadge(icon: icon, slate: slate, dark: dark),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: slate.withValues(alpha: 0.75),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.slate,
    required this.dark,
  });

  final IconData icon;
  final Color slate;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: slate.withValues(alpha: dark ? 0.22 : 0.12),
      ),
      child: Icon(icon, color: slate, size: 22),
    );
  }
}

class AddDialogCloseButton extends StatelessWidget {
  const AddDialogCloseButton({
    super.key,
    required this.slate,
    required this.dark,
    required this.onTap,
  });

  final Color slate;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: slate.withValues(alpha: dark ? 0.20 : 0.10),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.close_rounded, size: 18, color: slate),
        ),
      ),
    );
  }
}

/// What the "+" in בית's corner asks: a friend or an idea. Two rows in the
/// same shape as [AddPeopleDialog], and a friend leads on into that dialog.
abstract final class AddChoiceDialog {
  static Future<void> show(BuildContext context) async {
    if (!OfflineGuard.allow(context)) {
      return;
    }
    final bool? idea = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        final bool dark = theme.brightness == Brightness.dark;
        final Color slate = dark
            ? AppColors.primaryDarkDm
            : AppColors.primaryDark;
        return Dialog(
          backgroundColor: theme.colorScheme.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'מה להוסיף?',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    AddDialogCloseButton(
                      slate: slate,
                      dark: dark,
                      onTap: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AddMethodCard(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'הוספת חבר',
                  slate: slate,
                  dark: dark,
                  onTap: () => Navigator.of(dialogContext).pop(false),
                ),
                const SizedBox(height: 10),
                AddMethodCard(
                  icon: Icons.lightbulb_outline_rounded,
                  title: 'הוספת רעיון',
                  slate: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
                  dark: dark,
                  onTap: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (idea == null || !context.mounted) {
      return;
    }
    if (idea) {
      await context.push<Object?>('/matches/add');
    } else {
      await AddPeopleDialog.show(context);
    }
  }
}
