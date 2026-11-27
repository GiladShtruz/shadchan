import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shadchan/services/image_shrink.dart';

/// Every photo that enters the app is phone-sized: long side ≤ 1600px, JPEG.
void main() {
  Uint8List noisyPng(int width, int height) {
    final img.Image image = img.Image(width: width, height: height);
    // Noise, so the file is large the way a camera photo is.
    int seed = 7;
    for (final img.Pixel p in image) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      p
        ..r = seed & 0xff
        ..g = (seed >> 8) & 0xff
        ..b = (seed >> 16) & 0xff;
    }
    return img.encodePng(image);
  }

  test('a large photo comes out at most 1600px on its long side', () async {
    final Uint8List original = noisyPng(2400, 1200);
    final Uint8List? small = await ImageShrink.shrinkBytes(original);
    expect(small, isNotNull);
    expect(small!.length, lessThan(original.length));
    final img.Image decoded = img.decodeJpg(small)!;
    expect(decoded.width, ImageShrink.maxSide);
    expect(decoded.height, 800);
  });

  test('a portrait keeps its proportions', () async {
    final Uint8List? small = await ImageShrink.shrinkBytes(
      noisyPng(1000, 2000),
    );
    final img.Image decoded = img.decodeJpg(small!)!;
    expect(decoded.height, ImageShrink.maxSide);
    expect(decoded.width, 800);
  });

  test('a small photo and an unreadable file are left alone', () async {
    expect(await ImageShrink.shrinkBytes(noisyPng(40, 40)), isNull);
    expect(await ImageShrink.shrinkBytes(Uint8List(400 * 1024)), isNull);
  });
}
