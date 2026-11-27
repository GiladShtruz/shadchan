import 'package:flutter/material.dart';
import 'package:shadchan/screens/home_screen.dart';
import 'package:shadchan/screens/personal_privacy_screen.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/services/usage_actions.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/app_glyphs.dart';
import 'package:shadchan/widgets/home_community_link.dart';

/// The home of somebody who keeps a personal card and does not matchmake.
///
/// **Not a home of its own any more** (2026-11-27): it is the one
/// [HomeScreen], which shows and leaves out its blocks by the two
/// capabilities (a personal card, the matchmaker's tools). Kept as a name for
/// the routes and tests that open it.
class PersonalHomeScreen extends StatelessWidget {
  const PersonalHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const HomeScreen();
}

/// The three secondary actions of a single's home, quiet, at the very foot.
class PersonalFooterLinks extends StatelessWidget {
  const PersonalFooterLinks({super.key, required this.gender});
  final Gender? gender;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    Widget mark(AppGlyph g) =>
        AppGlyphIcon(g, size: 17, color: theme.colorScheme.onSurfaceVariant);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: <Widget>[
        Builder(
          builder: (BuildContext anchor) => FooterLink(
            icon: mark(AppGlyph.share),
            label: 'שיתוף האפליקציה',
            theme: theme,
            onTap: () async {
              try {
                await PersonalAreaService.invite(anchor);
              } on Object {
                // Nothing to share to is not worth a message.
              }
            },
          ),
        ),
        FooterLink(
          icon: mark(AppGlyph.key),
          label: 'ניהול ופרטיות',
          theme: theme,
          onTap: () => PersonalPrivacyScreen.open(context),
        ),
        FooterLink(
          icon: mark(AppGlyph.people),
          label: 'רוצה לחשוב גם על חברים?',
          theme: theme,
          onTap: () => UsageActions.startMatchmaking(context),
        ),
      ],
    );
  }
}
