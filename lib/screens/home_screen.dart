import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:shadchan/widgets/activity_figure_row.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/dialogs/app_menu.dart';
import 'package:shadchan/dialogs/board_add_sheet.dart';
import 'package:shadchan/dialogs/home_board_actions.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/services/tips_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/think_rotation.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/utils/new_idea_suggestions.dart';
import 'package:shadchan/utils/home_suggestions.dart';
import 'package:shadchan/utils/home_board_feed.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/utils/community_counts.dart';
import 'package:shadchan/utils/community_prompt_gate.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/search_navigation.dart';
import 'package:shadchan/utils/home_open_ideas.dart';
import 'package:shadchan/utils/home_search.dart';
import 'package:shadchan/utils/home_stage.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/utils/matchmaker_tips.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/reminder_alerts.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/board_row.dart';
import 'package:shadchan/widgets/home_activity_block.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/home_community_link.dart';
import 'package:shadchan/widgets/home_community_pulse.dart';
import 'package:shadchan/widgets/home_blocks.dart';
import 'package:shadchan/widgets/home_engagement_card.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/home_search_results.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/home_stage_panels.dart';
import 'package:shadchan/widgets/shadchan_app_bar.dart';

/// The landing screen: a calm workspace rather than a dashboard.
///
/// The page is read as a hierarchy, not as a list of equal boxes. First the
/// opening band with the one thought and the one button; then the two ways to
/// grow the database, drawn as two deliberately different cards; then the
/// narrow strips of what was just worked on and what is open; then the people
/// worth a thought as free circles on a wave; then the couples' banner; and
/// only at the bottom the way into the numbers and the month's tip. Nothing on
/// the resting screen is open, expanded or asking to be dismissed.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.initialSearch = '',
    this.focusBoard = false,
  });

  final String initialSearch;
  final bool focusBoard;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _homeScrollController = ScrollController();
  final GlobalKey _boardSectionKey = GlobalKey();

  /// Bumped by a tap on the wordmark, which deals the board again.
  int _boardRefresh = 0;

  /// The single vertical gap between every block on the page.
  static const double _blockGap = 14;

  /// The built-in tips, in one order picked per visit.
  ///
  /// Fixed for the life of the screen because the tip block is now swiped
  /// rather than re-rolled: a list that reshuffled on every rebuild would put a
  /// different tip behind the same backwards swipe. Rotating between visits is
  /// what stops the same tip greeting the matchmaker every morning.
  late final List<String> _tipOrder = List<String>.of(MatchmakerTips.tips)
    ..shuffle();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialSearch;
    _searchController.addListener(() => setState(() {}));
    _scheduleBoardFocus();
    _scheduleCommunityPrompts();
  }

  /// The one moment per launch when the app is allowed to say something of its
  /// own — a published note, a rating request, an invitation to the group.
  ///
  /// Deferred to after the first frame so the home screen is on screen behind
  /// whatever appears, and gated so at most one of the three ever does. The
  /// figure it is paced by is the same "כל הזמנים" score the activity block
  /// below shows.
  void _scheduleCommunityPrompts() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final PersonRepository people = context.read<PersonRepository>();
      final MatchRepository matches = context.read<MatchRepository>();
      CommunityPromptGate.maybeShow(
        context,
        people: people,
        matches: matches,
        counts: CommunityCounts.build(
          people: people.getAll(),
          matches: matches.getAll(),
          matchStatusEvents: matches.getAllStatusEvents(),
          excludedFromDating: DatingCountExclusions.all(),
        ),
        isSignedIn: context.read<AccountProvider>().isSignedIn,
      );
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusBoard && !oldWidget.focusBoard) {
      _scheduleBoardFocus();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _homeScrollController.dispose();
    super.dispose();
  }

  void _scheduleBoardFocus({bool force = false}) {
    if (!force && !widget.focusBoard) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? boardContext = _boardSectionKey.currentContext;
      if (!mounted || boardContext == null) {
        return;
      }
      final RenderObject? renderObject = boardContext.findRenderObject();
      if (renderObject is! RenderBox || !_homeScrollController.hasClients) {
        return;
      }
      final double desiredTop =
          MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
      final double target =
          (_homeScrollController.offset +
                  renderObject.localToGlobal(Offset.zero).dy -
                  desiredTop)
              .clamp(
                _homeScrollController.position.minScrollExtent,
                _homeScrollController.position.maxScrollExtent,
              );
      _homeScrollController.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();

    // **One type scale for the whole page, decided here rather than card by
    // card.** A dozen widgets across five files were each picking a Material
    // role that was right on their own card, and between them the landing page
    // was drawn in ten sizes with no order to them. See [HomeTypography]: the
    // roles are folded onto three, once, and the blocks go on asking for
    // whatever they always asked for.
    return Theme(
      data: theme.copyWith(
        textTheme: HomeTypography.scale(
          theme.textTheme,
          dark: theme.brightness == Brightness.dark,
        ),
      ),
      child: Builder(
        builder: (BuildContext context) => Scaffold(
          appBar: _buildGreetingAppBar(),
          body: SafeArea(
            child: Stack(
              children: <Widget>[
                // The board and the activity trail are app-wide singletons
                // rather than injected providers — the repositories write to
                // them when a record is deleted — so the page listens to them
                // directly.
                ListenableBuilder(
                  listenable: Listenable.merge(<Listenable>[
                    HomeBoardStore.instance,
                    RecentActivityStore.instance,
                  ]),
                  builder: (BuildContext context, _) => _buildHome(),
                ),
                _buildSearchPanel(Theme.of(context), personRepository),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- AppBars ------------------------------------------------------------

  /// The home bar: the app's name at the start, the bell and the menu at the
  /// other end, and the search row pinned under both.
  ///
  /// **The corner carries three dots again, not a face.** A photograph in the
  /// far corner of a bar is read as "this is you", not as "this is the way to
  /// everything else" — so the one control that opens settings, help, the
  /// privacy policy and the way to share the app was drawn as an avatar, and
  /// the menu those rows live on had nowhere to hang from at all. The overflow
  /// dots are what a phone's menu is looked for, and הפרופיל שלי is the first
  /// row on it, so the matchmaker's own page is one tap further and every other
  /// destination is one tap closer.
  ///
  /// **The search row is part of the bar now.** It used to be the first sliver
  /// on the page and went away with it; on a screen that is scrolled all day
  /// that is the one control that must not.
  ShadchanAppBar _buildGreetingAppBar() {
    // The same three controls, in the same order, as המאגר שלי and רעיונות —
    // see [ShadchanTabActions]. Only the "+" differs: this page is above both
    // of the other two, so its "+" asks which of them is meant.
    return ShadchanAppBar(
      onTitleTap: _backToTop,
      actions: const <Widget>[
        // בית keeps its own overflow menu — the app itself, the community
        // group, the guide, the privacy policy. המאגר שלי and הרעיונות שלי
        // carry the shorter list of destinations instead. See
        // [AppMenuVariant].
        ShadchanTabActions(menu: AppMenuVariant.home),
      ],
      bottom: ShadchanSearchBottom(
        child: ShadchanSearchField(
          controller: _searchController,
          hintText: 'חיפוש בכל המאגר',
          onCleared: _closeSearch,
        ),
      ),
    );
  }

  /// The wordmark's tap: home, as if it had just been opened — search closed,
  /// the page back at its top, and the board dealt again.
  void _backToTop() {
    if (_searchController.text.isNotEmpty) {
      _closeSearch();
    } else {
      FocusScope.of(context).unfocus();
    }
    setState(() => _boardRefresh++);
    if (_homeScrollController.hasClients) {
      _homeScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Leaves search: the results and the keyboard.
  void _closeSearch() {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() {});
  }

  // --- Home body ----------------------------------------------------------

  Widget _buildHome() {
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final UserProfileProvider userProfile = context
        .watch<UserProfileProvider>();
    final Gender? userGender = userProfile.gender;
    final bool hasOwnCard =
        userProfile.isSingle && context.watch<PersonalCardProvider>().hasCard;
    final HomeBoardStore board = HomeBoardStore.instance;

    if (board.takeFocusRequest()) {
      _scheduleBoardFocus(force: true);
    }

    final List<MatchIdea> allMatches = matchRepository.getAll();
    // "זוגות שיוצאים" is not on this page any more — it lives at the head of
    // "הרעיונות שלי", where the couples themselves are. See
    // `MatchesScreen`'s dating strip.
    final List<HomeOpenIdea> openIdeas = HomeOpenIdeas.build(
      matches: allMatches,
      personById: personRepository.getById,
      isAlerting: (MatchIdea match) =>
          ReminderAlerts.isAlerting(match.id, match.reminderDate),
      isDue: ReminderAlerts.isDue,
      reopenedAt: HomeOpenIdeas.reopenedFromEvents(
        statusEvents: matchRepository.getAllStatusEvents(),
      ),
    );

    final int friends = personRepository.databaseCount;
    final HomeStage stage = HomeStage.forCount(friends);
    final HomeMilestone milestone = HomeMilestone.forCount(friends);

    // At most one encouragement card, picked by what the database actually
    // needs next. A brand-new matchmaker already has the welcome card above, so
    // they get nothing here — being urged twice in one screen to do the thing
    // you have not done yet is nagging, not onboarding.
    final Widget? nudge;
    if (friends == 0) {
      nudge = null;
    } else if (friends >= 10 && allMatches.isEmpty) {
      // The one moment the app can say something genuinely useful about
      // opening a first proposal.
      nudge = HomeFirstIdeaCard(
        friends: friends,
        onOpenIdea: () => context.push('/matches/add'),
      );
    } else if (stage == HomeStage.starting) {
      // Under ten friends, importing a group really is the fastest way to grow.
      nudge = HomeImportInvite(onTap: () => context.push('/people/ai'));
    } else {
      nudge = null;
    }

    double inset() => homeHorizontalInset(context);
    // One gap between blocks, everywhere. The page used to run 12, 14, 16, 18
    // and 22 between its areas, which is what made a screen of otherwise calm
    // cards feel unsettled — nothing lined up with anything.
    SliverPadding block(Widget child, {double top = _blockGap}) {
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(inset(), top, inset(), 0),
        sliver: SliverToBoxAdapter(child: child),
      );
    }

    // The order of what follows *is* the design, and it is an order of
    // usefulness. The greeting, then the two ways to grow the database, then
    // the board — which is now the whole of "what am I working on", because
    // every open proposal lands on it by itself. Only after all of that does
    // the page turn to figures: what has been done, what the community is
    // doing, the week's shared target, and a tip to close on.
    //
    // **Three areas left this page rather than being redrawn on it.**
    // "עוצרים רגע לחשוב על חברים" is at the head of המאגר שלי, "רעיונות שהמאגר
    // מציע לך" and the couples who are out are at the head of הרעיונות שלי.
    // Each of them was an invitation into a screen it now sits on top of, which
    // is one tap shorter and one block of home screen cheaper. Gone entirely:
    // "הפעולות הבאות" — a ranked queue on a page that already has a board — and
    // "רעיונות פתוחים", which the board now carries.
    //
    // A block with nothing in it is not drawn at all rather than shown as an
    // empty box — an empty screen teaches that the app is empty.
    // The first name and nothing else. A greeting is how someone is spoken to,
    // not how they are filed — "בוקר טוב, רבקה כהן־שטרן" is a form letter.
    final String greetingName =
        userProfile.firstName ?? '{שדכן|שדכנית}'.forGender(userGender);

    return CustomScrollView(
      controller: _homeScrollController,
      slivers: <Widget>[
        // 1. The greeting, and one warm line under it. On the page rather than
        // in the bar, with nothing drawn around it. A matchmaker who also
        // keeps a card of their own finds the way into it in the far corner of
        // the same line — never a row of its own.
        block(
          HomeGreeting(
            greeting: _timeOfDayGreeting(
              TimeOfDay.fromDateTime(DateTime.now()),
            ),
            name: greetingName,
            line: '{בוא|בואי} ניצור היום חיבורים חדשים'.forGender(userGender),
            trailing: hasOwnCard
                ? TextButton.icon(
                    onPressed: () => context.go('/me'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    icon: const Icon(Icons.badge_outlined, size: 18),
                    label: const Text('ניהול הכרטיס שלי'),
                  )
                : null,
          ),
          top: 8,
        ),

        // A brand-new matchmaker lands on the real home screen with one
        // welcoming card on it, not on a wizard that has to be got through.
        if (friends == 0)
          block(
            HomeWelcomeCard(onAddPeople: () => AddPeopleDialog.show(context)),
          ),

        // 2. The four all-time figures — friends, ideas, couples who went
        // out, weddings — above the two ways to grow them.
        if (friends > 0)
          block(
            ActivityFigureRow(
              people: personRepository,
              matches: matchRepository,
            ),
          ),

        // 3. The two entry actions. Adding friends leads — a little deeper in
        // colour and a little wider — because every other thing on the page is
        // only possible once the database has people in it.
        //
        // **Pinned.** Scrolled past, the pair parks under the search bar and
        // rides there for the rest of the page — the two things the app is
        // opened to do stay one tap away however far down the board, the
        // figures or the tips somebody has gone.
        // Measured against the list's own width rather than the screen's,
        // so the header's promised height is exactly what the cards take.
        SliverLayoutBuilder(
          builder: (BuildContext context, SliverConstraints constraints) {
            return SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedAddCards(
                height:
                    HomeActionCards.heightFor(
                      context,
                      constraints.crossAxisExtent - 2 * inset(),
                    ) +
                    _blockGap +
                    10,
                inset: inset(),
                background: Theme.of(context).scaffoldBackgroundColor,
                child: HomeActionCards(
                  onAddPeople: () => AddPeopleDialog.show(context),
                  onAddIdea: () => context.push('/matches/add'),
                  emphasiseAddPeople: true,
                ),
              ),
            );
          },
        ),

        // The personal target: how far the database is from ten friends, then
        // twenty-five, then fifty, then a hundred. It stops entirely at a
        // hundred friends, where a target is no longer the useful thing to say.
        if (friends > 0 && stage.showsTarget)
          block(HomeMilestoneCard(milestone: milestone)),

        // Exactly one encouragement card, never a stack of them.
        if (nudge != null) block(nudge),

        // 3. הלוח שלי — every open proposal, whatever asked to be remembered
        // today, and whatever was pinned by hand. One surface for "what am I
        // working on", which is why "רעיונות פתוחים" no longer needs a row of
        // its own further down the page.
        _BoardSection(
          focusKey: _boardSectionKey,
          entries: board.entries,
          openIdeas: openIdeas,
          personRepository: personRepository,
          matchRepository: matchRepository,
          refresh: _boardRefresh,
        ),

        // 4. What has been done — the matchmaker's own score beside the
        // community's, two squares and one window at a time. The breakdown, the
        // chart and the leaderboard are all one tap away on a screen somebody
        // opened *to look at numbers*.
        block(HomeActivityBlock(onOpen: () => context.push('/activity'))),

        // 5 and 6. The community, live: what it did today, and the one target
        // it is working towards together this week. The only block on the page
        // that moves on its own, and the only one that is about other people —
        // which is why it sits directly under the numbers, where the page turns
        // from "your work" to "everybody's".
        block(HomeCommunityPulse(onOpen: () => context.push('/activity'))),

        // Somebody else's good news, for one launch. It draws nothing at all
        // when there is none, which is nearly always.
        block(const HomeEngagementCard()),

        // 7. The community's tip.
        block(
          HomeTipCarousel(
            tips: _tips(context),
            userGender: userGender,
            onAddTip: () => context.push('/profile/tips'),
          ),
        ),

        // Last on the page, under everything, where an invitation belongs when
        // it is not urgent and must never be in the way.
        block(const HomeCommunityLink()),

        SliverToBoxAdapter(
          child: SizedBox(
            height:
                MediaQuery.viewPaddingOf(context).bottom +
                kBottomNavigationBarHeight +
                16,
          ),
        ),
      ],
    );
  }

  /// The rotation the tip block swipes through: the tips that ship with the app
  /// first, then every approved community tip.
  ///
  /// The built-in ones are unsigned — there is nobody to credit — while a
  /// community tip carries the name of the matchmaker who wrote it. The order
  /// is fixed for the life of the screen so a swipe back really does return to
  /// the previous tip.
  List<HomeTip> _tips(BuildContext context) {
    final Gender? gender = context.watch<UserProfileProvider>().gender;
    final List<CommunityTip> community = context.watch<TipsProvider>().approved;
    return <HomeTip>[
      for (final String template in _tipOrder)
        HomeTip(text: template.forGender(gender)),
      for (final CommunityTip tip in community)
        HomeTip(
          text: tip.text,
          author: tip.authorName.isEmpty ? null : tip.authorName,
        ),
    ];
  }

  // --- Search -------------------------------------------------------------

  /// Live results over the home page, capped at half the screen height so the
  /// page underneath stays visible.
  ///
  /// The page underneath is *dimmed* and takes a tap to leave. Before that the
  /// results simply floated over a fully live home page, so there was no edge
  /// to the search and no way out of it except the button in the bar — a tap
  /// on the page behind went to whatever card happened to be under the finger.
  Widget _buildSearchPanel(ThemeData theme, PersonRepository repository) {
    final String query = _searchController.text.trim();
    if (query.isEmpty) {
      return const SizedBox.shrink();
    }

    // The whole database, word by word — see [HomeSearch].
    final HomeSearchResults results = HomeSearch.run(
      query,
      repository.getAll(),
      notesFor: repository.getNotesForPerson,
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeSearch,
            child: ColoredBox(
              color: theme.colorScheme.scrim.withValues(alpha: 0.32),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            // The field is in the bar now, so the body starts directly under
            // it and the results only need a hair of air above them.
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              elevation: 6,
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        child: Text(
                          'לא נמצאו תוצאות',
                          textAlign: TextAlign.center,
                          // `bodyLarge` folds to the heading ink; this line is
                          // an absence, not a heading.
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: AppColors.muted(
                              dark: theme.brightness == Brightness.dark,
                            ),
                          ),
                        ),
                      )
                    : HomeSearchResultsList(
                        results: results,
                        onOpenPerson: (Person person) {
                          _closeSearch();
                          pushLeavingSearch(context, '/people/${person.id}');
                        },
                        // A match inside the card opens the profile where the
                        // words are: the full card open, or the notes.
                        onOpenHit: (ContentHit hit) {
                          _closeSearch();
                          pushLeavingSearch(
                            context,
                            '/people/${hit.person.id}?focus=${hit.field.focus}',
                          );
                        },
                        onToggleFavorite: (Person person) =>
                            repository.toggleFavorite(person.id),
                        onOpenWhatsApp: _openWhatsApp,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openWhatsApp(Person person) async {
    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && mounted) {
      AppNotice.show(context, 'לא הצלחנו לפתוח את וואטסאפ');
    }
  }

  /// Hebrew greeting for the current part of the day: morning until noon,
  /// afternoon until 17:00, evening until 21:00, night from then until 05:00.
  /// The greetings themselves are gender-free — what follows the comma is the
  /// matchmaker's own name.
  static String _timeOfDayGreeting(TimeOfDay now) {
    final int hour = now.hour;
    if (hour >= 5 && hour < 12) {
      return 'בוקר טוב';
    }
    if (hour >= 12 && hour < 17) {
      return 'צהריים טובים';
    }
    if (hour >= 17 && hour < 21) {
      return 'ערב טוב';
    }
    return 'לילה טוב';
  }
}

// --- הלוח שלי ---------------------------------------------------------------

/// Everything the matchmaker is working on right now, on one surface.
///
/// **The figures first, then the board.** Four all-time counts head the
/// section — the same ones "הנתונים שלך" shows — and under them one window
/// onto a mixed feed.
///
/// **One feed, dealt from five sources.** Reminders whose date has arrived,
/// every open proposal, whatever was pinned, and reminders that have been
/// overdue for a while — in that order of priority, but interleaved rather
/// than shelved, so a busy morning is not twelve reminders before the first
/// proposal. See [HomeBoardFeed.mix]. When the matchmaker's own work comes to
/// fewer than [HomeBoardFeed.target] rows, the board is topped up with what the
/// app would offer anyway: a pair from "רעיונות שהמאגר מציע לך" and a friend
/// from "עוצרים רגע לחשוב על החברים".
///
/// **A pin is a promise to put it first.** Something pinned in the last
/// [_BoardSectionState._pinLeads] leads the board with a small pin on it;
/// after that it joins the mix as one of the matchmaker's own items and keeps
/// the pin. Without the window a matchmaker who had pinned eight things a
/// month ago would never see anything else at the top.
///
/// **Always open, framed, and three and a half rows high.** The board used to
/// fold; now it is a fixed, framed window that scrolls inside itself, short
/// enough that its bottom edge is always on screen.
class _BoardSection extends StatefulWidget {
  const _BoardSection({
    required this.focusKey,
    required this.entries,
    required this.openIdeas,
    required this.personRepository,
    required this.matchRepository,
    required this.refresh,
  });

  final Key focusKey;

  /// The pinned entries, newest first.
  final List<HomeBoardEntry> entries;

  /// Every proposal that is open right now, already ranked — the ones asking
  /// for something today first. See [HomeOpenIdeas].
  final List<HomeOpenIdea> openIdeas;

  final PersonRepository personRepository;
  final MatchRepository matchRepository;

  /// Bumped by a tap on the wordmark: a new deal of the same board.
  final int refresh;

  @override
  State<_BoardSection> createState() => _BoardSectionState();
}

class _BoardSectionState extends State<_BoardSection> {
  /// How many whole rows the board's window shows before it scrolls. A half
  /// row more peeks out under them, so the list plainly goes on — and the
  /// window stays short enough that its frame always ends on screen.
  static const int _windowRows = 3;

  /// One row: a two-line card plus the gap under it.
  static const double _rowExtent = AccentBar.rowHeight + 12;

  /// How long a fresh pin holds the top of the board.
  static const Duration _pinLeads = Duration(hours: 48);

  /// A reminder that came due within this long is news; older than this it is
  /// a reminder that has been left, and ranks below everything else of the
  /// matchmaker's own.
  static const Duration _freshFor = Duration(days: 7);

  /// The board's own scroll, kept alive across rebuilds so a matchmaker who
  /// scrolled down it does not lose their place every time a reminder ticks
  /// over.
  final ScrollController _listScroll = ScrollController();

  /// The app's own suggestions, worked out once per state of the database —
  /// pairing the whole database is not something to redo on every rebuild.
  String? _fillerKey;
  List<NewIdeaSuggestion> _pairs = const <NewIdeaSuggestion>[];
  List<HomeSuggestion> _thoughts = const <HomeSuggestion>[];

  @override
  void didUpdateWidget(covariant _BoardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refresh != oldWidget.refresh && _listScroll.hasClients) {
      _listScroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _listScroll.dispose();
    super.dispose();
  }

  double _boardHeight(BuildContext context, int rows) {
    final double shown = rows > _windowRows
        ? _windowRows + 0.5
        : rows.toDouble();
    return homeScaled(context, _rowExtent * shown);
  }

  bool _exists(HomeItemKind kind, String id) {
    return kind == HomeItemKind.person
        ? widget.personRepository.getById(id) != null
        : widget.matchRepository.getById(id) != null;
  }

  void _loadFillers() {
    final List<Person> everyone = widget.personRepository.getAll();
    final List<MatchIdea> matches = widget.matchRepository.getAll();
    DateTime latest = DateTime(2000);
    for (final Person p in everyone) {
      if (p.updatedAt.isAfter(latest)) {
        latest = p.updatedAt;
      }
    }
    for (final MatchIdea m in matches) {
      if (m.updatedAt.isAfter(latest)) {
        latest = m.updatedAt;
      }
    }
    final String key =
        '${everyone.length}|${matches.length}|'
        '${latest.millisecondsSinceEpoch}|${widget.refresh}|'
        '${DateUtils.dateOnly(DateTime.now())}';
    if (key == _fillerKey) {
      return;
    }
    _fillerKey = key;

    final List<List<NewIdeaSuggestion>> rounds = NewIdeaSuggestions.batches(
      NewIdeaSuggestions.build(
        people: everyone,
        matches: matches,
        dismissedFor: SuggestionDismissals.dismissedFor,
      ),
    );
    _pairs = rounds.isEmpty ? const <NewIdeaSuggestion>[] : rounds.first;

    final Set<String> later = ThinkLater.activeIds();
    _thoughts = HomeSuggestions.build(
      people: everyone
          .where(
            (Person p) =>
                !p.hidden &&
                !p.needsReview &&
                p.profileStatus == ProfileStatus.available &&
                !later.contains(p.id),
          )
          .toList(),
      matches: matches,
      events: widget.personRepository.getAllEvents(),
      activity: RecentActivityStore.instance.entries,
      limit: HomeBoardFeed.target,
    );
  }

  /// The whole board, in the order it is drawn.
  List<_BoardItem> _feed() {
    final DateTime now = DateTime.now();
    final HomeBoardStore store = HomeBoardStore.instance;

    // A row taken off with "הסרה" stays off until what put it there changes:
    // a reminder dated after the removal, a proposal that moved since.
    bool removedSince(HomeItemKind kind, String id, DateTime changedAt) {
      final DateTime? at = store.hiddenAt(HomeBoardStore.itemKey(kind, id));
      return at != null && !changedAt.isAfter(at);
    }

    // A suggestion the app made is simply left alone for a month.
    bool removedRecently(String key) {
      final DateTime? at = store.hiddenAt(key);
      return at != null && now.difference(at) < const Duration(days: 30);
    }

    // A pinned record that has since been deleted simply drops out.
    final List<HomeBoardEntry> pinned = widget.entries
        .where((HomeBoardEntry e) => _exists(e.kind, e.targetId))
        .toList();
    final Set<String> seen = <String>{
      for (final HomeBoardEntry e in pinned) '${e.kind.name}:${e.targetId}',
    };
    final List<_BoardItem> leading = <_BoardItem>[
      for (final HomeBoardEntry e in pinned)
        if (now.difference(e.addedAt) < _pinLeads)
          _BoardItem.entry(e, pinned: true),
    ];
    final List<_BoardItem> olderPins = <_BoardItem>[
      for (final HomeBoardEntry e in pinned)
        if (now.difference(e.addedAt) >= _pinLeads)
          _BoardItem.entry(e, pinned: true),
    ];

    // Reminders whose date has arrived, the most recent first.
    final List<(HomeItemKind, String, DateTime, String?)> due =
        <(HomeItemKind, String, DateTime, String?)>[];
    PersonReminders.all().forEach((String personId, DateTime at) {
      if (!at.isAfter(now) &&
          widget.personRepository.getById(personId) != null) {
        due.add((
          HomeItemKind.person,
          personId,
          at,
          PersonReminders.noteFor(personId),
        ));
      }
    });
    for (final MatchIdea match in widget.matchRepository.getAll()) {
      final DateTime? at = match.reminderDate;
      if (at != null && !at.isAfter(now)) {
        due.add((HomeItemKind.idea, match.id, at, match.reminderNote));
      }
    }
    due.sort(
      (
        (HomeItemKind, String, DateTime, String?) a,
        (HomeItemKind, String, DateTime, String?) b,
      ) => b.$3.compareTo(a.$3),
    );
    final List<_BoardItem> fresh = <_BoardItem>[];
    final List<_BoardItem> stale = <_BoardItem>[];
    for (final (HomeItemKind kind, String id, DateTime at, String? note)
        in due) {
      if (removedSince(kind, id, at) || !seen.add('${kind.name}:$id')) {
        continue;
      }
      final String text = (note ?? '').trim();
      final _BoardItem item = _BoardItem.entry(
        HomeBoardEntry(kind: kind, targetId: id, addedAt: at),
        hint: text.isEmpty ? 'הגיע מועד התזכורת' : text,
        reminder: true,
      );
      (now.difference(at) <= _freshFor ? fresh : stale).add(item);
    }

    // Every open proposal, in the order [HomeOpenIdeas] ranked them. What a
    // proposal has to say for itself is its next step, read live by the row.
    final List<_BoardItem> open = <_BoardItem>[
      for (final HomeOpenIdea idea in widget.openIdeas)
        if (!removedSince(
              HomeItemKind.idea,
              idea.match.id,
              idea.match.updatedAt,
            ) &&
            seen.add('${HomeItemKind.idea.name}:${idea.match.id}'))
          _BoardItem.entry(
            HomeBoardEntry(
              kind: HomeItemKind.idea,
              targetId: idea.match.id,
              addedAt: idea.match.updatedAt,
            ),
          ),
    ];

    final int own =
        leading.length +
        olderPins.length +
        fresh.length +
        stale.length +
        open.length;
    List<_BoardItem> pairs = const <_BoardItem>[];
    List<_BoardItem> thoughts = const <_BoardItem>[];
    final int room = HomeBoardFeed.fillerRoom(own);
    if (room > 0) {
      _loadFillers();
      final List<NewIdeaSuggestion> livePairs = _pairs
          .where(
            (NewIdeaSuggestion s) =>
                widget.matchRepository.findExisting(s.male.id, s.female.id) ==
                    null &&
                !SuggestionDismissals.isDismissed(s.male.id, s.female.id) &&
                !removedRecently(
                  HomeBoardStore.pairKey(s.male.id, s.female.id),
                ),
          )
          .toList();
      final List<HomeSuggestion> liveThoughts = _thoughts
          .where(
            (HomeSuggestion s) =>
                !seen.contains('${HomeItemKind.person.name}:${s.person.id}') &&
                !removedRecently(
                  HomeBoardStore.itemKey(HomeItemKind.person, s.person.id),
                ),
          )
          .toList();
      final (List<NewIdeaSuggestion>, List<HomeSuggestion>) split =
          HomeBoardFeed.splitFillers(livePairs, liveThoughts, room);
      pairs = <_BoardItem>[
        for (final NewIdeaSuggestion s in split.$1) _BoardItem.pair(s),
      ];
      thoughts = <_BoardItem>[
        for (final HomeSuggestion s in split.$2)
          _BoardItem.entry(
            HomeBoardEntry(
              kind: HomeItemKind.person,
              targetId: s.person.id,
              addedAt: now,
            ),
            hint: s.reason,
            suggested: true,
          ),
      ];
    }

    final List<BoardFeedItem<_BoardItem>> mixed =
        HomeBoardFeed.mix(<BoardFeedKind, List<_BoardItem>>{
          BoardFeedKind.freshReminder: fresh,
          BoardFeedKind.openIdea: open,
          BoardFeedKind.pinned: olderPins,
          BoardFeedKind.oldReminder: stale,
          BoardFeedKind.suggestedIdea: pairs,
          BoardFeedKind.thinkAbout: thoughts,
        }, seed: HomeBoardFeed.seedFor(now, widget.refresh));
    return <_BoardItem>[
      ...leading,
      for (final BoardFeedItem<_BoardItem> item in mixed) item.value,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    // Nothing to put on a board before the first friend.
    if (widget.personRepository.databaseCount == 0 && widget.entries.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final List<_BoardItem> live = _feed();

    return SliverToBoxAdapter(
      child: Column(
        key: widget.focusKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const HomeSectionHeader(
            title: 'הלוח שלי',
            subtitle: 'הרעיונות הפתוחים, התזכורות ומה שהצמדתי',
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: homeHorizontalInset(context),
            ),
            // **A frame, so the board reads as a box with its own scroll.** A
            // window of rows cut straight into the page looked like the page
            // itself carrying on, and a thumb scrolling the page got caught
            // inside the board until it reached the end of the list. The frame
            // and the always-visible scrollbar say "this scrolls on its own",
            // and the window is short enough that its bottom edge is always on
            // screen above whatever comes next.
            child: DecoratedBox(
              decoration: BoxDecoration(
                // The palette's brown, not its blue: the figures above and
                // the rows inside are already blue enough, and the board is
                // the page's one warm surface.
                color: Color.alphaBlend(
                  (dark ? AppColors.secondaryDarkDm : AppColors.secondary)
                      .withValues(alpha: dark ? 0.14 : 0.13),
                  theme.scaffoldBackgroundColor,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      (dark ? AppColors.secondaryDarkDm : AppColors.secondary)
                          .withValues(alpha: 0.55),
                  width: 1.4,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                child: live.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 18,
                        ),
                        child: Text(
                          'הלוח ריק — אפשר להצמיד אליו חבר או רעיון',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : SizedBox(
                        height: _boardHeight(context, live.length),
                        child: Scrollbar(
                          controller: _listScroll,
                          thumbVisibility: live.length > _windowRows,
                          child: ListView.builder(
                            controller: _listScroll,
                            padding: EdgeInsets.zero,
                            itemCount: live.length,
                            itemBuilder: (BuildContext context, int index) {
                              return _BoardRow(
                                item: live[index],
                                personRepository: widget.personRepository,
                                matchRepository: widget.matchRepository,
                                onPairDismissed: () => setState(() {}),
                              );
                            },
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              homeHorizontalInset(context),
              4,
              homeHorizontalInset(context),
              0,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => BoardAddSheet.show(context),
                style: TextButton.styleFrom(
                  foregroundColor: dark
                      ? AppColors.secondaryDarkDm
                      : AppColors.secondaryInk,
                  visualDensity: VisualDensity.compact,
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('הוספה ללוח'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two add cards as a pinned header: a strip of the page's own paper,
/// so the rows scrolling under it disappear behind it rather than through it.
class _PinnedAddCards extends SliverPersistentHeaderDelegate {
  _PinnedAddCards({
    required this.height,
    required this.inset,
    required this.background,
    required this.child,
  });

  final double height;
  final double inset;
  final Color background;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Filled to the promised extent whatever the child measures, so the
    // sliver's paint and layout extents can never disagree.
    return SizedBox.expand(
      child: ColoredBox(
        color: background,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            inset,
            _HomeScreenState._blockGap,
            inset,
            10,
          ),
          child: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedAddCards oldDelegate) => true;
}

/// One row of the board: a person or a proposal (an [entry]), or a pair the
/// database suggests ([pair]).
class _BoardItem {
  const _BoardItem.entry(
    HomeBoardEntry this.entry, {
    this.pinned = false,
    this.hint,
    this.reminder = false,
    this.suggested = false,
  }) : pair = null;

  const _BoardItem.pair(NewIdeaSuggestion this.pair)
    : entry = null,
      pinned = false,
      hint = null,
      reminder = false,
      suggested = true;

  final HomeBoardEntry? entry;
  final NewIdeaSuggestion? pair;

  /// Drawn with a small pin beside the name.
  final bool pinned;

  /// What the row says when the matchmaker has written nothing on it.
  final String? hint;

  /// On the board because a reminder came due.
  final bool reminder;

  /// Offered by the app rather than put there by the matchmaker.
  final bool suggested;
}

/// One item on the board, drawn as the app draws a row.
///
/// A person carries one accent bar on the reading-start edge, in their own
/// gender's colour — exactly the row המאגר שלי draws. A proposal, or a pair the
/// database suggests, carries two, one on each edge, exactly as רעיונות שלי
/// draws a couple.
///
/// **One small mark beside the name says why the row is there**: a pin for
/// what was pinned, a bell for a reminder that came due, a spark for what the
/// app suggests. An open proposal carries none — it is the board's default.
class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.item,
    required this.personRepository,
    required this.matchRepository,
    required this.onPairDismissed,
  });

  final _BoardItem item;
  final PersonRepository personRepository;
  final MatchRepository matchRepository;

  /// A suggested pair was turned down; the board deals again.
  final VoidCallback onPairDismissed;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final IconData? mark = item.pinned
        ? Icons.push_pin
        : item.reminder
        ? Icons.notifications_active_outlined
        : item.suggested
        ? Icons.auto_awesome_outlined
        : null;

    final NewIdeaSuggestion? pair = item.pair;
    if (pair != null) {
      final String why = pair.reasons.isEmpty
          ? 'רעיון שהמאגר מציע לך'
          : 'רעיון מהמאגר · ${pair.reasons.join(' · ')}';
      return _row(
        context,
        leading: HomeCardCoupleAvatars(
          personA: pair.female,
          personB: pair.male,
          radius: 16,
        ),
        title: '${_firstName(pair.female)} & ${_firstName(pair.male)}',
        subtitle: why,
        mark: mark,
        startAccent: AppColors.genderAccent(Gender.female, dark: dark),
        endAccent: AppColors.genderAccent(Gender.male, dark: dark),
        onTap: () => _considerPair(context, pair),
        menu: _SuggestedPairMenu(
          onOpen: () => _considerPair(context, pair),
          onDismiss: () async {
            await SuggestionDismissals.dismiss(pair.male.id, pair.female.id);
            onPairDismissed();
          },
        ),
      );
    }

    final HomeBoardEntry entry = item.entry!;
    final String? note = HomeBoardStore.instance
        .noteFor(entry.kind, entry.targetId)
        ?.trim();
    final bool hasNote = note != null && note.isNotEmpty;
    final Widget menu = BoardItemMenuButton(
      kind: entry.kind,
      targetId: entry.targetId,
    );
    // A long press opens the same menu the "⋯" does — it used to pin or
    // unpin on the spot, which was one surprise too many for a gesture that
    // lands by accident.
    void openMenu(BuildContext anchor) =>
        HomeBoardActions.showItemMenu(anchor, entry.kind, entry.targetId);

    if (entry.kind == HomeItemKind.person) {
      final Person person = personRepository.getById(entry.targetId)!;
      return _row(
        context,
        leading: HomeCardAvatar(person: person, radius: 20),
        title: person.fullName.trim(),
        subtitle: hasNote ? note : item.hint,
        mark: mark,
        startAccent: AppColors.genderAccent(person.gender, dark: dark),
        // A friend the app suggests thinking about opens the question that
        // page asks — who they could go with. Everyone else opens their card.
        onTap: item.suggested
            ? () => openSuggestionsFor(context, person.id)
            : () => context.push('/people/${person.id}'),
        onLongPress: openMenu,
        menu: menu,
      );
    }

    final MatchIdea match = matchRepository.getById(entry.targetId)!;
    final Person? personA = personRepository.getById(match.personAId);
    final Person? personB = personRepository.getById(match.personBId);
    // Which of the two is the boy decides which name the step names, and the
    // proposal itself does not promise an order — the same normalisation the
    // ideas page does before it draws a card.
    final bool swap =
        personA?.gender == Gender.female || personB?.gender == Gender.male;
    final Person? male = swap ? personB : personA;
    final Person? female = swap ? personA : personB;
    final MatchNextStep? step = MatchStages.nextStep(match);

    return _row(
      context,
      leading: HomeCardCoupleAvatars(
        personA: personA,
        personB: personB,
        radius: 16,
      ),
      title: '${_firstName(personA)} & ${_firstName(personB)}',
      // What the matchmaker wrote wins the line, then why the row is here,
      // then the step the app worked out.
      subtitle: hasNote
          ? note
          : item.hint ??
                (step == null
                    ? null
                    // Already reads "השלב הבא: …" — see [MatchStages.shortLabel].
                    : MatchStages.shortLabel(step, male: male, female: female)),
      mark: mark,
      // Women lead in RTL, which is the side רעיונות שלי puts them on too.
      startAccent: AppColors.genderAccent(Gender.female, dark: dark),
      endAccent: AppColors.genderAccent(Gender.male, dark: dark),
      onTap: () => context.push('/matches/${match.id}'),
      onLongPress: openMenu,
      menu: menu,
    );
  }

  /// The two cards facing each other, and a proposal if the matchmaker agrees
  /// — the same route "רעיונות שהמאגר מציע לך" takes.
  Future<void> _considerPair(
    BuildContext context,
    NewIdeaSuggestion pair,
  ) async {
    final bool? open = await openMatchComparison(
      context,
      source: pair.male,
      candidate: pair.female,
    );
    if (open != true || !context.mounted) {
      return;
    }
    final MatchIdea? created = await matchRepository.create(
      pair.male.id,
      pair.female.id,
    );
    if (created == null || !context.mounted) {
      return;
    }
    await MatchQuickActions.promote(
      context,
      created,
      female: pair.female,
      male: pair.male,
    );
  }

  Widget _row(
    BuildContext context, {
    required Widget leading,
    required String title,
    required Color startAccent,
    required VoidCallback onTap,
    required Widget menu,
    ValueChanged<BuildContext>? onLongPress,
    Color? endAccent,
    String? subtitle,
    IconData? mark,
  }) {
    return BoardRow(
      leading: leading,
      title: title,
      startAccent: startAccent,
      onTap: onTap,
      menu: menu,
      onLongPress: onLongPress,
      endAccent: endAccent,
      subtitle: subtitle,
      mark: mark,
    );
  }
}

/// A pair the database suggests is not a record yet, so there is nothing to
/// remind about, write on or pin until it is one. Its menu offers the two
/// answers the suggestion itself asks for.
class _SuggestedPairMenu extends StatelessWidget {
  const _SuggestedPairMenu({required this.onOpen, required this.onDismiss});

  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'פעולות',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 190),
      icon: const Icon(Icons.more_horiz, size: 20),
      iconSize: 20,
      onSelected: (String value) {
        switch (value) {
          case 'open':
            onOpen();
          case 'dismiss':
            onDismiss();
        }
      },
      itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'open', child: Text('פתיחת רעיון')),
        PopupMenuItem<String>(value: 'dismiss', child: Text('לא מתאים')),
      ],
    );
  }
}

String _firstName(Person? person) {
  if (person == null) {
    return '—';
  }
  final String first = person.firstName.trim();
  return first.isNotEmpty ? first : person.fullName.trim();
}
