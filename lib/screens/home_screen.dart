import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/match_suggestion_flow.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// The landing screen shown on every non-first launch (and after the user
/// finishes the initial contact import). It greets the matchmaker, features a
/// random contact to "think about", and lists everyone else in a shuffled
/// order that changes each time the app is opened.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Seed for the per-launch shuffle. Generated once so the order stays stable
  /// while this screen is alive, but differs on the next app launch.
  late final int _seed = Random().nextInt(0x7fffffff);

  /// How many times the user pressed "skip" — advances the featured contact.
  int _skips = 0;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final UserProfileProvider profile = context.watch<UserProfileProvider>();

    final List<Person> people = _orderedEligiblePeople(personRepository);
    final int pendingCount = personRepository.getPending().length;

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('בית')),
      body: SafeArea(
        child: people.isEmpty && pendingCount == 0
            ? _buildEmptyState(theme)
            : _buildContent(theme, profile, people, pendingCount),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    UserProfileProvider profile,
    List<Person> people,
    int pendingCount,
  ) {
    final Person? featured = people.isEmpty
        ? null
        : people[_skips % people.length];

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          sliver: SliverToBoxAdapter(
            child: _Greeting(profile: profile),
          ),
        ),
        if (featured != null) ...<Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            sliver: SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: _skipTransition,
                child: _FeaturedCard(
                  key: ValueKey<String>('featured-${featured.id}-$_skips'),
                  person: featured,
                  onOpenMatches: () => _openMatches(featured),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _ActionButtons(
                onSkip: _skip,
                onMatch: () => _openMatches(featured),
              ),
            ),
          ),
        ],
        if (pendingCount > 0)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _PendingUpdateCard(
                count: pendingCount,
                onTap: () => context.push('/people/pending'),
              ),
            ),
          ),
        if (people.isNotEmpty) ...<Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: <Widget>[
                  Text('החברים שלך:', style: theme.textTheme.titleLarge),
                  const SizedBox(width: 8),
                  Text(
                    '(${people.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: Divider(height: 16)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverList.separated(
              itemCount: people.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final Person person = people[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PersonAvatar(person: person, radius: 20),
                  title: Text(
                    person.fullName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: _subtitleFor(person).isEmpty
                      ? null
                      : Text(_subtitleFor(person)),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.push('/people/${person.id}'),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.groups_outlined, size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'עוד אין חברים במאגר',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'בוא נוסיף כמה חברים כדי שנוכל להתחיל לחשוב על שידוכים',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push('/people/import'),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('הוספת חברים'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skipTransition(Widget child, Animation<double> animation) {
    final Animation<Offset> offset = Tween<Offset>(
      begin: const Offset(0.35, 0.18),
      end: Offset.zero,
    ).animate(animation);
    final Animation<double> scale = Tween<double>(
      begin: 0.82,
      end: 1.0,
    ).animate(animation);
    final Animation<double> rotation = Tween<double>(
      begin: 0.06,
      end: 0.0,
    ).animate(animation);

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: offset,
        child: RotationTransition(
          turns: rotation,
          child: ScaleTransition(scale: scale, child: child),
        ),
      ),
    );
  }

  void _skip() {
    HapticFeedback.selectionClick();
    setState(() => _skips++);
  }

  Future<void> _openMatches(Person person) async {
    await MatchSuggestionFlow.open(context, sourcePerson: person);
  }

  List<Person> _orderedEligiblePeople(PersonRepository repository) {
    final List<Person> people = repository
        .getAll()
        .where(
          (Person p) =>
              !p.needsReview && !p.hidden && !p.profileStatus.isArchived,
        )
        .toList();
    people.sort((Person a, Person b) => _shuffleKey(a).compareTo(_shuffleKey(b)));
    return people;
  }

  /// Deterministic per-launch ordering key: stable for the lifetime of this
  /// screen (so the list doesn't jump around on rebuilds) yet reshuffled on the
  /// next launch via [_seed]. New contacts slot in deterministically too.
  int _shuffleKey(Person person) => (person.id.hashCode ^ _seed) & 0x7fffffff;

  String _subtitleFor(Person person) {
    final List<String> parts = <String>[
      if (person.age != null) '${person.age}',
      if (person.religiousLevel != null) person.religiousLevel!.displayName,
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ];
    return parts.join(' · ');
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.profile});

  final UserProfileProvider profile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = profile.name ?? 'שדכן';
    final bool isFemale = profile.gender == Gender.female;
    final String dear = isFemale ? 'היקרה' : 'היקר';
    final String letsGo = isFemale ? 'בואי נחשוב' : 'בוא נחשוב';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$name $dear!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$letsGo על החברים שלך!',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PendingUpdateCard extends StatelessWidget {
  const _PendingUpdateCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = Colors.amber.shade800;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.4)),
      ),
      color: accent.withValues(alpha: 0.10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(Icons.edit_note, color: accent, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'נותרו עוד $count אנשים לעדכן במאגר שלך!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_left, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    super.key,
    required this.person,
    required this.onOpenMatches,
  });

  final Person person;
  final VoidCallback onOpenMatches;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = <String>[
      if (person.age != null) '${person.age}',
      if (person.religiousLevel != null) person.religiousLevel!.displayName,
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ].join(' · ');

    return Card(
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        onTap: onOpenMatches,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[
                theme.colorScheme.primaryContainer,
                theme.colorScheme.secondaryContainer,
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            children: <Widget>[
              Hero(
                tag: 'person-${person.id}',
                child: PersonAvatar(person: person, radius: 52),
              ),
              const SizedBox(height: 16),
              Text(
                person.fullName.trim(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              if (subtitle.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer
                        .withValues(alpha: 0.8),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.touch_app_outlined,
                    size: 16,
                    color: theme.colorScheme.onPrimaryContainer
                        .withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'הקש כדי לחשוב על התאמות',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.7),
                    ),
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

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.onSkip, required this.onMatch});

  final VoidCallback onSkip;
  final VoidCallback onMatch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: _EmojiButton(
            emoji: '⏭️',
            label: 'דלג',
            background: theme.colorScheme.surfaceContainerHighest,
            foreground: theme.colorScheme.onSurface,
            onTap: onSkip,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _EmojiButton(
            emoji: '❤️',
            label: 'התאמות',
            background: theme.colorScheme.primary,
            foreground: theme.colorScheme.onPrimary,
            onTap: onMatch,
          ),
        ),
      ],
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({
    required this.emoji,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
