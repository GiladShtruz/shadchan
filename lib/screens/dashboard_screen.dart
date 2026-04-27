import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/hebrew_date_utils.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/widgets/app_drawer.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final List<Person> allPeople = personRepository
        .getAll()
        .where((Person p) => !p.needsReview)
        .toList();
    final List<MatchIdea> allMatches = matchRepository.getAll();

    final int peopleCount = allPeople.length;
    final int mazelTovCount = allPeople
        .where((Person p) => p.profileStatus == ProfileStatus.mazelTov)
        .length;
    final ({int year, int month, int day})? currentHebrewDate =
        HebrewDateUtils.today();
    final List<Person> birthdaysThisMonth = _birthdaysInCurrentHebrewMonth(
      allPeople,
      currentHebrewDate,
    );

    final int openIdeasCount = allMatches
        .where(
          (MatchIdea m) =>
              m.status == MatchStatus.idea ||
              m.status == MatchStatus.checking ||
              m.status == MatchStatus.unavailable,
        )
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
        title: 'כרטיסים במאגר',
        value: peopleCount.toString(),
        subtitle: '',
        icon: Icons.people_outline,
        color: theme.colorScheme.primary,
        route: '/people',
      ),
      _StatItem(
        title: 'רעיונות פתוחים',
        value: openIdeasCount.toString(),
        subtitle: 'רעיון, בדיקה או צד תפוס',
        icon: Icons.lightbulb_outline,
        color: Colors.amber.shade700,
        route: '/matches?statuses=idea,checking,unavailable',
      ),
      _StatItem(
        title: 'זוגות שיוצאים',
        value: datingCount.toString(),
        subtitle: '',
        icon: Icons.favorite,
        color: Colors.green.shade600,
        route: '/matches?statuses=dating',
      ),
      _StatItem(
        title: 'זוגות שיצאו',
        value: datedCount.toString(),
        subtitle: '',
        icon: Icons.heart_broken,
        color: Colors.deepPurple,
        route: '/matches?archived=true&statuses=dated',
      ),
      _StatItem(
        title: 'רעיונות שנפסלו',
        value: rejectedIdeasCount.toString(),
        subtitle: 'הצעות שנדחו',
        icon: Icons.cancel_outlined,
        color: Colors.red.shade500,
        route: '/matches?archived=true&statuses=rejected',
      ),
      _StatItem(
        title: 'מזל טוב',
        value: mazelTovCount.toString(),
        subtitle: 'חברים שהתחתנו',
        icon: Icons.celebration_outlined,
        color: Colors.teal.shade500,
        route: '/people?archived=true&statuses=mazelTov',
      ),
    ];

    final _StatItem marriedStat = _StatItem(
      title: 'חתונות',
      value: marriedCount.toString(),
      subtitle: 'שידוכים שלי',
      icon: Icons.favorite,
      color: Colors.pink.shade400,
      route: '/matches?archived=true&statuses=married',
    );

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('נתונים'),
        centerTitle: true,
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverGrid.builder(
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _WideStatCard(item: marriedStat),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              child: _MonthlyBirthdaysSection(
                people: birthdaysThisMonth,
                currentHebrewDate: currentHebrewDate,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<Person> _birthdaysInCurrentHebrewMonth(
    List<Person> people,
    ({int year, int month, int day})? currentHebrewDate,
  ) {
    if (currentHebrewDate == null) {
      return const <Person>[];
    }

    final List<Person> birthdays = people.where((Person person) {
      final ({int year, int month, int day})? birthday = _hebrewBirthdayParts(
        person,
      );
      return birthday?.month == currentHebrewDate.month;
    }).toList();

    birthdays.sort((Person a, Person b) {
      final int dayA = _hebrewBirthdayParts(a)?.day ?? 0;
      final int dayB = _hebrewBirthdayParts(b)?.day ?? 0;
      final int dayComparison = dayA.compareTo(dayB);
      if (dayComparison != 0) {
        return dayComparison;
      }
      return a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
    });

    return birthdays;
  }

  static ({int year, int month, int day})? _hebrewBirthdayParts(Person person) {
    final int? month = person.hebrewBirthMonth;
    final int? day = person.hebrewBirthDay;
    final int? year = person.hebrewBirthYear;
    if (year != null && month != null && day != null) {
      return (year: year, month: month, day: day);
    }
    final DateTime? birthDate = person.birthDate;
    return birthDate == null ? null : HebrewDateUtils.fromGregorian(birthDate);
  }
}

class _StatItem {
  const _StatItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(item.route),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(item.icon, color: item.color, size: 24),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                item.value,
                style: theme.textTheme.headlineLarge?.copyWith(
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
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
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

class _WideStatCard extends StatelessWidget {
  const _WideStatCard({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(item.route),
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: <Widget>[
            Icon(item.icon, color: item.color, size: 32),
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
                      fontWeight: FontWeight.w600,
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

class _MonthlyBirthdaysSection extends StatelessWidget {
  const _MonthlyBirthdaysSection({
    required this.people,
    required this.currentHebrewDate,
  });

  final List<Person> people;
  final ({int year, int month, int day})? currentHebrewDate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String monthName = _currentMonthName();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('ימי הולדת החודש העברי', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          monthName.isNotEmpty ? monthName : 'החודש הנוכחי',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (people.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'אין ימי הולדת החודש',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: people.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
              itemBuilder: (BuildContext context, int index) {
                final Person person = people[index];
                return ListTile(
                  leading: const Icon(Icons.cake_outlined),
                  title: Text(person.fullName.trim()),
                  subtitle: Text(_birthdaySubtitle(person)),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.push('/people/${person.id}'),
                );
              },
            ),
          ),
      ],
    );
  }

  String _currentMonthName() {
    final ({int year, int month, int day})? current = currentHebrewDate;
    if (current == null) {
      return '';
    }
    final String formatted = HebrewDateUtils.format(
      year: current.year,
      month: current.month,
      day: current.day,
    );
    final List<String> parts = formatted.split(' ');
    if (parts.length >= 3 && parts[2] == 'ב׳') {
      return '${parts[1]} ${parts[2]}';
    }
    return parts.length >= 2 ? parts[1] : formatted;
  }

  String _birthdaySubtitle(Person person) {
    final ({int year, int month, int day})? current = currentHebrewDate;
    final ({int year, int month, int day})? birthday =
        DashboardScreen._hebrewBirthdayParts(person);
    if (current == null || birthday == null) {
      return '';
    }

    final String hebrewDate = HebrewDateUtils.format(
      year: current.year,
      month: birthday.month,
      day: birthday.day,
    );
    final DateTime? gregorianDate = HebrewDateUtils.toGregorian(
      year: current.year,
      month: birthday.month,
      day: birthday.day,
    );
    final String gregorianText = gregorianDate == null
        ? ''
        : AppDateUtils.formatDate(gregorianDate);
    if (gregorianText.isEmpty) {
      return hebrewDate;
    }
    return '$hebrewDate · $gregorianText';
  }
}
