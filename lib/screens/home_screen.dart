import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/dialogs/home_board_actions.dart';
import 'package:shadchan/dialogs/reminders_panel.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/profile_screen.dart';
import 'package:shadchan/screens/think_screen.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/services/tips_service.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/app_colors.dart';
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
import 'package:shadchan/widgets/home_blocks.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/home_stage_panels.dart';
import 'package:shadchan/widgets/person_list_card.dart';

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

  /// Which window "הפעילות שלך" is showing. A screen-lifetime choice, not a
  /// stored setting: it is a question asked of the moment, not a preference.
  HomeActivityRange _activityRange = HomeActivityRange.week;

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
    final String name = profile.name ?? '{שדכן|שדכנית}'.forGender(gender);
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
        // Only ever the matchmaker's own reminders. A bell that is always there
        // with nothing behind it is an unanswered notification.
        if (_hasAnyReminder(context))
          IconButton(
            tooltip: 'תזכורות',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => RemindersPanel.show(context),
          ),
        IconButton(
          tooltip: 'חיפוש',
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searchVisible = true),
        ),
      ],
    );
  }

  /// True when the matchmaker has set a reminder of their own — on a person or
  /// on a proposal. Nothing else in the app creates one.
  bool _hasAnyReminder(BuildContext context) {
    if (PersonReminders.all().isNotEmpty) {
      return true;
    }
    return context.read<MatchRepository>().getAll().any(
      (MatchIdea match) => match.reminderDate != null,
    );
  }

  AppBar _buildSearchAppBar(ThemeData theme) {
    final bool hasText = _searchController.text.trim().isNotEmpty;

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 8,
      // Centered inside the banner, capped in width so it never sits under the
      // search icon that stays visible in the actions.
      title: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textAlign: TextAlign.center,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                hintText: 'חיפוש במאגר שלך',
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
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'סגירת חיפוש',
          icon: const Icon(Icons.search),
          onPressed: () {
            _searchController.clear();
            setState(() => _searchVisible = false);
          },
        ),
      ],
    );
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
      limit: HomeConfig.openIdeasInRow,
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

    final ActivityTotals totals = ActivityStats.totals(
      people: allPeople,
      matches: allMatches,
      matchStatusEvents: matchRepository.getAllStatusEvents(),
      events: personRepository.getAllEvents(),
    );

    double inset() => homeHorizontalInset(context);
    SliverPadding block(Widget child, {double top = 12}) {
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(inset(), top, inset(), 0),
        sliver: SliverToBoxAdapter(child: child),
      );
    }

    // The order of what follows *is* the design, and it is an order of
    // usefulness rather than of features: first the two things that grow the
    // database, then what the matchmaker parked or asked to be reminded of,
    // then a moment to think, then the work already in flight, then what the
    // app itself recommends, and only at the end what has been achieved.
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
            top: 14,
          ),

        // 2. The two entry actions. They stay at the top at every stage,
        // because everything below them is only possible once they have been
        // used.
        block(
          HomeActionCards(
            onAddPeople: () => AddPeopleDialog.show(context),
            onAddIdea: () => context.push('/matches/add'),
            emphasiseAddPeople: stage.leadsWithGrowth,
          ),
          top: friends == 0 ? 12 : 14,
        ),

        if (stage.showsTarget) block(HomeMilestoneCard(milestone: milestone)),

        // From ten friends on, the app has enough to say "two of these might
        // fit". Only until the first proposal exists.
        if (friends >= 10 && allMatches.isEmpty)
          block(
            HomeFirstIdeaCard(
              friends: friends,
              onOpenIdea: () => context.push('/matches/add'),
            ),
          ),

        if (stage.showsImportTool)
          block(HomeImportInvite(onTap: () => context.push('/people/ai'))),

        // 3. הלוח שלי — what was pinned by hand, plus whatever asked to be
        // remembered today. Absent entirely when there is nothing on it.
        _BoardSection(
          focusKey: _boardSectionKey,
          entries: board.entries,
          personRepository: personRepository,
          matchRepository: matchRepository,
        ),

        // 4. The invitation to think. A banner and nothing else: no faces, no
        // names, no count — the people live on the page it opens.
        if (friends >= 3)
          block(HomeThinkBanner(onTap: () => ThinkScreen.open(context))),

        // 5. רעיונות פתוחים — the proposals with an actual reason to be looked
        // at again today.
        if (stage.showsIdeaAreas)
          _OpenIdeasSection(
            ideas: openIdeas,
            personRepository: personRepository,
          ),

        // 6. The emotional anchor, and the only block on the page wearing
        // colour. Drawn only while there is somebody to celebrate.
        _DatingSection(
          matches: datingMatches.take(HomeConfig.datingCouplesInRow).toList(),
          personRepository: personRepository,
        ),

        // 7. What the app recommends, ranked by urgency — three at a time.
        if (nextActions.isNotEmpty)
          SliverToBoxAdapter(
            child: HomeNextActionsRow(
              actions: nextActions,
              onOpen: (HomeNextAction action) => action.isPerson
                  ? context.push('/people/${action.person!.id}')
                  : context.push('/matches/${action.match!.id}'),
            ),
          ),

        // 8. The pairs the database worked out on its own. Held back until the
        // database is big enough to keep producing them — below fifty friends
        // the well runs dry and the block becomes a promise the app cannot
        // keep, so the screen goes on pushing towards growth instead.
        if (friends > HomeConfig.databaseIdeasMinFriends)
          block(
            HomeHeroBand(onShowIdeas: () => context.push('/ideas/new')),
            top: 18,
          ),

        // 9. What has been done, in one number. Everything behind it is a tap
        // away rather than on the workspace.
        block(
          HomeActivityPanel(
            range: _activityRange,
            total: switch (_activityRange) {
              HomeActivityRange.week => totals.week,
              HomeActivityRange.month => totals.month,
              HomeActivityRange.allTime => totals.allTime,
            },
            onRangeChanged: (HomeActivityRange range) =>
                setState(() => _activityRange = range),
            onOpen: () => context.push('/stats/month'),
          ),
          top: 16,
        ),

        // 10. The community's tip.
        block(
          HomeTipCarousel(tips: _tips(context), userGender: userGender),
          top: 16,
        ),

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

    return Align(
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
/// Always exactly one row, however many notes there are, and hidden entirely
/// when there are none.
class _BoardSection extends StatelessWidget {
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

  /// The pinned entries plus the due reminders, without repeating an item that
  /// is both.
  List<HomeBoardEntry> _live() {
    // A pinned record that has since been deleted simply drops out.
    final List<HomeBoardEntry> pinned = entries.where((HomeBoardEntry entry) {
      return entry.kind == HomeItemKind.person
          ? personRepository.getById(entry.targetId) != null
          : matchRepository.getById(entry.targetId) != null;
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
          personRepository.getById(personId) == null) {
        return;
      }
      addDue(
        HomeItemKind.person,
        personId,
        at,
        PersonReminders.noteFor(personId),
      );
    });
    for (final MatchIdea match in matchRepository.getAll()) {
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
    final List<HomeBoardEntry> live = _live();
    if (live.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        key: focusKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const HomeSectionHeader(
            title: 'הלוח שלי',
            icon: Icons.push_pin_outlined,
            subtitle: 'אנשים או רעיונות שחשוב לי לזכור',
          ),
          HomeNoteBoard(
            // The end padding is smaller than a note, so the next one always
            // peeks in from the edge — which is what says the row scrolls,
            // without an arrow and without a second line of notes.
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
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
              separatorBuilder: (_, _) => SizedBox(width: homeCardGap(context)),
              itemBuilder: (BuildContext context, int index) => _BoardCard(
                entry: live[index],
                personRepository: personRepository,
                matchRepository: matchRepository,
              ),
            ),
          ),
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

// --- רעיונות שכדאי לחזור אליהם ----------------------------------------------

/// Not the list of open proposals — that is what the proposals screen is for.
///
/// Only the ones with a reason to be looked at again today: a reminder that has
/// come due, or an idea that has not moved in weeks. A row of every open
/// proposal is a list to scroll past; a row of the two that are actually asking
/// for something is a row that gets used.
class _OpenIdeasSection extends StatelessWidget {
  const _OpenIdeasSection({
    required this.ideas,
    required this.personRepository,
  });

  final List<HomeOpenIdea> ideas;
  final PersonRepository personRepository;

  /// An idea nobody has moved for this long is worth surfacing again.
  static const int _staleAfterDays = HomeConfig.openIdeaStaleAfterDays;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final List<HomeOpenIdea> worthReturningTo = ideas.where((
      HomeOpenIdea idea,
    ) {
      return idea.alerting ||
          now.difference(idea.match.updatedAt).inDays >= _staleAfterDays;
    }).toList();

    if (worthReturningTo.isEmpty) {
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
            icon: Icons.lightbulb_outline,
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
                    index < worthReturningTo.length;
                    index++
                  ) ...<Widget>[
                    if (index > 0) const SizedBox(width: 2),
                    () {
                      final HomeOpenIdea idea = worthReturningTo[index];
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
        22,
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
