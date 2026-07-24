import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

List<Widget> buildDashboardSummarySlivers(
  BuildContext context, {
  bool showSectionTitle = false,
  bool compact = false,
  double bottomPadding = 96,
  VoidCallback? onPeopleTap,
}) {
  final ThemeData theme = Theme.of(context);
  final PersonRepository personRepository = context.watch<PersonRepository>();
  final MatchRepository matchRepository = context.watch<MatchRepository>();

  final List<Person> storedPeople = personRepository.getAll();
  // Every non-deleted contact counts towards the general total, including those
  // still waiting for an update.
  final List<Person> visiblePeople = storedPeople
      .where((Person p) => !p.hidden)
      .toList();
  final List<Person> allPeople = visiblePeople
      .where((Person p) => !p.needsReview)
      .toList();
  final List<MatchIdea> allMatches = matchRepository.getAll();

  final int peopleCount = visiblePeople.length;
  final int mazelTovCount = allPeople
      .where((Person p) => p.profileStatus == ProfileStatus.mazelTov)
      .length;
  final int ideasCount = allMatches
      .where((MatchIdea m) => _isVisibleInActiveMatchesView(m, storedPeople))
      .length;
  final int rejectedIdeasCount = allMatches
      .where((MatchIdea m) => m.status == MatchStatus.rejected)
      .length;
  final int datingCount = allMatches
      .where((MatchIdea m) => m.status == MatchStatus.dating)
      .length;
  final int datedCount = allMatches
      .where((MatchIdea m) => m.status == MatchStatus.dated)
      .length;
  final int marriedCount = allMatches
      .where((MatchIdea m) => m.status == MatchStatus.married)
      .length;

  final List<_StatItem> stats = <_StatItem>[
    _StatItem(
      title: 'חברים',
      value: peopleCount.toString(),
      subtitle: '',
      icon: Icons.people_outline,
      color: theme.colorScheme.primary,
      route: '/people',
      onTap: onPeopleTap,
    ),
    _StatItem(
      title: 'רעיונות',
      value: ideasCount.toString(),
      subtitle: 'כל מה שמופיע בהצעות',
      icon: Icons.lightbulb_outline,
      color: Colors.amber.shade700,
      route: '/matches',
    ),
    _StatItem(
      title: 'יוצאים',
      value: datingCount.toString(),
      subtitle: '',
      icon: Icons.favorite,
      color: Colors.green.shade600,
      route: '/matches?statuses=dating',
    ),
    // _StatItem(
    //   title: 'זוגות שיצאו',
    //   value: datedCount.toString(),
    //   subtitle: '',
    //   icon: Icons.heart_broken,
    //   color: Colors.deepPurple,
    //   route: '/matches?archived=true&statuses=dated',
    // ),
    // _StatItem(
    //   title: 'רעיונות שנפסלו',
    //   value: rejectedIdeasCount.toString(),
    //   subtitle: 'הצעות שנדחו',
    //   icon: Icons.cancel_outlined,
    //   color: Colors.red.shade500,
    //   route: '/matches?archived=true&statuses=rejected',
    // ),
    // _StatItem(
    //   title: 'מזל טוב',
    //   value: mazelTovCount.toString(),
    //   subtitle: 'חברים שהתחתנו',
    //   icon: Icons.celebration_outlined,
    //   color: Colors.teal.shade500,
    //   route: '/people?archived=true&statuses=mazelTov',
    // ),
  ];

  final _StatItem marriedStat = _StatItem(
    title: 'מזל טוב',
    value: marriedCount.toString(),
    subtitle: 'שידוכים שלי',
    icon: Icons.favorite,
    color: Colors.pink.shade400,
    route: '/matches?archived=true&statuses=married',
  );
  final List<_StatItem> allStats = <_StatItem>[...stats, marriedStat];

  if (compact) {
    return <Widget>[
      if (showSectionTitle)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.12,
            ),
            itemCount: allStats.length,
            itemBuilder: (BuildContext context, int index) {
              return _CompactStatCard(item: allStats[index]);
            },
          ),
        ),
    ];
  }

  return <Widget>[
    if (showSectionTitle)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Text('נתונים', style: theme.textTheme.titleLarge),
        ),
      ),
    SliverPadding(
      padding: EdgeInsets.fromLTRB(16, showSectionTitle ? 0 : 16, 16, 0),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.16,
        ),
        itemCount: stats.length,
        itemBuilder: (BuildContext context, int index) {
          return _StatCard(item: stats[index]);
        },
      ),
    ),
    SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPadding),
        child: _WideStatCard(item: marriedStat),
      ),
    ),
  ];
}

bool _isVisibleInActiveMatchesView(MatchIdea match, List<Person> people) {
  if (match.status.isArchived) {
    return false;
  }

  final Person? personA = _personById(people, match.personAId);
  final Person? personB = _personById(people, match.personBId);
  return !(personA?.profileStatus.isArchived ?? false) &&
      !(personB?.profileStatus.isArchived ?? false);
}

Person? _personById(List<Person> people, String id) {
  for (final Person person in people) {
    if (person.id == id) {
      return person;
    }
  }
  return null;
}

class _StatItem {
  const _StatItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
    this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;

  /// Optional tap override. When set, it runs instead of navigating to
  /// [route] (used so the "חברים" card scrolls to the in-page list rather than
  /// opening the standalone people screen).
  final VoidCallback? onTap;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tint = item.color.withValues(alpha: 0.12);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: item.color.withValues(alpha: 0.18)),
      ),
      child: InkWell(
        onTap: item.onTap ?? () => context.go(item.route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.color, size: 21),
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  item.value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: item.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (item.subtitle.isNotEmpty)
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactStatCard extends StatelessWidget {
  const _CompactStatCard({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.colorScheme.primary;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: InkWell(
        onTap: item.onTap ?? () => context.go(item.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.value,
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideStatCard extends StatelessWidget {
  const _WideStatCard({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: item.color.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: item.color.withValues(alpha: 0.22)),
      ),
      child: InkWell(
        onTap: item.onTap ?? () => context.go(item.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(item.icon, color: item.color, size: 26),
              ),
              const SizedBox(width: 16),
              Text(
                item.value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: item.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty)
                      Text(
                        item.subtitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
