import 'package:flutter/material.dart';

/// **The one bar the app draws.**
///
/// A coloured rule appears all over this app — down the edge of a person's row
/// in המאגר שלי, down both edges of a proposal card in רעיונות שלי, under the
/// two entry cards and under each figure on the home screen — and every one of
/// them had been drawn by hand where it was needed. They came out at different
/// thicknesses, different corner radii and different opacities, which is what
/// makes a page of otherwise identical rows read as several unrelated lists.
///
/// So there is one bar, in two orientations, and nothing else draws one:
///
/// * [AccentStripe] runs down an edge of a row or a card and says *whose* it
///   is — one on a person, one on each edge of a couple.
/// * [AccentUnderline] runs along the foot of a card and says what kind of
///   thing it is.
///
/// Both are [thickness] thick and take the same [radius] on the edge that
/// faces inwards, so a stripe and an underline meeting at a corner are
/// evidently the same rule turned ninety degrees.
abstract final class AccentBar {
  /// How thick every bar in the app is.
  static const double thickness = 4;

  /// The rounding on a bar's inward-facing end. Matches the corner radius the
  /// rows themselves take, so the bar reads as part of the card's own edge.
  static const double radius = 12;

  /// How tall the bar on an ordinary list row is.
  ///
  /// A figure rather than a stretch: a `Row` cannot stretch a child to a
  /// height it does not yet know, and wrapping every row in an
  /// `IntrinsicHeight` to find out costs a second layout pass on a list that
  /// is routinely hundreds of rows long. Rows are a fixed two lines of type,
  /// so the figure is right and the cost is nothing.
  static const double rowHeight = 56;
}

/// A vertical accent bar down one edge of a row or card.
///
/// [atStart] puts it on the reading-start edge — the right, in this app's RTL
/// — which is where a single bar always goes. An item with two sides to it
/// carries a second one with `atStart: false`, so a couple is read as two
/// people from the edges in.
class AccentStripe extends StatelessWidget {
  const AccentStripe({
    super.key,
    required this.color,
    this.atStart = true,
    this.height,
  });

  final Color color;
  final bool atStart;

  /// Null stretches the bar to whatever the row comes to, which is what a row
  /// inside a `Row` of `IntrinsicHeight` or a stretched `CrossAxisAlignment`
  /// wants. A figure is only given here where the row cannot say.
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AccentBar.thickness,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadiusDirectional.horizontal(
          end: atStart ? const Radius.circular(AccentBar.radius) : Radius.zero,
          start: atStart ? Radius.zero : const Radius.circular(AccentBar.radius),
        ),
      ),
    );
  }
}

/// A horizontal accent bar along the foot of a card.
///
/// Drawn flush to the bottom edge, so the card's own `clipBehavior` is what
/// rounds its ends — which is why it takes no radius of its own and why a card
/// carrying one must clip.
class AccentUnderline extends StatelessWidget {
  const AccentUnderline({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(height: AccentBar.thickness, color: color);
  }
}
