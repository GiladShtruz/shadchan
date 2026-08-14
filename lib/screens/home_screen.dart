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
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/profile_screen.dart';
import 'package:shadchan/screens/think_screen.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/home_open_ideas.dart';
import 'package:shadchan/utils/home_promote.dart';
import 'package:shadchan/utils/home_stage.dart';
import 'package:shadchan/utils/home_stats_banner.dart';
import 'package:shadchan/utils/home_suggestions.dart';
import 'package:shadchan/utils/matchmaker_tips.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/reminder_alerts.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
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

  /// Picked once per visit to the screen, so every entry shows a different tip.
  late String _tip;

  /// Advances once per visit. "שווה לקדם" and the numbers banner rotate on it,
  /// so the same five faces and the same sentence are not waiting every time.
  late final int _visit = HomeVisitCounter.next();

  @override
  void initState() {
    super.initState();
    _tip = MatchmakerTips.next();
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
    final RecentActivityStore activity = RecentActivityStore.instance;

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

    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: visiblePeople,
      matches: allMatches,
      events: personRepository.getAllEvents(),
      activity: activity.entries,
    );

    final int friends = personRepository.databaseCount;
    final HomeStage stage = HomeStage.forCount(friends);
    final HomeMilestone milestone = HomeMilestone.forCount(friends);

    final List<HomePromoteItem> promote = HomePromote.build(
      people: visiblePeople,
      matches: allMatches,
      personById: personRepository.getById,
      events: personRepository.getAllEvents(),
      notes: personRepository.getAllNotes(),
      activity: activity.entries,
      rotation: _visit,
    );
    final HomeStatLine statLine = HomeStatsBanner.build(
      matches: allMatches,
      friends: friends,
      rotation: _visit,
    );

    double inset() => homeHorizontalInset(context);
    SliverPadding block(Widget child, {double top = 12}) {
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(inset(), top, inset(), 0),
        sliver: SliverToBoxAdapter(child: child),
      );
    }

    // The order of what follows *is* the design. Everything that leads to an
    // action comes before everything that reports on one, and a block that
    // would be empty at this stage is not drawn at all rather than shown as an
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

        // The automatic pair suggestions lead once the database can actually
        // produce them. Design, wording and behaviour are untouched.
        if (stage.leadsWithAutomaticIdeas)
          block(
            HomeHeroBand(onShowIdeas: () => context.push('/ideas/new')),
            top: 14,
          ),

        block(
          HomeActionCards(
            onAddPeople: () => AddPeopleDialog.show(context),
            onAddIdea: () => context.push('/matches/add'),
            emphasiseAddPeople: stage.leadsWithGrowth,
          ),
          top: stage.leadsWithAutomaticIdeas || friends == 0 ? 12 : 14,
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

        _BoardSection(
          focusKey: _boardSectionKey,
          entries: board.entries,
          personRepository: personRepository,
          matchRepository: matchRepository,
        ),

        // "שווה לקדם" replaces both the recent-activity trail and the general
        // open-ideas list: a name with no reason attached says nothing about
        // what to do with it.
        if (promote.isNotEmpty && friends > 0)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const HomeSectionHeader(
                  title: 'שווה לקדם',
                  icon: Icons.trending_up,
                ),
                HomeCarousel(
                  itemCount: promote.length,
                  itemBuilder: (BuildContext context, int index) {
                    final HomePromoteItem item = promote[index];
                    return HomePromoteCard(
                      item: item,
                      onTap: () => item.isPerson
                          ? context.push('/people/${item.person!.id}')
                          : context.push('/matches/${item.match!.id}'),
                    );
                  },
                ),
              ],
            ),
          ),

        if (friends >= 3)
          block(HomeThinkBanner(onTap: () => ThinkScreen.open(context))),

        if (stage.showsIdeaAreas)
          _OpenIdeasSection(
            ideas: openIdeas,
            personRepository: personRepository,
          ),

        if (stage != HomeStage.starting)
          _WorthThinkingSection(suggestions: suggestions),

        // The emotional anchor, after the blocks that lead to action.
        _DatingSection(
          matches: datingMatches.take(HomeConfig.datingCouplesInRow).toList(),
          personRepository: personRepository,
        ),

        block(
          HomeStatBanner(
            text: statLine.text,
            onTap: () => context.push('/stats/month'),
          ),
          top: 16,
        ),

        block(
          HomeTipStrip(
            tip: _tip.forGender(userGender),
            userGender: userGender,
            onAnother: () {
              setState(() {
                _tip = MatchmakerTips.next(previous: _tip);
              });
            },
          ),
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

/// The people and proposals the matchmaker parked to come back to. Hidden
/// entirely until something is pinned.
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

  @override
  Widget build(BuildContext context) {
    // A pinned record that has since been deleted simply drops out.
    final List<HomeBoardEntry> live = entries.where((HomeBoardEntry entry) {
      return entry.kind == HomeItemKind.person
          ? personRepository.getById(entry.targetId) != null
          : matchRepository.getById(entry.targetId) != null;
    }).toList();

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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: homeIsNarrow(context) ? 8 : 10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (int index = 0; index < live.length; index++) ...<Widget>[
                    if (index > 0) SizedBox(width: homeCardGap(context)),
                    _BoardCard(
                      entry: live[index],
                      personRepository: personRepository,
                      matchRepository: matchRepository,
                    ),
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
          case 'remove':
            HomeBoardActions.remove(context, kind, targetId);
        }
      },
      itemBuilder: (BuildContext context) {
        final bool hasNote =
            (HomeBoardStore.instance.entryFor(kind, targetId)?.note ?? '')
                .isNotEmpty;
        return <PopupMenuEntry<String>>[
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

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          HomeSectionHeader(
            title: 'רעיונות שכדאי לחזור אליהם',
            icon: Icons.lightbulb_outline,
            onSeeAll: () => context.go('/matches'),
          ),
          HomeCarousel(
            itemCount: worthReturningTo.length,
            itemBuilder: (BuildContext context, int index) {
              final HomeOpenIdea idea = worthReturningTo[index];
              return _OpenIdeaCard(
                match: idea.match,
                alerting: idea.alerting,
                personA: personRepository.getById(idea.match.personAId),
                personB: personRepository.getById(idea.match.personBId),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OpenIdeaCard extends StatelessWidget {
  const _OpenIdeaCard({
    required this.match,
    required this.alerting,
    required this.personA,
    required this.personB,
  });

  final MatchIdea match;

  /// The reminder came due and the card has not been opened since.
  final bool alerting;

  final Person? personA;
  final Person? personB;

  @override
  Widget build(BuildContext context) {
    return HomeIdeaCard(
      personA: personA,
      personB: personB,
      title: '${_firstName(personA)} & ${_firstName(personB)}',
      status: match.status.displayName,
      statusColor: AppColors.statusColor(match.status.name),
      onTap: () => context.push('/matches/${match.id}'),
      // The badge only asks to be looked at; opening the card answers it.
      marker: alerting ? const HomeAlertBadge() : null,
    );
  }
}

// --- חברים ששווה לחשוב עליהם ------------------------------------------------

class _WorthThinkingSection extends StatelessWidget {
  const _WorthThinkingSection({required this.suggestions});

  final List<HomeSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          HomeSectionHeader(
            title: 'חברים ששווה לחשוב עליהם',
            icon: Icons.auto_awesome_outlined,
            onSeeAll: () => context.go('/people'),
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
                    index < suggestions.length;
                    index++
                  ) ...<Widget>[
                    if (index > 0) const SizedBox(width: 2),
                    HomeSuggestionBubble(
                      person: suggestions[index].person,
                      reason: suggestions[index].reason,
                      onTap: () => context.push(
                        '/people/${suggestions[index].person.id}',
                      ),
                    ),
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
