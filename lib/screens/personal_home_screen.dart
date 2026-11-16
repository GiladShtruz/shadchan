import 'dart:math';

import 'package:shadchan/widgets/personal_community_news.dart';
import 'package:flutter/material.dart';
import 'package:shadchan/dialogs/card_photo_choice_dialog.dart';
import 'package:shadchan/dialogs/personal_card_lifecycle.dart';
import 'package:shadchan/screens/personal_privacy_screen.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/home_community_link.dart';
import 'package:shadchan/widgets/personal_home_sections.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/personal_area_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/my_matchmakers_screen.dart';
import 'package:shadchan/screens/personal_area_screen.dart';
import 'package:shadchan/services/personal_helpers_store.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/utils/community_prompt_gate.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/reminders_bell_button.dart';
import 'package:shadchan/widgets/shadchan_app_bar.dart';

/// Three personal destinations, separate from the matchmaker database tabs.
class PersonalAreaScreen extends StatelessWidget {
  const PersonalAreaScreen({
    super.key,
    this.section,
    this.friendUid,
    this.createData = PersonalAreaProvider.new,
  });
  final PersonalAreaProvider Function() createData;
  final String? section, friendUid;
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => createData(),
    child: _PersonalShell(section: section, friendUid: friendUid),
  );
}

class _PersonalShell extends StatefulWidget {
  const _PersonalShell({this.section, this.friendUid});
  final String? section, friendUid;
  @override
  State<_PersonalShell> createState() => _PersonalShellState();
}

class _PersonalShellState extends State<_PersonalShell> {
  int _tab = 0;

  /// Counts arrivals at the home, so each one can show a different
  /// community figure. Starts anywhere, so a fresh launch does not always
  /// open on the same one.
  static int _visit = Random().nextInt(1 << 16);
  int _tabFor(String? section) => switch (section) {
    'profile' => 2,
    'helpers' || 'approved' || 'requests' => 1,
    _ => 0,
  };
  @override
  void initState() {
    super.initState();
    _tab = _tabFor(widget.section);
    _visit++;
    WorkspaceStore.setLastArea(WorkArea.personal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CommunityPromptGate.maybeAskHomeAreaOnly(context);
    });
  }

  @override
  void didUpdateWidget(covariant _PersonalShell old) {
    super.didUpdateWidget(old);
    if (old.section != widget.section || old.friendUid != widget.friendUid) {
      final int next = _tabFor(widget.section);
      if (next == 0 && _tab != 0) _visit++;
      _tab = next;
    }
  }

  void _select(int index) {
    setState(() {
      if (index == 0 && _tab != 0) _visit++;
      _tab = index;
    });
    final router = GoRouter.maybeOf(context);
    router?.go(
      index == 0
          ? '/me'
          : index == 1
          ? '/me?section=helpers'
          : '/me?section=profile',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget shell() => Theme(
      data: theme.copyWith(
        textTheme: HomeTypography.scale(
          theme.textTheme,
          dark: theme.brightness == Brightness.dark,
        ),
      ),
      child: Scaffold(
        appBar: ShadchanAppBar(
          title: ['האזור האישי', 'השדכנים שלי', 'פרופיל'][_tab],
          actions: const [RemindersBellButton(boxed: true)],
        ),
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: [
              TickerMode(
                enabled: _tab == 0,
                child: _PersonalHome(onSelectTab: _select, visit: _visit),
              ),
              TickerMode(
                enabled: _tab == 1,
                child: MyMatchmakersScreen(
                  approved: widget.section == 'approved',
                  friendUid: widget.friendUid,
                ),
              ),
              TickerMode(
                enabled: _tab == 2,
                child: const PersonalProfileScreen(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _tab,
          onTap: _select,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'בית',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.handshake_outlined),
              activeIcon: Icon(Icons.handshake_rounded),
              label: 'השדכנים שלי',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'פרופיל',
            ),
          ],
        ),
      ),
    );
    if (!Hive.isBoxOpen('settings')) return shell();
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box<dynamic>(
        'settings',
      ).listenable(keys: [PersonalHelperActions.hiddenKey]),
      builder: (_, _, _) => ListenableBuilder(
        listenable: PersonalHelpersStore.revision,
        builder: (_, _) => shell(),
      ),
    );
  }
}

/// The personal home — light, alive, and inviting rather than a management
/// page. The order is the design: the greeting → two shortcuts (the card,
/// the matchmakers) → the matchmakers who were active lately → the one thing
/// worth doing now → one community figure, a different one each visit → the
/// secondary links. The card in full, the status and "מה אני מחפש/ת" live on
/// "פרופיל"; every matchmaker friend lives on "השדכנים שלי".
///
/// The card itself is drawn here once only — on the first visit after it was
/// written, so the owner sees what they made. From then on it is a shortcut.
/// Nothing here shows what any matchmaker does with the card.
class _PersonalHome extends StatefulWidget {
  const _PersonalHome({required this.onSelectTab, required this.visit});

  /// Moves the shell to one of its tabs: 1 "השדכנים שלי", 2 "פרופיל".
  final ValueChanged<int> onSelectTab;

  /// Turned over on every arrival at the home; picks the community figure.
  final int visit;

  @override
  State<_PersonalHome> createState() => _PersonalHomeState();
}

class _PersonalHomeState extends State<_PersonalHome> {
  bool _restoring = false;

  /// Asked at most once per visit: "לא עכשיו" is an answer for now, and the
  /// question comes back on the next visit — the card goes on carrying its
  /// first four photos meanwhile, and nothing is deleted.
  bool _photoChoiceAsked = false;

  /// Whether this visit draws the card itself — decided once, the first time
  /// a card is there to decide about.
  bool? _showCard;

  /// Set once the owner has seen their new card on the home.
  static const String cardShownKey = 'personalHome.cardShown';

  /// A card younger than this counts as just made.
  static const Duration _newCard = Duration(days: 1);

  bool _decideShowCard(Person card) {
    final bool seen =
        Hive.isBoxOpen('settings') &&
        Hive.box<dynamic>('settings').get(cardShownKey) == 'true';
    final bool fresh = DateTime.now().difference(card.createdAt) < _newCard;
    if (!seen) persistHomeSetting(cardShownKey, 'true');
    return !seen && fresh;
  }

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

  void _toMatchmaker() {
    WorkspaceStore.setLastArea(WorkArea.matchmaker);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    final Person? card = cards.card;
    final bool hasCard = card != null && !cards.isDeleted;
    _maybeAskPhotoChoice(cards);
    if (hasCard) _showCard ??= _decideShowCard(card);
    final String first = (profile.firstName ?? '').trim();
    void toMatchmakers() => widget.onSelectTab(1);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: <Widget>[
        HomeGreeting(
          greeting: _greeting(DateTime.now().hour),
          name: first.isEmpty ? 'שלום' : first,
          trailing: WorkspaceStore.matchmakerEnabled
              ? SwitchToMatchmakerButton(onTap: _toMatchmaker)
              : null,
        ),
        const SizedBox(height: 14),
        PersonalShortcuts(
          onCard: () => widget.onSelectTab(2),
          onMatchmakers: toMatchmakers,
        ),
        if (hasCard && (_showCard ?? false)) ...<Widget>[
          const SizedBox(height: 14),
          PersonalMyCard(card: card, active: cards.hasCard),
        ],
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
        const PersonalCommunityNews(includeStats: false),
        const SizedBox(height: 22),
        const Divider(height: 1),
        const SizedBox(height: 10),
        _PersonalFooter(gender: profile.gender),
      ],
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
          icon: icon(Icons.settings_outlined),
          label: 'הגדרות חשבון',
          theme: theme,
          onTap: () => context.push('/profile/settings'),
        ),
      ],
    );
  }
}
