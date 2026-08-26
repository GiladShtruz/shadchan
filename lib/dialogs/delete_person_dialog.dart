import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// Deleting a friend, and everything that only existed because they were here.
///
/// **A proposal is a pair, so half a pair is not a proposal.** Deleting a
/// friend used to leave every idea they were in behind — the confirmation even
/// said so — which left the רעיונות list full of cards with one empty side,
/// each of them saying "אחד הצדדים כבר לא קיים במאגר" and none of them
/// removable except one at a time. Their ideas go with them now.
///
/// The dialog says what is about to happen *before* it happens: an open idea is
/// work in progress, and losing three of them without being told is not a
/// delete anybody agreed to. Ideas that are already closed are counted in the
/// same sentence but do not carry the warning on their own — nothing is lost
/// there that was not already over.
abstract final class DeletePersonFlow {
  /// Asks, and — if the answer is yes — deletes the person together with every
  /// idea they appear in. Returns whether the deletion happened.
  static Future<bool> run(BuildContext context, Person person) async {
    final PersonRepository people = context.read<PersonRepository>();
    final MatchRepository matches = context.read<MatchRepository>();
    final List<MatchIdea> related = matches.getByPersonId(person.id);
    final int open = related
        .where((MatchIdea match) => !match.status.isArchived)
        .length;

    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'למחוק את החבר?',
      message: _message(person, total: related.length, open: open),
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (!confirmed) {
      return false;
    }

    for (final MatchIdea match in related) {
      await matches.deleteMatch(match.id);
    }
    await people.delete(person.id);
    return true;
  }

  static String _message(
    Person person, {
    required int total,
    required int open,
  }) {
    final String name = person.fullName.trim();
    if (total == 0) {
      return 'האם למחוק את $name?';
    }

    final String them = person.gender == Gender.female ? 'אליה' : 'אליו';
    final String ideas = total == 1
        ? 'רעיון אחד שקשור $them'
        : '$total רעיונות שקשורים $them';
    final String openLine = open == 0
        ? ''
        : open == 1
        ? '\nאחד מהם עדיין פתוח.'
        : '\n$open מהם עדיין פתוחים.';

    return 'האם למחוק את $name?\n\nיימחק גם $ideas.$openLine';
  }
}
