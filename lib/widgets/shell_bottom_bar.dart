import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/app_tokens.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/widgets/app_glyphs.dart';

/// The one bottom bar of the app.
///
/// Read right to left: בית | צ'אטים | פרופיל | המאגר | רעיונות, with
/// "פרופיל" in the middle, drawn as the user's own face in a circle that
/// rises a little above the bar.
///
/// **The bar itself is the ordinary height of a navigation bar.** It used to
/// reserve the circle's full height, and since the strip above the bar was
/// painted in the page colour the bar read as tall as the circle. Now the
/// Scaffold reserves only [barHeight]; the circle is painted [lift] above the
/// bar's top edge over the page, and [_OverflowStack] lets a tap on that
/// raised part still reach it (a tap beside the circle there goes to the
/// page, as it should). A single who does not matchmake has a
/// short bar — בית | צ'אטים | פרופיל | השדכנים שלי — and never the database
/// or the ideas.
///
/// [selected] is the index into those items, or -1 when the page on screen
/// is none of them.
class ShellBottomBar extends StatelessWidget {
  const ShellBottomBar({
    super.key,
    required this.matchmaker,
    required this.selected,
    required this.onSelected,
  });

  final bool matchmaker;
  final int selected;
  final ValueChanged<int> onSelected;

  static const double barHeight = 58;

  /// How far the profile circle rises above the bar's top edge.
  static const double lift = 18;

  static const double faceRadius = 21;

  /// The labels in order, for tests and screen readers.
  static List<String> labelsFor({required bool matchmaker}) => matchmaker
      ? const <String>['בית', 'צ\'אטים', 'פרופיל', 'המאגר', 'רעיונות']
      : const <String>['בית', 'צ\'אטים', 'פרופיל', 'השדכנים שלי'];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BottomNavigationBarThemeData bar = theme.bottomNavigationBarTheme;
    final Color background = bar.backgroundColor ?? theme.colorScheme.surface;
    final Color on = bar.selectedItemColor ?? theme.colorScheme.primary;
    final Color off =
        bar.unselectedItemColor ?? theme.colorScheme.onSurfaceVariant;
    final List<String> labels = labelsFor(matchmaker: matchmaker);
    final double bottom = MediaQuery.viewPaddingOf(context).bottom;
    final bool dark = theme.brightness == Brightness.dark;
    final AppTokens tokens = context.tokens;

    /// At night the active tab takes the accent of what it holds — the
    /// action colour for בית and רעיונות, the blue for the people and the
    /// conversations, the bordeaux for a single's matchmakers — not only a
    /// lighter grey. The light theme keeps its one blue.
    Color onFor(int index) {
      if (!dark) return on;
      if (!matchmaker && index == 3) return tokens.femaleAccent;
      return switch (index) {
        0 || 4 => tokens.ctaAccent,
        _ => tokens.maleAccent,
      };
    }

    Widget item(int index, Widget icon, Widget activeIcon) {
      final bool active = index == selected;
      final Color on = onFor(index);
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          label: labels[index],
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => onSelected(index),
            containedInkWell: true,
            highlightShape: BoxShape.rectangle,
            child: SizedBox(
              height: barHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconTheme.merge(
                    data: IconThemeData(color: active ? on : off, size: 24),
                    child: active ? activeIcon : icon,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      color: active ? on : off,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final List<Widget> items = <Widget>[
      item(0, const Icon(Icons.home_outlined), const Icon(Icons.home_rounded)),
      item(1, const _ChatsIcon(filled: false), const _ChatsIcon(filled: true)),
      _ProfileItem(
        label: labels[2],
        active: selected == 2,
        on: dark ? tokens.textPrimary : on,
        off: off,
        ring: background,
        onTap: () => onSelected(2),
      ),
      if (matchmaker) ...<Widget>[
        item(3, const Icon(Icons.group_outlined), const Icon(Icons.group)),
        item(4, const IdeaBulbIcon(), const IdeaBulbIcon(filled: true)),
      ] else
        item(
          3,
          const Icon(Icons.handshake_outlined),
          const Icon(Icons.handshake_rounded),
        ),
    ];

    // The stack is the outermost box of the bar, sized by its first child
    // to the bar alone; the row of items hangs [lift] above it.
    return _OverflowStack(
      overflow: lift,
      children: <Widget>[
        SizedBox(
          height: barHeight + bottom,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              // At night a hairline marks the bar's edge; a shadow on a dark
              // page is only more dark.
              border: dark
                  ? Border(top: BorderSide(color: tokens.outline, width: 0.6))
                  : null,
              boxShadow: dark
                  ? null
                  : const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 10,
                        offset: Offset(0, -2),
                      ),
                    ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottom,
          top: -lift,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: items,
          ),
        ),
      ],
    );
  }
}

/// A [Stack] that answers taps up to [overflow] pixels above its own top
/// edge, where the profile circle is painted.
///
/// Every [RenderBox] refuses a position outside its own size before asking
/// its children, so the stack has to be the bar's outermost box and has to
/// make the exception itself; its children are then asked as usual, and a
/// tap above the bar that lands on no item (beside the circle) is refused and
/// goes to the page.
class _OverflowStack extends Stack {
  const _OverflowStack({required this.overflow, super.children})
    : super(clipBehavior: Clip.none);

  final double overflow;

  @override
  RenderStack createRenderObject(BuildContext context) => _RenderOverflowStack(
    overflow: overflow,
    textDirection: Directionality.maybeOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderStack renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _RenderOverflowStack).overflow = overflow;
  }
}

class _RenderOverflowStack extends RenderStack {
  _RenderOverflowStack({required this.overflow, super.textDirection})
    : super(clipBehavior: Clip.none);

  double overflow;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final Rect area = Rect.fromLTRB(0, -overflow, size.width, size.height);
    if (!area.contains(position)) {
      return false;
    }
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

/// The chats icon, with the number of conversations that have something
/// unread — the same number on every phone of the account.
class _ChatsIcon extends StatelessWidget {
  const _ChatsIcon({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ChatService.unread,
      builder: (BuildContext context, int unread, _) => Badge(
        isLabelVisible: unread > 0,
        backgroundColor: context.tokens.badge,
        textColor: context.tokens.onBadge,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(
          filled
              ? Icons.chat_bubble_rounded
              : Icons.chat_bubble_outline_rounded,
        ),
      ),
    );
  }
}

/// "פרופיל": the user's own photograph in a circle raised above the bar,
/// or a plain silhouette while there is none.
class _ProfileItem extends StatelessWidget {
  const _ProfileItem({
    required this.label,
    required this.active,
    required this.on,
    required this.off,
    required this.ring,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color on;
  final Color off;
  final Color ring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final AppTokens tokens = context.tokens;
    String? path;
    try {
      path = context.select<UserProfileProvider, String?>(
        (UserProfileProvider p) => p.photoPath,
      );
    } on ProviderNotFoundException {
      path = null;
    }
    final bool hasPhoto = path != null && File(path).existsSync();
    const double r = ShellBottomBar.faceRadius;
    final int px = (r * 2 * MediaQuery.devicePixelRatioOf(context)).ceil();

    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: ShellBottomBar.barHeight + ShellBottomBar.lift,
            // Scaled down rather than overflowing at a large system font.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Container(
                    key: const ValueKey<String>('shell-profile-face'),
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ring,
                      // A soft frame, never a glow: at night the blue when
                      // active and a quiet cream when not.
                      border: Border.all(
                        color: dark
                            ? (active
                                  ? tokens.maleAccent
                                  : tokens.textPrimary.withValues(alpha: 0.45))
                            : (active ? on : off.withValues(alpha: 0.35)),
                        width: active ? 2.4 : 1.4,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Color(dark ? 0x40000000 : 0x29000000),
                          blurRadius: dark ? 6 : 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: r,
                      backgroundColor: tokens.surfaceActive,
                      foregroundImage: hasPhoto
                          ? ResizeImage(
                              FileImage(File(path)),
                              width: px,
                              policy: ResizeImagePolicy.fit,
                            )
                          : null,
                      child: hasPhoto
                          ? null
                          : Icon(
                              Icons.person_rounded,
                              size: r * 1.5,
                              color: off.withValues(alpha: 0.7),
                            ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      color: active ? on : off,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
