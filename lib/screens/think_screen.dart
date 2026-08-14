import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/utils/home_suggestions.dart';
import 'package:shadchan/utils/profile_palette.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// "עוצרים רגע לחשוב על שידוך?" — friends, one after another, each with the
/// reason they came up.
///
/// There is no session here on purpose: no timer, no "5 people left", no
/// progress. Thinking about one person and closing the screen is a complete
/// use of it. Everything a matchmaker might then want to do — open an idea,
/// look at matches, update details, change a status — already lives on the
/// person's own page, so a tap goes there rather than growing a second set of
/// actions that would have to be kept in step.
class ThinkScreen extends StatefulWidget {
  const ThinkScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ThinkScreen(),
      ),
    );
  }

  @override
  State<ThinkScreen> createState() => _ThinkScreenState();
}

class _ThinkScreenState extends State<ThinkScreen> {
  /// Fixed for the life of the screen so the list does not reshuffle under the
  /// finger while it is being scrolled.
  final int _seed = DateTime.now().millisecondsSinceEpoch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final List<Person> people = personRepository
        .getAll()
        .where((Person person) => !person.hidden && !person.needsReview)
        .toList();
    final List<MatchIdea> matches = matchRepository.getAll();

    final List<HomeSuggestion> suggestions = HomeSuggestions.build(
      people: people,
      matches: matches,
      events: personRepository.getAllEvents(),
      activity: RecentActivityStore.instance.entries,
      limit: 60,
    );
    final List<_ThinkRow> rows = _withOccasionalStranger(suggestions, people);

    return Scaffold(
      backgroundColor: ProfilePalette.canvas(theme),
      appBar: AppBar(
        backgroundColor: ProfilePalette.canvas(theme),
        foregroundColor: ProfilePalette.text(theme),
        titleTextStyle: ProfilePalette.appBarTitleStyle(theme),
        title: const Text('עוצרים רגע לחשוב'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: rows.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    'כשיהיו במאגר עוד חברים, כאן יהיה על מי לחשוב.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: ProfilePalette.muted(theme),
                    ),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  final _ThinkRow row = rows[index];
                  return _PersonThought(
                    person: row.person,
                    reason: row.reason,
                    onTap: () => context.push('/people/${row.person.id}'),
                  );
                },
              ),
      ),
    );
  }

  /// Every so often, someone with no particular reason at all.
  ///
  /// A list built only from rules keeps returning the same corner of the
  /// database. One genuinely random face every few rows is what opens a
  /// direction nobody was looking for.
  List<_ThinkRow> _withOccasionalStranger(
    List<HomeSuggestion> suggestions,
    List<Person> people,
  ) {
    final List<_ThinkRow> rows = <_ThinkRow>[
      for (final HomeSuggestion suggestion in suggestions)
        _ThinkRow(person: suggestion.person, reason: suggestion.reason),
    ];
    if (people.length < 6) {
      return rows;
    }

    final math.Random random = math.Random(_seed);
    final Set<String> shown = rows
        .map((_ThinkRow row) => row.person.id)
        .toSet();
    final List<Person> strangers = people
        .where((Person person) => !shown.contains(person.id))
        .toList();
    if (strangers.isEmpty) {
      return rows;
    }
    strangers.shuffle(random);

    final List<_ThinkRow> mixed = <_ThinkRow>[];
    int next = 0;
    for (int i = 0; i < rows.length; i++) {
      mixed.add(rows[i]);
      if ((i + 1) % 7 == 0 && next < strangers.length) {
        mixed.add(
          _ThinkRow(
            person: strangers[next++],
            reason: 'סתם ככה — אולי דווקא עכשיו יעלה הרעיון הנכון',
          ),
        );
      }
    }
    return mixed;
  }
}

class _ThinkRow {
  const _ThinkRow({required this.person, required this.reason});

  final Person person;
  final String reason;
}

class _PersonThought extends StatelessWidget {
  const _PersonThought({
    required this.person,
    required this.reason,
    required this.onTap,
  });

  final Person person;
  final String reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: ProfilePalette.surface(theme),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              PersonAvatar(person: person, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      person.fullName.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ProfilePalette.text(theme),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ProfilePalette.muted(theme),
                        height: 1.35,
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
