import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';

abstract final class MatchSuggestionFlow {
  static Future<void> open(
    BuildContext context, {
    required Person sourcePerson,
  }) async {
    final Person person =
        context.read<PersonRepository>().getById(sourcePerson.id) ??
        sourcePerson;

    if (person.gender == Gender.unknown) {
      _showSnackBar(context, 'יש לבחור מגדר לאיש הקשר לפני פתיחת התאמות');
      return;
    }

    final Gender oppositeGender = person.gender == Gender.male
        ? Gender.female
        : Gender.male;
    final MatchProposalFilters? savedFilters = _savedFiltersFor(person);

    final Person? selectedPerson = await PersonPickerSheet.show(
      context,
      title: 'התאמות עבור ${person.fullName.trim()}',
      filterGender: oppositeGender,
      excludeIds: <String>{person.id},
      minAge: savedFilters?.minAge,
      maxAge: savedFilters?.maxAge,
      religiousLevels:
          savedFilters?.religiousLevels ??
          MatchSuggestionUtils.religiousLevelsFor(person.religiousLevel),
      profileStatuses: savedFilters?.profileStatuses ?? const [],
      candidatePredicate: (Person candidate) {
        if (savedFilters != null) {
          return MatchSuggestionUtils.isEligibleCandidate(
            source: person,
            candidate: candidate,
          );
        }

        return MatchSuggestionUtils.isSuggestedCandidate(
          source: person,
          candidate: candidate,
        );
      },
      emptySubtitle: 'לא נמצאו התאמות לפי הסינון האוטומטי',
    );

    if (selectedPerson == null || !context.mounted) {
      return;
    }

    final Person male = person.gender == Gender.male ? person : selectedPerson;
    final Person female = person.gender == Gender.female
        ? person
        : selectedPerson;

    final MatchRepository matchRepository = context.read<MatchRepository>();
    final MatchIdea? existingMatch = matchRepository.findExisting(
      male.id,
      female.id,
    );

    if (existingMatch != null) {
      final bool shouldView = await _showDuplicateMatchDialog(
        context,
        nameA: male.fullName.trim(),
        nameB: female.fullName.trim(),
      );

      if (shouldView && context.mounted) {
        context.push('/matches/${existingMatch.id}');
      }
      return;
    }

    final MatchIdea? newMatch = await matchRepository.create(
      male.id,
      female.id,
    );
    if (newMatch != null && context.mounted) {
      context.push('/matches/${newMatch.id}');
    }
  }

  static Future<bool> _showDuplicateMatchDialog(
    BuildContext context, {
    required String nameA,
    required String nameB,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('כבר קיימת הצעה'),
          content: Text('כבר קיימת הצעה בין $nameA ל-$nameB'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('סגור'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('צפה בהצעה'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  static void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static MatchProposalFilters? _savedFiltersFor(Person person) {
    return MatchProposalFilterSheet.savedFiltersFor(person.id);
  }
}
