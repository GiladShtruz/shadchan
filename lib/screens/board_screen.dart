import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/widgets/home_board.dart';

/// "הלוח שלי" in full — every row, and the five shelves to look through it
/// (הכל | כרטיסים וגישה | התראות | רעיונות פתוחים | הצעות מהמאגר).
///
/// The home screen shows only the few rows the board ranks highest and links
/// here ("לכל הלוח"); the chips, the customisation and "הוספה ללוח" live on
/// this page, where somebody came to look through the board rather than to
/// glance at it.
class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final PersonRepository people = context.watch<PersonRepository>();
    final MatchRepository matches = context.watch<MatchRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('הלוח שלי')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            HomeBoardStore.instance,
            RecentActivityStore.instance,
          ]),
          builder: (BuildContext context, _) => CustomScrollView(
            slivers: <Widget>[
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              HomeBoardSection(
                focusKey: const ValueKey<String>('board-screen'),
                mode: HomeBoardMode.screen,
                entries: HomeBoardStore.instance.entries,
                openIdeas: boardOpenIdeas(matches: matches, people: people),
                personRepository: people,
                matchRepository: matches,
                refresh: 0,
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.viewPaddingOf(context).bottom + 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
