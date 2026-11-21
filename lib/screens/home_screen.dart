import 'package:flutter/material.dart';
import 'package:shadchan/widgets/app_refresh.dart';
import 'package:shadchan/screens/personal_home_screen.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/app_menu.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/home_search_filter_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_counts.dart';
import 'package:shadchan/utils/community_prompt_gate.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/search_navigation.dart';
import 'package:shadchan/utils/home_open_ideas.dart';
import 'package:shadchan/utils/home_search.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/home_board.dart';
import 'package:shadchan/widgets/home_engagement_card.dart';
import 'package:shadchan/widgets/activity_figure_row.dart';
import 'package:shadchan/widgets/home_action_area.dart';
import 'package:shadchan/widgets/home_week_block.dart';
import 'package:shadchan/widgets/home_card_friends.dart';
import 'package:shadchan/widgets/home_partner_matchmakers.dart';
import 'package:shadchan/dialogs/card_photo_choice_dialog.dart';
import 'package:shadchan/widgets/home_my_matchmakers.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/widgets/add_fab.dart';
import 'package:shadchan/widgets/home_search_results.dart';
import 'package:shadchan/widgets/home_section.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _homeScrollController = ScrollController();
  final GlobalKey _boardSectionKey = GlobalKey();

  /// Bumped when the user comes back to the app after a while, which deals
  /// the friends with a card and the action list again.
  int _boardRefresh = 0;
  DateTime _pausedAt = DateTime.now();

  /// The single vertical gap between every block on the page.
  static const double _blockGap = 14;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialSearch;
    _searchController.addListener(() => setState(() {}));
    _scheduleBoardFocus();
    _scheduleCommunityPrompts();
    _schedulePhotoChoice();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    }
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {
        // Away for a while: a fresh deal. A glance at another app is not.
        if (DateTime.now().difference(_pausedAt) > const Duration(hours: 1)) {
          _boardRefresh++;
        }
      });
    }
  }

  /// Asked once per launch on this home too, not only on the personal one: a
  /// single who works in the matchmaker area may never open their own. An
  /// older card with more than four photos shows its matchmakers the first
  /// four until the owner chooses; nothing is deleted before that.
  static bool _photoChoiceAsked = false;

  void _schedulePhotoChoice() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _photoChoiceAsked) return;
      final PersonalCardProvider cards = context.read<PersonalCardProvider>();
      final Person? card = cards.card;
      if (card == null || cards.isDeleted || !cards.needsPhotoChoice) return;
      _photoChoiceAsked = true;
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
    WidgetsBinding.instance.removeObserver(this);
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
          // The same floating "+" as המאגר שלי and הרעיונות שלי, in the same
          // corner; here it asks which of the two is meant.
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
      // The logo opens the user's own profile.
      onTitleTap: () => context.go('/profile'),
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
    // Somebody who keeps a card (or is about to write one) sees it on this
    // same home — written or not, deleted or not.
    final bool hasOwnCard = userProfile.isSingle;
    context.watch<PersonalCardProvider>();
    final HomeBoardStore board = HomeBoardStore.instance;

    if (board.takeFocusRequest()) {
      _scheduleBoardFocus(force: true);
    }

    final List<HomeOpenIdea> openIdeas = boardOpenIdeas(
      matches: matchRepository,
      people: personRepository,
    );
    final int friends = personRepository.databaseCount;

    double inset() => homeHorizontalInset(context);
    // One gap between blocks, everywhere.
    SliverPadding block(Widget child, {double top = _blockGap}) {
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(inset(), top, inset(), 0),
        sliver: SliverToBoxAdapter(child: child),
      );
    }

    // **An action screen, not a dashboard.** In a few seconds somebody who
    // opens the app should see where they stand (the four squares), the two
    // things they can add (two large buttons, pinned under the search bar),
    // and what is worth moving forward ("מה השלב הבא שלך?" — a chat-list of
    // rows with hairlines between them, no card per row, then "הצג עוד").
    final String greetingName =
        userProfile.firstName ?? '{שדכן|שדכנית}'.forGender(userGender);

    return AppRefreshIndicator(
      scope: RefreshScope.records,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        controller: _homeScrollController,
        slivers: <Widget>[
          // 1. The greeting. A matchmaker who also keeps a card of their own
          // finds the way into it in the far corner of the same line.
          block(
            HomeGreeting(
              greeting: _timeOfDayGreeting(
                TimeOfDay.fromDateTime(DateTime.now()),
              ),
              name: greetingName,
              // No photo beside the greeting: the user's face is the profile
              // circle in the middle of the bottom bar.
              line: '{בוא|בואי} ניצור היום חיבורים חדשים'.forGender(userGender),
            ),
            top: 8,
          ),

          // 2. The four all-time figures, back in their squares — smaller and
          // closer together than they once were, each still a tap into its list.
          if (friends > 0)
            block(
              ActivityFigureRow(
                people: personRepository,
                matches: matchRepository,
                compact: true,
              ),
              top: 8,
            ),

          // 3. "הוספת חברים" | "הוספת רעיון" — the page's two main buttons.
          // Pinned: the greeting and the figures scroll away, the search bar
          // and these two stay at the top of the page.
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          HomeActionArea.pinnedSliver(context, inset: inset()),

          // 4. "הפעולה הבאה שלך" — the progress line, then what to do next,
          // five rows and "הצג עוד". First after the greeting: it is what the
          // page is opened for.
          block(const HomeNextStepTitle(), top: 22),
          block(const HomeWeeklyProgress(), top: 6),
          const SliverToBoxAdapter(child: SizedBox(height: 6)),
          HomeBoardSection(
            focusKey: _boardSectionKey,
            mode: HomeBoardMode.actions,
            entries: board.entries,
            openIdeas: openIdeas,
            personRepository: personRepository,
            matchRepository: matchRepository,
            refresh: _boardRefresh,
          ),

          // 5. "החברים שלך" — the friends this matchmaker thinks about — and
          // "שדכנים שותפים" — the matchmakers they think with.
          block(const HomeCardFriendsSection(), top: 22),
          block(const HomePartnerMatchmakers()),

          // 6. "השדכנים שלי" — only for somebody who keeps a card of their own:
          // the matchmakers among their friends, as one more row of faces, and
          // under it what is new around the card and the one step worth doing
          // for it. The card itself lives on the profile, not on a button here.
          if (hasOwnCard) ...<Widget>[
            block(const HomeMyMatchmakers()),
            block(const PersonalHomeBlock()),
          ],

          // 7. "הפעילות שלי" | "פעילות הקהילה" and the community's weekly
          // target under them.
          block(
            HomeWeekBlock(
              onOpen: () => AppNavigation.open(context, '/activity'),
            ),
          ),

          // Somebody else's good news, for one launch. It draws nothing at all
          // when there is none, which is nearly always.
          block(const HomeEngagementCard()),

          SliverToBoxAdapter(
            child: SizedBox(
              height:
                  MediaQuery.viewPaddingOf(context).bottom +
                  kBottomNavigationBarHeight +
                  16,
            ),
          ),
        ],
      ),
    );
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
