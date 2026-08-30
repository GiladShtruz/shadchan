import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/dialogs/person_whatsapp_menu.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/utils/dating_check_in.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/utils/search_navigation.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/match_idea_card.dart';
import 'package:shadchan/widgets/search_results_panel.dart';
import 'package:shadchan/widgets/shadchan_app_bar.dart';

/// The five states a proposal can be in, as the screen groups them.
///
/// "נסגרו" is what used to be called "ארכיון". A matchmaker does not archive
/// anything — they close a proposal — and the tab now carries the same word the
/// card does, so the button and the card it filters cannot disagree.
enum MatchCategory { all, open, waiting, dating, closed }

extension on MatchCategory {
  String get displayName {
    switch (this) {
      case MatchCategory.all:
        return 'הכל';
      case MatchCategory.open:
        return 'פתוחים';
      case MatchCategory.waiting:
        return 'בהמתנה';
      case MatchCategory.dating:
        return 'יוצאים';
      case MatchCategory.closed:
        return 'נסגרו';
    }
  }
}

/// Which half of the closed pile is showing.
enum _ClosedTab { rejected, dated }

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    this.initialShowArchived = false,
    this.initialStatuses = const <MatchStatus>[],
    this.focusMatchId,
    this.promptShareForMatchId,
  });

  final bool initialShowArchived;
  final List<MatchStatus> initialStatuses;

  /// One proposal to lift to the top of the list and light up.
  ///
  /// **This is what is left of `/matches/:id`.** A proposal used to have a page
  /// of its own, and every link in the app — a reminder, a notification, a home
  /// card — pushed it. There is no such page now: the card carries everything
  /// the page did. So those links land here instead, and rather than dropping
  /// the reader at the top of a list of forty and letting them hunt, the
  /// proposal they asked for is put first and wears the accent.
  final String? focusMatchId;

  /// A proposal that was just created, whose "יאללה לקדם!" sheet opens by
  /// itself. Making an idea and telling somebody about it is one act, and the
  /// second half is the half that gets forgotten.
  final String? promptShareForMatchId;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScroll = ScrollController();

  MatchCategory _category = MatchCategory.all;
  _ClosedTab _closedTab = _ClosedTab.rejected;
  bool _promptedShare = false;

  /// Which proposals have their action panel open right now.
  ///
  /// Owned here rather than in the cards because it is a fact about the
  /// *screen*: with something open, the list is being worked in rather than
  /// scanned, and the row of category tiles over it folds away to give the
  /// panel the room. See the header block in [build].
  final Set<String> _openCards = <String>{};

  /// Where the list was standing when a proposal's actions were opened.
  ///
  /// The anchor for "is the reader still looking at that card" — see
  /// [_handleScroll]. Null while nothing is open.
  double? _openAnchor;

  /// True once the reader has scrolled well away from the open panel and left
  /// it alone for [_awayAfter].
  bool _awayFromOpenCard = false;

  Timer? _awayTimer;

  /// How far from the open panel counts as having left it. Roughly a screenful
  /// of cards: anything less and the panel is probably still partly visible.
  static const double _awayDistance = 420;

  /// How long the reader has to stay away before the filters come back.
  static const Duration _awayAfter = Duration(seconds: 10);

  /// Whether the category tiles are folded away right now.
  ///
  /// **Exactly one thing decides this, and it is not the scroll.** The tiles
  /// used to hide on the way down the list and come back on the way up, which
  /// meant the map of the screen — five counts, and the only way between the
  /// five shelves — was missing at the moment somebody was furthest into a
  /// list and most likely to want to switch shelves. They are pinned under the
  /// search row now and stay there. The one time they go away is while a
  /// proposal's actions are open, because that panel is a promotion row, three
  /// status tiles and a journal, and it needs the third of the screen the
  /// filters were holding.
  ///
  /// **And they come back when the panel stops being what is being looked
  /// at.** A panel left open at the top of a list of forty went on holding the
  /// filters hostage for the rest of the session, however far down the reader
  /// had gone since. So: scroll a screenful away from it, leave it alone for
  /// ten seconds, and the map of the screen returns — without closing anything,
  /// because the panel is still where it was left.
  bool get _headerHidden => _openCards.isNotEmpty && !_awayFromOpenCard;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _listScroll.addListener(_handleScroll);
    _category = widget.initialShowArchived
        ? MatchCategory.closed
        : _categoryFor(widget.initialStatuses);
    if (widget.initialStatuses.contains(MatchStatus.dated) ||
        widget.initialStatuses.contains(MatchStatus.married)) {
      _closedTab = _ClosedTab.dated;
    }
    _scheduleSharePrompt();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _awayTimer?.cancel();
    _listScroll
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  /// Watches how far the list has travelled from the open panel.
  ///
  /// Distance from where the list was standing when the panel opened, rather
  /// than the panel's own position on screen: the cards are built lazily and a
  /// panel scrolled out of the viewport has no position to measure. A screenful
  /// away is the point at which it is certainly not what is being read.
  void _handleScroll() {
    final double? anchor = _openAnchor;
    if (anchor == null || !_listScroll.hasClients) {
      return;
    }
    final bool away = (_listScroll.offset - anchor).abs() > _awayDistance;
    if (!away) {
      // Back at the panel: the clock stops, and the filters go away again.
      _awayTimer?.cancel();
      _awayTimer = null;
      if (_awayFromOpenCard && mounted) {
        setState(() => _awayFromOpenCard = false);
      }
      return;
    }
    if (_awayFromOpenCard || _awayTimer != null) {
      return;
    }
    _awayTimer = Timer(_awayAfter, () {
      _awayTimer = null;
      if (mounted) {
        setState(() => _awayFromOpenCard = true);
      }
    });
  }

  void _handleCardActions(String matchId, bool open) {
    if (!mounted) {
      return;
    }
    final bool changed = open
        ? _openCards.add(matchId)
        : _openCards.remove(matchId);
    if (!changed) {
      return;
    }
    _awayTimer?.cancel();
    _awayTimer = null;
    _awayFromOpenCard = false;
    _openAnchor = _openCards.isEmpty
        ? null
        : (_listScroll.hasClients ? _listScroll.offset : 0);
    // Closing the last one puts the tiles straight back — they only ever went
    // away to make room for a panel that is now gone.
    setState(() {});
  }

  /// A long press on a proposal: the one way to delete it.
  ///
  /// **Deliberately behind a gesture and not on the action panel.** Every
  /// button under "פעולות" moves a proposal along; deleting one removes it and
  /// its journal from the database for good, and a control that destructive
  /// sitting in the same row as "העברה להמתנה" is a mis-tap waiting to happen.
  /// Closing an idea is what the panel is for — this is for the proposal that
  /// should never have been opened.
  Future<void> _confirmDelete(
    MatchIdea match,
    Person? female,
    Person? male,
  ) async {
    final String names = <String>[
      if ((female?.firstName ?? '').trim().isNotEmpty) female!.firstName.trim(),
      if ((male?.firstName ?? '').trim().isNotEmpty) male!.firstName.trim(),
    ].join(' ו');
    final MatchRepository repository = context.read<MatchRepository>();
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'מחיקת הרעיון',
      message: names.isEmpty
          ? 'למחוק את הרעיון? היומן וההיסטוריה שלו יימחקו איתו.'
          : 'למחוק את הרעיון של $names? היומן וההיסטוריה שלו יימחקו איתו.',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }
    await repository.deleteMatch(match.id);
    if (mounted) {
      AppNotice.show(context, 'הרעיון נמחק');
    }
  }

  static MatchCategory _categoryFor(List<MatchStatus> statuses) {
    if (statuses.isEmpty) {
      return MatchCategory.all;
    }
    switch (statuses.first) {
      case MatchStatus.dating:
        return MatchCategory.dating;
      case MatchStatus.unavailable:
        return MatchCategory.waiting;
      case MatchStatus.rejected:
      case MatchStatus.dated:
      case MatchStatus.married:
        return MatchCategory.closed;
      case MatchStatus.idea:
      case MatchStatus.checking:
        return MatchCategory.open;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    // Watched so a change to a person's availability re-groups the lists.
    final PersonRepository personRepository = context.watch<PersonRepository>();

    final String query = _searchController.text.trim();
    final bool searching = query.isNotEmpty;

    // **The categories are computed over whatever is on screen.** Searching
    // narrows the population, so the counts have to narrow with it — the whole
    // point of keeping the buttons during a search is to answer "what kinds of
    // proposal does this person have?", and counts taken over the whole
    // database would answer a question nobody asked.
    final List<MatchIdea> population = searching
        ? matchRepository.search(query, personRepository)
        : matchRepository.getAll();
    final Map<MatchCategory, List<MatchIdea>> groups = _groupMatches(
      population,
      personRepository,
    );
    final List<MatchIdea> dueReminders = searching
        ? const <MatchIdea>[]
        : _dueReminders(matchRepository.getAll());
    // Over the whole database rather than over the search: the strip at the
    // head of the page celebrates every couple who is out, and narrowing it to
    // whatever was typed would make it say something that is not true.
    final int datingCount = matchRepository
        .getAll()
        .where((MatchIdea match) => match.status == MatchStatus.dating)
        .length;

    // Reached by following a link to one proposal, this screen is a pushed page
    // rather than the tab — so the start edge has to carry the way back, and
    // "רעיון חדש" moves in beside the other actions. A page you cannot leave is
    // worse than a button you have to look for.
    final bool pushed = widget.focusMatchId != null;

    return Scaffold(
      // **The bar says "הרעיונות שלי", and the search row is pinned to it.** The
      // heading used to be the first line of the page and the field the second,
      // both of them folding away on a scroll — which is exactly when a list
      // long enough to scroll wants its search. The name is in the banner and
      // the field hangs off it; what is still allowed to fold is only the part
      // that is genuinely optional, the category buttons.
      //
      // The count line under the heading is gone with it. "12 רעיונות פעילים"
      // was a number nobody acts on — the category buttons directly below carry
      // the same figure per kind, which is the form it is actually read in.
      appBar: ShadchanAppBar(
        title: 'הרעיונות שלי',
        leading: pushed ? const BackButton() : null,
        // The bell, the "+" and the overflow menu, exactly as בית and המאגר
        // שלי wear them — see [ShadchanTabActions].
        actions: <Widget>[
          ShadchanTabActions(
            add: ShadchanAddButton(
              tooltip: 'רעיון חדש',
              onPressed: () => context.push('/matches/add'),
            ),
          ),
        ],
        bottom: ShadchanSearchBottom(
          child: ShadchanSearchField(
            controller: _searchController,
            hintText: 'חיפוש לפי שם',
            onCleared: _closeSearch,
          ),
        ),
      ),
      // The results panel is laid over the page while there is a query, the
      // way it is on בית and המאגר שלי: the categories and the list underneath
      // still narrow, and the panel is the short way straight to one proposal.
      // See [SearchResultsPanel].
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              // **The category buttons are pinned under the search row.** They
              // sit outside the scrolling list, directly below the bar the field
              // hangs off, so the five counts and the way between the five
              // shelves are on screen however far down a list of forty somebody
              // has gone. The one thing that folds them away is a proposal's
              // action panel opening underneath — see [_headerHidden].
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.bottomCenter,
                child: _headerHidden
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // **The two blocks that used to open the home
                          // screen.** "כל הכבוד! X זוגות שלך יוצאים" and
                          // "רעיונות שהמאגר מציע לך" were both invitations into
                          // this page, sitting on the page before it; they are
                          // at the head of the page they were about now, which
                          // is one tap shorter and two blocks of home screen
                          // cheaper. They fold away with the category buttons
                          // while a proposal's actions are open — see
                          // [_headerHidden].
                          //
                          // Not drawn during a search: what somebody typing a
                          // name wants is the proposals that match it, not two
                          // banners above them.
                          if (!searching && datingCount > 0)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: DatingCouplesStrip(
                                count: datingCount,
                                onTap: () => setState(
                                  () => _category = MatchCategory.dating,
                                ),
                              ),
                            ),
                          // Held back until the database is big enough to keep
                          // producing pairs — below fifty friends the well runs
                          // dry and the row becomes a promise the app cannot
                          // keep.
                          if (!searching &&
                              personRepository.databaseCount >
                                  HomeConfig.databaseIdeasMinFriends)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: HomeHeroBand(
                                onShowIdeas: () => context.push('/ideas/new'),
                              ),
                            ),
                          // Drawn during a search too. Which kinds of proposal a
                          // person has — two open, one closed — is exactly what
                          // somebody typing their name wants to know, and hiding
                          // the split at the moment they ask was the one time it
                          // mattered most.
                          _CategoryButtons(
                            selected: _category,
                            counts: <MatchCategory, int>{
                              for (final MatchCategory category
                                  in MatchCategory.values)
                                category: groups[category]!.length,
                            },
                            onSelected: (MatchCategory category) =>
                                setState(() => _category = category),
                          ),
                          // The row of name chips that used to hang here is
                          // gone. It completed a half-typed name, which was the
                          // best answer available when a search could only
                          // filter the list; the panel over this page answers
                          // the same question by naming the actual proposals
                          // and opening the one that is tapped, and a strip of
                          // chips behind the panel's scrim is unreachable.
                        ],
                      ),
              ),
              Expanded(
                child: _buildCategory(
                  theme,
                  groups,
                  dueReminders,
                  personRepository,
                  searching: searching,
                ),
              ),
            ],
          ),
          if (searching) _buildSearchPanel(population, personRepository),
        ],
      ),
    );
  }

  /// Live results over the list, capped at half the screen.
  ///
  /// **A search that only filters is half an answer.** Typing a name used to
  /// narrow the five categories and leave the proposal somewhere inside
  /// whichever of them it belongs to — which still means finding it. Each row
  /// here opens that proposal directly.
  ///
  /// The population is the one the page already computed, so the panel and the
  /// counts above it can never disagree about what the query matched.
  Widget _buildSearchPanel(
    List<MatchIdea> population,
    PersonRepository personRepository,
  ) {
    return SearchResultsPanel(
      onDismiss: _closeSearch,
      rows: <Widget>[
        for (final MatchIdea match in population)
          _searchRow(match, personRepository),
      ],
    );
  }

  Widget _searchRow(MatchIdea match, PersonRepository personRepository) {
    final Person? personA = personRepository.getById(match.personAId);
    final Person? personB = personRepository.getById(match.personBId);
    final String names =
        '${personA?.fullName ?? 'לא ידוע'} · ${personB?.fullName ?? 'לא ידוע'}';

    return SearchResultRow(
      leading: SearchResultCouple(a: personA, b: personB),
      title: names,
      subtitle: '${match.status.icon} ${match.status.displayName}',
      onTap: () {
        _closeSearch();
        pushLeavingSearch(context, '/matches/${match.id}');
      },
    );
  }

  /// Leaves search: the panel and the keyboard.
  void _closeSearch() {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() {});
  }

  // --- Grouping -----------------------------------------------------------

  /// Newest first inside every category.
  Map<MatchCategory, List<MatchIdea>> _groupMatches(
    List<MatchIdea> matches,
    PersonRepository personRepository,
  ) {
    final Map<MatchCategory, List<MatchIdea>> groups =
        <MatchCategory, List<MatchIdea>>{
          for (final MatchCategory category in MatchCategory.values)
            category: <MatchIdea>[],
        };

    for (final MatchIdea match in matches) {
      final Person? personA = personRepository.getById(match.personAId);
      final Person? personB = personRepository.getById(match.personBId);
      final MatchProposalTab? tab = matchProposalTabFor(
        status: match.status,
        anyPersonArchived:
            (personA?.profileStatus.isArchived ?? false) ||
            (personB?.profileStatus.isArchived ?? false),
        anyPersonPaused:
            (personA?.profileStatus.pausesMatches ?? false) ||
            (personB?.profileStatus.pausesMatches ?? false),
      );
      switch (tab) {
        case MatchProposalTab.open:
          groups[MatchCategory.all]!.add(match);
          groups[MatchCategory.open]!.add(match);
        case MatchProposalTab.waiting:
          groups[MatchCategory.all]!.add(match);
          groups[MatchCategory.waiting]!.add(match);
        case MatchProposalTab.dating:
          groups[MatchCategory.all]!.add(match);
          groups[MatchCategory.dating]!.add(match);
        case MatchProposalTab.dated:
        case MatchProposalTab.rejected:
        case MatchProposalTab.weddings:
          groups[MatchCategory.closed]!.add(match);
        case null:
          break;
      }
    }

    for (final List<MatchIdea> group in groups.values) {
      group.sort(_byFocusThenNewest);
    }
    return groups;
  }

  /// Newest first — except the proposal somebody followed a link to, which is
  /// first whatever its date. See [MatchesScreen.focusMatchId].
  int _byFocusThenNewest(MatchIdea a, MatchIdea b) {
    final String? focus = widget.focusMatchId;
    if (focus != null) {
      if (a.id == focus) {
        return -1;
      }
      if (b.id == focus) {
        return 1;
      }
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  /// Proposals whose reminder date has arrived. A reminder set for the future
  /// is not one of them.
  List<MatchIdea> _dueReminders(List<MatchIdea> matches) {
    final DateTime today = DateTime.now();
    final DateTime endOfToday = DateTime(
      today.year,
      today.month,
      today.day,
      23,
      59,
      59,
    );

    final List<MatchIdea> due = matches.where((MatchIdea match) {
      final DateTime? date = match.reminderDate;
      return date != null &&
          !date.isAfter(endOfToday) &&
          !match.status.isArchived;
    }).toList();
    due.sort(
      (MatchIdea a, MatchIdea b) => a.reminderDate!.compareTo(b.reminderDate!),
    );
    return due;
  }

  // --- Lists --------------------------------------------------------------

  Widget _buildCategory(
    ThemeData theme,
    Map<MatchCategory, List<MatchIdea>> groups,
    List<MatchIdea> dueReminders,
    PersonRepository personRepository, {
    required bool searching,
  }) {
    if (_category == MatchCategory.closed) {
      return _buildClosed(
        groups[MatchCategory.closed]!,
        personRepository,
        searching: searching,
      );
    }

    // The due-reminder list sits at the top of the broad live views whatever
    // the proposals' own status is.
    final bool showReminders =
        (_category == MatchCategory.all || _category == MatchCategory.open) &&
        dueReminders.isNotEmpty;
    // **And each of them appears exactly once.** A proposal lifted to the top
    // because its reminder came due used to be drawn a second time further
    // down, in its ordinary place — the same pair, the same card, twice on one
    // screen, which reads as a bug every time and makes the list longer than
    // the work in it.
    final Set<String> remindedIds = showReminders
        ? <String>{for (final MatchIdea match in dueReminders) match.id}
        : const <String>{};
    final List<MatchIdea> matches = showReminders
        ? groups[_category]!
              .where((MatchIdea match) => !remindedIds.contains(match.id))
              .toList()
        : groups[_category]!;

    if (matches.isEmpty && !showReminders) {
      return searching
          ? const EmptyState(
              icon: Icons.search,
              title: 'לא נמצאו תוצאות',
              subtitle: '{נסה|נסי} לחפש בשם אחר, או {בחר|בחרי} סוג אחר למעלה',
            )
          : _emptyState(_category);
    }

    return ListView(
      controller: _listScroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        if (showReminders) ...<Widget>[
          _RemindersHeader(count: dueReminders.length),
          for (final MatchIdea match in dueReminders)
            _card(match, personRepository, isDueReminder: true),
          const SizedBox(height: 8),
          Text(
            _category == MatchCategory.all
                ? 'כל הרעיונות הפעילים (${matches.length})'
                : 'כל הרעיונות הפתוחים (${matches.length})',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final MatchIdea match in matches) _card(match, personRepository),
      ],
    );
  }

  Widget _buildClosed(
    List<MatchIdea> closed,
    PersonRepository personRepository, {
    required bool searching,
  }) {
    final List<MatchIdea> rejected = closed
        .where((MatchIdea m) => m.status == MatchStatus.rejected)
        .toList();
    final List<MatchIdea> dated = closed
        .where(
          (MatchIdea m) =>
              m.status == MatchStatus.dated || m.status == MatchStatus.married,
        )
        .toList();
    final List<MatchIdea> shown = _closedTab == _ClosedTab.rejected
        ? rejected
        : dated;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<_ClosedTab>(
            showSelectedIcon: false,
            segments: <ButtonSegment<_ClosedTab>>[
              ButtonSegment<_ClosedTab>(
                value: _ClosedTab.rejected,
                label: Text('רעיונות שנדחו (${rejected.length})'),
              ),
              ButtonSegment<_ClosedTab>(
                value: _ClosedTab.dated,
                label: Text('זוגות שיצאו (${dated.length})'),
              ),
            ],
            selected: <_ClosedTab>{_closedTab},
            onSelectionChanged: (Set<_ClosedTab> selection) =>
                setState(() => _closedTab = selection.first),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? EmptyState(
                  icon: _closedTab == _ClosedTab.rejected
                      ? Icons.cancel_outlined
                      : Icons.history,
                  title: searching
                      ? 'לא נמצאו תוצאות'
                      : _closedTab == _ClosedTab.rejected
                      ? 'אין רעיונות שנדחו'
                      : 'אין זוגות שיצאו',
                  subtitle: 'מה שיסתיים יופיע כאן',
                )
              : ListView(
                  controller: _listScroll,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  children: <Widget>[
                    for (final MatchIdea match in shown)
                      _card(match, personRepository),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _card(
    MatchIdea match,
    PersonRepository personRepository, {
    bool isDueReminder = false,
  }) {
    final Person? personA = personRepository.getById(match.personAId);
    final Person? personB = personRepository.getById(match.personBId);

    Person? male = personA;
    Person? female = personB;
    if (personA?.gender == Gender.female || personB?.gender == Gender.male) {
      male = personB;
      female = personA;
    }

    return MatchIdeaCard(
      match: match,
      male: male,
      female: female,
      compact: false,
      highlighted: isDueReminder || match.id == widget.focusMatchId,
      onActionsOpenChanged: (bool open) => _handleCardActions(match.id, open),
      onLongPress: () => _confirmDelete(match, female, male),
      // Only computed for a couple who are actually out — every other card
      // would be reading the whole status ledger for a line it never draws.
      datingSince: match.status == MatchStatus.dating
          ? DatingCheckIn.startedAt(
              match,
              events: context.read<MatchRepository>().getAllStatusEvents(),
            )
          : null,
      onAdvance: (MatchNextStep step) => MatchQuickActions.advance(
        context,
        match,
        step,
        female: female,
        male: male,
      ),
      onSetStage: (MatchStage stage) => MatchQuickActions.setStage(
        context,
        match,
        stage,
        female: female,
        male: male,
      ),
      onCheckInWith: (Person person) {
        final DateTime? since = DatingCheckIn.startedAt(
          match,
          events: context.read<MatchRepository>().getAllStatusEvents(),
        );
        if (since == null) {
          return;
        }
        MatchQuickActions.checkInOnCouple(
          context,
          match,
          person: person,
          startedAt: since,
        );
      },
      onChangeCheckInFrequency: (int days) =>
          context.read<MatchRepository>().setCheckInFrequency(match.id, days),
      // **Tapping a proposal compares the two cards.** It used to open a page
      // of its own, which existed to hold the actions that now live on the card
      // itself — so what is actually left to want from a proposal is to read
      // the two people side by side and decide.
      onTap: () => _compare(female, male),
      onOpenPersonWhatsApp: (Person person) =>
          _openWhatsApp(person, identical(person, male) ? female : male),
      onCompletePersonCard: (Person person) =>
          context.push('/people/${person.id}/edit'),
      // Everything a matchmaker does after a round of phone calls — this one is
      // on a break, that one is out, close that one — is doable from the list.
      // Opening a proposal to change one word was the reason statuses went
      // stale.
      onPersonStatusPicked: (Person person, ProfileStatus status) =>
          MatchQuickActions.setPersonStatus(context, person, status),
      onQuickAction: (MatchQuickAction action) => MatchQuickActions.run(
        context,
        action,
        match,
        female: female,
        male: male,
      ),
    );
  }

  Widget _emptyState(MatchCategory category) {
    switch (category) {
      case MatchCategory.all:
        return EmptyState(
          icon: Icons.favorite_border,
          title: 'אין רעיונות פעילים',
          subtitle: '{צור|צרי} רעיון חדש בין שני חברים',
          buttonText: 'רעיון חדש',
          onButtonPressed: () => context.push('/matches/add'),
        );
      case MatchCategory.open:
        return EmptyState(
          icon: Icons.favorite_border,
          title: 'אין רעיונות פתוחים',
          subtitle: '{צור|צרי} רעיון חדש בין שני חברים',
          buttonText: 'רעיון חדש',
          onButtonPressed: () => context.push('/matches/add'),
        );
      case MatchCategory.waiting:
        return const EmptyState(
          icon: Icons.pause_circle_outline,
          title: 'אין רעיונות בהמתנה',
          subtitle: 'רעיון שאחד הצדדים בו לא פנוי יופיע כאן',
        );
      case MatchCategory.dating:
        return const EmptyState(
          icon: Icons.volunteer_activism_outlined,
          title: 'אין זוגות שיוצאים',
          subtitle: 'זוגות בתהליך יופיעו כאן',
        );
      case MatchCategory.closed:
        return const EmptyState(
          icon: Icons.archive_outlined,
          title: 'עוד לא נסגרו רעיונות',
          subtitle: 'מה שיסתיים יופיע כאן',
        );
    }
  }

  // --- Actions ------------------------------------------------------------

  /// The two candidates facing each other — the same comparison "התאמות" and
  /// "רעיונות חדשים" open, so a pair is always weighed in one place.
  Future<void> _compare(Person? female, Person? male) async {
    if (female == null || male == null) {
      _snack('אחד הצדדים כבר לא קיים במאגר');
      return;
    }
    await openMatchComparison(
      context,
      source: female,
      candidate: male,
      // The proposal already exists — this is only the side-by-side look.
      showOpenIdeaAction: false,
    );
  }

  Future<void> _promote(MatchIdea match, Person? female, Person? male) {
    return MatchQuickActions.promote(
      context,
      match,
      female: female,
      male: male,
    );
  }

  /// One side's chat button. Who is being written to is already decided by
  /// which face was tapped; all that is left is whether the other side's card
  /// goes with it, and [PersonWhatsAppMenu] only asks when there is one.
  Future<void> _openWhatsApp(Person person, Person? other) async {
    final bool launched = await PersonWhatsAppMenu.open(
      context,
      person: person,
      other: other,
    );
    if (!launched) {
      _snack('לא הצלחנו לפתוח את וואטסאפ');
    }
  }

  /// A brand-new proposal opens its share sheet by itself, once.
  void _scheduleSharePrompt() {
    final String? matchId = widget.promptShareForMatchId;
    if (matchId == null || _promptedShare) {
      return;
    }
    _promptedShare = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final MatchRepository matches = context.read<MatchRepository>();
      final PersonRepository people = context.read<PersonRepository>();
      final MatchIdea? match = matches.getById(matchId);
      if (match == null) {
        return;
      }
      final Person? personA = people.getById(match.personAId);
      final Person? personB = people.getById(match.personBId);
      final bool aIsFemale = personA?.gender == Gender.female;
      await _promote(
        match,
        aIsFemale ? personA : personB,
        aIsFemale ? personB : personA,
      );
    });
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    AppNotice.show(context, message);
  }

  void _handleSearchChanged() {
    setState(() {});
  }
}

/// The five category buttons, each carrying its own count.
///
/// **They do not scroll.** They used to sit in a horizontal strip, which meant
/// that on any ordinary phone the last one or two were off the edge — so the
/// closed pile, and sometimes "יוצאים", were invisible until somebody thought
/// to swipe a row that gives no sign it can be swiped. Five buttons fit across
/// a phone if the label goes above the number instead of beside it, so that is
/// what they do: the whole map of the screen, visible at once.
class _CategoryButtons extends StatelessWidget {
  const _CategoryButtons({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final MatchCategory selected;
  final Map<MatchCategory, int> counts;
  final ValueChanged<MatchCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: <Widget>[
          for (final MatchCategory category in MatchCategory.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _CategoryButton(
                  label: category.displayName,
                  count: counts[category] ?? 0,
                  isSelected: selected == category,
                  // The closed pile is deliberately quieter than the live ones.
                  isMuted: category == MatchCategory.closed,
                  theme: theme,
                  onTap: () => onSelected(category),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.isMuted,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final bool isMuted;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = isMuted
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.primary;

    return Material(
      color: isSelected
          ? accent.withValues(alpha: 0.14)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // The name on top and the number under it. Scaled down rather
              // than wrapped, so "בהמתנה" in a narrow column stays one line and
              // every button keeps the same height.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? accent : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "ביקשת שנזכיר לך" — the heading over the due-reminder cards.
class _RemindersHeader extends StatelessWidget {
  const _RemindersHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.secondary.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'ביקשת שנזכיר לך ($count)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'הגיע הזמן לבדוק מה קורה עם הרעיונות האלה',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
