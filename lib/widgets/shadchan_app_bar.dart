import 'package:flutter/material.dart';
import 'package:shadchan/dialogs/app_menu.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/reminders_bell_button.dart';

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
/// **The page's own name is back in the bar, and the search row hangs off it.**
/// The heading had moved onto the page, which cost a whole line under a banner
/// that was only repeating the app's name to somebody already inside it; and
/// the search row was a sliver, which meant it scrolled away exactly when a
/// long list made it worth having. A [title] replaces the wordmark on the tabs
/// that have a name of their own, and [ShadchanSearchBottom] pins the field
/// under the bar so neither the name nor the field ever leaves the screen.
class ShadchanAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShadchanAppBar({
    super.key,
    this.actions = const <Widget>[],
    this.leading,
    this.bottom,
    this.title,
  });

  /// The page's own controls, at the far end of the bar.
  final List<Widget> actions;

  /// A way back, for the screens that are pushed rather than tabbed. Null on a
  /// tab, where the bar starts with the wordmark and nothing before it.
  final Widget? leading;

  final PreferredSizeWidget? bottom;

  /// The page's own name, in place of the wordmark.
  ///
  /// **המאגר שלי and רעיונות sign themselves now.** The heading used to live on
  /// the page, under a bar that said "שדכן" — which cost a full line of the
  /// screen to repeat the app's name on a tab the reader is already inside.
  /// The bar carries the wordmark only on בית, where there is no other name for
  /// the page; everywhere else it carries the page's, and the line that used to
  /// hold it is gone.
  final String? title;

  /// Deliberately shorter than Material's 56. The three tabs each hang a search
  /// row off the bottom of this bar, and the pair has to stay out of the way of
  /// the page it belongs to.
  static const double toolbarHeight = 50;

  @override
  Size get preferredSize {
    return Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? name = title;

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
      toolbarHeight: toolbarHeight,
      leading: leading,
      // With nothing before it the wordmark starts hard against the page's own
      // margin, so it lines up with the cards underneath.
      leadingWidth: leading == null ? 0 : null,
      titleSpacing: leading == null ? 16 : 4,
      centerTitle: false,
      title: name == null
          ? const ShadchanWordmark()
          : Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.15,
                color: theme.colorScheme.onSurface,
              ),
            ),
      actions: <Widget>[...actions, const SizedBox(width: 6)],
      bottom: bottom,
    );
  }
}

/// The three controls every tab wears, in one order and with nothing between
/// them.
///
/// **The three bars carried three different corners.** בית had the bell and the
/// overflow dots; המאגר שלי had the bell and a "+"; רעיונות had the bell and a
/// different "+" — and none of them had all three, so the menu was reachable
/// from one tab out of three and the "+" from two. Whichever tab somebody was
/// on, one of the two things they might want was somewhere else.
///
/// So the group is a widget rather than a list each screen writes out: the
/// dots, the "+" and the bell, always, in that order reading across the bar.
/// Only what the "+" *does* differs — see [add] — because that is the one thing
/// that genuinely depends on the page.
///
/// **Two of them touch and one does not.** Three squares with equal gaps read
/// as a strip; three with no gap at all read as one slab, and the bell —
/// which is the one control of the three that is about something *arriving*
/// rather than about this page — was pressed hard against the "+" beside it.
/// So the "+" sits against the overflow dots, where the pair is the page's own
/// menu of things to do, and a hair of air separates that pair from the bell.
/// Each square keeps its own border, so nothing runs together.
class ShadchanTabActions extends StatelessWidget {
  const ShadchanTabActions({
    super.key,
    required this.add,
    this.menu = AppMenuVariant.list,
  });

  /// The middle control. [ShadchanAddButton] for a page with one thing to add,
  /// [AddMenuButton] for the home screen, which has two.
  final Widget add;

  /// Which overflow menu the bar carries. בית has its own — see
  /// [AppMenuVariant]; the two lists share the other.
  final AppMenuVariant menu;

  @override
  Widget build(BuildContext context) {
    // A Row rather than three entries in `actions`, so the spacing between them
    // is decided here once instead of by whichever screen wrote the list —
    // `AppBar` puts its own air between `actions` children.
    //
    // In RTL the first child is the rightmost, so this reads across the screen
    // from the left as: the menu dots at the outer edge, then the "+", then the
    // bell nearest the page's own name.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const RemindersBellButton(boxed: true),
        const SizedBox(width: 5),
        add,
        AppMenuButton(boxed: true, variant: menu),
      ],
    );
  }
}

/// A "+" that does one thing, for the two tabs where it can only mean one
/// thing.
class ShadchanAddButton extends StatelessWidget {
  const ShadchanAddButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return HomeBarButton(
      tooltip: tooltip,
      icon: const Icon(Icons.add),
      onPressed: onPressed,
    );
  }
}

/// The search row worn as the bar's own bottom edge.
///
/// **It does not scroll away any more.** Search was a sliver at the top of each
/// page, which meant the one control every one of these screens exists to be
/// used with was gone the moment somebody scrolled past it — and coming back to
/// it cost a flick to the top of a list of four hundred names. Hung off the bar
/// it is always exactly where it was left, the way it is in a messaging app.
///
/// Held to the field's own height plus one small gap: a fixed strip across the
/// top of every screenful has to earn each pixel it takes.
class ShadchanSearchBottom extends StatelessWidget
    implements PreferredSizeWidget {
  const ShadchanSearchBottom({super.key, required this.child});

  final Widget child;

  /// [ShadchanSearchField]'s own 44, and 8 of air under it.
  static const double _height = 52;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: child,
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
/// read as "type here" without being read at all. It rides in the bar's own
/// bottom edge — see [ShadchanSearchBottom] — so it is where it was left
/// however far down the page somebody has scrolled.
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
