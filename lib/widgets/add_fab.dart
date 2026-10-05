import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The "+" in the thumb's corner, the same on בית, המאגר שלי and הרעיונות
/// שלי.
///
/// `endFloat` in RTL is the bottom-left corner — the same place the messaging
/// apps everyone already uses put theirs, and the same shape: a rounded square
/// in the palette's light blue, with a white heart and a light-blue plus at
/// its centre. What a tap does is the page's own business.
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
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const HeartPlusIcon(),
    );
  }
}

/// A white heart with a light-blue plus in its middle — "add a friend", in
/// the app's own sign.
///
/// The plus is drawn rather than taken from the icon font: short and heavy
/// with round ends, the way WhatsApp draws its own, where `Icons.add` is long
/// and thin.
class HeartPlusIcon extends StatelessWidget {
  const HeartPlusIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 28,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Icon(Icons.favorite_rounded, color: Colors.white, size: 28),
          // The heart's body sits a touch above the glyph's centre.
          Padding(
            padding: EdgeInsets.only(bottom: 2),
            child: CustomPaint(
              size: Size.square(10),
              painter: _BoldPlusPainter(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoldPlusPainter extends CustomPainter {
  const _BoldPlusPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..strokeWidth = 2.8
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
      oldDelegate.color != color;
}
