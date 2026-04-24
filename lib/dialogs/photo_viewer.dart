import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.personId,
    required this.photoPaths,
    required this.initialIndex,
  });

  final String personId;
  final List<String> photoPaths;
  final int initialIndex;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pageController;
  late List<String> _photoPaths;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _photoPaths = List<String>.from(widget.photoPaths);
    _currentIndex = widget.initialIndex.clamp(
      0,
      _photoPaths.isEmpty ? 0 : _photoPaths.length - 1,
    );
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            if (_photoPaths.isEmpty)
              const Center(
                child: Text(
                  'אין תמונות להצגה',
                  style: TextStyle(color: Colors.white),
                ),
              )
            else
              PageView.builder(
                controller: _pageController,
                itemCount: _photoPaths.length,
                onPageChanged: (int index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (BuildContext context, int index) {
                  final File file = File(_photoPaths[index]);
                  return InteractiveViewer(
                    child: Center(
                      child: file.existsSync()
                          ? Image.file(file, fit: BoxFit.contain)
                          : Container(
                              width: 220,
                              height: 220,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'התמונה לא זמינה',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                    ),
                  );
                },
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
            if (_photoPaths.isNotEmpty)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: _deleteCurrentPhoto,
                  icon: const Icon(Icons.delete, color: Colors.white),
                ),
              ),
            if (_photoPaths.isNotEmpty)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/${_photoPaths.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCurrentPhoto() async {
    final bool shouldDelete = await ConfirmDialog.show(
      context,
      title: 'למחוק את התמונה?',
      message: 'האם למחוק את התמונה הזו?',
      confirmText: 'מחיקה',
      isDestructive: true,
    );

    if (shouldDelete != true || !mounted || _photoPaths.isEmpty) {
      return;
    }

    final String currentPath = _photoPaths[_currentIndex];
    final File file = File(currentPath);
    if (file.existsSync()) {
      file.deleteSync();
    }

    final PersonRepository repository = context.read<PersonRepository>();
    final Person? person = repository.getById(widget.personId);
    if (person != null) {
      person.photosPaths = List<String>.from(person.photosPaths)
        ..remove(currentPath);
      await repository.update(person);
    }

    setState(() {
      _photoPaths = List<String>.from(_photoPaths)..removeAt(_currentIndex);
      if (_photoPaths.isEmpty) {
        return;
      }

      _currentIndex = _currentIndex.clamp(0, _photoPaths.length - 1);
    });

    if (_photoPaths.isEmpty) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    _pageController.jumpToPage(_currentIndex);
  }
}
