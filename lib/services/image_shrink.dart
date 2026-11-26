import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// **Every photo that enters the app is made phone-sized first** — the way
/// WhatsApp sends a picture: the long side at most [maxSide] pixels and JPEG
/// at [quality]. On a phone screen that is indistinguishable from the camera
/// original, and it is typically a tenth of the size: less on the device, and
/// far less in the account's cloud storage, which is where every photo of a
/// friend, a personal card, a profile and a chat ends up.
///
/// Two ways in:
/// * a gallery pick asks the platform's own picker to do it
///   ([pickerMaxSide] / [pickerQuality] on `ImagePicker`), which is native
///   and instant;
/// * everything else — a picture shared in from WhatsApp, a photo inside a
///   WhatsApp export, the photo editor's output — goes through [shrinkInto]
///   or [shrinkInPlace], which decode, rotate by EXIF, scale and re-encode on
///   a background isolate.
///
/// A photo already small enough is kept byte for byte, and a re-encode that
/// would come out *larger* than the original is thrown away. A file that
/// cannot be decoded is copied unchanged — a photo is never lost to this.
abstract final class ImageShrink {
  /// The longest side of a stored photo, in pixels.
  static const int maxSide = 1600;

  /// JPEG quality of a re-encoded photo.
  static const int quality = 82;

  /// The same two numbers for `ImagePicker.pickImage` / `pickMultiImage`.
  static const double pickerMaxSide = 1600;
  static const int pickerQuality = 82;

  /// Under this many bytes a photo is not worth decoding to check its size.
  static const int _smallEnough = 250 * 1024;

  /// [source] written to [targetPath], shrunk when it is worth it.
  static Future<void> shrinkInto(File source, String targetPath) async {
    final Uint8List bytes = await source.readAsBytes();
    final Uint8List? small = await shrinkBytes(bytes);
    await File(targetPath).writeAsBytes(small ?? bytes, flush: true);
  }

  /// [path] rewritten smaller, when it is worth it. Never throws.
  static Future<void> shrinkInPlace(String path) async {
    try {
      final File file = File(path);
      if (!file.existsSync()) return;
      final Uint8List bytes = await file.readAsBytes();
      final Uint8List? small = await shrinkBytes(bytes);
      if (small != null) await file.writeAsBytes(small, flush: true);
    } catch (_) {
      // The original stays as it was.
    }
  }

  /// [bytes] as a phone-sized JPEG, or null when they are already small
  /// enough, cannot be decoded, or would not come out any smaller.
  static Future<Uint8List?> shrinkBytes(Uint8List bytes) async {
    if (bytes.length <= _smallEnough) return null;
    try {
      return await compute(_shrink, bytes);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _shrink(Uint8List bytes) {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // The camera's EXIF rotation is applied before the tag is dropped, so a
    // portrait photo does not come out lying on its side.
    img.Image image = img.bakeOrientation(decoded);
    final int longest = image.width >= image.height
        ? image.width
        : image.height;
    if (longest > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(
              image,
              width: maxSide,
              interpolation: img.Interpolation.average,
            )
          : img.copyResize(
              image,
              height: maxSide,
              interpolation: img.Interpolation.average,
            );
    }
    final Uint8List encoded = img.encodeJpg(image, quality: quality);
    return encoded.length < bytes.length ? encoded : null;
  }
}
