import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// Viewing and lightly fixing one photo.
///
/// Deliberately few tools: crop (a free frame dragged by its corners and edges,
/// with the photo panned and pinched under it), rotate, straighten, and
/// brightness. That is what a photo forwarded from WhatsApp actually needs —
/// it arrived sideways, or dark, or with the person off to one side — and every
/// tool past that turns a card editor into an image app.
///
/// It is written against `dart:ui` rather than an editing package because the
/// whole job is one `drawImageRect` under a transform: adding a plugin here
/// would mean native configuration on both platforms for four sliders.
class PhotoEditScreen extends StatefulWidget {
  const PhotoEditScreen({super.key, required this.path});

  final String path;

  /// Returns the path of the edited photo, or null when nothing was saved.
  /// The result is a *new* file, so an edit never destroys the original until
  /// the caller swaps it in.
  static Future<String?> open(BuildContext context, String path) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (BuildContext context) => PhotoEditScreen(path: path),
      ),
    );
  }

  @override
  State<PhotoEditScreen> createState() => _PhotoEditScreenState();
}

class _PhotoEditScreenState extends State<PhotoEditScreen> {
  final TransformationController _viewer = TransformationController();
  final GlobalKey _frameKey = GlobalKey();

  ui.Image? _image;
  bool _saving = false;

  /// Whole turns, applied before the fine angle.
  int _quarterTurns = 0;

  /// Fine straightening, in degrees.
  double _straighten = 0;

  /// -1 … 1, zero being the photo as it is.
  double _brightness = 0;

  /// The kept part of the frame, as fractions of it (0…1 on both axes).
  /// Dragged freely by its handles — no fixed proportion — while panning and
  /// pinching the photo under it chooses what falls inside.
  Rect _crop = _fullCrop;

  static const Rect _fullCrop = Rect.fromLTRB(0, 0, 1, 1);

  @override
  void initState() {
    super.initState();
    // **The crop is the viewer's transform**, and the save button's enabled
    // state depends on it — so a pan or a pinch has to rebuild the bar. Without
    // this listener a crop alone left "שמירה" disabled, which is the bug that
    // made cropping look unsaveable.
    _viewer.addListener(_onViewerChanged);
    _load();
  }

  void _onViewerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _viewer.removeListener(_onViewerChanged);
    _viewer.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final File file = File(widget.path);
    if (!file.existsSync()) {
      return;
    }
    final Uint8List bytes = await file.readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _image = frame.image);
  }

  bool get _isChanged =>
      _crop != _fullCrop ||
      _quarterTurns != 0 ||
      _straighten.abs() > 0.01 ||
      _brightness.abs() > 0.01 ||
      _viewer.value != Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ui.Image? image = _image;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('עריכת תמונה'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'סגירה',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _saving || image == null || !_isChanged ? null : _save,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('שמירה'),
          ),
        ],
      ),
      body: image == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AspectRatio(
                        aspectRatio: _frameRatio(image),
                        child: ClipRRect(
                          key: _frameKey,
                          borderRadius: BorderRadius.circular(4),
                          child: ColoredBox(
                            color: Colors.black,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                InteractiveViewer(
                                  transformationController: _viewer,
                                  minScale: 0.5,
                                  maxScale: 5,
                                  clipBehavior: Clip.none,
                                  // Panning and zooming inside the frame is
                                  // the crop: what stays inside is kept.
                                  // Whole turns are a `RotatedBox`, not part of
                                  // the rotation angle: it lays the photo out
                                  // in its own proportion and then turns it,
                                  // so a turned photo is still the whole
                                  // photo. Rotating a `cover` image inside the
                                  // already-turned frame used to cut off most
                                  // of it without anybody asking for a crop.
                                  child: Transform.rotate(
                                    angle: _straightenAngle,
                                    child: RotatedBox(
                                      quarterTurns: _quarterTurns,
                                      child: ColorFiltered(
                                        colorFilter: _brightnessFilter,
                                        child: RawImage(
                                          image: image,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // The crop frame itself: the outside dimmed,
                                // a border and thirds, and a handle on every
                                // corner and edge. Only the handles take a
                                // finger; everywhere else pans the photo.
                                _CropOverlay(
                                  crop: _crop,
                                  onChanged: (Rect crop) =>
                                      setState(() => _crop = crop),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _Tools(
                  straighten: _straighten,
                  brightness: _brightness,
                  // A turn changes the frame's proportion, so a crop drawn for
                  // the old one would land somewhere else — start it afresh.
                  onRotate: () => setState(() {
                    _quarterTurns = (_quarterTurns + 1) % 4;
                    _crop = _fullCrop;
                  }),
                  onStraighten: (double value) =>
                      setState(() => _straighten = value),
                  onBrightness: (double value) =>
                      setState(() => _brightness = value),
                  onReset: () => setState(() {
                    _crop = _fullCrop;
                    _quarterTurns = 0;
                    _straighten = 0;
                    _brightness = 0;
                    _viewer.value = Matrix4.identity();
                  }),
                  theme: theme,
                ),
              ],
            ),
    );
  }

  /// The frame's width over its height: the photo's own proportion, turned
  /// with it. The crop inside it is free.
  double _frameRatio(ui.Image image) {
    final double ratio = image.width / image.height;
    return _quarterTurns.isOdd ? 1 / ratio : ratio;
  }

  double get _straightenAngle => _straighten * math.pi / 180;

  double get _totalAngle => _quarterTurns * math.pi / 2 + _straightenAngle;

  /// A plain luminance offset. Multiplying instead would blow out anything
  /// already bright, which is the opposite of what a dark phone photo needs.
  ColorFilter get _brightnessFilter {
    final double offset = _brightness * 90;
    return ColorFilter.matrix(<double>[
      1, 0, 0, 0, offset, //
      0, 1, 0, 0, offset, //
      0, 0, 1, 0, offset, //
      0, 0, 0, 1, 0, //
    ]);
  }

  /// Renders exactly what the frame shows into a new file.
  ///
  /// The same transform chain the preview uses is replayed onto a canvas, so
  /// what was on screen is what is written — no second interpretation of the
  /// crop that could disagree with the one the user was looking at.
  Future<void> _save() async {
    final ui.Image? image = _image;
    final RenderBox? frame =
        _frameKey.currentContext?.findRenderObject() as RenderBox?;
    if (image == null || frame == null) {
      return;
    }

    setState(() => _saving = true);
    try {
      final Size frameSize = frame.size;
      // Output at the photo's own resolution rather than the phone's, so an
      // edit is not also a downscale.
      // (On an odd turn the photo's width runs along the frame's height.)
      final double outputScale =
          (image.width /
                  (_quarterTurns.isOdd ? frameSize.height : frameSize.width))
              .clamp(1.0, 4.0)
              .toDouble();
      // Only the part inside the crop frame is written.
      final Rect kept = Rect.fromLTRB(
        _crop.left * frameSize.width,
        _crop.top * frameSize.height,
        _crop.right * frameSize.width,
        _crop.bottom * frameSize.height,
      );
      final double outWidth = kept.width * outputScale;
      final double outHeight = kept.height * outputScale;

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, outWidth, outHeight),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, outWidth, outHeight),
        Paint()..color = Colors.black,
      );
      canvas.save();
      canvas.scale(outputScale);
      canvas.translate(-kept.left, -kept.top);
      // The pan/zoom the user set inside the frame.
      canvas.transform(_viewer.value.storage);
      // Then the rotation about the frame's centre, matching the preview's
      // Transform.rotate around a RotatedBox: the photo is laid out in a box
      // of its own proportion (the frame's, swapped on an odd turn), centred,
      // and turned by the whole turns plus the straightening together.
      final Size photoBox = _quarterTurns.isOdd
          ? Size(frameSize.height, frameSize.width)
          : frameSize;
      canvas.translate(frameSize.width / 2, frameSize.height / 2);
      canvas.rotate(_totalAngle);
      canvas.translate(-photoBox.width / 2, -photoBox.height / 2);

      final Paint paint = Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter = _brightnessFilter;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        _coverRect(
          Size(image.width.toDouble(), image.height.toDouble()),
          photoBox,
        ),
        paint,
      );
      canvas.restore();

      final ui.Image rendered = await recorder.endRecording().toImage(
        outWidth.round(),
        outHeight.round(),
      );
      final ByteData? encoded = await rendered.toByteData(
        format: ui.ImageByteFormat.png,
      );
      rendered.dispose();
      if (encoded == null) {
        _fail();
        return;
      }

      final Directory photos = await PhotoPickerService.ensurePhotosDirectory();
      final File output = File(
        '${photos.path}${Platform.pathSeparator}'
        'edited_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await output.writeAsBytes(encoded.buffer.asUint8List());

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(output.path);
    } catch (_) {
      _fail();
    }
  }

  /// Where a `BoxFit.cover` image lands inside the frame — the same rectangle
  /// `RawImage` drew in the preview.
  Rect _coverRect(Size image, Size frame) {
    final double scale = math.max(
      frame.width / image.width,
      frame.height / image.height,
    );
    final double width = image.width * scale;
    final double height = image.height * scale;
    return Rect.fromLTWH(
      (frame.width - width) / 2,
      (frame.height - height) / 2,
      width,
      height,
    );
  }

  void _fail() {
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    AppNotice.show(context, 'לא הצלחנו לשמור את התמונה');
  }
}

class _Tools extends StatelessWidget {
  const _Tools({
    required this.straighten,
    required this.brightness,
    required this.onRotate,
    required this.onStraighten,
    required this.onBrightness,
    required this.onReset,
    required this.theme,
  });

  final double straighten;
  final double brightness;
  final VoidCallback onRotate;
  final ValueChanged<double> onStraighten;
  final ValueChanged<double> onBrightness;
  final VoidCallback onReset;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'החיתוך לא חובה — התמונה נשמרת בגודל המקורי שלה. '
              'כדי לחתוך, גררו את הפינות והצדדים של המסגרת',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            _Slider(
              icon: Icons.straighten,
              label: 'יישור',
              value: straighten,
              min: -15,
              max: 15,
              onChanged: onStraighten,
            ),
            _Slider(
              icon: Icons.brightness_6_outlined,
              label: 'בהירות',
              value: brightness,
              min: -1,
              max: 1,
              onChanged: onBrightness,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                TextButton.icon(
                  onPressed: onRotate,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.rotate_90_degrees_ccw_outlined),
                  label: const Text('סיבוב'),
                ),
                TextButton.icon(
                  onPressed: onReset,
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('איפוס'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The free crop frame drawn over the photo: everything outside it dimmed, a
/// border with thirds inside it, and eight handles — four corners and four
/// edges — that move its sides. Nothing else on it takes a touch, so a finger
/// anywhere but a handle still pans and pinches the photo underneath.
class _CropOverlay extends StatelessWidget {
  const _CropOverlay({required this.crop, required this.onChanged});

  /// Fractions of the frame, 0…1.
  final Rect crop;
  final ValueChanged<Rect> onChanged;

  /// The smallest the crop may get, as a fraction of the frame on each axis.
  static const double _minSize = 0.12;

  /// The finger's target around each handle.
  static const double _hit = 36;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        final Rect box = Rect.fromLTRB(
          crop.left * size.width,
          crop.top * size.height,
          crop.right * size.width,
          crop.bottom * size.height,
        );

        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            IgnorePointer(
              child: CustomPaint(size: size, painter: _CropGuides(box)),
            ),
            for (final _Edge edge in _Edge.values)
              _handle(edge: edge, box: box, size: size),
          ],
        );
      },
    );
  }

  Widget _handle({required _Edge edge, required Rect box, required Size size}) {
    final Offset at = edge.anchorOn(box);
    return Positioned(
      left: at.dx - _hit / 2,
      top: at.dy - _hit / 2,
      width: _hit,
      height: _hit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (DragUpdateDetails details) {
          final double dx = details.delta.dx / size.width;
          final double dy = details.delta.dy / size.height;
          double left = crop.left;
          double top = crop.top;
          double right = crop.right;
          double bottom = crop.bottom;
          if (edge.movesLeft) {
            left = (left + dx).clamp(0.0, right - _minSize);
          }
          if (edge.movesRight) {
            right = (right + dx).clamp(left + _minSize, 1.0);
          }
          if (edge.movesTop) {
            top = (top + dy).clamp(0.0, bottom - _minSize);
          }
          if (edge.movesBottom) {
            bottom = (bottom + dy).clamp(top + _minSize, 1.0);
          }
          onChanged(Rect.fromLTRB(left, top, right, bottom));
        },
        child: Center(
          child: Container(
            width: edge.isCorner
                ? 18
                : (edge.movesTop || edge.movesBottom ? 26 : 6),
            height: edge.isCorner
                ? 18
                : (edge.movesLeft || edge.movesRight ? 26 : 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(edge.isCorner ? 4 : 3),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Colors.black45, blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The eight handles of the crop frame, and which sides each one moves.
enum _Edge {
  topLeft(movesLeft: true, movesTop: true),
  topRight(movesRight: true, movesTop: true),
  bottomLeft(movesLeft: true, movesBottom: true),
  bottomRight(movesRight: true, movesBottom: true),
  top(movesTop: true),
  bottom(movesBottom: true),
  left(movesLeft: true),
  right(movesRight: true);

  const _Edge({
    this.movesLeft = false,
    this.movesRight = false,
    this.movesTop = false,
    this.movesBottom = false,
  });

  final bool movesLeft;
  final bool movesRight;
  final bool movesTop;
  final bool movesBottom;

  bool get isCorner => (movesLeft || movesRight) && (movesTop || movesBottom);

  Offset anchorOn(Rect box) => Offset(
    movesLeft ? box.left : (movesRight ? box.right : box.center.dx),
    movesTop ? box.top : (movesBottom ? box.bottom : box.center.dy),
  );
}

/// The dimmed outside, a white frame and rule-of-thirds lines inside it —
/// what says "this is a crop".
class _CropGuides extends CustomPainter {
  const _CropGuides(this.box);

  final Rect box;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(box),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    final Paint line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (int i = 1; i < 3; i++) {
      final double x = box.left + box.width * i / 3;
      final double y = box.top + box.height * i / 3;
      canvas.drawLine(Offset(x, box.top), Offset(x, box.bottom), line);
      canvas.drawLine(Offset(box.left, y), Offset(box.right, y), line);
    }
    canvas.drawRect(
      box,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropGuides oldDelegate) =>
      oldDelegate.box != box;
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: AppColors.primaryLight,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
