import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// "רוצה לסנכרן עם הכרטיס הקיים?" — the one question asked before a friend's
/// personal card joins the record the matchmaker already keeps for them.
///
/// Said before anything is written, and the same everywhere it is asked: the
/// card's details and the filter will follow what the friend wrote, and
/// nothing the matchmaker kept on the friend — notes, tags, history, ideas
/// open or closed, reminders — goes anywhere.
abstract final class CardLinkDialog {
  /// The sentence under the question. Public for the request dialog, which
  /// says the same thing about what happens once access is given.
  static String explanation(Person person) {
    final String name = _first(person);
    return 'הסנכרון יעדכן את פרטי הכרטיס והסינון לפי המידע ש$name '
            '{הגדיר|הגדירה}, ולא ימחק הערות, תגיות, היסטוריה, רעיונות פתוחים '
            'או סגורים, תזכורות או כל פעילות קודמת שלך. '
            'מכאן ממשיכים עם כרטיס אחד מסונכרן.'
        .forGender(person.gender == Gender.female ? Gender.female : Gender.male);
  }

  static String _first(Person person) {
    final String first = person.firstName.trim();
    return first.isNotEmpty ? first : person.fullName.trim();
  }

  /// The question itself: "[שם] הוסיף כרטיס אישי. רוצה לסנכרן עם הכרטיס
  /// הקיים?"
  static String question(Person person) {
    final String name = person.fullName.trim().isEmpty
        ? _first(person)
        : person.fullName.trim();
    return '$name {הוסיף|הוסיפה} כרטיס אישי. רוצה לסנכרן עם הכרטיס הקיים?'
        .forGender(person.gender == Gender.female ? Gender.female : Gender.male);
  }

  /// Asks, and answers whether to go on. [confirmLabel] is the yes button.
  static Future<bool> ask(
    BuildContext context,
    Person person, {
    String? title,
    String confirmLabel = 'סנכרון',
  }) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        return AlertDialog(
          scrollable: true,
          title: Text(title ?? question(person)),
          content: Text(
            explanation(person),
            style: theme.textTheme.bodyMedium,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('לא עכשיו'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return yes ?? false;
  }

  /// The whole "yes" for a card that is waiting on the friend already in the
  /// database: asks, then joins the card to that same record.
  static Future<void> confirmAndLink(
    BuildContext context, {
    required String ownerUid,
    required Person person,
  }) async {
    if (!OfflineGuard.allow(context)) {
      return;
    }
    final CardAccessProvider access = context.read<CardAccessProvider>();
    if (!await ask(context, person) || !context.mounted) {
      return;
    }
    final bool linked = await access.confirmLink(ownerUid);
    if (!context.mounted) {
      return;
    }
    AppNotice.show(
      context,
      linked
          ? 'הכרטיס של ${_first(person)} מסונכרן עכשיו'
          : 'הסנכרון יושלם ברגע שהכרטיס ייטען',
    );
  }
}
