import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

/// "אפשר לשמור עד 4 תמונות בכרטיס" — for an owner whose card came from an
/// older version with more photos than a card may carry.
///
/// **Nothing is ever dropped without the owner choosing.** Older versions let
/// a personal card hold any number of photos; a card now holds
/// [PersonalCardCodec.maxPhotos]. Cutting the list down to its first four
/// silently would decide for the owner which of their own pictures the
/// matchmakers stop seeing, so instead they are asked, once, before they go
/// on: every photo is shown, the first four are ticked to start with, and the
/// card is saved only with what they keep. The photo *files* are left on the
/// device either way — only the card stops carrying the ones not chosen.
abstract final class CardPhotoChoiceDialog {
  /// Whether [photos] is more than a card may carry.
  static bool needed(List<String> photos) =>
      photos.length > PersonalCardCodec.maxPhotos;

  /// The photos the owner chose to keep, in the card's order, or null when
  /// they backed out without choosing.
  static Future<List<String>?> show(
    BuildContext context,
    List<String> photos, {
    Gender? gender,
  }) {
    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          _CardPhotoChoice(photos: photos, gender: gender),
    );
  }

  static String message(Gender? gender) => GenderText.resolveOrBoth(
    'אפשר לשמור עד ${PersonalCardCodec.maxPhotos} תמונות בכרטיס. '
    '{בחר|בחרי} אילו תמונות {תרצה|תרצי} להשאיר.',
    gender,
  );
}

class _CardPhotoChoice extends StatefulWidget {
  const _CardPhotoChoice({required this.photos, this.gender});

  final List<String> photos;
  final Gender? gender;

  @override
  State<_CardPhotoChoice> createState() => _CardPhotoChoiceState();
}

class _CardPhotoChoiceState extends State<_CardPhotoChoice> {
  late final Set<int> _chosen = <int>{
    for (int i = 0; i < widget.photos.length; i++)
      if (i < PersonalCardCodec.maxPhotos) i,
  };

  void _toggle(int index) {
    setState(() {
      if (_chosen.contains(index)) {
        _chosen.remove(index);
      } else if (_chosen.length < PersonalCardCodec.maxPhotos) {
        _chosen.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int max = PersonalCardCodec.maxPhotos;
    final bool full = _chosen.length >= max;
    return AlertDialog(
      scrollable: true,
      title: const Text('בחירת תמונות לכרטיס'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              CardPhotoChoiceDialog.message(widget.gender),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'נבחרו ${_chosen.length} מתוך $max',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (int i = 0; i < widget.photos.length; i++)
                  SizedBox.square(
                    dimension: 88,
                    child: _PhotoTile(
                      path: widget.photos[i],
                      chosen: _chosen.contains(i),
                      dimmed: full && !_chosen.contains(i),
                      onTap: () => _toggle(i),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('לא עכשיו'),
        ),
        FilledButton(
          onPressed: _chosen.isEmpty
              ? null
              : () {
                  final List<int> order = _chosen.toList()..sort();
                  Navigator.of(
                    context,
                  ).pop(<String>[for (final int i in order) widget.photos[i]]);
                },
          child: const Text('שמירה'),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.path,
    required this.chosen,
    required this.dimmed,
    required this.onTap,
  });

  final String path;
  final bool chosen;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final File file = File(path);
    return Semantics(
      button: true,
      selected: chosen,
      label: chosen ? 'תמונה שנבחרה' : 'תמונה שלא נבחרה',
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: dimmed ? 0.45 : 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: chosen ? AppColors.primaryDark : AppColors.divider,
                width: chosen ? 2.4 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (file.existsSync())
                  Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: AppColors.softBlue,
                      child: Icon(Icons.image_not_supported_outlined),
                    ),
                  )
                else
                  const ColoredBox(
                    color: AppColors.softBlue,
                    child: Icon(Icons.image_not_supported_outlined),
                  ),
                PositionedDirectional(
                  top: 4,
                  end: 4,
                  child: Icon(
                    chosen
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: chosen ? AppColors.primaryDark : Colors.white,
                    shadows: const <Shadow>[
                      Shadow(blurRadius: 4, color: Colors.black38),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
