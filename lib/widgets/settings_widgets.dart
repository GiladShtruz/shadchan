import 'package:flutter/material.dart';

/// The shape the settings are made of, and the reason there are only two
/// pieces.
///
/// The settings page used to be a stack of nine headings, each with its own
/// white card, several of them holding a single row — which reads as a list of
/// unrelated boxes rather than as a page with a structure. What replaced it is
/// one heading per *subject*, one card under it, and several rows inside. A
/// subject with one row does not get a card of its own; it gets a row in the
/// card next to it.

/// One titled group of rows.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});

  final String title;

  /// The rows. Dividers are drawn between them here rather than by the caller,
  /// so no group can end up with a stray one at the bottom.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row: a small icon on the reading edge, a title, and a chevron when it
/// opens something.
///
/// **A subtitle is the exception, not the default.** Most of the greys that
/// used to sit under these rows repeated the title in more words; the ones left
/// are the rows whose title genuinely does not say enough on its own.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.enabled = true,
    this.destructive = false,
    this.leadingOverride,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Replaces the chevron. A row that opens a screen keeps the chevron; a row
  /// that *does* something gets whatever says so, or nothing.
  final Widget? trailing;

  final bool enabled;

  /// Signing out and the like. Coloured, and no louder than that — a red row
  /// among grey ones is already the loudest thing on the page.
  final bool destructive;

  /// A spinner or an avatar in place of the icon, while something is running.
  final Widget? leadingOverride;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? tint = destructive ? theme.colorScheme.error : null;

    return ListTile(
      enabled: enabled,
      leading: leadingOverride ?? Icon(icon, size: 22, color: tint),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(color: tint),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: theme.textTheme.bodySmall),
      trailing:
          trailing ??
          (onTap == null
              ? null
              // `chevron_right`, matching every other "opens a screen" row in
              // the app. Material does not mirror this glyph, so switching it
              // here alone would make the settings the one place in the app
              // whose arrows point the other way.
              : Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                )),
      onTap: enabled ? onTap : null,
    );
  }
}

/// The spinner that stands in for a row's icon while its action runs.
class SettingsSpinner extends StatelessWidget {
  const SettingsSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
