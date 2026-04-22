import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/core/constants/enums.dart';
import 'package:shadchan/data/models/match_idea.dart';
import 'package:shadchan/data/models/person.dart';
import 'package:shadchan/data/repositories/match_repository.dart';
import 'package:shadchan/data/repositories/person_repository.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final List<Person> allPeople = personRepository.getAll();
    final List<MatchIdea> allMatches = matchRepository.getAll();

    final int peopleCount = allPeople.length;
    final int activePeopleCount = allPeople
        .where((Person p) => !p.profileStatus.isArchived)
        .length;
    final int mazelTovCount = allPeople
        .where((Person p) => p.profileStatus == ProfileStatus.mazelTov)
        .length;

    final int ideasCount = allMatches
        .where(
          (MatchIdea m) =>
              m.status == MatchStatus.idea || m.status == MatchStatus.checking,
        )
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
        title: 'כרטיסים במאגר',
        value: peopleCount.toString(),
        subtitle: '',
        icon: Icons.people_outline,
        color: theme.colorScheme.primary,
      ),
      _StatItem(
        title: 'רעיונות לשידוכים',
        value: ideasCount.toString(),
        subtitle: '',
        icon: Icons.lightbulb_outline,
        color: Colors.amber.shade700,
      ),
      _StatItem(
        title: 'זוגות שיוצאים',
        value: datingCount.toString(),
        subtitle: '',
        icon: Icons.favorite,
        color: Colors.green.shade600,
      ),
      _StatItem(
        title: 'זוגות שיצאו',
        value: datedCount.toString(),
        subtitle: '',
        icon: Icons.history,
        color: Colors.deepPurple,
      ),
      _StatItem(
        title: 'חתונות',
        value: marriedCount.toString(),
        subtitle: 'שידוכים שלי',
        icon: Icons.favorite_border,
        color: Colors.pink.shade400,
      ),
      _StatItem(
        title: 'מזל טוב',
        value: mazelTovCount.toString(),
        subtitle: 'חברים שהתחתנו',
        icon: Icons.celebration_outlined,
        color: Colors.orange.shade600,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('נתונים'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemCount: stats.length,
          itemBuilder: (BuildContext context, int index) {
            return _StatCard(item: stats[index]);
          },
        ),
      ),
    );
  }
}

class _StatItem {
  const _StatItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(item.icon, color: item.color, size: 28),
            const Spacer(),
            Text(
              item.value,
              style: theme.textTheme.displaySmall?.copyWith(
                color: item.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              item.subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
