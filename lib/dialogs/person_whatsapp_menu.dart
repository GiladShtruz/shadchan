import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';

/// What one candidate's WhatsApp button does, wherever it is drawn.
///
/// The button belongs to a *person*, never to a proposal. A single icon on a
/// pair card cannot mean anything on its own — "message who?" — and the sheet
/// that used to answer that question listed four options, two of which were
/// usually greyed out. So each side of a proposal now carries its own icon, and
/// what it does is decided here:
///
/// * the other side has a card worth sending → offer the chat or that card, both
///   lines naming who receives what, because "שליחת הכרטיס" with no names is a
///   way to send the wrong person's details to the wrong person;
/// * the other side has no card → there is no choice to make, so the chat opens.
///
/// Returns false when nothing could be opened — no number, or no WhatsApp — so
/// the caller can say so.
abstract final class PersonWhatsAppMenu {
  static Future<bool> open(
    BuildContext context, {
    required Person person,
    Person? other,
  }) async {
    final bool otherHasCard = WhatsAppUtils.hasSendableCard(other);
    if (!otherHasCard || other == null) {
      return WhatsAppUtils.openChat(person);
    }

    final String name = _firstName(person);
    final String otherName = _firstName(other);

    final bool? sendCard = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text(
                  'WhatsApp עם $name',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ListTile(
                leading: const FaIcon(
                  FontAwesomeIcons.whatsapp,
                  color: Color(0xFF25D366),
                ),
                title: Text('פתיחת שיחה עם $name'),
                onTap: () => Navigator.of(sheetContext).pop(false),
              ),
              ListTile(
                leading: Icon(
                  Icons.contact_mail_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text('שליחת הכרטיס של $otherName אל $name'),
                subtitle: const Text('הטקסט וכל התמונות של הכרטיס'),
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (sendCard == null) {
      // Dismissed. Nothing failed, so the caller must not report a failure.
      return true;
    }
    return sendCard
        ? WhatsAppUtils.sendCardTo(person, other)
        : WhatsAppUtils.openChat(person);
  }
}

/// What to call somebody in a line of copy: their first name, or the best
/// stand-in there is. Shared by both sheets below and above so a candidate is
/// never "המועמד" in one and their full name in the other.
String _firstName(Person person) {
  final String first = person.firstName.trim();
  if (first.isNotEmpty) {
    return first;
  }
  final String full = person.fullName.trim();
  return full.isEmpty ? 'המועמד' : full;
}

/// The WhatsApp button on the "יאללה לקדם" row of a proposal.
///
/// **One button, both candidates, everything it can do in one list.**
/// [PersonWhatsAppMenu] belongs to a person and is drawn on each side's own
/// avatar; this belongs to the *proposal* and is what the matchmaker reaches
/// for when the line under the pair says there is something to push forward.
/// Making them pick a side first and an action second would be two taps to do
/// the thing the row exists to prompt, so all four are here at once — a chat
/// with each of them, and each one's card sent to the other.
///
/// Sending a card is offered only where there is one to send: an empty
/// "כרטיס" arrives as a message with nothing in it, and the row that would
/// have offered it is simply absent.
abstract final class MatchWhatsAppSheet {
  /// Whether the button is worth drawing at all. Nobody to message, no button.
  static bool isAvailable({required Person? female, required Person? male}) =>
      _hasPhone(female) || _hasPhone(male);

  static bool _hasPhone(Person? person) =>
      (person?.phone ?? '').trim().isNotEmpty;

  static bool _hasCard(Person? person) => WhatsAppUtils.hasSendableCard(person);

  /// Returns what happened, so the proposal can write it down. Dismissing the
  /// sheet is [MatchShareResult.nothing] — not a failure, and not a share.
  static Future<MatchShareResult> open(
    BuildContext context, {
    required Person? female,
    required Person? male,
  }) async {
    final _WhatsAppChoice? choice = await showModalBottomSheet<_WhatsAppChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);

        List<Widget> rowsFor(Person? person, Person? other) {
          if (person == null || !_hasPhone(person)) {
            return const <Widget>[];
          }
          final String name = _firstName(person);
          return <Widget>[
            ListTile(
              leading: const FaIcon(
                FontAwesomeIcons.whatsapp,
                color: Color(0xFF25D366),
              ),
              title: Text('פתיחת שיחה עם $name'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_WhatsAppChoice(person: person, other: null)),
            ),
            if (other != null && _hasCard(other))
              ListTile(
                leading: Icon(
                  Icons.contact_mail_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text('שליחת הכרטיס של ${_firstName(other)} אל $name'),
                subtitle: const Text('הטקסט וכל התמונות של הכרטיס'),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_WhatsAppChoice(person: person, other: other)),
              ),
          ];
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text(
                  'WhatsApp',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text(
                  'שיחה מהירה, או שליחת הכרטיס של הצד השני — '
                  'הטקסט וכל התמונות',
                ),
              ),
              ...rowsFor(female, male),
              ...rowsFor(male, female),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (choice == null) {
      return MatchShareResult.nothing;
    }
    final Person? other = choice.other;
    final String name = _firstName(choice.person);
    if (other == null) {
      final bool opened = await WhatsAppUtils.openChat(choice.person);
      return MatchShareResult(
        opened: opened,
        label: opened ? 'נפתחה שיחה עם $name' : null,
      );
    }
    final bool sent = await WhatsAppUtils.sendCardTo(choice.person, other);
    return MatchShareResult(
      opened: sent,
      label: sent ? 'הכרטיס של ${_firstName(other)} נשלח ל$name' : null,
    );
  }
}

/// What one trip through [MatchWhatsAppSheet] came to.
///
/// **A share is worth recording and a dismissal is not**, and the two used to
/// be indistinguishable: the sheet answered `true` both when a card went out
/// and when the matchmaker changed their mind, because all the caller did with
/// the answer was decide whether to apologise. Now the proposal's own row and
/// its journal both read this, so "nothing happened" has to be its own answer.
class MatchShareResult {
  const MatchShareResult({required this.opened, this.label});

  /// Nothing was chosen. Not a failure — there is nothing to apologise for —
  /// and nothing to write down either.
  static const MatchShareResult nothing = MatchShareResult(opened: true);

  /// False only when something was chosen and could not be opened.
  final bool opened;

  /// What went out, in the words the proposal will show and file: "הכרטיס של
  /// שרה נשלח לדוד". Null when nothing did.
  final String? label;

  bool get shared => label != null;
}

/// What was picked: whom to message, and whose card to send them (or none).
class _WhatsAppChoice {
  const _WhatsAppChoice({required this.person, required this.other});

  final Person person;
  final Person? other;
}
