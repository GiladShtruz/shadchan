import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/utils/community_links.dart';

/// "הצטרפו לקהילת הוואטסאפ של שדכן" — one quiet line at the very bottom of the
/// home page.
///
/// **A line, not a card, and last on the page.** The same invitation already
/// arrives as a dialog every hundred actions ([CommunityPromptsStore]); this is
/// the version for somebody who dismissed it once and went looking for it a
/// month later, and it has to be findable without ever being in the way. So it
/// is a single row under everything else, in the muted type the rest of the
/// page's footnotes use, with WhatsApp's own green on the icon alone so the eye
/// can find it without the row shouting.
///
/// Draws nothing when there is no invite link set — see
/// [CommunityLinks.hasUpdatesGroup]. A row that opens nothing is worse than no
/// row.
class HomeCommunityLink extends StatelessWidget {
  const HomeCommunityLink({super.key});

  static const String label = 'הצטרפו לקהילת הוואטסאפ של שדכן';

  @override
  Widget build(BuildContext context) {
    if (!CommunityLinks.hasUpdatesGroup) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);

    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => CommunityLinks.openLink(CommunityLinks.updatesGroupUrl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 17,
                color: Color(0xFF25D366),
              ),
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
      ),
    );
  }
}
