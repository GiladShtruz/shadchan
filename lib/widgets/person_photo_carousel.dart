import 'dart:io';

import 'package:flutter/material.dart';

/// A swipeable gallery of a person's photos with RTL arrows and a dot
/// indicator. Shared by the person profile and the proposal detail screen so
/// both browse photos the same way.
///
/// When [photosPaths] is empty, [placeholder] is shown instead (e.g. an
/// avatar). Missing files are handled gracefully by [Image.file].
class PersonPhotoCarousel extends StatefulWidget {
  const PersonPhotoCarousel({
    super.key,
    required this.photosPaths,
    this.height = 260,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.placeholder,
    this.backgroundColor,
  });

  final List<String> photosPaths;
  final double height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final Widget? placeholder;

  /// Fills the space around the photo. Worth setting with [BoxFit.contain],
  /// where a portrait and a landscape shot leave very different margins.
  final Color? backgroundColor;

  @override
  State<PersonPhotoCarousel> createState() => _PersonPhotoCarouselState();
}

class _PersonPhotoCarouselState extends State<PersonPhotoCarousel> {
  final PageController _pageController = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int target, int count) {
    final int clamped = target.clamp(0, count - 1);
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> photos = widget.photosPaths;

    Widget content;
    if (photos.isEmpty) {
      content = Center(child: widget.placeholder ?? const SizedBox.shrink());
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          PageView.builder(
            controller: _pageController,
            itemCount: photos.length,
            onPageChanged: (int index) => setState(() => _index = index),
            itemBuilder: (BuildContext context, int index) {
              return Image.file(File(photos[index]), fit: widget.fit);
            },
          ),
          if (photos.length > 1) ...<Widget>[
            // In RTL the pager advances leftwards, so the left arrow goes
            // forward and the right arrow goes back.
            if (_index + 1 < photos.length)
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ArrowButton(
                    icon: Icons.chevron_left,
                    onPressed: () => _goTo(_index + 1, photos.length),
                  ),
                ),
              ),
            if (_index > 0)
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ArrowButton(
                    icon: Icons.chevron_right,
                    onPressed: () => _goTo(_index - 1, photos.length),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              // The dots sit on their own dark pill so they stay readable over
              // a pale photo or the empty margins left by BoxFit.contain.
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List<Widget>.generate(photos.length, (int index) {
                      return Container(
                        width: index == _index ? 9 : 7,
                        height: index == _index ? 9 : 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _index
                              ? Colors.white
                              : Colors.white54,
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Container(
        height: widget.height,
        color: widget.backgroundColor,
        child: content,
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}
