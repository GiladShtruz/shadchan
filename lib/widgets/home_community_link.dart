import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/dialogs/app_menu.dart';
import 'package:shadchan/utils/community_links.dart';

/// The two quiet invitations at the very bottom of the home page: joining the
/// WhatsApp community, and passing the app on to a friend.
///
/// **Lines, not cards, and last on the page.** The group invitation already
/// arrives as a dialog every hundred actions ([CommunityPromptsStore]); this is
/// the version for somebody who dismissed it once and went looking for it a
/// month later, and it has to be findable without ever being in the way. The
/// share row sits beside it for the same reason: recommending the app is
/// something a matchmaker does when they think of it, not something the app
/// should ask for.
///
/// So both are single rows under everything else, in the muted type the rest of
/// the page's footnotes use, with colour on the icons alone so the eye can find
/// them without either row shouting.
///
/// The group row draws nothing when there is no invite link set — see
/// [CommunityLinks.hasUpdatesGroup]. A row that opens nothing is worse than no
/// row. The share row is always there: the phone always has a share sheet.
class HomeCommunityLink extends StatelessWidget {
  const HomeCommunityLink({super.key});

  static const String label = 'הצטרפו לקהילת הוואטסאפ של שדכן';
  static const String shareLabel = 'שתפו את שדכן עם חבר';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      // Side by side while both fit, stacked when the phone is too narrow for
      // that — never one line squeezed to three words.
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: <Widget>[
          if (CommunityLinks.hasUpdatesGroup)
            _FooterLink(
              icon: const FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 17,
                color: Color(0xFF25D366),
              ),
              label: label,
              onTap: () =>
                  CommunityLinks.openLink(CommunityLinks.updatesGroupUrl),
              theme: theme,
            ),
          _FooterLink(
            icon: Icon(
              Icons.ios_share_outlined,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            label: shareLabel,
            onTap: shareTheApp,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.theme,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            icon,
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
