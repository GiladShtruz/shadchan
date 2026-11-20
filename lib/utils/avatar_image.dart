import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A face from the network, decoded at the size it is drawn — never at the
/// size it was uploaded.
///
/// **Why this exists.** Matchmakers' community photos are whatever the phone's
/// camera produced (several megabytes, 12 megapixels). A plain [NetworkImage]
/// in a 44px circle decodes every one of them in full: ~48MB of pixels each,
/// held in the image cache after the page is gone. A list of thirty
/// matchmakers was enough to push a mid-range phone into memory pressure and
/// make the whole app stutter, on every screen, until it was restarted
/// ("שדכנים שאני מכיר", 2026-11-20).
///
/// The decode is held to twice the drawn size on each side ([ResizeImagePolicy.fit]
/// keeps the aspect ratio), so a cover-cropped circle stays sharp on a 3x
/// screen while costing a few hundred kilobytes.
ImageProvider<Object> avatarImage(
  BuildContext context,
  String url, {
  required double diameter,
}) {
  final double dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
  final int px = (diameter * dpr * 2).ceil().clamp(48, 1024);
  return ResizeImage(
    NetworkImage(url),
    width: px,
    height: px,
    policy: ResizeImagePolicy.fit,
  );
}

/// [bytes] shrunk so the longest side is at most [maxSide], as PNG — or
/// null when it cannot be decoded. Used before a community avatar is
/// uploaded, so other phones never download a camera frame for a 44px face.
Future<Uint8List?> shrinkImageBytes(
  Uint8List bytes, {
  int maxSide = 480,
}) async {
  try {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );
    final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
      buffer,
    );
    final int w = descriptor.width;
    final int h = descriptor.height;
    final bool landscape = w >= h;
    final ui.Codec codec = await descriptor.instantiateCodec(
      targetWidth: landscape && w > maxSide ? maxSide : null,
      targetHeight: !landscape && h > maxSide ? maxSide : null,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ByteData? data = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
