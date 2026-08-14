import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/person_avatar_assets.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';

/// The person's full card, full screen: every photo, swipeable, with the text
/// written about them readable over it.
///
/// This is the read-only counterpart to the profile page — opened by tapping
/// the profile photo. Its app bar exposes card sharing and a direct WhatsApp
/// conversation without forcing the user back to the profile.
class PersonCardViewer extends StatefulWidget {
  const PersonCardViewer({super.key, required this.personId});

  final String personId;

  static Future<void> open(BuildContext context, String personId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) => PersonCardViewer(personId: personId),
      ),
    );
  }

  @override
  State<PersonCardViewer> createState() => _PersonCardViewerState();
}

class _PersonCardViewerState extends State<PersonCardViewer> {
  final PageController _pageController = PageController();

  int _currentIndex = 0;

  /// Whether the card text is opened to its full height. Collapsed it shows a
  /// few lines over the photo; expanded it scrolls on its own.
  bool _isTextExpanded = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watched rather than read once: deleting a photo from elsewhere, or an
    // edit to the card text, should be reflected here without reopening.
    final Person? person = context.watch<PersonRepository>().getById(
      widget.personId,
    );

    if (person == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Text('האדם לא נמצא', style: TextStyle(color: Colors.white)),
          ),
        ),
      );
    }

    final List<String> photoPaths = person.photosPaths
        .where((String path) => File(path).existsSync())
        .toList();
    final String description = (person.description ?? '').trim();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (photoPaths.isEmpty)
            _EmptyCardBackdrop(person: person)
          else
            PageView.builder(
              controller: _pageController,
              itemCount: photoPaths.length,
              onPageChanged: (int index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (BuildContext context, int index) {
                return InteractiveViewer(
                  child: Center(
                    child: Image.file(
                      File(photoPaths[index]),
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          _TopBar(
            title: person.fullName.trim(),
            counter: photoPaths.length > 1
                ? '${_currentIndex + 1}/${photoPaths.length}'
                : null,
            showActions: true,
            onShare: () => ShareUtils.sharePerson(person),
            onWhatsApp: () => _openWhatsApp(person),
          ),
          if (photoPaths.length > 1)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: description.isEmpty ? 24 : 0,
                  ),
                  child: _PhotoDots(
                    count: photoPaths.length,
                    currentIndex: _currentIndex,
                    // The dots sit above the card text when there is one, and
                    // at the bottom edge when there isn't.
                    aboveCardText: description.isNotEmpty,
                  ),
                ),
              ),
            ),
          if (description.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _CardText(
                text: description,
                isExpanded: _isTextExpanded,
                showToggle: true,
                onToggle: () =>
                    setState(() => _isTextExpanded = !_isTextExpanded),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openWhatsApp(Person person) async {
    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && mounted) {
      _showError('אין מספר טלפון תקין לפתיחת WhatsApp');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.counter,
    required this.showActions,
    required this.onShare,
    required this.onWhatsApp,
  });

  final String title;
  final String? counter;
  final bool showActions;
  final VoidCallback onShare;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        // A scrim so the name and the close button stay readable whatever the
        // photo behind them looks like.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.black54, Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool narrow = constraints.maxWidth < 370;
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 16),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'סגירה',
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: narrow ? 14 : 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (showActions) ...<Widget>[
                      TextButton.icon(
                        onPressed: onShare,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: narrow ? 5 : 8,
                          ),
                        ),
                        icon: Icon(
                          Icons.share_outlined,
                          size: narrow ? 17 : 19,
                        ),
                        label: Text(
                          'שיתוף כרטיס',
                          style: TextStyle(fontSize: narrow ? 11 : 13),
                        ),
                      ),
                      IconButton(
                        onPressed: onWhatsApp,
                        icon: const FaIcon(
                          FontAwesomeIcons.whatsapp,
                          color: Colors.white,
                          size: 20,
                        ),
                        tooltip: 'פתיחת שיחה ב-WhatsApp',
                      ),
                    ],
                    if (counter != null && (!narrow || !showActions))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          counter!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The card text over the photo: a few lines by default, the whole thing —
/// scrollable — once opened.
class _CardText extends StatelessWidget {
  const _CardText({
    required this.text,
    required this.isExpanded,
    required this.showToggle,
    required this.onToggle,
  });

  final String text;
  final bool isExpanded;
  final bool showToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.55;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Colors.black, Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: isExpanded ? maxHeight : double.infinity,
                  ),
                  child: SingleChildScrollView(
                    // Only the opened card scrolls; collapsed it is clipped to
                    // its line limit and there is nothing to scroll.
                    physics: isExpanded
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    child: Text(
                      text,
                      maxLines: isExpanded ? null : 4,
                      overflow: isExpanded
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              if (showToggle) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white30)),
                  ),
                  child: TextButton(
                    onPressed: onToggle,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      alignment: AlignmentDirectional.centerStart,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(isExpanded ? 'הצג פחות' : 'הכרטיס המלא'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoDots extends StatelessWidget {
  const _PhotoDots({
    required this.count,
    required this.currentIndex,
    required this.aboveCardText,
  });

  final int count;
  final int currentIndex;
  final bool aboveCardText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Cleared out of the card text's way when one is showing.
      padding: EdgeInsets.only(bottom: aboveCardText ? 190 : 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(count, (int index) {
          final bool isCurrent = index == currentIndex;
          return Container(
            width: isCurrent ? 9 : 7,
            height: isCurrent ? 9 : 7,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent ? Colors.white : Colors.white38,
            ),
          );
        }),
      ),
    );
  }
}

/// What the viewer shows for someone with no photos: their placeholder avatar,
/// so the card text still has something to sit on.
class _EmptyCardBackdrop extends StatelessWidget {
  const _EmptyCardBackdrop({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final String? avatarAsset = PersonAvatarAssets.pathFor(
      person.gender,
      person.avatarIndex,
    );

    return Center(
      child: avatarAsset != null
          ? Opacity(
              opacity: 0.5,
              child: Image.asset(avatarAsset, width: 200, height: 200),
            )
          : const Icon(Icons.person_outline, size: 140, color: Colors.white24),
    );
  }
}
