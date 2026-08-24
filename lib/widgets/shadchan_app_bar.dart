import 'package:flutter/material.dart';
import 'package:shadchan/widgets/home_app_bar.dart';

/// The app's own banner, worn by all three tabs.
///
/// **One row on cream paper, with the app's name at the start of it.** Every
/// tab used to open with a different top: the home screen had a photograph, a
/// centred wordmark and three squares; המאגר שלי and רעיונות had the theme's
/// blue-grey bar with a centred heading. Three tabs of one app that do not
/// agree about their own top read as three apps, so the banner is now one
/// widget and the pages differ only in what they hang off the end of it.
///
/// **The wordmark leads, the controls trail.** The title slot starts at the
/// start edge — the right, in this RTL app — rather than being centred, which
/// is what frees the middle of the bar and stops the mark competing with the
/// page heading. Everything a page can do sits in [actions], at the left end.
///
/// The page's own heading is deliberately *not* in here. It moved onto the page
/// itself, at the size a heading deserves, the way the home greeting did — a
/// 56px strip shared with a mark and a row of controls is not where a title
/// should have to fight for room. See [ScreenHeading].
class ShadchanAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShadchanAppBar({
    super.key,
    this.actions = const <Widget>[],
    this.leading,
    this.bottom,
  });

  /// The page's own controls, at the far end of the bar.
  final List<Widget> actions;

  /// A way back, for the screens that are pushed rather than tabbed. Null on a
  /// tab, where the bar starts with the wordmark and nothing before it.
  final Widget? leading;

  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize {
    return Size.fromHeight(
      kToolbarHeight + (bottom?.preferredSize.height ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppBar(
      // The bar is the page, not a band across the top of it: the theme paints
      // app bars in the brand blue-grey, and on that strip the white chips and
      // the tinted mark read as floating decoration rather than as the top of
      // the paper the cards below are printed on.
      backgroundColor: theme.scaffoldBackgroundColor,
      foregroundColor: theme.colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: leading,
      // With nothing before it the wordmark starts hard against the page's own
      // margin, so it lines up with the cards underneath.
      leadingWidth: leading == null ? 0 : null,
      titleSpacing: leading == null ? 16 : 4,
      centerTitle: false,
      title: const ShadchanWordmark(),
      actions: <Widget>[...actions, const SizedBox(width: 6)],
      bottom: bottom,
    );
  }
}

/// A page's own heading, on the page rather than in the banner.
///
/// The counterpart of [ShadchanAppBar]: the bar carries the app's name, and
/// this carries the screen's. Same weight and colour as [HomeGreeting], so the
/// three tabs open at the same size whatever their first line says.
class ScreenHeading extends StatelessWidget {
  const ScreenHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;

  /// One quiet line under it, for a screen with something short worth saying
  /// about what is on it.
  final String? subtitle;

  /// A control that belongs on the heading's own line rather than in the bar.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? note = subtitle;
    final Widget? end = trailing;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (note != null && note.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?end,
      ],
    );
  }
}

/// The rounded search field the tabs share, drawn directly under the banner the
/// way a messaging app draws it.
///
/// **A row, not an icon.** A magnifier in the corner is one more thing to find
/// before the thing actually being looked for; a field that is simply there is
/// read as "type here" without being read at all. It scrolls away with the page
/// — see the callers — so it costs nothing once somebody is past the top.
class ShadchanSearchField extends StatelessWidget {
  const ShadchanSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.autofocus = false,
    this.onCleared,
    this.trailing = const <Widget>[],
  });

  final TextEditingController controller;
  final String hintText;
  final bool autofocus;

  /// Called after the X inside the field empties it, for a caller that has
  /// something of its own to put away with the query.
  final VoidCallback? onCleared;

  /// Controls that belong beside the field rather than inside it — the filter
  /// and sort buttons on המאגר שלי.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasText = controller.text.trim().isNotEmpty;
    final VoidCallback? cleared = onCleared;

    OutlineInputBorder border(Color color) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: color),
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                hintText: hintText,
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: border(theme.colorScheme.outlineVariant),
                enabledBorder: border(theme.colorScheme.outlineVariant),
                focusedBorder: border(
                  theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
                suffixIcon: hasText
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        tooltip: 'ניקוי',
                        onPressed: () {
                          controller.clear();
                          cleared?.call();
                        },
                      )
                    : null,
              ),
            ),
          ),
        ),
        for (final Widget control in trailing) ...<Widget>[
          const SizedBox(width: 2),
          control,
        ],
      ],
    );
  }
}
