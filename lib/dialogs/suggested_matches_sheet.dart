import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';
import 'package:shadchan/widgets/candidate_card_view.dart';
import 'package:shadchan/widgets/extended_filter_toggle.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// A short list of the people who fit [source] by gender, religious level and
/// age. Used while building a new idea: picking someone here fills in the other
/// side of the proposal.
abstract final class SuggestedMatchesSheet {
  static Future<Person?> show(BuildContext context, {required Person source}) {
    return showDialog<Person>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _SuggestedMatchesDialog(source: source),
    );
  }
}

class _SuggestedMatchesDialog extends StatefulWidget {
  const _SuggestedMatchesDialog({required this.source});

  final Person source;

  @override
  State<_SuggestedMatchesDialog> createState() =>
      _SuggestedMatchesDialogState();
}

class _SuggestedMatchesDialogState extends State<_SuggestedMatchesDialog> {
  /// Whether the list is narrowed to the whole of the source's card rather than
  /// to the basics. Off by default, like every other candidate list in the app
  /// — see [ExtendedFilterToggle].
  bool _extended = false;

  /// Whose card is open inline.
  final Set<String> _expandedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Person source = widget.source;
    final String name = source.firstName.trim().isNotEmpty
        ? source.firstName.trim()
        : source.fullName.trim();
    final bool canNarrow = MatchSuggestionUtils.hasExtendedPreferences(source);

    final List<Person> candidates =
        context
            .watch<PersonRepository>()
            .getAll()
            .where(
              (Person candidate) =>
                  !candidate.hidden &&
                  (_extended && canNarrow
                      ? MatchSuggestionUtils.matchesOwnPreferences(
                          source: source,
                          candidate: candidate,
                        )
                      : MatchSuggestionUtils.matchesBasicPreferences(
                          source: source,
                          candidate: candidate,
                        )),
            )
            .toList()
          ..sort(
            (Person a, Person b) =>
                a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
          );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'התאמות עבור $name',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'סגירה',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (canNarrow)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ExtendedFilterToggle(
                    selected: _extended,
                    onChanged: (bool value) =>
                        setState(() => _extended = value),
                  ),
                ),
              ),
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text(
                  _extended
                      ? 'אף אחד לא עומד בסינון המורחב.'
                      : 'לא נמצאו התאמות מתאימות במאגר.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Person candidate = candidates[index];
                    final bool expanded = _expandedIds.contains(candidate.id);

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ListTile(
                          leading: PersonAvatar(person: candidate, radius: 22),
                          title: Text(
                            candidate.fullName.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: candidate.age == null
                              ? null
                              : Text('גיל ${candidate.age}'),
                          // The card, readable without leaving the choice —
                          // the same control every other candidate list wears.
                          trailing: hasCandidateCard(candidate)
                              ? CandidateCardButton(
                                  expanded: expanded,
                                  onPressed: () => setState(() {
                                    if (!_expandedIds.remove(candidate.id)) {
                                      _expandedIds.add(candidate.id);
                                    }
                                  }),
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(candidate),
                        ),
                        if (expanded)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                            child: CandidateQuickCard(candidate: candidate),
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
