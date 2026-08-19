import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/contact_channel.dart';

/// WhatsApp's own green, used wherever the app draws its mark.
const Color kWhatsAppGreen = Color(0xFF25D366);

/// The one messaging control on a person's row or card.
///
/// It is a single button that changes what it is, rather than a WhatsApp icon
/// that is sometimes a lie:
///
/// * a mobile number gets WhatsApp,
/// * any other number gets the phone's own SMS app,
/// * no number at all gets a pencil that leads to filling the card in — which
///   is the only thing that can actually be done about it.
///
/// [onEdit] is what the third case does. Leave it null on a surface with no
/// editing to offer and the button simply is not drawn there.
class ContactChannelButton extends StatelessWidget {
  const ContactChannelButton({
    super.key,
    required this.person,
    required this.onWhatsApp,
    this.onEdit,
    this.size = 20,
    this.visualDensity = VisualDensity.compact,
    this.constraints,
  });

  final Person person;
  final VoidCallback onWhatsApp;
  final VoidCallback? onEdit;
  final double size;
  final VisualDensity visualDensity;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ContactChannel channel = ContactChannels.forPerson(person);
    // Named tooltips: two of these buttons can sit in one list, and "וואטסאפ"
    // on both says nothing about which person is about to be messaged.
    final String name = person.fullName.trim().isEmpty
        ? person.firstName.trim()
        : person.fullName.trim();

    switch (channel) {
      case ContactChannel.whatsapp:
        return IconButton(
          visualDensity: visualDensity,
          constraints: constraints,
          tooltip: 'WhatsApp עם $name',
          icon: FaIcon(
            FontAwesomeIcons.whatsapp,
            size: size,
            color: kWhatsAppGreen,
          ),
          onPressed: onWhatsApp,
        );
      case ContactChannel.sms:
        return IconButton(
          visualDensity: visualDensity,
          constraints: constraints,
          tooltip: 'הודעה ל$name',
          icon: Icon(
            Icons.sms_outlined,
            size: size,
            color: theme.colorScheme.primary,
          ),
          onPressed: () => ContactChannels.openSms(person.phone),
        );
      case ContactChannel.none:
        final VoidCallback? edit = onEdit;
        if (edit == null) {
          return const SizedBox.shrink();
        }
        return IconButton(
          visualDensity: visualDensity,
          constraints: constraints,
          tooltip: 'השלמת הכרטיסייה של $name',
          icon: Icon(
            Icons.edit_outlined,
            size: size,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          onPressed: edit,
        );
    }
  }
}
