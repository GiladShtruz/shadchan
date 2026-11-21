import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shadchan/widgets/app_refresh.dart';
import 'package:shadchan/utils/personal_nav.dart';
import 'package:shadchan/services/usage_actions.dart';
import 'package:shadchan/dialogs/card_photo_choice_dialog.dart';
import 'package:shadchan/dialogs/personal_card_lifecycle.dart';
import 'package:shadchan/screens/personal_privacy_screen.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/home_community_link.dart';
import 'package:shadchan/widgets/personal_home_sections.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/my_matchmakers_screen.dart';
import 'package:shadchan/services/personal_helpers_store.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/reminders_bell_button.dart';
import 'package:shadchan/widgets/shadchan_app_bar.dart';

/// The home of somebody who keeps a personal card and does not matchmake.
///
/// **One home, not an area.** It is the same `/home` tab every user has; it
/// only draws what is relevant to a single — the card, the matchmakers who
/// see it, what is new around it — under the app's ordinary bar.
class PersonalHomeScreen extends StatelessWidget {
  const PersonalHomeScreen({super.key});

  /// Counts arrivals at the home, so each one can show a different
  /// community figure. Starts anywhere, so a fresh launch does not always
  /// open on the same one.
  static int _visit = Random().nextInt(1 << 16);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    _visit++;
    final Widget page = Theme(
      data: theme.copyWith(
        textTheme: HomeTypography.scale(
          theme.textTheme,
          dark: theme.brightness == Brightness.dark,
        ),
      ),
      child: Scaffold(
        appBar: const ShadchanAppBar(
          actions: <Widget>[RemindersBellButton(boxed: true)],
        ),
        body: SafeArea(child: PersonalHome(visit: _visit)),
      ),
    );
    if (!Hive.isBoxOpen('settings')) return page;
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box<dynamic>(
        'settings',
      ).listenable(keys: <String>[PersonalHelperActions.hiddenKey]),
      builder: (_, _, _) => ListenableBuilder(
        listenable: PersonalHelpersStore.revision,
        builder: (_, _) => page,
      ),
    );
  }
}

/// What a matchmaker who also keeps a card sees of it on the one home, under
/// the "השדכנים שלי" row: anything new around the card and the one step worth
/// doing for it — between the matchmaker's own blocks, with no heading that
/// splits the page into two worlds.
///
/// **No shortcut buttons.** "הכרטיס שלי" lives prominently on the profile,
/// and "השדכנים שלי" is the row of faces above this block; two large buttons
/// about them only repeated both. Who sees the card is that same row.
class PersonalHomeBlock extends StatelessWidget {
  const PersonalHomeBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    final Person? card = cards.card;
    final bool hasCard = card != null && !cards.isDeleted;
    void toMatchmakers() => PersonalNav.openMatchmakers(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PersonalWhatsNewSection(
          card: hasCard ? card : null,
          nextStep: hasCard
              ? PersonalNextAction.stepFor(
                  context,
                  card: card,
                  live: cards.hasCard,
                ).kind
              : null,
          onMatchmakers: toMatchmakers,
        ),
        if (hasCard) ...<Widget>[
          const SizedBox(height: 14),
          PersonalNextAction(
            card: card,
            live: cards.hasCard,
            onMatchmakers: toMatchmakers,
          ),
        ] else ...<Widget>[
          const SizedBox(height: 14),
          PersonalCardPrompt(
            deleted: cards.isDeleted,
            onAction: cards.isDeleted
                ? () => PersonalCardLifecycle.restore(context)
                : () => PersonalAreaService.editCard(context),
          ),
        ],
      ],
    );
  }
}

/// The personal home — a live, simple screen, like a service app's: less
/// management, more "what is new around me" and "what is worth doing now".
///
/// **The order is the design:** greeting → "הכרטיס שלי" | "השדכנים שלי" →
/// "מה חדש אצלי" (only when there is something) → the matchmakers active
/// lately → the one thing worth doing now → one community figure, a different
/// one each visit → "מי רואה אותי" → the secondary links, quiet, at the foot.
///
/// About seventy per cent of the page is what is happening around the owner
/// and thirty is actions, so it is worth coming back to and never reads as a
/// form. The card in full, "מה אני מחפש/ת", recordings and settings are not
/// here — they live on "פרופיל". White page, secondary areas in the light
/// cream, few frames, one thing per area.
class PersonalHome extends StatefulWidget {
  const PersonalHome({super.key, required this.visit});

  /// Turned over on every arrival at the home; picks the community figure.
  final int visit;

  @override
  State<PersonalHome> createState() => _PersonalHomeState();
}

class _PersonalHomeState extends State<PersonalHome> {
  bool _restoring = false;

  /// Asked at most once per visit: "לא עכשיו" is an answer for now, and the
  /// question comes back on the next visit — the card goes on carrying its
  /// first four photos meanwhile, and nothing is deleted.
  bool _photoChoiceAsked = false;

  void _maybeAskPhotoChoice(PersonalCardProvider cards) {
    if (_photoChoiceAsked || !cards.needsPhotoChoice || cards.isDeleted) {
      return;
    }
    _photoChoiceAsked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final Person? card = cards.card;
      if (!mounted || card == null || !cards.needsPhotoChoice) return;
      final List<String>? keep = await CardPhotoChoiceDialog.show(
        context,
        card.photosPaths,
        gender: card.gender == Gender.unknown
            ? context.read<UserProfileProvider>().gender
            : card.gender,
      );
      if (keep != null && mounted) {
        await cards.keepPhotos(keep);
      }
    });
  }

  static String _greeting(int hour) => hour >= 5 && hour < 12
      ? 'בוקר טוב'
      : hour >= 12 && hour < 17
      ? 'צהריים טובים'
      : hour >= 17 && hour < 21
      ? 'ערב טוב'
      : 'לילה טוב';

  Future<void> _restore() async {
    setState(() => _restoring = true);
    await PersonalCardLifecycle.restore(context);
    if (mounted) setState(() => _restoring = false);
  }

  @override
  Widget build(BuildContext context) {
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    final Person? card = cards.card;
    final bool hasCard = card != null && !cards.isDeleted;
    _maybeAskPhotoChoice(cards);
    final String first = (profile.firstName ?? '').trim();
    void toMatchmakers() => PersonalNav.openMatchmakers(context);

    return AppRefreshIndicator(
      scope: RefreshScope.matchmakers,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: <Widget>[
          HomeGreeting(
            greeting: _greeting(DateTime.now().hour),
            name: first.isEmpty ? 'שלום' : first,
          ),
          const SizedBox(height: 14),
          PersonalShortcuts(
            onCard: () => PersonalNav.openCard(context),
            onMatchmakers: toMatchmakers,
          ),
          // Only when there is real news around the owner.
          PersonalWhatsNewSection(
            card: hasCard ? card : null,
            nextStep: hasCard
                ? PersonalNextAction.stepFor(
                    context,
                    card: card,
                    live: cards.hasCard,
                  ).kind
                : null,
            onMatchmakers: toMatchmakers,
          ),
          PersonalRecentMatchmakers(onSeeAll: toMatchmakers),
          const SizedBox(height: 22),
          if (hasCard)
            PersonalNextAction(
              card: card,
              live: cards.hasCard,
              onMatchmakers: toMatchmakers,
            )
          else ...<Widget>[
            const PersonalSectionTitle(PersonalNextAction.title),
            PersonalCardPrompt(
              deleted: cards.isDeleted,
              busy: _restoring,
              onAction: cards.isDeleted
                  ? _restore
                  : () => PersonalAreaService.editCard(context),
            ),
          ],
          PersonalCommunityFigure(visit: widget.visit),
          if (hasCard) const PersonalWhoSees(),
          const SizedBox(height: 22),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _PersonalFooter(gender: profile.gender),
        ],
      ),
    );
  }
}

/// The three secondary actions, quiet, at the very foot.
class _PersonalFooter extends StatelessWidget {
  const _PersonalFooter({required this.gender});
  final Gender? gender;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    Icon icon(IconData data) =>
        Icon(data, size: 17, color: theme.colorScheme.onSurfaceVariant);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: <Widget>[
        Builder(
          builder: (BuildContext anchor) => FooterLink(
            icon: icon(Icons.share_outlined),
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
          icon: icon(Icons.lock_outline_rounded),
          label: 'ניהול ופרטיות',
          theme: theme,
          onTap: () => PersonalPrivacyScreen.open(context),
        ),
        FooterLink(
          icon: icon(Icons.diversity_1_outlined),
          label: 'רוצה לחשוב גם על חברים?',
          theme: theme,
          onTap: () => UsageActions.startMatchmaking(context),
        ),
      ],
    );
  }
}
