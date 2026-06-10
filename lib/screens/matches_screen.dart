import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    this.initialShowArchived = false,
    this.initialStatuses = const <MatchStatus>[],
  });

  final bool initialShowArchived;
  final List<MatchStatus> initialStatuses;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();

  TabController? _tabController;
  List<MatchProposalTab> _visibleTabs = const <MatchProposalTab>[];
  bool _appliedInitialTab = false;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _showArchived = widget.initialShowArchived;
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.read<PersonRepository>();

    final String query = _searchController.text.trim();
    final List<MatchIdea> matches = query.isNotEmpty
        ? matchRepository.search(query, personRepository)
        : matchRepository.getAll();

    final Map<MatchProposalTab, List<MatchIdea>> groups = _groupMatches(
      matches: matches,
      personRepository: personRepository,
    );

    final List<MatchProposalTab> visibleTabs = _showArchived
        ? <MatchProposalTab>[
            MatchProposalTab.dated,
            MatchProposalTab.rejected,
            if (groups[MatchProposalTab.weddings]!.isNotEmpty)
              MatchProposalTab.weddings,
          ]
        : <MatchProposalTab>[
            MatchProposalTab.open,
            MatchProposalTab.waiting,
            MatchProposalTab.dating,
          ];

    final TabController tabController = _syncTabController(visibleTabs);

    // The tab bar lives on the app bar, so its labels must use the app bar's
    // foreground colour (white on the purple bar) instead of purple-on-purple.
    final Color appBarForeground =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;

    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'ארכיון' : 'רעיונות'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: Icon(
              _showArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
            tooltip: _showArchived ? 'חזרה לרעיונות' : 'ארכיון',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: TabBar(
            controller: tabController,
            // Spread the tabs evenly across the full width of the app bar.
            isScrollable: false,
            labelColor: appBarForeground,
            unselectedLabelColor: appBarForeground.withValues(alpha: 0.7),
            indicatorColor: appBarForeground,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            tabs: visibleTabs.map((MatchProposalTab tab) {
              return Tab(text: tab.displayName);
            }).toList(),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[

          Expanded(
            child: TabBarView(
              controller: tabController,
              children: visibleTabs.map((MatchProposalTab tab) {
                return _MatchesTabView(
                  matches: groups[tab]!,
                  tab: tab,
                  isSearchResult: query.isNotEmpty,
                  personRepository: personRepository,
                  theme: theme,
                  onCreate: () => context.push('/matches/add'),
                );
              }).toList(),
            ),
          ),
        ],
      ),


    );
  }

  Map<MatchProposalTab, List<MatchIdea>> _groupMatches({
    required List<MatchIdea> matches,
    required PersonRepository personRepository,
  }) {
    final Map<MatchProposalTab, List<MatchIdea>> groups =
        <MatchProposalTab, List<MatchIdea>>{
          for (final MatchProposalTab tab in MatchProposalTab.values)
            tab: <MatchIdea>[],
        };

    for (final MatchIdea match in matches) {
      final Person? personA = personRepository.getById(match.personAId);
      final Person? personB = personRepository.getById(match.personBId);
      final bool anyArchived =
          (personA?.profileStatus.isArchived ?? false) ||
          (personB?.profileStatus.isArchived ?? false);
      final bool anyPaused =
          (personA?.profileStatus.pausesMatches ?? false) ||
          (personB?.profileStatus.pausesMatches ?? false);

      final MatchProposalTab? tab = matchProposalTabFor(
        status: match.status,
        anyPersonArchived: anyArchived,
        anyPersonPaused: anyPaused,
      );
      if (tab != null) {
        groups[tab]!.add(match);
      }
    }

    return groups;
  }

  TabController _syncTabController(List<MatchProposalTab> visibleTabs) {
    final TabController? current = _tabController;
    if (current != null && current.length == visibleTabs.length) {
      _visibleTabs = visibleTabs;
      return current;
    }

    int initialIndex = 0;
    if (!_appliedInitialTab) {
      final MatchProposalTab? initialTab = _initialTab();
      if (initialTab != null) {
        final int index = visibleTabs.indexOf(initialTab);
        if (index >= 0) {
          initialIndex = index;
        }
      }
    } else if (current != null && _visibleTabs.isNotEmpty) {
      final MatchProposalTab previous =
          _visibleTabs[current.index.clamp(0, _visibleTabs.length - 1)];
      final int index = visibleTabs.indexOf(previous);
      initialIndex = index >= 0
          ? index
          : current.index.clamp(0, visibleTabs.length - 1);
    }

    current?.dispose();
    final TabController controller = TabController(
      length: visibleTabs.length,
      vsync: this,
      initialIndex: initialIndex.clamp(0, visibleTabs.length - 1),
    );
    _tabController = controller;
    _visibleTabs = visibleTabs;
    _appliedInitialTab = true;
    return controller;
  }

  MatchProposalTab? _initialTab() {
    if (widget.initialStatuses.isEmpty) {
      return null;
    }
    switch (widget.initialStatuses.first) {
      case MatchStatus.dating:
        return MatchProposalTab.dating;
      case MatchStatus.dated:
        return MatchProposalTab.dated;
      case MatchStatus.rejected:
        return MatchProposalTab.rejected;
      case MatchStatus.married:
        return MatchProposalTab.weddings;
      case MatchStatus.unavailable:
        return MatchProposalTab.waiting;
      case MatchStatus.idea:
      case MatchStatus.checking:
        return MatchProposalTab.open;
    }
  }

  void _handleSearchChanged() {
    setState(() {});
  }
}

class _MatchesTabView extends StatelessWidget {
  const _MatchesTabView({
    required this.matches,
    required this.tab,
    required this.isSearchResult,
    required this.personRepository,
    required this.theme,
    required this.onCreate,
  });

  final List<MatchIdea> matches;
  final MatchProposalTab tab;
  final bool isSearchResult;
  final PersonRepository personRepository;
  final ThemeData theme;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return _EmptyMatchesState(
        tab: tab,
        isSearchResult: isSearchResult,
        onCreate: onCreate,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: matches.length,
      itemBuilder: (BuildContext context, int index) {
        final MatchIdea match = matches[index];
        final Person? personA = personRepository.getById(match.personAId);
        final Person? personB = personRepository.getById(match.personBId);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _MatchCard(
            match: match,
            personA: personA,
            personB: personB,
            onTap: () => context.push('/matches/${match.id}'),
            theme: theme,
          ),
        );
      },
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.personA,
    required this.personB,
    required this.onTap,
    required this.theme,
  });

  final MatchIdea match;
  final Person? personA;
  final Person? personB;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = AppColors.statusColor(match.status.name);
    final String personAName = personA?.fullName.trim().isNotEmpty == true
        ? personA!.fullName.trim()
        : 'אדם נמחק';
    final String personBName = personB?.fullName.trim().isNotEmpty == true
        ? personB!.fullName.trim()
        : 'אדם נמחק';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(right: BorderSide(width: 4, color: statusColor)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _AvatarOrDeleted(person: personA),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        personAName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      ' ↔ ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        personBName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AvatarOrDeleted(person: personB),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${match.status.icon} ${match.status.displayName}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'נפתח: ${AppDateUtils.formatDateShort(match.createdAt)} · עודכן: ${AppDateUtils.timeAgo(match.updatedAt)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarOrDeleted extends StatelessWidget {
  const _AvatarOrDeleted({required this.person});

  final Person? person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (person == null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.person_off_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return PersonAvatar(person: person!, radius: 18);
  }
}

class _EmptyMatchesState extends StatelessWidget {
  const _EmptyMatchesState({
    required this.tab,
    required this.isSearchResult,
    required this.onCreate,
  });

  final MatchProposalTab tab;
  final bool isSearchResult;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (isSearchResult) {
      return const EmptyState(
        icon: Icons.search,
        title: 'לא נמצאו תוצאות',
        subtitle: 'נסו לחפש בשם אחר',
      );
    }

    switch (tab) {
      case MatchProposalTab.open:
        return EmptyState(
          icon: Icons.favorite_border,
          title: 'אין הצעות פתוחות',
          subtitle: 'צרו הצעה חדשה בין שני אנשים',
          buttonText: 'הצעה חדשה',
          onButtonPressed: onCreate,
        );
      case MatchProposalTab.waiting:
        return const EmptyState(
          icon: Icons.pause_circle_outline,
          title: 'אין הצעות בהמתנה',
          subtitle: 'הצעות שאחד הצדדים בהן אינו פנוי יופיעו כאן',
        );
      case MatchProposalTab.dating:
        return const EmptyState(
          icon: Icons.volunteer_activism_outlined,
          title: 'אין זוגות שיוצאים',
          subtitle: 'זוגות בתהליך יציאה יופיעו כאן',
        );
      case MatchProposalTab.dated:
        return const EmptyState(
          icon: Icons.history,
          title: 'אין הצעות שיצאו',
          subtitle: 'זוגות שיצאו ונפרדו יופיעו כאן',
        );
      case MatchProposalTab.rejected:
        return const EmptyState(
          icon: Icons.cancel_outlined,
          title: 'אין הצעות שנדחו',
          subtitle: 'הצעות שנדחו יופיעו כאן',
        );
      case MatchProposalTab.weddings:
        return const EmptyState(
          icon: Icons.celebration_outlined,
          title: 'אין חתונות עדיין',
          subtitle: 'שידוכים שהגיעו לחופה יופיעו כאן',
        );
    }
  }
}
