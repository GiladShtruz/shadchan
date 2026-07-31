import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:hive/hive.dart';

/// Works out where the face sits inside a photo, so a round avatar can be
/// centred on it instead of cropping it off.
///
/// Detection runs on-device (ML Kit) and only ever reads the file — no photo
/// leaves the device. Every result is cached, in memory and in the Hive
/// `settings` box, keyed by the photo path: a photo is analysed once and every
/// later app start reuses the answer, so avatars never flicker.
abstract final class FaceCropService {
  static const String _keyPrefix = 'faceAlign.';

  /// Stored for photos where no face was found, so they are not re-analysed on
  /// every launch. Read back as [Alignment.center].
  static const String _noFaceMarker = 'none';

  static final Map<String, Alignment> _memoryCache = <String, Alignment>{};

  /// Photos currently being analysed, so a widget rebuild mid-detection does
  /// not start the same work twice.
  static final Map<String, Future<Alignment>> _inFlight =
      <String, Future<Alignment>>{};

  static FaceDetector? _detector;

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  /// The alignment already known for [path], or null when the photo has not
  /// been analysed yet. Synchronous, so a widget can paint the right crop on
  /// its very first frame.
  static Alignment? cached(String path) {
    final Alignment? fromMemory = _memoryCache[path];
    if (fromMemory != null) {
      return fromMemory;
    }

    final Object? stored = _box?.get('$_keyPrefix$path');
    if (stored is! String) {
      return null;
    }

    final Alignment alignment = _parse(stored);
    _memoryCache[path] = alignment;
    return alignment;
  }

  /// The alignment for [path], detecting the face first when it is not cached
  /// yet. Falls back to [Alignment.center] for photos without a detectable
  /// face and whenever detection is unavailable.
  static Future<Alignment> resolve(String path) {
    final Alignment? known = cached(path);
    if (known != null) {
      return Future<Alignment>.value(known);
    }

    return _inFlight[path] ??= _detect(path).whenComplete(() {
      _inFlight.remove(path);
    });
  }

  /// Drops the cached alignment of a photo that is no longer used, so the
  /// settings box does not grow with entries for deleted files.
  static Future<void> forget(String path) async {
    _memoryCache.remove(path);
    await _box?.delete('$_keyPrefix$path');
  }

  static Future<Alignment> _detect(String path) async {
    try {
      final ui.Size? size = await _imageSize(path);
      if (size == null) {
        return Alignment.center;
      }

      final List<Face> faces = await _faceDetector().processImage(
        InputImage.fromFilePath(path),
      );
      if (faces.isEmpty) {
        await _store(path, _noFaceMarker);
        return Alignment.center;
      }

      // With several people in the photo the largest face is the one the card
      // is about.
      final Face largest = faces.reduce(
        (Face a, Face b) =>
            _area(a.boundingBox) >= _area(b.boundingBox) ? a : b,
      );
      final Alignment alignment = _alignmentFor(
        face: largest.boundingBox,
        imageWidth: size.width,
        imageHeight: size.height,
      );

      _memoryCache[path] = alignment;
      await _store(path, '${alignment.x},${alignment.y}');
      return alignment;
    } catch (error, stackTrace) {
      // A photo we cannot analyse simply keeps the plain centred crop.
      debugPrint(
        'FaceCropService.detect failed for $path: $error\n$stackTrace',
      );
      return Alignment.center;
    }
  }

  /// The alignment that puts the centre of [face] in the middle of a *square*
  /// `BoxFit.cover` crop — which is what every avatar in the app is.
  ///
  /// With cover, the visible part of the source is a square of `min(w, h)`, and
  /// Flutter positions it at `(source - visible) * (alignment + 1) / 2`. This
  /// inverts that so the face centre lands on the middle of the visible square,
  /// clamped to the edges when the face sits too close to one of them.
  static Alignment _alignmentFor({
    required Rect face,
    required double imageWidth,
    required double imageHeight,
  }) {
    final double visible = imageWidth < imageHeight ? imageWidth : imageHeight;
    return Alignment(
      _axisAlignment(face.center.dx, imageWidth, visible),
      _axisAlignment(face.center.dy, imageHeight, visible),
    );
  }

  static double _axisAlignment(
    double faceCenter,
    double total,
    double visible,
  ) {
    final double slack = total - visible;
    if (slack <= 0) {
      return 0;
    }
    final double value = 2 * (faceCenter - visible / 2) / slack - 1;
    return value.clamp(-1.0, 1.0);
  }

  static double _area(Rect rect) => rect.width * rect.height;

  static Future<void> _store(String path, String value) async {
    await _box?.put('$_keyPrefix$path', value);
  }

  static Alignment _parse(String stored) {
    if (stored == _noFaceMarker) {
      return Alignment.center;
    }
    final List<String> parts = stored.split(',');
    if (parts.length != 2) {
      return Alignment.center;
    }
    final double? x = double.tryParse(parts[0]);
    final double? y = double.tryParse(parts[1]);
    if (x == null || y == null) {
      return Alignment.center;
    }
    return Alignment(x, y);
  }

  /// The photo's pixel dimensions the way it is actually shown — the space the
  /// face detector reports its boxes in.
  ///
  /// A camera photo often carries an EXIF orientation, and the header's width
  /// and height are the two axes *before* it is applied. Both the renderer and
  /// the detector work on the upright picture, so the header pair is swapped
  /// when a small test decode comes back the other way round. Only a thumbnail
  /// is decoded — the full image is never held in memory just to be measured.
  static Future<ui.Size?> _imageSize(String path) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromFilePath(
      path,
    );
    try {
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
        buffer,
      );
      final double rawWidth = descriptor.width.toDouble();
      final double rawHeight = descriptor.height.toDouble();
      if (rawWidth <= 0 || rawHeight <= 0) {
        descriptor.dispose();
        return null;
      }

      final ui.Codec codec = await descriptor.instantiateCodec(targetWidth: 64);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final bool uprightIsWide = frame.image.width > frame.image.height;
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();

      final bool swapped = uprightIsWide != (rawWidth > rawHeight);
      return swapped
          ? ui.Size(rawHeight, rawWidth)
          : ui.Size(rawWidth, rawHeight);
    } finally {
      buffer.dispose();
    }
  }

  static FaceDetector _faceDetector() {
    // Kept alive between photos: creating a detector spins up the native model
    // each time, which would make a list of avatars crawl.
    return _detector ??= FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
    );
  }
}
