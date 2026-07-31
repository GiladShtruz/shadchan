import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The ways a contact can get into the database. Mirrors the "הוספת חברים"
/// tiles on the home screen so both entry points offer the same choices.
enum AddPeopleMethod { fromContacts, manual, ai }

/// Asks how the user wants to add contacts and routes to the chosen flow.
abstract final class AddPeopleDialog {
  static Future<void> show(BuildContext context) async {
    final AddPeopleMethod? method = await showDialog<AddPeopleMethod>(
      context: context,
      builder: (BuildContext dialogContext) => const _AddPeopleDialog(),
    );

    if (method == null || !context.mounted) {
      return;
    }

    switch (method) {
      case AddPeopleMethod.fromContacts:
        context.push('/people/import');
      case AddPeopleMethod.manual:
        context.push('/people/add');
      case AddPeopleMethod.ai:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('בקרוב! נעדכן כשהעזרה של ה‑AI תהיה מוכנה ✨'),
            ),
          );
    }
  }
}

class _AddPeopleDialog extends StatelessWidget {
  const _AddPeopleDialog();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    // A single calm slate accent carries the whole dialog — no gradients, no
    // per-card colours. The icon badges wear a soft wash of it against a cream
    // surface, matching the reference mock.
    final Color slate = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Stack(
        children: <Widget>[
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 30),
                _HeaderBadge(slate: slate, dark: dark),
                const SizedBox(height: 22),
                Text(
                  'מוסיפים חבר/ה למאגר',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'בחרו איך תרצו להוסיף חבר/ה חדש/ה',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: slate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'שלוש דרכים פשוטות להוסיף למאגר',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: <Widget>[
                      _MethodCard(
                        icon: Icons.contacts_rounded,
                        title: 'הוספה מאנשי הקשר',
                        subtitle: 'בחרו איש קשר קיים מהטלפון',
                        slate: slate,
                        dark: dark,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(AddPeopleMethod.fromContacts),
                      ),
                      const SizedBox(height: 14),
                      _MethodCard(
                        icon: Icons.edit_rounded,
                        title: 'הוספה ידנית',
                        subtitle: 'מלאו פרטים של חבר/ה חדש/ה',
                        slate: slate,
                        dark: dark,
                        onTap: () =>
                            Navigator.of(context).pop(AddPeopleMethod.manual),
                      ),
                      const SizedBox(height: 14),
                      _MethodCard(
                        icon: Icons.auto_awesome_rounded,
                        title: 'היעזרו ב‑AI להוספה',
                        subtitle: 'תנו ל‑AI לעזור לכם להוסיף ולהשלים פרטים',
                        slate: slate,
                        dark: dark,
                        badge: 'חדש!',
                        onTap: () =>
                            Navigator.of(context).pop(AddPeopleMethod.ai),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SecurityFooter(slate: slate, dark: dark),
              ],
            ),
          ),
          PositionedDirectional(
            top: 12,
            end: 12,
            child: _CloseButton(
              slate: slate,
              dark: dark,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The soft round avatar badge with a person-add glyph and a light scatter of
/// sparkles, all in the same muted palette.
class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.slate, required this.dark});

  final Color slate;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 128,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            top: 6,
            left: 34,
            child: Icon(
              Icons.auto_awesome,
              size: 15,
              color: slate.withValues(alpha: 0.55),
            ),
          ),
          Positioned(
            top: 20,
            right: 26,
            child: Icon(
              Icons.auto_awesome,
              size: 11,
              color: slate.withValues(alpha: 0.4),
            ),
          ),
          Positioned(
            top: 26,
            right: 44,
            child: _Dot(color: slate.withValues(alpha: 0.45)),
          ),
          Positioned(
            bottom: 24,
            left: 40,
            child: _Dot(color: AppColors.secondary.withValues(alpha: 0.5)),
          ),
          Positioned(
            bottom: 34,
            right: 40,
            child: _Dot(color: slate.withValues(alpha: 0.3)),
          ),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slate.withValues(alpha: dark ? 0.24 : 0.14),
            ),
            child: Icon(Icons.person_add_alt_1, color: slate, size: 44),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// One selectable route into the add flow: a soft slate icon badge, a title and
/// subtitle, an optional "new" pill, and a chevron.
class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.slate,
    required this.dark,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color slate;
  final bool dark;
  final VoidCallback onTap;
  final String? badge;

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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: <Widget>[
                _IconBadge(icon: icon, slate: slate, dark: dark),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (badge != null) ...<Widget>[
                            const SizedBox(width: 8),
                            _NewBadge(label: badge!, slate: slate),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_left_rounded,
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
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: slate.withValues(alpha: dark ? 0.22 : 0.12),
      ),
      child: Icon(icon, color: slate, size: 26),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge({required this.label, required this.slate});

  final String label;
  final Color slate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: slate,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SecurityFooter extends StatelessWidget {
  const _SecurityFooter({required this.slate, required this.dark});

  final Color slate;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: slate.withValues(alpha: dark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Flexible(
            child: Text(
              'המידע נשמר בצורה מאובטחת ורק אתם רואים אותו',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.verified_user_rounded,
            size: 16,
            color: slate.withValues(alpha: 0.9),
          ),
        ],
      ),
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
          width: 38,
          height: 38,
          child: Icon(Icons.close_rounded, size: 20, color: slate),
        ),
      ),
    );
  }
}
