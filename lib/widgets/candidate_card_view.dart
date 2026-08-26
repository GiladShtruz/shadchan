import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/person_photo_carousel.dart';

/// Whether [person] has a card worth opening — text, photographs, or both.
///
/// The one place that question is answered, so a chevron never appears over an
/// empty panel and never fails to appear over a full one.
bool hasCandidateCard(Person person) {
  return (person.description ?? '').trim().isNotEmpty ||
      person.photosPaths.any((String path) => File(path).existsSync());
}

/// The control that opens a candidate's card without leaving the list.
///
/// **It exists on every list of candidates now, not just one.** The התאמות view
/// opened from the heart on המאגר שלי had it; the manual search on that same
/// screen, the picker that chooses the other side of a new idea, and the short
/// suggestions list did not — so whether a card could be read without losing
/// your place depended on which of four near-identical lists you happened to be
/// looking at. Everywhere a candidate is listed, this is how their card opens.
///
/// **Quiet, but not invisible.** It used to be a bare grey chevron on the name
/// line, which read as decoration next to two round action buttons and was
/// missed. It is the app's own small tinted square now — the same shape and the
/// same tint as the icons on the overflow menu — so it reads as a control that
/// belongs here, and it still never competes with the decisions beside it.
class CandidateCardButton extends StatelessWidget {
  const CandidateCardButton({
    super.key,
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    return Tooltip(
      message: expanded ? 'סגירת הכרטיס' : 'הצגת הכרטיס',
      child: Material(
        color: ink.withValues(alpha: dark ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 26,
            height: 26,
            child: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.expand_more_rounded, size: 17, color: ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// A candidate's send-card, opened in place: the photographs and the text, on
/// warm paper under the row they belong to.
class CandidateQuickCard extends StatelessWidget {
  const CandidateQuickCard({
    super.key,
    required this.candidate,
    this.surfaceColor,
    this.textColor,
  });

  final Person candidate;

  /// The paper the card is printed on. Defaults to the theme's own warm
  /// surface; the profile passes its palette so the card matches the page it
  /// opens inside.
  final Color? surfaceColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color paper =
        surfaceColor ?? theme.colorScheme.surfaceContainerHighest;
    final String description = (candidate.description ?? '').trim();
    final List<String> photoPaths = candidate.photosPaths
        .where((String path) => File(path).existsSync())
        .toList(growable: false);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (photoPaths.isNotEmpty)
            PersonPhotoCarousel(
              photosPaths: photoPaths,
              height: 220,
              borderRadius: BorderRadius.zero,
              fit: BoxFit.contain,
              backgroundColor: paper,
            ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor ?? theme.colorScheme.onSurface,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
