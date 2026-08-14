import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/app_colors.dart';

/// Viewing and lightly fixing one photo.
///
/// Deliberately four tools and no more: reposition, rotate, straighten, and
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
                        aspectRatio: 3 / 4,
                        child: ClipRRect(
                          key: _frameKey,
                          borderRadius: BorderRadius.circular(12),
                          child: ColoredBox(
                            color: Colors.black,
                            child: InteractiveViewer(
                              transformationController: _viewer,
                              minScale: 0.5,
                              maxScale: 5,
                              clipBehavior: Clip.none,
                              // Panning and zooming inside the frame is the
                              // crop: what stays inside is what is kept.
                              child: Transform.rotate(
                                angle: _totalAngle,
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
                        ),
                      ),
                    ),
                  ),
                ),
                _Tools(
                  straighten: _straighten,
                  brightness: _brightness,
                  onRotate: () =>
                      setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                  onStraighten: (double value) =>
                      setState(() => _straighten = value),
                  onBrightness: (double value) =>
                      setState(() => _brightness = value),
                  onReset: () => setState(() {
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

  double get _totalAngle =>
      _quarterTurns * math.pi / 2 + _straighten * math.pi / 180;

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
      final double outputScale = (image.width / frameSize.width)
          .clamp(1.0, 4.0)
          .toDouble();
      final double outWidth = frameSize.width * outputScale;
      final double outHeight = frameSize.height * outputScale;

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
      // The pan/zoom the user set inside the frame.
      canvas.transform(_viewer.value.storage);
      // Then the rotation, about the frame's centre, matching Transform.rotate.
      canvas.translate(frameSize.width / 2, frameSize.height / 2);
      canvas.rotate(_totalAngle);
      canvas.translate(-frameSize.width / 2, -frameSize.height / 2);

      final Paint paint = Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter = _brightnessFilter;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        _coverRect(
          Size(image.width.toDouble(), image.height.toDouble()),
          frameSize,
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('לא הצלחנו לשמור את התמונה')),
      );
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
              'גררו והצביטו כדי למקם ולחתוך את התמונה',
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
