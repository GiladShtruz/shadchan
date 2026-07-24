import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// A short list of the people who fit [source] by gender, religious level and
/// age. Used while building a new idea: picking someone here fills in the other
/// side of the proposal.
abstract final class SuggestedMatchesSheet {
  static Future<Person?> show(BuildContext context, {required Person source}) {
    final String name = source.firstName.trim().isNotEmpty
        ? source.firstName.trim()
        : source.fullName.trim();

    return showDialog<Person>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        final List<Person> candidates =
            context
                .read<PersonRepository>()
                .getAll()
                .where(
                  (Person candidate) =>
                      !candidate.hidden &&
                      MatchSuggestionUtils.isSuggestedCandidate(
                        source: source,
                        candidate: candidate,
                      ),
                )
                .toList()
              ..sort(
                (Person a, Person b) => a.fullName.toLowerCase().compareTo(
                  b.fullName.toLowerCase(),
                ),
              );

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 56,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.6,
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
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                if (candidates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Text(
                      'לא נמצאו התאמות מתאימות במאגר.',
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
                        return ListTile(
                          leading: PersonAvatar(person: candidate, radius: 22),
                          title: Text(
                            candidate.fullName.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: candidate.age == null
                              ? null
                              : Text('גיל ${candidate.age}'),
                          onTap: () =>
                              Navigator.of(dialogContext).pop(candidate),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
