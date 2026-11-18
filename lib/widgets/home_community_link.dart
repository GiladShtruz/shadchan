import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/dialogs/app_menu.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/utils/share_utils.dart';

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
  const HomeCommunityLink({super.key, this.compact = false});

  static const String label = 'הצטרפו לקהילת הוואטסאפ של שדכן';
  static const String shareLabel = 'שתפו את שדכן עם חברים';

  static const String compactLabel = 'הצטרפות לוואטסאפ';
  static const String compactShareLabel = 'שיתוף עם חברים';

  /// One line, light grey, nothing coloured — the foot of the action list on
  /// בית, where it must not compete with the actions above it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (compact) {
      return _buildCompact(context, theme);
    }

    return Center(
      // Side by side while both fit, stacked when the phone is too narrow for
      // that — never one line squeezed to three words.
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: <Widget>[
          if (CommunityLinks.hasUpdatesGroup)
            FooterLink(
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
          FooterLink(
            icon: Icon(
              Icons.share_outlined,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            label: shareLabel,
            onTap: () => shareTheApp(origin: ShareUtils.originOf(context)),
            theme: theme,
          ),
        ],
      ),
    );
  }
}

extension on HomeCommunityLink {
  Widget _buildCompact(BuildContext context, ThemeData theme) {
    final Color grey = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: 0.6,
    );
    final TextStyle? style = theme.textTheme.labelSmall?.copyWith(
      color: grey,
      fontWeight: FontWeight.w600,
    );
    Widget link(Widget icon, String text, VoidCallback onTap) => InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            icon,
            const SizedBox(width: 5),
            Text(text, maxLines: 1, style: style),
          ],
        ),
      ),
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (CommunityLinks.hasUpdatesGroup) ...<Widget>[
            link(
              FaIcon(FontAwesomeIcons.whatsapp, size: 13, color: grey),
              HomeCommunityLink.compactLabel,
              () => CommunityLinks.openLink(CommunityLinks.updatesGroupUrl),
            ),
            Text('·', style: style),
          ],
          link(
            Icon(Icons.share_outlined, size: 13, color: grey),
            HomeCommunityLink.compactShareLabel,
            () => shareTheApp(origin: ShareUtils.originOf(context)),
          ),
        ],
      ),
    );
  }
}

/// One quiet footnote link: a small icon and muted words, no card around it.
/// Also the personal area's "share the app" line.
class FooterLink extends StatelessWidget {
  const FooterLink({
    super.key,
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
