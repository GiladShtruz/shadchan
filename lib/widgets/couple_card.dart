import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// A small tile for one proposal: the two people's photos (or initials) side by
/// side with their first names underneath. Used by the horizontal rows on the
/// home screen, where a proposal should always read as one couple rather than
/// as two separate people.
class CoupleCard extends StatelessWidget {
  const CoupleCard({
    super.key,
    required this.personA,
    required this.personB,
    required this.onTap,
    this.footer,
  });

  final Person? personA;
  final Person? personB;
  final VoidCallback onTap;

  /// Optional line under the names, e.g. how long ago the idea was opened.
  final String? footer;

  static const double width = 132;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? footerText = footer?.trim();

    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _CoupleAvatars(personA: personA, personB: personB),
                const SizedBox(height: 10),
                Text(
                  _coupleLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (footerText != null && footerText.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    footerText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _coupleLabel() {
    return '${_shortName(personA)} & ${_shortName(personB)}';
  }

  static String _shortName(Person? person) {
    if (person == null) {
      return '—';
    }
    final String first = person.firstName.trim();
    return first.isNotEmpty ? first : person.fullName.trim();
  }
}

/// The two avatars, slightly overlapping so the pair reads as a unit.
class _CoupleAvatars extends StatelessWidget {
  const _CoupleAvatars({required this.personA, required this.personB});

  final Person? personA;
  final Person? personB;

  static const double _radius = 24;
  static const double _overlap = 12;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _radius * 2,
      width: _radius * 4 - _overlap,
      child: Stack(
        children: <Widget>[
          PositionedDirectional(
            start: 0,
            child: _avatar(context, personA),
          ),
          PositionedDirectional(
            start: _radius * 2 - _overlap,
            child: _avatar(context, personB),
          ),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context, Person? person) {
    final ThemeData theme = Theme.of(context);
    final Widget inner = person == null
        ? CircleAvatar(
            radius: _radius,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.person_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : PersonAvatar(person: person, radius: _radius);

    // A ring in the card colour keeps the two circles readable where they meet.
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.surface, width: 2),
      ),
      child: inner,
    );
  }
}
