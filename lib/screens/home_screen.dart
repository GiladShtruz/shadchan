import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:shadchan/widgets/people_filters_sheet.dart';
import 'package:shadchan/widgets/add_fab.dart';
import 'package:shadchan/widgets/activity_figure_row.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/dialogs/app_menu.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/home_search_filter_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/services/tips_service.dart';
import 'package:shadchan/utils/app_colors.dart';
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
import 'package:shadchan/utils/matchmaker_tips.dart';
import 'package:shadchan/utils/reminder_alerts.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_activity_block.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/home_community_link.dart';
import 'package:shadchan/widgets/home_community_pulse.dart';
import 'package:shadchan/widgets/home_blocks.dart';
import 'package:shadchan/widgets/home_board.dart';
import 'package:shadchan/widgets/home_engagement_card.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/home_search_results.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/home_stage_panels.dart';
import 'package:shadchan/widgets/shadchan_app_bar.dart';
import 'package:shadchan/utils/app_navigation.dart';

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
          // The same "+" as המאגר שלי, in the same corner; here it asks which
          // of the two is meant.
          floatingActionButton: AddFab(
            tooltip: 'הוספה',
            onPressed: () => AddChoiceDialog.show(context),
          ),
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
          // The same filter as המאגר שלי. The search stays free text; with a
          // filter set it looks only through the cards that pass it.
          trailing: <Widget>[
            IconButton(
              tooltip: 'סינון',
              onPressed: _openSearchFilters,
              icon: Icon(
                _hasSearchFilters ? Icons.filter_list_alt : Icons.tune,
                color: _hasSearchFilters
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          ],
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
    setState(() => _filterPanelOpen = false);
  }

  /// The filter set from the search row — saved until it is cleared, so
  /// every search after it, on this visit or a later one, looks only through
  /// the cards that pass it.
  PeopleFilterState? _searchFilters = HomeSearchFilterStore.filters;

  /// Whether the filtered cards are listed while nothing is typed: right
  /// after the filter is set, until a tap beside the panel puts it away.
  bool _filterPanelOpen = false;

  bool get _hasSearchFilters =>
      _searchFilters != null && !_searchFilters!.isEmpty;

  Future<void> _openSearchFilters() async {
    final PeopleFilterState? result = await showPeopleFiltersSheet(
      context,
      repository: context.read<PersonRepository>(),
      initial: _searchFilters,
    );
    if (result == null || !mounted) {
      return;
    }
    HomeSearchFilterStore.filters = result;
    setState(() {
      _searchFilters = result.isEmpty ? null : result;
      _filterPanelOpen = !result.isEmpty;
    });
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
        HomeBoardSection(
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
        block(
          HomeActivityBlock(
            onOpen: () => AppNavigation.open(context, '/activity'),
          ),
        ),

        // 5 and 6. The community, live: what it did today, and the one target
        // it is working towards together this week. The only block on the page
        // that moves on its own, and the only one that is about other people —
        // which is why it sits directly under the numbers, where the page turns
        // from "your work" to "everybody's".
        block(
          HomeCommunityPulse(
            onOpen: () => AppNavigation.open(context, '/activity'),
          ),
        ),

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
    final TipsProvider tips = context.watch<TipsProvider>();
    final List<CommunityTip> community = tips.visibleCommunity;
    return <HomeTip>[
      for (final BuiltInTip tip in tips.builtInTips(_tipOrder))
        if (!tip.hidden) HomeTip(text: tip.text.forGender(gender)),
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
    final PeopleFilterState? filters = _hasSearchFilters
        ? _searchFilters
        : null;
    if (query.isEmpty && !(filters != null && _filterPanelOpen)) {
      return const SizedBox.shrink();
    }

    // The whole database, word by word — see [HomeSearch] — or, with a
    // filter set, only the cards that pass it. With nothing typed the
    // filtered cards themselves are the answer.
    final Iterable<Person> pool = filters == null
        ? repository.getAll()
        : repository.getAll().where(filters.matches);
    final HomeSearchResults results = query.isEmpty
        ? HomeSearchResults(
            people: pool.where((Person p) => !p.hidden).toList()
              ..sort(
                (Person a, Person b) => a.fullName.toLowerCase().compareTo(
                  b.fullName.toLowerCase(),
                ),
              ),
            content: const <ContentHit>[],
          )
        : HomeSearch.run(query, pool, notesFor: repository.getNotesForPerson);

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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (filters != null)
                      _SearchFilterLine(
                        count: query.isEmpty ? results.people.length : null,
                        onClear: () => setState(() {
                          HomeSearchFilterStore.filters = null;
                          _searchFilters = null;
                          _filterPanelOpen = false;
                        }),
                      ),
                    Flexible(
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
                                pushLeavingSearch(
                                  context,
                                  '/people/${person.id}',
                                );
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
                  ],
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

/// The line over the home search results while a filter is set: what is
/// being searched, and the way to stop.
class _SearchFilterLine extends StatelessWidget {
  const _SearchFilterLine({required this.count, required this.onClear});

  /// How many cards pass, when they are listed themselves.
  final int? count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 6, 0),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.filter_list_alt,
            size: 16,
            color: AppColors.muted(dark: dark),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              count == null
                  ? 'מחפש רק בכרטיסים שעומדים בסינון'
                  : '$count כרטיסים עומדים בסינון',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('ניקוי הסינון')),
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
