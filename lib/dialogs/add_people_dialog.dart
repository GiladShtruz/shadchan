import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

/// The ways a contact can get into the database. Mirrors the "הוספת חברים"
/// tiles on the home screen so both entry points offer the same choices.
enum AddPeopleMethod { fromContacts, manual, ai }

/// Asks how the user wants to add contacts and routes to the chosen flow.
abstract final class AddPeopleDialog {
  static Future<void> show(BuildContext context) async {
    // The seconds spent reading this dialog are seconds the contact cache can
    // be coming off disk in. It touches no permission and no address book —
    // only a Hive box the app wrote itself — so warming it here costs nothing
    // even when the answer turns out to be "הוספה ידנית".
    unawaited(ContactsImportService.prewarmCache());

    // Backing out of a flow returns to this choice, not to the page under it:
    // the dialog is the step before, so it is what "back" should land on.
    // A flow that finished — something was added, or it moved on to a profile
    // or to the database — ends the loop.
    while (context.mounted) {
      final AddPeopleMethod? method = await showDialog<AddPeopleMethod>(
        context: context,
        builder: (BuildContext dialogContext) => const _AddPeopleDialog(),
      );
      if (method == null || !context.mounted) {
        return;
      }

      final String location = GoRouter.of(
        context,
      ).routerDelegate.currentConfiguration.uri.toString();
      final Object? result = await context.push<Object?>(switch (method) {
        AddPeopleMethod.fromContacts => '/people/import',
        AddPeopleMethod.manual => '/people/add',
        AddPeopleMethod.ai => '/people/ai',
      });
      if (!context.mounted || result != null) {
        return;
      }
      // Only a plain back press leaves the caller's page on top again, at the
      // same location. A save that replaced the form with a profile, or an
      // import that went to המאגר שלי, does not.
      final bool backWhereWeStarted =
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          GoRouter.of(
                context,
              ).routerDelegate.currentConfiguration.uri.toString() ==
              location;
      if (!backWhereWeStarted) {
        return;
      }
    }
  }
}

class _AddPeopleDialog extends StatelessWidget {
  const _AddPeopleDialog();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    // A single calm slate accent carries the whole dialog. The window is the
    // size of its three choices and nothing more — a title line, the rows and
    // one quiet sentence; no illustration and no empty band above them.
    final Color slate = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
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
                    'הוספת חברים למאגר',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _CloseButton(
                  slate: slate,
                  dark: dark,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MethodCard(
              icon: Icons.contacts_rounded,
              title: 'הוספה מאנשי הקשר',
              slate: slate,
              dark: dark,
              onTap: () =>
                  Navigator.of(context).pop(AddPeopleMethod.fromContacts),
            ),
            const SizedBox(height: 10),
            _MethodCard(
              icon: Icons.edit_rounded,
              title: 'הוספה ידנית',
              slate: slate,
              dark: dark,
              onTap: () => Navigator.of(context).pop(AddPeopleMethod.manual),
            ),
            const SizedBox(height: 10),
            _MethodCard(
              icon: Icons.auto_awesome_rounded,
              title: 'הוספה באמצעות AI',
              slate: slate,
              dark: dark,
              onTap: () => Navigator.of(context).pop(AddPeopleMethod.ai),
            ),
            const SizedBox(height: 14),
            _SecurityFooter(slate: slate),
          ],
        ),
      ),
    );
  }
}

/// One selectable route into the add flow: a soft slate icon badge, its name,
/// and a chevron. No explanation under it — the three names say it.
class _MethodCard extends StatelessWidget {
  const _MethodCard({
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
      color: dark ? theme.colorScheme.surface : const Color(0xFFFCFAF5),
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

class _SecurityFooter extends StatelessWidget {
  const _SecurityFooter({required this.slate});

  final Color slate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Gender? gender = context.userGender;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.verified_user_rounded,
          size: 14,
          color: slate.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'המידע נשמר בצורה מאובטחת ורק {אתה רואה|את רואה} אותו'.forGender(
              gender,
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({
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
