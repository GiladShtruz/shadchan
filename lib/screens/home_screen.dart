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
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/home_suggestions.dart';
import 'package:shadchan/utils/matchmaker_tips.dart';
import 'package:shadchan/utils/monthly_stats.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_list_card.dart';

/// The landing screen: a calm workspace rather than a dashboard.
///
/// Everything below the banner is a row of identically sized cards, in a fixed
/// order — the two ways to grow the database, what the matchmaker parked on
/// their board, what they just worked on, the open ideas, who quietly slipped
/// out of view, the couples who are dating, and only then the numbers and a
/// tip. Nothing on the resting screen is open, expanded or asking to be
/// dismissed; every deeper option waits behind a tap.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialSearch = ''});

  final String initialSearch;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _searchVisible = false;

  /// Picked once per visit to the screen, so every entry shows a different tip.
  late String _tip;

  @override
  void initState() {
    super.initState();
    _tip = MatchmakerTips.next();
    _searchController.text = widget.initialSearch;
    _searchVisible = widget.initialSearch.trim().isNotEmpty;
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final String name = profile.name ?? 'שדכן';
    final TimeOfDay now = TimeOfDay.fromDateTime(DateTime.now());

    return AppBar(
      titleSpacing: 16,
      centerTitle: false,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // First child sits at the start edge, which in RTL is the right.
          Icon(_timeOfDayIcon(now), size: 22),
          const SizedBox(width: 8),
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
        IconButton(
          tooltip: 'הגדרות',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push('/settings'),
        ),
      ],
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
                hintText: 'חפש במאגר שלך',
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
    final HomeBoardStore board = HomeBoardStore.instance;
    final RecentActivityStore activity = RecentActivityStore.instance;

    final List<MatchIdea> allMatches = matchRepository.getAll();
    final List<Person> allPeople = personRepository.getAll();
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
    // "Open" is everything still in play that has not become a couple yet, with
    // the newest ideas leading the row.
    final List<MatchIdea> openMatches =
        allMatches
            .where(
              (MatchIdea m) =>
                  !m.status.isArchived && m.status != MatchStatus.dating,
            )
            .toList()
          ..sort(
            (MatchIdea a, MatchIdea b) => b.createdAt.compareTo(a.createdAt),
          );

    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: visiblePeople,
      matches: allMatches,
    );

    final bool compactActions =
        visiblePeople.length >= HomeConfig.compactActionsFromPeopleCount;

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
          sliver: SliverToBoxAdapter(
            child: _QuickActions(compact: compactActions),
          ),
        ),
        _BoardSection(
          entries: board.entries,
          personRepository: personRepository,
          matchRepository: matchRepository,
        ),
        _QuickReturnSection(
          entries: activity.entries,
          personRepository: personRepository,
          matchRepository: matchRepository,
        ),
        _OpenIdeasSection(
          matches: openMatches.take(HomeConfig.openIdeasInRow).toList(),
          personRepository: personRepository,
        ),
        _WorthThinkingSection(suggestions: suggestions),
        _DatingSection(
          matches: datingMatches.take(HomeConfig.datingCouplesInRow).toList(),
          personRepository: personRepository,
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
          sliver: SliverToBoxAdapter(
            child: _MonthlyStatsCard(
              stats: MonthlyStats.current(allMatches, allPeople),
              onTap: () => context.push('/stats/month'),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
          sliver: SliverToBoxAdapter(
            child: _TipCard(
              tip: _tip,
              onAnother: () {
                setState(() {
                  _tip = MatchmakerTips.next(previous: _tip);
                });
              },
            ),
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

  static IconData _timeOfDayIcon(TimeOfDay now) {
    final int hour = now.hour;
    if (hour >= 5 && hour < 17) {
      return Icons.wb_sunny_outlined;
    }
    if (hour >= 17 && hour < 21) {
      return Icons.wb_twilight;
    }
    return Icons.nightlight_outlined;
  }
}

// --- The two main actions ---------------------------------------------------

/// "הוסף חברים" and "הוסף רעיון". Building the database is the one thing that
/// matters at the start, so until it is going the first action gets a card of
/// its own; from [HomeConfig.compactActionsFromPeopleCount] people up, the two
/// collapse into a single compact row.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _QuickActionCard(
                icon: Icons.person_add_alt,
                title: 'הוסף חברים',
                subtitle: 'לא משאירים אף חבר/ה רווק/ה מאחור',
                highlighted: true,
                onTap: () => AddPeopleDialog.show(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.auto_awesome_outlined,
                title: 'הוסף רעיון',
                subtitle: 'שמור את הרעיונות במקום אחד',
                onTap: () => context.push('/matches/add'),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        _QuickActionCard(
          icon: Icons.person_add_alt,
          title: 'הוסף חברים',
          subtitle: 'המאגר שלך מתחיל מהאנשים שלך',
          highlighted: true,
          large: true,
          onTap: () => AddPeopleDialog.show(context),
        ),
        const SizedBox(height: 10),
        _QuickActionCard(
          icon: Icons.auto_awesome_outlined,
          title: 'הוסף רעיון',
          subtitle: 'שמור את הרעיונות במקום אחד',
          onTap: () => context.push('/matches/add'),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
    this.large = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Makes this the filled, primary call to action. The other card is the same
  /// design in the same hue, only lighter: a soft wash of the primary colour
  /// with no border, so the pair reads as one family with a clear lead.
  final bool highlighted;

  /// The roomier variant used while the database is still small.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    // The light theme's `primary` is a pale blue-grey — too washed out to carry
    // a filled button, so the deeper tone is used there.
    final Color fill = dark ? theme.colorScheme.primary : AppColors.primaryDark;
    final Color onFill = theme.colorScheme.onPrimary;

    final Color background = highlighted
        ? fill
        : fill.withValues(alpha: dark ? 0.20 : 0.12);
    final Color titleColor = highlighted
        ? onFill
        : (dark ? fill : AppColors.primaryInk);
    final Color subtitleColor = highlighted
        ? onFill.withValues(alpha: 0.85)
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      elevation: highlighted ? 3 : 0,
      shadowColor: fill.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: large ? 20 : 14,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      title,
                      style:
                          (large
                                  ? theme.textTheme.titleLarge
                                  : theme.textTheme.titleMedium)
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: titleColor,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: large ? 38 : 28, color: titleColor),
            ],
          ),
        ),
      ),
    );
  }
}

// --- הלוח שלי ---------------------------------------------------------------

/// The people and proposals the matchmaker parked to come back to. Hidden
/// entirely until something is pinned.
class _BoardSection extends StatelessWidget {
  const _BoardSection({
    required this.entries,
    required this.personRepository,
    required this.matchRepository,
  });

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const HomeSectionHeader(
            title: 'הלוח שלי',
            icon: Icons.push_pin_outlined,
            subtitle: 'אנשים ורעיונות ששמרת לחזור אליהם',
          ),
          HomeCarousel(
            itemCount: live.length,
            itemBuilder: (BuildContext context, int index) {
              return _BoardCard(
                entry: live[index],
                personRepository: personRepository,
                matchRepository: matchRepository,
              );
            },
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
        reminder: personRepository.personReminderFor(person.id),
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
      reminder: match.reminderDate,
      onTap: () => context.push('/matches/${match.id}'),
    );
  }

  Widget _card(
    BuildContext context, {
    required Widget leading,
    required String title,
    required DateTime? reminder,
    required VoidCallback onTap,
  }) {
    return HomeMiniCard(
      leading: leading,
      title: title,
      subtitle: entry.note,
      onTap: onTap,
      footer: reminder == null
          ? null
          : HomeCardFooter(
              label: AppDateUtils.formatDateShort(reminder),
              icon: Icons.event_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
      menu: _BoardCardMenu(kind: entry.kind, targetId: entry.targetId),
    );
  }
}

/// The small per-card menu. It is only ever a single icon at rest — the options
/// open on tap, so the home screen itself stays free of open menus.
class _BoardCardMenu extends StatelessWidget {
  const _BoardCardMenu({required this.kind, required this.targetId});

  final HomeItemKind kind;
  final String targetId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return PopupMenuButton<String>(
      tooltip: 'אפשרויות',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 190),
      // A `child` rather than an `icon`: the icon form is an IconButton, whose
      // 48px tap target would reach across the card and swallow taps meant for
      // the card itself.
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          Icons.more_vert,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
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
            child: Text(hasNote ? 'ערוך הערה' : 'הוסף הערה'),
          ),
          PopupMenuItem<String>(
            value: 'reminder',
            child: Text(
              _hasReminder(context) ? 'ערוך תזכורת' : 'הוסף תזכורת',
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'remove',
            child: Text('הסר מהלוח'),
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

// --- חזרה מהירה -------------------------------------------------------------

/// The trail back to whatever was just worked on. One card per person or
/// proposal, newest first.
class _QuickReturnSection extends StatelessWidget {
  const _QuickReturnSection({
    required this.entries,
    required this.personRepository,
    required this.matchRepository,
  });

  final List<HomeActivityEntry> entries;
  final PersonRepository personRepository;
  final MatchRepository matchRepository;

  @override
  Widget build(BuildContext context) {
    final List<HomeActivityEntry> live = entries.where((
      HomeActivityEntry entry,
    ) {
      return entry.kind == HomeItemKind.person
          ? personRepository.getById(entry.targetId) != null
          : matchRepository.getById(entry.targetId) != null;
    }).toList();

    if (live.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const HomeSectionHeader(
            title: 'חזרה מהירה',
            icon: Icons.history,
            subtitle: 'הפעולות האחרונות שלך',
          ),
          HomeCarousel(
            itemCount: live.length,
            itemBuilder: (BuildContext context, int index) {
              return _QuickReturnCard(
                entry: live[index],
                personRepository: personRepository,
                matchRepository: matchRepository,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickReturnCard extends StatelessWidget {
  const _QuickReturnCard({
    required this.entry,
    required this.personRepository,
    required this.matchRepository,
  });

  final HomeActivityEntry entry;
  final PersonRepository personRepository;
  final MatchRepository matchRepository;

  @override
  Widget build(BuildContext context) {
    final Widget footer = HomeCardFooter(
      label: AppDateUtils.timeAgoShort(entry.at),
      icon: Icons.schedule,
    );

    if (entry.kind == HomeItemKind.person) {
      final Person person = personRepository.getById(entry.targetId)!;
      return HomeMiniCard(
        leading: HomeCardAvatar(person: person),
        title: person.fullName.trim(),
        subtitle: entry.action.label,
        footer: footer,
        onTap: () => context.push('/people/${person.id}'),
      );
    }

    final MatchIdea match = matchRepository.getById(entry.targetId)!;
    final Person? personA = personRepository.getById(match.personAId);
    final Person? personB = personRepository.getById(match.personBId);
    return HomeMiniCard(
      leading: HomeCardCoupleAvatars(personA: personA, personB: personB),
      title: '${_firstName(personA)} & ${_firstName(personB)}',
      subtitle: entry.action.label,
      footer: footer,
      onTap: () => context.push('/matches/${match.id}'),
    );
  }
}

// --- רעיונות פתוחים ---------------------------------------------------------

class _OpenIdeasSection extends StatelessWidget {
  const _OpenIdeasSection({
    required this.matches,
    required this.personRepository,
  });

  final List<MatchIdea> matches;
  final PersonRepository personRepository;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          HomeSectionHeader(
            title: 'רעיונות פתוחים',
            icon: Icons.lightbulb_outline,
            onSeeAll: () => context.go('/matches'),
          ),
          HomeCarousel(
            itemCount: matches.length,
            itemBuilder: (BuildContext context, int index) {
              final MatchIdea match = matches[index];
              return _OpenIdeaCard(
                match: match,
                personA: personRepository.getById(match.personAId),
                personB: personRepository.getById(match.personBId),
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
    required this.personA,
    required this.personB,
  });

  final MatchIdea match;
  final Person? personA;
  final Person? personB;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? reminder = match.reminderDate;
    final bool reminderDue =
        reminder != null && !reminder.isAfter(DateTime.now());

    return HomeMiniCard(
      leading: HomeCardCoupleAvatars(personA: personA, personB: personB),
      title: '${_firstName(personA)} & ${_firstName(personB)}',
      subtitle: 'עודכן ${AppDateUtils.timeAgoShort(match.updatedAt)}',
      footer: HomeCardFooter(
        label: match.status.displayName,
        color: AppColors.statusColor(match.status.name),
        tinted: true,
      ),
      onTap: () => context.push('/matches/${match.id}'),
      // A reminder that came due is a small mark in the corner, nothing more.
      menu: reminderDue
          ? Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.notifications_active,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            )
          : null,
    );
  }
}

// --- אולי שווה לחשוב עליהם --------------------------------------------------

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
            title: 'אולי שווה לחשוב עליהם',
            icon: Icons.auto_awesome_outlined,
            onSeeAll: () => context.go('/people'),
          ),
          HomeCarousel(
            itemCount: suggestions.length,
            itemBuilder: (BuildContext context, int index) {
              final HomeSuggestion suggestion = suggestions[index];
              return HomeMiniCard(
                leading: HomeCardAvatar(person: suggestion.person),
                title: suggestion.person.fullName.trim(),
                subtitle: suggestion.reason,
                onTap: () => context.push('/people/${suggestion.person.id}'),
              );
            },
          ),
        ],
      ),
    );
  }
}

// --- זוגות שיוצאים ----------------------------------------------------------

/// Pure encouragement, not a work queue: it exists only while there is someone
/// to celebrate, and it is the one row that wears colour.
class _DatingSection extends StatelessWidget {
  const _DatingSection({
    required this.matches,
    required this.personRepository,
  });

  final List<MatchIdea> matches;
  final PersonRepository personRepository;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final ThemeData theme = Theme.of(context);
    final Color accent = AppColors.statusDating;

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const HomeSectionHeader(
            title: 'זוגות שיוצאים',
            icon: Icons.favorite,
            subtitle: 'בזכותך הם נפגשו — שיהיה במזל טוב!',
          ),
          HomeCarousel(
            itemCount: matches.length,
            itemBuilder: (BuildContext context, int index) {
              final MatchIdea match = matches[index];
              return HomeMiniCard(
                leading: HomeCardCoupleAvatars(
                  personA: personRepository.getById(match.personAId),
                  personB: personRepository.getById(match.personBId),
                ),
                title:
                    '${_firstName(personRepository.getById(match.personAId))} '
                    '& ${_firstName(personRepository.getById(match.personBId))}',
                subtitle: 'יוצאים ${AppDateUtils.timeAgoShort(match.updatedAt)}',
                footer: HomeCardFooter(
                  label: 'שיהיה במזל טוב',
                  icon: Icons.favorite,
                  color: accent,
                ),
                background: accent.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.18 : 0.10,
                ),
                borderColor: accent.withValues(alpha: 0.35),
                onTap: () => context.push('/matches/${match.id}'),
              );
            },
          ),
        ],
      ),
    );
  }
}

// --- Bottom of the page -----------------------------------------------------

/// The month's numbers, moved below the work so opening the app lands on
/// actions rather than on a scoreboard. Tapping opens the full stats screen.
class _MonthlyStatsCard extends StatelessWidget {
  const _MonthlyStatsCard({required this.stats, required this.onTap});

  final MonthStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.insights_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'הנתונים שלך החודש',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  _StatCell(
                    value: stats.ideas,
                    label: 'רעיונות',
                    color: MonthlyStats.ideasColor,
                  ),
                  _StatCell(
                    value: stats.people,
                    label: 'חברים',
                    color: MonthlyStats.peopleColor,
                  ),
                  _StatCell(
                    value: stats.dating,
                    label: 'יוצאים',
                    color: MonthlyStats.datingColor,
                  ),
                  _StatCell(
                    value: stats.weddings,
                    label: 'חתונות',
                    color: MonthlyStats.weddingsColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of advice, and a way to ask for another. Deliberately the quietest
/// card on the page.
class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip, required this.onAnother});

  final String tip;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.lightbulb_outline,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
          IconButton(
            tooltip: 'טיפ אחר',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: theme.colorScheme.primary,
            onPressed: onAnother,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
