import 'dart:io';

import 'package:flutter/material.dart';

/// The photo strip used while adding or editing a person: a horizontal row of
/// thumbnails where the first one is the card's main photo, plus buttons to add
/// more or remove one.
class PersonPhotoEditor extends StatelessWidget {
  const PersonPhotoEditor({
    super.key,
    required this.photoPaths,
    required this.onAddPhoto,
    required this.onSetPrimary,
    this.onRemove,
    this.onReorder,
  });

  final List<String> photoPaths;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onSetPrimary;
  final ValueChanged<int>? onRemove;
  final ReorderCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('תמונות', style: theme.textTheme.titleMedium)),
            TextButton.icon(
              onPressed: onAddPhoto,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('הוספת תמונות'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (photoPaths.isEmpty)
          Text(
            'אין תמונות — יוצג איור ברירת המחדל',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          SizedBox(
            height: 96,
            child: onReorder == null
                ? ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photoPaths.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (BuildContext context, int index) {
                      return _PhotoThumb(
                        path: photoPaths[index],
                        isPrimary: index == 0,
                        onSetPrimary: () => onSetPrimary(index),
                        onRemove: onRemove == null
                            ? null
                            : () => onRemove!(index),
                      );
                    },
                  )
                : ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    itemCount: photoPaths.length,
                    onReorder: onReorder!,
                    itemBuilder: (BuildContext context, int index) {
                      final String path = photoPaths[index];
                      return Padding(
                        key: ValueKey<String>(path),
                        padding: EdgeInsetsDirectional.only(
                          end: index == photoPaths.length - 1 ? 0 : 12,
                        ),
                        child: _PhotoThumb(
                          path: path,
                          isPrimary: index == 0,
                          onSetPrimary: () => onSetPrimary(index),
                          onRemove: onRemove == null
                              ? null
                              : () => onRemove!(index),
                          reorderIndex: index,
                        ),
                      );
                    },
                  ),
          ),
        if (photoPaths.length > 1 && onReorder != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            'גרירה באמצעות הידית משנה את סדר התמונות',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.path,
    required this.isPrimary,
    required this.onSetPrimary,
    required this.onRemove,
    this.reorderIndex,
  });

  final String path;
  final bool isPrimary;
  final VoidCallback onSetPrimary;
  final VoidCallback? onRemove;
  final int? reorderIndex;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final File file = File(path);

    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: file.existsSync()
              ? Image.file(
                  file,
                  width: 80,
                  height: 96,
                  cacheWidth: 160,
                  fit: BoxFit.cover,
                )
              : Container(
                  width: 80,
                  height: 96,
                  color: theme.colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        PositionedDirectional(
          top: 4,
          end: 4,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              tooltip: isPrimary ? 'זו התמונה הראשית' : 'הגדרה כתמונה ראשית',
              onPressed: isPrimary ? null : onSetPrimary,
              icon: Icon(
                isPrimary ? Icons.star : Icons.star_border,
                color: isPrimary ? Colors.amber : Colors.white,
              ),
            ),
          ),
        ),
        if (onRemove != null)
          PositionedDirectional(
            top: 4,
            start: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'הסרת התמונה',
                onPressed: onRemove,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
        if (isPrimary)
          PositionedDirectional(
            bottom: 4,
            start: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'ראשית',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        if (reorderIndex != null)
          PositionedDirectional(
            bottom: 4,
            end: 4,
            child: ReorderableDragStartListener(
              index: reorderIndex!,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.drag_indicator_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
