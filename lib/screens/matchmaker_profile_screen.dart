import 'package:flutter/material.dart';
import 'package:shadchan/models/community_profile.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/profile_palette.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/contact_channel_button.dart';

/// One matchmaker's public page, opened by tapping their name on the
/// leaderboard.
///
/// **A person, not a scoreboard entry.** The board is a list of names with
/// numbers beside them, and until now that was the whole of what one matchmaker
/// could know about another — which is a strange thing for a feature whose
/// entire purpose is that nobody here is working alone. This page is the other
/// half: who they are, where they work, what they are willing to help with, and
/// a way to say hello.
///
/// **What is deliberately not on it.** No age. No activity of any kind — not
/// how long they have been at this, not how many couples or weddings, not which
/// age ranges they work in, not a preferred way of being approached, and no way
/// to forward the page on. A public page about a colleague is not a
/// performance review, and every one of those figures turns "here is somebody
/// who might help" into "here is how you compare". The one number in the whole
/// feature is the rank on the board this page was opened from, which is where a
/// ranking belongs.
///
/// Everything here is optional, so the page is built from whatever is actually
/// there: a matchmaker who filled nothing in is a photograph and a name, and
/// the page says plainly that there is nothing more rather than drawing empty
/// boxes.
class MatchmakerProfileScreen extends StatefulWidget {
  const MatchmakerProfileScreen({
    super.key,
    required this.uid,
    this.fallbackName = '',
    this.fallbackPhotoUrl = '',
  });

  /// Whose page this is — the document id on `communityMembers`.
  final String uid;

  /// What the leaderboard already knew, drawn while the read is in flight.
  ///
  /// **So the page opens with the person on it.** The row that was tapped
  /// already carries the name and the face; opening onto a spinner and
  /// replacing it a moment later with the same name is a transition that says
  /// "loading" about information nobody had to wait for.
  final String fallbackName;
  final String fallbackPhotoUrl;

  @override
  State<MatchmakerProfileScreen> createState() =>
      _MatchmakerProfileScreenState();
}

class _MatchmakerProfileScreenState extends State<MatchmakerProfileScreen> {
  CommunityProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final CommunityProfile? profile = await CommunityService.profile(
      widget.uid,
    );
    if (mounted) {
      setState(() {
        _profile = profile;
        _loading = false;
      });
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final bool launched = await WhatsAppUtils.openChatWithPhone(phone);
    if (!launched && mounted) {
      AppNotice.show(context, 'לא הצלחנו לפתוח את וואטסאפ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProfile? profile = _profile;
    final String name = profile?.name.trim().isNotEmpty ?? false
        ? profile!.name.trim()
        : (widget.fallbackName.trim().isEmpty
              ? 'שדכן'
              : widget.fallbackName.trim());
    final String photoUrl = profile?.photoUrl.isNotEmpty ?? false
        ? profile!.photoUrl
        : widget.fallbackPhotoUrl;
    final String phone = profile?.contactPhone ?? '';
    final bool canWhatsApp = PhoneUtils.toWhatsAppNumber(phone) != null;

    return Scaffold(
      backgroundColor: ProfilePalette.canvas(theme),
      appBar: AppBar(
        backgroundColor: ProfilePalette.canvas(theme),
        foregroundColor: ProfilePalette.text(theme),
        titleTextStyle: ProfilePalette.appBarTitleStyle(theme),
        title: const Text('פרופיל שדכן'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            _Header(name: name, photoUrl: photoUrl),
            if ((profile?.about ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                profile!.about,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ProfilePalette.muted(theme),
                  height: 1.45,
                ),
              ),
            ],
            if (canWhatsApp) ...<Widget>[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _openWhatsApp(phone),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                label: const Text('פנייה בוואטסאפ'),
                style: FilledButton.styleFrom(
                  backgroundColor: kWhatsAppGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
            if ((profile?.shares ?? const <MatchmakerShare>[]).isNotEmpty) ...<
              Widget
            >[const SizedBox(height: 20), _SharesCard(shares: profile!.shares)],
            if ((profile?.benefit ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              _BenefitCard(text: profile!.benefit),
            ],
            if (!_loading &&
                (profile == null || !profile.hasDetails)) ...<Widget>[
              const SizedBox(height: 24),
              Text(
                profile == null
                    ? 'לא הצלחנו לטעון את הפרופיל כרגע.'
                    : 'השדכן/ית עוד לא הוסיפו פרטים לפרופיל הציבורי.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ProfilePalette.muted(theme),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The face and the name, and nothing beside them.
class _Header extends StatelessWidget {
  const _Header({required this.name, required this.photoUrl});

  final String name;
  final String photoUrl;

  static const double _radius = 46;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget fallback = CircleAvatar(
      radius: _radius,
      backgroundColor: theme.brightness == Brightness.dark
          ? theme.colorScheme.surfaceContainerHighest
          : AppColors.primaryLight,
      child: const Icon(
        Icons.person_outline,
        size: _radius,
        color: AppColors.primary,
      ),
    );

    return Column(
      children: <Widget>[
        if (photoUrl.isEmpty)
          fallback
        else
          ClipOval(
            child: Image.network(
              photoUrl,
              width: _radius * 2,
              height: _radius * 2,
              fit: BoxFit.cover,
              // A picture that will not load is not worth an error box on
              // somebody's profile — the neutral circle is the same one a
              // matchmaker without a photograph gets.
              errorBuilder: (_, _, _) => fallback,
            ),
          ),
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.2,
            color: ProfilePalette.text(theme),
          ),
        ),
      ],
    );
  }
}

/// Everything the matchmaker chose to say, in one area rather than as fields.
class _SharesCard extends StatelessWidget {
  const _SharesCard({required this.shares});

  final List<MatchmakerShare> shares;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: ProfilePalette.surface(theme),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'קצת עליי',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ProfilePalette.text(theme),
            ),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < shares.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 10),
            Text(
              shares[i].kind.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: ProfilePalette.muted(theme),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              shares[i].text,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
                color: ProfilePalette.text(theme),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "הטבה לקהילה", when there is one.
class _BenefitCard extends StatelessWidget {
  const _BenefitCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark ? AppColors.secondaryDarkDm : AppColors.secondary;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? 0.14 : 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.card_giftcard_rounded, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'הטבה לקהילה',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ProfilePalette.text(theme),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                    color: ProfilePalette.text(theme),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
