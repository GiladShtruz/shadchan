import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/profile_palette.dart';

/// "לעדכן חברים שלך שמשדכים ב׳שדכן׳ שיצרת כרטיס?" — on by default.
///
/// Off, no matchmaker is told the card exists, whoever they are: one answer
/// for everybody, like [PersonalCardProvider.acceptsRequests]. Shown while the
/// card is first written and kept under the card's privacy on "האזור האישי".
class CardAnnounceSwitch extends StatelessWidget {
  const CardAnnounceSwitch({super.key, this.framed = true});

  /// Drawn as its own paper card (the editor) or as a plain row inside a
  /// settings group.
  final bool framed;

  static const String title = 'לעדכן חברים שלך שמשדכים ב׳שדכן׳ שיצרת כרטיס?';

  static String subtitleFor(Gender? gender) =>
      'הם יראו רק שיש לך כרטיס ויוכלו לבקש ממך גישה. הפרטים והתמונות שלך '
              'יישארו פרטיים עד {שתאשר|שתאשרי} להם.'
          .forGender(gender);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    final Widget tile = SwitchListTile(
      value: cards.announces,
      onChanged: cards.setAnnounces,
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 4, 10, 4),
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          subtitleFor(context.userGender),
          style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
        ),
      ),
    );
    if (!framed) {
      return tile;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: ProfilePalette.surface(theme),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: tile,
      ),
    );
  }
}
