import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/dialogs/app_menu.dart';
import 'package:shadchan/dialogs/board_add_sheet.dart';
import 'package:shadchan/dialogs/home_board_actions.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/profile_screen.dart';
import 'package:shadchan/screens/think_screen.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/services/tips_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_counts.dart';
import 'package:shadchan/utils/community_prompt_gate.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/home_next_actions.dart';
import 'package:shadchan/utils/home_open_ideas.dart';
import 'package:shadchan/utils/home_stage.dart';
import 'package:shadchan/utils/matchmaker_tips.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/reminder_alerts.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/home_activity_block.dart';
import 'package:shadchan/widgets/home_community_link.dart';
import 'package:shadchan/widgets/home_blocks.dart';
import 'package:shadchan/widgets/home_engagement_card.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/home_stage_panels.dart';
import 'package:shadchan/widgets/person_list_card.dart';
import 'package:shadchan/widgets/reminders_bell_button.dart';

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
  bool _searchVisible = false;

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
    _searchVisible = widget.initialSearch.trim().isNotEmpty;
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
        needsLeaderboardConsent: context
            .read<CommunityProvider>()
            .needsLeaderboardConsent,
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
    final UserProfileProvider profile = context.watch<UserProfileProvider>();

    return Scaffold(
      appBar: _searchVisible
          ? _buildSearchAppBar(theme)
          : _buildGreetingAppBar(theme, profile),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // The board and the activity trail are app-wide singletons rather
            // than injected providers — the repositories write to them when a
            // record is deleted — so the page listens to them directly.
            ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[
                HomeBoardStore.instance,
                RecentActivityStore.instance,
              ]),
              builder: (BuildContext context, _) => _buildHome(),
            ),
            if (_searchVisible) _buildSearchPanel(theme, personRepository),
          ],
        ),
      ),
    );
  }

  // --- AppBars ------------------------------------------------------------

  AppBar _buildGreetingAppBar(ThemeData theme, UserProfileProvider profile) {
    final Gender? gender = profile.gender;
    // The first name and nothing else. A greeting is how someone is spoken to,
    // not how they are filed — "בוקר טוב, רבקה כהן־שטרן" is a form letter, and
    // a surname in the bar also crowds out the reminders and search icons on a
    // narrow phone.
    final String name = profile.firstName ?? '{שדכן|שדכנית}'.forGender(gender);
    final TimeOfDay now = TimeOfDay.fromDateTime(DateTime.now());

    return AppBar(
      titleSpacing: 16,
      centerTitle: false,
      // The photo is the way into the matchmaker's own page, which is also
      // where every setting lives — so the bar carries no gear.
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // First child sits at the start edge, which in RTL is the right.
          UserProfileAvatar(
            photoPath: profile.photoPath,
            gender: gender,
            name: profile.name,
            radius: 17,
            showEditBadge: profile.photoPath == null,
            onTap: () => context.push('/profile'),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '${_timeOfDayGreeting(now)}, $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        // The same bell, in the same slot, as המאגר שלי and רעיונות.
        const RemindersBellButton(),
        IconButton(
          tooltip: 'חיפוש',
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searchVisible = true),
        ),
        // Last in the row, which in RTL is the far left — where a phone's
        // overflow menu is looked for. Everything on it also lives in the
        // settings; this is the short way to it, and the only place in the app
        // where "how do I get help" is answered without finding them first.
        const AppMenuButton(),
      ],
    );
  }

  AppBar _buildSearchAppBar(ThemeData theme) {
    final bool hasText = _searchController.text.trim().isNotEmpty;

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      // The field takes the whole banner between the two edges rather than a
      // fixed 260px centred inside the title slot. Centring inside that slot
      // never looked centred: the slot itself is off-centre, because the close
      // button in `actions` eats one end of the bar and nothing balances it at
      // the other. A field that simply spans the row has no centre to get
      // wrong, and it is as wide as the cards underneath it.
      title: Padding(
        padding: const EdgeInsetsDirectional.only(start: 12),
        child: SizedBox(
          height: 44,
          child: TextField(
            controller: _searchController,
            autofocus: true,
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surface,
              hintText: 'חיפוש במאגר שלך',
              prefixIcon: const Icon(Icons.search, size: 20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide.none,
              ),
              suffixIcon: hasText
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      tooltip: 'ניקוי',
                      onPressed: _searchController.clear,
                    )
                  : null,
            ),
          ),
        ),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'סגירת חיפוש',
          icon: const Icon(Icons.close),
          onPressed: _closeSearch,
        ),
      ],
    );
  }

  /// Leaves search entirely: the results, the bar, and the keyboard.
  void _closeSearch() {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() => _searchVisible = false);
  }

  // --- Home body ----------------------------------------------------------

  Widget _buildHome() {
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final Gender? userGender = context.watch<UserProfileProvider>().gender;
    final HomeBoardStore board = HomeBoardStore.instance;

    if (board.takeFocusRequest()) {
      _scheduleBoardFocus(force: true);
    }

    final List<MatchIdea> allMatches = matchRepository.getAll();
    final List<Person> allPeople = personRepository.getAll();
    // The month's figures are not computed here any more: the home screen shows
    // one encouraging line, and every number, chart and comparison lives on the
    // screen that line opens.
    final List<Person> visiblePeople = allPeople
        .where((Person p) => !p.hidden)
        .toList();

    final List<MatchIdea> datingMatches =
        allMatches
            .where((MatchIdea m) => m.status == MatchStatus.dating)
            .toList()
          ..sort(
            (MatchIdea a, MatchIdea b) => b.updatedAt.compareTo(a.updatedAt),
          );
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

    // What the app itself thinks is most worth doing, ranked. Deliberately not
    // the board, and deliberately not chronological.
    final List<HomeNextAction> nextActions = HomeNextActions.build(
      people: visiblePeople,
      matches: allMatches,
      personById: personRepository.getById,
      personReminder: PersonReminders.forPerson,
    );

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
    // usefulness. Thinking about a shidduch and the pairs the database found
    // come first: they are the matchmaking itself, and the previous version
    // buried them under the two add buttons, where the eye had already left the
    // top of the screen by the time it reached them. The two ways to grow the
    // database follow, still large and still unmissable. Then what was parked
    // or is in flight, then what the app recommends, and only at the end what
    // has been achieved.
    //
    // A block with nothing in it is not drawn at all rather than shown as an
    // empty box — an empty screen teaches that the app is empty.
    return CustomScrollView(
      controller: _homeScrollController,
      slivers: <Widget>[
        // A brand-new matchmaker lands on the real home screen with one
        // welcoming card on it, not on a wizard that has to be got through.
        if (friends == 0)
          block(
            HomeWelcomeCard(onAddPeople: () => AddPeopleDialog.show(context)),
          ),

        // 1. The invitation to think. A banner and nothing else: no faces, no
        // names, no count — the people live on the page it opens.
        if (friends >= 3)
          block(HomeThinkBanner(onTap: () => ThinkScreen.open(context))),

        // 2. The pairs the database worked out on its own. Held back until the
        // database is big enough to keep producing them — below fifty friends
        // the well runs dry and the block becomes a promise the app cannot
        // keep, so the screen goes on pushing towards growth instead.
        if (friends > HomeConfig.databaseIdeasMinFriends)
          block(HomeHeroBand(onShowIdeas: () => context.push('/ideas/new'))),

        // 3. The two entry actions — still the largest, loudest thing on the
        // page, because everything else on it is only possible once they have
        // been used.
        block(
          HomeActionCards(
            onAddPeople: () => AddPeopleDialog.show(context),
            onAddIdea: () => context.push('/matches/add'),
            emphasiseAddPeople: stage.leadsWithGrowth,
          ),
        ),

        // 4. The personal target: how far the database is from ten friends,
        // then twenty-five, then fifty, then a hundred.
        //
        // It has its own slot rather than sharing the encouragement slot below,
        // which is how it came to be almost never drawn — the first-idea nudge
        // and the import offer both outranked it, so the one block on the page
        // that shows the matchmaker their own progress was the one that lost
        // every time. It stops entirely at a hundred friends, where a target is
        // no longer the useful thing to say.
        if (friends > 0 && stage.showsTarget)
          block(HomeMilestoneCard(milestone: milestone)),

        // 5. Exactly one encouragement card, never a stack of them. The
        // first-idea nudge and the bulk-import offer used to be able to appear
        // together, which put two differently shaped boxes between the add
        // buttons and the actual work.
        if (nudge != null) block(nudge),

        // 5. הלוח שלי — what was pinned by hand, plus whatever asked to be
        // remembered today. Absent entirely when there is nothing on it.
        _BoardSection(
          focusKey: _boardSectionKey,
          entries: board.entries,
          personRepository: personRepository,
          matchRepository: matchRepository,
        ),

        // 6. רעיונות פתוחים — every proposal that is open right now, with the
        // ones asking for something today at the head of the row.
        _OpenIdeasSection(ideas: openIdeas, personRepository: personRepository),

        // 7. The emotional anchor, and the only block on the page wearing
        // colour. Drawn only while there is somebody to celebrate.
        _DatingSection(
          matches: datingMatches.take(HomeConfig.datingCouplesInRow).toList(),
          personRepository: personRepository,
        ),

        // 8. What the app recommends, mixed by kind and scrolled sideways.
        if (nextActions.isNotEmpty)
          SliverToBoxAdapter(
            child: HomeNextActionsRow(
              actions: nextActions,
              onOpen: (HomeNextAction action) => _openAction(action),
            ),
          ),

        // 9. What has been done — the matchmaker's own score beside the
        // community's, in one window at a time. Two numbers and a switch;
        // the breakdown, the chart and the leaderboard are all one tap away on
        // a screen somebody opened *to look at numbers*.
        block(HomeActivityBlock(onOpen: () => context.push('/activity'))),

        // Somebody else's good news, for one launch. It draws nothing at all
        // when there is none, which is nearly always.
        block(const HomeEngagementCard()),

        // 10. The community's tip.
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

  /// Opens whatever one of "הפעולות הבאות שלך" is about.
  ///
  /// Most cards carry a record and open it. The two habit prompts — a week with
  /// no friend added, a week with no idea — carry nothing, so they open the
  /// flow that answers them instead. That is the whole reason they are on the
  /// row: an action the app names has to be doable from where it is named.
  void _openAction(HomeNextAction action) {
    if (action.person != null) {
      context.push('/people/${action.person!.id}');
      return;
    }
    if (action.match != null) {
      context.push('/matches/${action.match!.id}');
      return;
    }
    switch (action.kind) {
      case HomeActionKind.addFriendNudge:
        AddPeopleDialog.show(context);
      case HomeActionKind.newIdeaNudge:
        context.push('/matches/add');
      case HomeActionKind.reminderDue:
      case HomeActionKind.datingCheckIn:
      case HomeActionKind.staleIdea:
      case HomeActionKind.missingDetails:
      case HomeActionKind.noIdeas:
      case HomeActionKind.staleCard:
        break;
    }
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
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Person> people =
        repository.getAll().where((Person p) => !p.hidden).where((Person p) {
          return p.fullName.toLowerCase().contains(query) ||
              (p.phone ?? '').contains(query);
        }).toList()..sort(
          (Person a, Person b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
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
                child: people.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        child: Text(
                          'לא נמצאו תוצאות',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        shrinkWrap: true,
                        itemCount: people.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Person person = people[index];
                          return PersonListCard(
                            person: person,
                            heroEnabled: false,
                            onTap: () => context.push('/people/${person.id}'),
                            onToggleFavorite: () =>
                                repository.toggleFavorite(person.id),
                            onOpenWhatsApp: () => _openWhatsApp(person),
                          );
                        },
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('לא הצלחנו לפתוח את וואטסאפ')),
        );
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

/// The people and proposals the matchmaker parked to come back to — plus
/// whatever asked to be remembered today.
///
/// Two sources, one surface. A note pinned by hand and a reminder whose date has
/// arrived are the same thing from where the matchmaker is standing: something
/// they told the app to put back in front of them. The reminders lead, because
/// they are the ones with a date attached.
///
/// Always exactly one row, however many notes there are.
///
/// **It folds, and it remembers.** The board is an optional tool: some
/// matchmakers pin to it constantly and some never open it, and a permanently
/// visible empty corkboard on the home screen of the second group is a block
/// they scroll past every day. So an empty board is one compact line with an
/// arrow, a board with something on it opens by default, and whichever way the
/// matchmaker last left it is how they find it next time. The one thing that
/// overrides their choice is the first item landing on an empty board — being
/// shown what was just added is the point of adding it.
class _BoardSection extends StatefulWidget {
  const _BoardSection({
    required this.focusKey,
    required this.entries,
    required this.personRepository,
    required this.matchRepository,
  });

  final Key focusKey;
  final List<HomeBoardEntry> entries;
  final PersonRepository personRepository;
  final MatchRepository matchRepository;

  @override
  State<_BoardSection> createState() => _BoardSectionState();
}

class _BoardSectionState extends State<_BoardSection> {
  /// Where the matchmaker's own open/closed choice is kept. Absent means they
  /// have never touched it, which is not the same as "closed".
  static const String _foldKey = 'home.boardExpanded';

  bool? _choice;

  /// How many notes were on the board last build, so the empty → not-empty
  /// moment can be spotted. -1 is "not measured yet".
  int _lastLiveCount = -1;

  @override
  void initState() {
    super.initState();
    final Object? raw = Hive.isBoxOpen('settings')
        ? Hive.box<dynamic>('settings').get(_foldKey)
        : null;
    _choice = switch (raw) {
      true || 'true' => true,
      false || 'false' => false,
      _ => null,
    };
  }

  void _setChoice(bool expanded) {
    setState(() => _choice = expanded);
    persistHomeSetting(_foldKey, expanded.toString());
  }

  /// The pinned entries plus the due reminders, without repeating an item that
  /// is both.
  List<HomeBoardEntry> _live() {
    // A pinned record that has since been deleted simply drops out.
    final List<HomeBoardEntry> pinned = widget.entries.where((
      HomeBoardEntry entry,
    ) {
      return entry.kind == HomeItemKind.person
          ? widget.personRepository.getById(entry.targetId) != null
          : widget.matchRepository.getById(entry.targetId) != null;
    }).toList();

    final Set<String> seen = <String>{
      for (final HomeBoardEntry entry in pinned)
        '${entry.kind.name}:${entry.targetId}',
    };
    final List<HomeBoardEntry> due = <HomeBoardEntry>[];

    void addDue(HomeItemKind kind, String id, DateTime at, String? note) {
      if (!seen.add('${kind.name}:$id')) {
        return;
      }
      due.add(
        HomeBoardEntry(
          kind: kind,
          targetId: id,
          addedAt: at,
          note: (note ?? '').trim().isEmpty ? 'הגיע מועד התזכורת' : note,
        ),
      );
    }

    PersonReminders.all().forEach((String personId, DateTime at) {
      if (at.isAfter(DateTime.now()) ||
          widget.personRepository.getById(personId) == null) {
        return;
      }
      addDue(
        HomeItemKind.person,
        personId,
        at,
        PersonReminders.noteFor(personId),
      );
    });
    for (final MatchIdea match in widget.matchRepository.getAll()) {
      final DateTime? at = match.reminderDate;
      if (at == null || at.isAfter(DateTime.now())) {
        continue;
      }
      addDue(HomeItemKind.idea, match.id, at, match.reminderNote);
    }

    due.sort(
      (HomeBoardEntry a, HomeBoardEntry b) => a.addedAt.compareTo(b.addedAt),
    );
    return <HomeBoardEntry>[...due, ...pinned];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<HomeBoardEntry> live = _live();
    // The board is drawn from the first friend on, empty or not — unlike every
    // other block on this page, which is hidden when it has nothing in it. It
    // is the one area the matchmaker fills *by hand*, and a surface that only
    // appears once something is already on it can never be the place you go to
    // put the first thing there.
    if (live.isEmpty && widget.personRepository.databaseCount == 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    // Something has just landed on a board that was empty. Whatever the
    // matchmaker last chose, they are shown what they added — and the choice is
    // updated, so it stays open rather than snapping shut on the next build.
    if (_lastLiveCount == 0 && live.isNotEmpty && _choice == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _setChoice(true);
        }
      });
    }
    _lastLiveCount = live.length;

    // The *default* follows the content: an empty board is folded, because the
    // cork, its frame and its "הלוח ריק" line take a third of a phone screen to
    // say that there is nothing there. An explicit choice always wins over it —
    // including opening the empty board, which is how the first note gets
    // pinned in the first place.
    final bool expanded = _choice ?? live.isNotEmpty;

    return SliverToBoxAdapter(
      child: Column(
        key: widget.focusKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          HomeSectionHeader(
            title: 'הלוח שלי',
            subtitle: expanded ? 'אנשים או רעיונות שחשוב לי לזכור' : null,
            expanded: expanded,
            onToggle: () => _setChoice(!expanded),
          ),
          if (!expanded)
            const SizedBox(height: 4)
          else ...<Widget>[
            HomeNoteBoard(
              child: live.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'הלוח ריק — אפשר להצמיד אליו חבר או רעיון',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    )
                  // The end padding is smaller than a note, so the next one always
                  // peeks in from the edge — which is what says the row scrolls,
                  // without an arrow and without a second line of notes.
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      // The notes are exactly as tall as this viewport, and each
                      // one is drawn slightly rotated with a shadow under it — so
                      // a viewport that clipped to its own bounds would shave the
                      // low corner and the shadow off every note. The board's own
                      // `ClipRRect` is the real edge; between it and here there is
                      // only the cork's vertical padding, which is exactly the
                      // room those corners need.
                      clipBehavior: Clip.none,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding: EdgeInsetsDirectional.fromSTEB(
                        homeIsNarrow(context) ? 10 : 12,
                        0,
                        28,
                        0,
                      ),
                      itemCount: live.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(width: homeCardGap(context)),
                      itemBuilder: (BuildContext context, int index) =>
                          _BoardCard(
                            entry: live[index],
                            personRepository: widget.personRepository,
                            matchRepository: widget.matchRepository,
                          ),
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                homeHorizontalInset(context),
                8,
                homeHorizontalInset(context),
                0,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => BoardAddSheet.show(context),
                  style: TextButton.styleFrom(
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
        ],
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.entry,
    required this.personRepository,
    required this.matchRepository,
  });

  final HomeBoardEntry entry;
  final PersonRepository personRepository;
  final MatchRepository matchRepository;

  @override
  Widget build(BuildContext context) {
    if (entry.kind == HomeItemKind.person) {
      final Person person = personRepository.getById(entry.targetId)!;
      return _card(
        context,
        leading: HomeCardAvatar(person: person),
        title: person.fullName.trim(),
        onTap: () => context.push('/people/${person.id}'),
      );
    }

    final MatchIdea match = matchRepository.getById(entry.targetId)!;
    final Person? personA = personRepository.getById(match.personAId);
    final Person? personB = personRepository.getById(match.personBId);
    return _card(
      context,
      leading: HomeCardCoupleAvatars(personA: personA, personB: personB),
      title: '${_firstName(personA)} & ${_firstName(personB)}',
      onTap: () => context.push('/matches/${match.id}'),
    );
  }

  Widget _card(
    BuildContext context, {
    required Widget leading,
    required String title,
    required VoidCallback onTap,
  }) {
    return HomeBoardNote(
      tintSeed: '${entry.kind.name}:${entry.targetId}',
      leading: leading,
      title: title,
      subtitle: entry.note,
      onTap: onTap,
      actions: _BoardCardMenu(kind: entry.kind, targetId: entry.targetId),
    );
  }
}

/// The note's own options, opened from the button along its bottom edge. It is
/// only ever a closed button at rest, so the home screen stays free of open
/// menus.
///
/// A note that is on the board because its reminder came due is not pinned, so
/// it is offered the pin rather than "הסרה מהלוח" — removing it from a board it
/// was never put on would have nothing to remove.
class _BoardCardMenu extends StatelessWidget {
  const _BoardCardMenu({required this.kind, required this.targetId});

  final HomeItemKind kind;
  final String targetId;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'פעולות',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 190),
      // A `child` rather than an `icon`: the icon form is an IconButton, whose
      // fixed tap target does not fit the note's bottom edge.
      child: const HomeNoteActionsButton(),
      onSelected: (String value) async {
        switch (value) {
          case 'note':
            await HomeBoardActions.editNote(context, kind, targetId);
          case 'reminder':
            await HomeBoardActions.editReminder(context, kind, targetId);
          case 'pin':
            HomeBoardStore.instance.add(kind, targetId);
          case 'remove':
            HomeBoardActions.remove(context, kind, targetId);
        }
      },
      itemBuilder: (BuildContext context) {
        final HomeBoardEntry? pinned = HomeBoardStore.instance.entryFor(
          kind,
          targetId,
        );
        final bool hasNote = (pinned?.note ?? '').isNotEmpty;
        return <PopupMenuEntry<String>>[
          if (pinned != null)
            PopupMenuItem<String>(
              value: 'note',
              child: Text(hasNote ? 'עריכת הערה' : 'הוספת הערה'),
            ),
          PopupMenuItem<String>(
            value: 'reminder',
            child: Text(
              _hasReminder(context) ? 'עריכת תזכורת' : 'הוספת תזכורת',
            ),
          ),
          const PopupMenuDivider(),
          if (pinned == null)
            const PopupMenuItem<String>(value: 'pin', child: Text('הצמדה ללוח'))
          else
            const PopupMenuItem<String>(
              value: 'remove',
              child: Text('הסרה מהלוח'),
            ),
        ];
      },
    );
  }

  bool _hasReminder(BuildContext context) {
    if (kind == HomeItemKind.person) {
      return context.read<PersonRepository>().personReminderFor(targetId) !=
          null;
    }
    return context.read<MatchRepository>().getById(targetId)?.reminderDate !=
        null;
  }
}

// --- רעיונות פתוחים ---------------------------------------------------------

/// Every proposal that is open right now, in one horizontal row.
///
/// The row used to hold only the proposals with a reason to be looked at again
/// today — a due reminder, or an idea that had not moved in weeks — which meant
/// that on most days the one place on the home screen that answers "what is
/// open?" was not drawn at all. It is a fixed part of the screen now, and the
/// urgency lives in the *order*: due reminders and reopened proposals lead,
/// then the rest, newest first.
class _OpenIdeasSection extends StatelessWidget {
  const _OpenIdeasSection({
    required this.ideas,
    required this.personRepository,
  });

  final List<HomeOpenIdea> ideas;
  final PersonRepository personRepository;

  @override
  Widget build(BuildContext context) {
    final List<HomeOpenIdea> openIdeas = ideas;
    if (openIdeas.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    // The open ideas inherit the wave: free circles on soft water rather than
    // one more row of white rectangles. The page already carries a board, a
    // banner, three action cards and a tip — another rounded box would have
    // been the fifth variation on the same shape.
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          HomeSectionHeader(
            title: 'רעיונות פתוחים',
            onSeeAll: () => context.go('/matches'),
          ),
          HomeWaveBackground(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: homeHorizontalInset(context),
                vertical: HomeConfig.suggestionRowPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (
                    int index = 0;
                    index < openIdeas.length;
                    index++
                  ) ...<Widget>[
                    if (index > 0) const SizedBox(width: 2),
                    () {
                      final HomeOpenIdea idea = openIdeas[index];
                      final Person? a = personRepository.getById(
                        idea.match.personAId,
                      );
                      final Person? b = personRepository.getById(
                        idea.match.personBId,
                      );
                      return HomeOpenIdeaBubble(
                        personA: a,
                        personB: b,
                        title: '${_firstName(a)} & ${_firstName(b)}',
                        status: idea.match.status.displayName,
                        statusColor: AppColors.statusColor(
                          idea.match.status.name,
                        ),
                        alerting: idea.alerting,
                        onTap: () => context.push('/matches/${idea.match.id}'),
                      );
                    }(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- זוגות שיוצאים ----------------------------------------------------------

/// Pure encouragement, not a work queue: it exists only while there is someone
/// to celebrate, and it is the one block on the page that wears colour.
class _DatingSection extends StatelessWidget {
  const _DatingSection({required this.matches, required this.personRepository});

  final List<MatchIdea> matches;
  final PersonRepository personRepository;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final List<HomeDatingCouple> couples = <HomeDatingCouple>[
      for (final MatchIdea match in matches)
        () {
          final Person? personA = personRepository.getById(match.personAId);
          final Person? personB = personRepository.getById(match.personBId);
          return HomeDatingCouple(
            matchId: match.id,
            names: '${_firstName(personA)} & ${_firstName(personB)}',
            duration: AppDateUtils.elapsedLabel(match.updatedAt),
            personA: personA,
            personB: personB,
          );
        }(),
    ];

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        homeHorizontalInset(context),
        _HomeScreenState._blockGap,
        homeHorizontalInset(context),
        0,
      ),
      sliver: SliverToBoxAdapter(
        child: HomeDatingBanner(
          couples: couples,
          onOpen: (String matchId) => context.push('/matches/$matchId'),
        ),
      ),
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
