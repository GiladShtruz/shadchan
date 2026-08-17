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
    final bool otherHasCard = (other?.description ?? '').trim().isNotEmpty;
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

  static String _firstName(Person person) {
    final String first = person.firstName.trim();
    if (first.isNotEmpty) {
      return first;
    }
    final String full = person.fullName.trim();
    return full.isEmpty ? 'המועמד' : full;
  }
}
