import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_tokens.dart';

/// The "+" in the thumb's corner, the same on בית, המאגר שלי and הרעיונות
/// שלי.
///
/// `endFloat` in RTL is the bottom-left corner — the same place the messaging
/// apps everyone already uses put theirs, and the same shape: a rounded square
/// in the palette's light blue with a plain plus. It used to be a plus inside
/// a heart; but the tap opens a choice of *what* to add anyway, so the button
/// only has to say "add". What a tap does is the page's own business.
class AddFab extends StatelessWidget {
  const AddFab({super.key, required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      tooltip: tooltip,
      heroTag: tooltip,
      onPressed: onPressed,
      // At night the "+" is the action colour, the terracotta; by day the
      // light blue it always was.
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? context.tokens.ctaAccent
          : context.tokens.maleAccent,
      foregroundColor: context.tokens.onAccent,
      elevation: Theme.of(context).brightness == Brightness.dark ? 1 : 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const BoldPlusIcon(),
    );
  }
}

/// A plain plus — short and heavy with round ends, the way WhatsApp draws its
/// own, where `Icons.add` is long and thin.
class BoldPlusIcon extends StatelessWidget {
  const BoldPlusIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      size: const Size.square(20),
      painter: _BoldPlusPainter(
        dark ? context.tokens.onAccent : Colors.white,
        width: 3.4,
      ),
    );
  }
}

class _BoldPlusPainter extends CustomPainter {
  const _BoldPlusPainter(this.color, {this.width = 2.8});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final double inset = stroke.strokeWidth / 2;
    canvas
      ..drawLine(
        Offset(size.width / 2, inset),
        Offset(size.width / 2, size.height - inset),
        stroke,
      )
      ..drawLine(
        Offset(inset, size.height / 2),
        Offset(size.width - inset, size.height / 2),
        stroke,
      );
  }

  @override
  bool shouldRepaint(covariant _BoldPlusPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.width != width;
}
