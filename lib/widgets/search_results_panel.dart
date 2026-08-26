import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// Live results, dropped under the search row and over the page.
///
/// **Filtering a list is not the same as finding something in it.** המאגר שלי
/// and רעיונות used to answer a query by narrowing the list underneath: the
/// right record was in there somewhere, and getting to it still meant reading
/// down a column of cards past the category buttons, the filter chips and
/// whatever else the page happens to draw above the first row. The home screen
/// answered the same query with a panel of results, each one a tap away from
/// the thing itself — and that is what somebody typing a name is actually
/// asking for.
///
/// So all three screens answer the same way now. The list underneath still
/// narrows, because it is still the right thing to look at once the panel has
/// been dismissed; the panel is simply the short way through it.
///
/// **It closes the way a search closes.** The page underneath is dimmed and a
/// tap on it clears the query and the keyboard together, so there is a way out
/// that is not the small X inside the field.
class SearchResultsPanel extends StatelessWidget {
  const SearchResultsPanel({
    super.key,
    required this.rows,
    required this.onDismiss,
    this.emptyText = 'לא נמצאו תוצאות',
  });

  /// One widget per result, drawn with a hairline between them. Use
  /// [SearchResultRow] unless a screen has a genuine reason not to.
  final List<Widget> rows;

  /// Clears the query and the keyboard. Called by a tap on the dimmed page.
  final VoidCallback onDismiss;

  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ColoredBox(
              color: theme.colorScheme.scrim.withValues(alpha: 0.32),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            // The field is in the bar, so the body starts directly under it and
            // the panel needs only a hair of air above it.
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              elevation: 6,
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                // Half the screen at most: the page underneath has to stay
                // visible, or the panel is a screen and should have been one.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        child: Text(
                          emptyText,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shrinkWrap: true,
                        itemCount: rows.length,
                        separatorBuilder: (BuildContext context, _) => Divider(
                          height: 1,
                          thickness: 1,
                          indent: 16,
                          endIndent: 16,
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        itemBuilder: (BuildContext context, int index) =>
                            rows[index],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One result: a mark, a name, one quiet line under it, and the whole row is
/// the tap target.
///
/// Deliberately plainer than the cards on the page behind it. A panel of full
/// cards is a second list to read; a panel of rows is an answer to be pointed
/// at.
class SearchResultRow extends StatelessWidget {
  const SearchResultRow({
    super.key,
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// A person's face, at the size this row draws it.
  static Widget avatar(Person person) =>
      PersonAvatar(person: person, radius: 19);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? note = subtitle;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  if (note != null && note.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // `chevron_right` and not `chevron_left`: Material's directional
            // icons mirror themselves, so in this RTL app this is the one that
            // points the way the tap goes.
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// The two faces of a proposal, overlapped, for a row on the ideas panel.
class SearchResultCouple extends StatelessWidget {
  const SearchResultCouple({super.key, required this.a, required this.b});

  final Person? a;
  final Person? b;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const double radius = 15;

    Widget face(Person? person) {
      if (person == null) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.person_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      }
      return PersonAvatar(person: person, radius: radius);
    }

    return SizedBox(
      width: radius * 3.2,
      height: radius * 2,
      child: Stack(
        children: <Widget>[
          PositionedDirectional(start: 0, child: face(a)),
          PositionedDirectional(
            start: radius * 1.2,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: face(b),
            ),
          ),
        ],
      ),
    );
  }
}
