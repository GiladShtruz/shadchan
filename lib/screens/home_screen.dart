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
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/services/tips_service.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_counts.dart';
import 'package:shadchan/utils/community_prompt_gate.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/search_navigation.dart';
import 'package:shadchan/utils/home_open_ideas.dart';
import 'package:shadchan/utils/home_stage.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/utils/matchmaker_tips.dart';
import 'package:shadchan/utils/monthly_stats.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/reminder_alerts.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/community_widgets.dart';
import 'package:shadchan/widgets/home_activity_block.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/home_community_link.dart';
import 'package:shadchan/widgets/home_community_pulse.dart';
import 'package:shadchan/widgets/home_blocks.dart';
import 'package:shadchan/widgets/home_engagement_card.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/home_stage_panels.dart';
import 'package:shadchan/widgets/person_list_card.dart';
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
      actions: const <Widget>[
        // בית keeps its own overflow menu — the app itself, the community
        // group, the guide, the privacy policy. המאגר שלי and הרעיונות שלי
        // carry the shorter list of destinations instead. See
        // [AppMenuVariant].
        ShadchanTabActions(add: AddMenuButton(), menu: AppMenuVariant.home),
      ],
      bottom: ShadchanSearchBottom(
        child: ShadchanSearchField(
          controller: _searchController,
          hintText: 'חיפוש במאגר שלך',
          onCleared: _closeSearch,
        ),
      ),
    );
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
        // in the bar, with nothing drawn around it. The search row that used to
        // sit above it is in the banner now — see [_buildGreetingAppBar].
        block(
          HomeGreeting(
            greeting: _timeOfDayGreeting(
              TimeOfDay.fromDateTime(DateTime.now()),
            ),
            name: greetingName,
            line: '{בוא|בואי} ניצור היום חיבורים חדשים'.forGender(userGender),
          ),
          top: 8,
        ),

        // A brand-new matchmaker lands on the real home screen with one
        // welcoming card on it, not on a wizard that has to be got through.
        if (friends == 0)
          block(
            HomeWelcomeCard(onAddPeople: () => AddPeopleDialog.show(context)),
          ),

        // 2. The two entry actions — the largest, loudest thing on the page,
        // because everything else on it is only possible once they have been
        // used. Two equal cards; adding friends leads by colour, not by size.
        block(
          HomeActionCards(
            onAddPeople: () => AddPeopleDialog.show(context),
            onAddIdea: () => context.push('/matches/add'),
            emphasiseAddPeople: stage.leadsWithGrowth,
          ),
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
                child: people.isEmpty
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
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        shrinkWrap: true,
                        itemCount: people.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Person person = people[index];
                          return PersonListCard(
                            person: person,
                            heroEnabled: false,
                            onTap: () {
                              _closeSearch();
                              pushLeavingSearch(
                                context,
                                '/people/${person.id}',
                              );
                            },
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
/// Three sources, one board. **Every open proposal is on it by itself** — that
/// is what replaced "רעיונות פתוחים" as a row of its own further down the page:
/// the answer to "what is open?" and the answer to "what did I park?" were two
/// separate strips saying overlapping things, and the board is the one the
/// matchmaker already treats as their desk. To that are added the reminders
/// whose date has arrived, and whatever was pinned by hand.
///
/// The order is the order of urgency: a reminder that came due leads, then what
/// was pinned deliberately, then the rest of the open proposals.
///
/// **A proposal's note carries its next step**, in exactly the words the ideas
/// page uses for it — see [MatchStages.buttonLabel]. Nothing new decides what
/// that step is; the board reads the same stage the card does.
///
/// **A list, not a pinboard.** The cork surface with paper notes pinned to it
/// was the one thing on this page drawn in a language of its own: it scrolled
/// sideways while the page scrolled down, it could only ever show two items at
/// a time, and every item on it was a different shape from the same item in
/// המאגר שלי or רעיונות שלי. The rows here are the rows those screens use — one
/// accent bar down the edge of a person, one down each edge of a couple — so a
/// friend looks like themselves wherever the app draws them.
///
/// **Open unless it was closed.** The board opens by default, empty or not,
/// and folds only when the matchmaker folds it — that choice is kept and
/// nothing overrides it.
///
/// **Four figures head it**: the same all-time counts as "הנתונים שלך" on the
/// activity screen, small, each opening the records behind it.
class _BoardSection extends StatefulWidget {
  const _BoardSection({
    required this.focusKey,
    required this.entries,
    required this.openIdeas,
    required this.personRepository,
    required this.matchRepository,
  });

  final Key focusKey;
  final List<HomeBoardEntry> entries;

  /// Every proposal that is open right now, already ranked — the ones asking
  /// for something today first. See [HomeOpenIdeas].
  final List<HomeOpenIdea> openIdeas;

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

  /// How many rows the section shows before "עוד N". Long enough that a
  /// working matchmaker sees their whole day without opening anything, short
  /// enough that a database with forty open proposals does not bury every
  /// other block on the page under them.
  static const int _collapsedRows = 5;

  bool _showAll = false;

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

  /// The pinned entries, the due reminders and every open proposal, without
  /// repeating an item that is more than one of those.
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

    // And every open proposal, in the order the row already ranked them —
    // whatever is not already on the board because it was pinned or because its
    // reminder came due. They carry no note of their own: what a proposal has
    // to say for itself is its next step, and the card reads that live.
    final List<HomeBoardEntry> open = <HomeBoardEntry>[
      for (final HomeOpenIdea idea in widget.openIdeas)
        if (seen.add('${HomeItemKind.idea.name}:${idea.match.id}'))
          HomeBoardEntry(
            kind: HomeItemKind.idea,
            targetId: idea.match.id,
            addedAt: idea.match.updatedAt,
          ),
    ];

    return <HomeBoardEntry>[...due, ...pinned, ...open];
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

    // Open until the matchmaker closes it, and then closed until they open it.
    final bool expanded = _choice ?? true;
    final List<HomeBoardEntry> shown = _showAll
        ? live
        : live.take(_collapsedRows).toList();
    final int hidden = live.length - shown.length;

    return SliverToBoxAdapter(
      child: Column(
        key: widget.focusKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          HomeSectionHeader(
            title: 'הלוח שלי',
            subtitle: expanded
                ? 'הרעיונות הפתוחים, התזכורות ומה שהצמדתי'
                : null,
            expanded: expanded,
            onToggle: () => _setChoice(!expanded),
          ),
          if (!expanded)
            const SizedBox(height: 4)
          else ...<Widget>[
            _BoardStats(
              people: widget.personRepository,
              matches: widget.matchRepository,
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: homeHorizontalInset(context),
              ),
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
                  : Column(
                      children: <Widget>[
                        for (final HomeBoardEntry entry in shown)
                          _BoardRow(
                            entry: entry,
                            personRepository: widget.personRepository,
                            matchRepository: widget.matchRepository,
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                homeHorizontalInset(context),
                4,
                homeHorizontalInset(context),
                0,
              ),
              child: Row(
                children: <Widget>[
                  TextButton.icon(
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
                  const Spacer(),
                  // The rest of the list opens in place. There is no screen
                  // behind this section to send anybody to — the board *is*
                  // the list — so a "הצגת הכל" that navigated would have
                  // nowhere to go.
                  if (hidden > 0)
                    TextButton(
                      onPressed: () => setState(() => _showAll = true),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: Text('עוד $hidden'),
                    )
                  else if (_showAll && live.length > _collapsedRows)
                    TextButton(
                      onPressed: () => setState(() => _showAll = false),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: const Text('הצגה מקוצרת'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "חברים", "רעיונות", "זוגות שיצאו", "חתונות" — all time, in a row of four
/// at the head of the section.
///
/// Counted by [ActivityStats.allTime], exactly as "הנתונים שלך" counts them,
/// and each opens the same all-time list that screen opens.
///
/// **One word each, and no picture.** They read "חברים שהוספת" and "רעיונות
/// שפתחת" once, which is a sentence about the matchmaker where a label was
/// wanted — and it was long enough to wrap, which is what made four short wide
/// tiles into four tall boxes. A figure over a noun is the whole of it; the
/// icon over each one was a third thing to look at in a tile the width of a
/// thumb.
class _BoardStats extends StatelessWidget {
  const _BoardStats({required this.people, required this.matches});

  final PersonRepository people;
  final MatchRepository matches;

  @override
  Widget build(BuildContext context) {
    final ActivityBreakdown all = ActivityStats.allTime(
      people: people.getAll(),
      matches: matches.getAll(),
      matchStatusEvents: matches.getAllStatusEvents(),
      excludedFromDating: DatingCountExclusions.all(),
    );
    final double inset = homeHorizontalInset(context);

    Widget tile(int value, String label, MonthlyStatMetric m) {
      return Expanded(
        child: _BoardStatTile(
          value: value,
          label: label,
          onTap: () => context.push('/stats/month/${m.name}?window=all'),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
      // Equal heights whichever label is the longest.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            tile(all.friends, 'חברים', MonthlyStatMetric.people),
            const SizedBox(width: 8),
            tile(all.ideas, 'רעיונות', MonthlyStatMetric.ideas),
            const SizedBox(width: 8),
            tile(all.couples, 'זוגות שיצאו', MonthlyStatMetric.dating),
            const SizedBox(width: 8),
            tile(all.engagements, 'חתונות', MonthlyStatMetric.weddings),
          ],
        ),
      ),
    );
  }
}

/// One figure: the number, the noun under it, and the page's one rule along
/// the foot.
///
/// **Brown on all four**, and not a colour per metric. A different accent per
/// tile turns a row of four into four unrelated things and invites the reader
/// to work out what each colour means, which is nothing — the four are one
/// set of figures about one database.
class _BoardStatTile extends StatelessWidget {
  const _BoardStatTile({
    required this.value,
    required this.label,
    required this.onTap,
  });

  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: AppColors.onSurface.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      // The rule is flush to the bottom edge; this clip is what rounds it.
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // The four tiles are stretched to one height by an `IntrinsicHeight`
        // above, so this column has to fill that height rather than sit at the
        // top of it — otherwise a tile whose label had to shrink ends up with
        // its rule floating a few pixels above the card's own foot, and the
        // four rules no longer line up.
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 9, 4, 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        CommunityFigure.format(value),
                        maxLines: 1,
                        // The one figure on the page drawn larger than the
                        // type scale: it is the thing being read, and at the
                        // page's title size four of them in a row disappear
                        // into the nouns under them.
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: HomeTypography.lead,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AccentUnderline(
              color: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// One item on the board, drawn as the app draws a row.
///
/// A person carries one accent bar on the reading-start edge, in their own
/// gender's colour — exactly the row המאגר שלי draws. A proposal carries two,
/// one on each edge, exactly as רעיונות שלי draws a couple. Nothing else about
/// the two rows differs, so the board reads as the same list as the rest of
/// the app rather than as a surface of its own.
class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.entry,
    required this.personRepository,
    required this.matchRepository,
  });

  final HomeBoardEntry entry;
  final PersonRepository personRepository;
  final MatchRepository matchRepository;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    if (entry.kind == HomeItemKind.person) {
      final Person person = personRepository.getById(entry.targetId)!;
      return _row(
        context,
        leading: HomeCardAvatar(person: person, radius: 20),
        title: person.fullName.trim(),
        subtitle: entry.note,
        startAccent: AppColors.genderAccent(person.gender, dark: dark),
        onTap: () => context.push('/people/${person.id}'),
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
    // The proposal's next step, decided by exactly what decides it on the
    // ideas page — [MatchStages] reads the same stage the card does — and said
    // in as few words as a row can hold.
    final MatchNextStep? step = MatchStages.nextStep(match);
    final String? note = entry.note?.trim();

    return _row(
      context,
      leading: HomeCardCoupleAvatars(
        personA: personA,
        personB: personB,
        radius: 16,
      ),
      title: '${_firstName(personA)} & ${_firstName(personB)}',
      // What the matchmaker wrote wins the line; the step the app worked out
      // fills it when they wrote nothing. Both on one row would be two
      // sentences competing in a space that holds one.
      subtitle: note != null && note.isNotEmpty
          ? note
          : step == null
          ? null
          // Already reads "השלב הבא: …" — see [MatchStages.shortLabel].
          : MatchStages.shortLabel(step, male: male, female: female),
      // Women lead in RTL, which is the side רעיונות שלי puts them on too.
      startAccent: AppColors.genderAccent(Gender.female, dark: dark),
      endAccent: AppColors.genderAccent(Gender.male, dark: dark),
      onTap: () => context.push('/matches/${match.id}'),
    );
  }

  Widget _row(
    BuildContext context, {
    required Widget leading,
    required String title,
    required Color startAccent,
    required VoidCallback onTap,
    Color? endAccent,
    String? subtitle,
  }) {
    final ThemeData theme = Theme.of(context);
    final String? sub = subtitle?.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                AccentStripe(color: startAccent, height: AccentBar.rowHeight),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 10),
                  child: leading,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (sub != null && sub.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _BoardRowMenu(kind: entry.kind, targetId: entry.targetId),
                if (endAccent != null) ...<Widget>[
                  const SizedBox(width: 4),
                  AccentStripe(
                    color: endAccent,
                    atStart: false,
                    height: AccentBar.rowHeight,
                  ),
                ] else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
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
class _BoardRowMenu extends StatelessWidget {
  const _BoardRowMenu({required this.kind, required this.targetId});

  final HomeItemKind kind;
  final String targetId;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'פעולות',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 190),
      icon: const Icon(Icons.more_horiz, size: 20),
      iconSize: 20,
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

String _firstName(Person? person) {
  if (person == null) {
    return '—';
  }
  final String first = person.firstName.trim();
  return first.isNotEmpty ? first : person.fullName.trim();
}
