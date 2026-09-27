import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/dialogs/person_whatsapp_menu.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/dating_check_in.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/utils/reminder_alerts.dart';
import 'package:shadchan/utils/search_navigation.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/match_idea_card.dart';
import 'package:shadchan/widgets/search_results_panel.dart';
import 'package:shadchan/widgets/shadchan_app_bar.dart';
import 'package:shadchan/utils/app_navigation.dart';
import 'package:shadchan/utils/back_interceptor.dart';

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

  /// One proposal to open the list on: its category is chosen, the list is
  /// scrolled to where it stands, and it is lit up.
  ///
  /// **This is what is left of `/matches/:id`.** A proposal used to have a page
  /// of its own, and every link in the app — a reminder, a notification, a home
  /// card — pushed it. There is no such page now: the card carries everything
  /// the page did. So those links land here instead, and rather than dropping
  /// the reader at the top of a list of forty and letting them hunt, the list
  /// opens scrolled to the proposal they asked for, which wears the accent.
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

  /// Ideas swiped off the top this session. Held here as well as on disk so
  /// the swiped card leaves the block on the very next frame — a `Dismissible`
  /// still in the tree after its dismissal is an error.
  final Map<String, DateTime?> _takenOffTop = <String, DateTime?>{};

  Future<void> _takeOffTop(MatchIdea match) async {
    final OverlayState? notices = AppNotice.capture(context);
    final DateTime? reminder = match.reminderDate;
    setState(() => _takenOffTop[match.id] = reminder);
    await ReminderAlerts.takeOffTop(match.id, reminder);
    AppNotice.showOn(
      notices,
      'הרעיון חזר למקומו ברשימה',
      atBottom: true,
      actionLabel: 'ביטול',
      onAction: () async {
        await ReminderAlerts.putBackOnTop(match.id);
        if (mounted) {
          setState(() => _takenOffTop.remove(match.id));
        }
      },
    );
  }

  /// Which proposals have their action panel open right now.
  ///
  /// Owned here rather than in the cards because it is a fact about the
  /// *screen*: with something open, the list is being worked in rather than
  /// scanned, and the row of category tiles over it folds away to give the
  /// panel the room. See the header block in [build].
  final Set<String> _openCards = <String>{};

  /// Ticked to close every open panel at once.
  final ValueNotifier<int> _closeActions = ValueNotifier<int>(0);

  /// **Back closes "פעולות" first.** With a proposal's actions open, the
  /// first back press folds them away and leaves the reader on this page; only
  /// the next one leaves it.
  bool _handleBack() {
    if (_openCards.isEmpty || !mounted || !BackInterceptor.isInFront(context)) {
      return false;
    }
    _closeActions.value++;
    return true;
  }

  /// On the focused proposal's card, so the list can be scrolled to it.
  final GlobalKey _focusKey = GlobalKey();

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

  /// Whether the two banners at the head of the page are folded away.
  ///
  /// Only while a proposal's actions are open, and only until the reader has
  /// scrolled a screenful away from that panel and left it for [_awayAfter].
  /// The category row is **not** part of this any more: it is one compact line
  /// pinned under the search field and stays there whatever is open.
  bool get _headerHidden => _openCards.isNotEmpty && !_awayFromOpenCard;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _listScroll.addListener(_handleScroll);
    BackInterceptor.add(_handleBack);
    _category = widget.initialShowArchived
        ? MatchCategory.closed
        : _categoryFor(widget.initialStatuses);
    if (widget.initialStatuses.contains(MatchStatus.dated) ||
        widget.initialStatuses.contains(MatchStatus.married)) {
      _closedTab = _ClosedTab.dated;
    }
    _openOnFocus();
    _scheduleSharePrompt();
  }

  /// Opens the list where the focused proposal is: on the category that holds
  /// it (a closed one is not in "הכל"), then scrolled until its card is in
  /// front of the reader.
  void _openOnFocus() {
    final String? focus = widget.focusMatchId;
    if (focus == null) {
      return;
    }
    final MatchRepository matches = context.read<MatchRepository>();
    final MatchIdea? match = matches.getById(focus);
    if (match == null) {
      return;
    }
    final Map<MatchCategory, List<MatchIdea>> groups = _groupMatches(
      matches.getAll(),
      context.read<PersonRepository>(),
    );
    if (groups[MatchCategory.closed]!.any((MatchIdea m) => m.id == focus)) {
      _category = MatchCategory.closed;
      _closedTab = match.status == MatchStatus.rejected
          ? _ClosedTab.rejected
          : _ClosedTab.dated;
    } else if (!groups[MatchCategory.all]!.any(
      (MatchIdea m) => m.id == focus,
    )) {
      return;
    } else if (groups[MatchCategory.waiting]!.any(
      (MatchIdea m) => m.id == focus,
    )) {
      // A proposal that is waiting is shown in the waiting list itself — which
      // is where a status change that paused it sends the matchmaker to see
      // where it went. See [MatchQuickActions.setPersonStatus].
      _category = MatchCategory.waiting;
    } else {
      _category = MatchCategory.all;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus(0));
  }

  /// The cards are built lazily, so a card further down has no context until
  /// the list comes near it: step down a screen at a time until it is built,
  /// then bring it into view.
  void _scrollToFocus(int attempt) {
    if (!mounted || !_listScroll.hasClients) {
      return;
    }
    final BuildContext? target = _focusKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        alignment: 0.15,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    final ScrollPosition position = _listScroll.position;
    if (attempt > 40 || position.pixels >= position.maxScrollExtent) {
      return;
    }
    _listScroll.jumpTo(
      (position.pixels + position.viewportDimension * 0.8).clamp(
        0,
        position.maxScrollExtent,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToFocus(attempt + 1),
    );
  }

  @override
  void dispose() {
    BackInterceptor.remove(_handleBack);
    _closeActions.dispose();
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
  /// **Never straight away.** Nothing in the app is deleted by a long press
  /// alone: it asks first, and only a "מחיקה" deletes. After that it still
  /// says so at the bottom with "ביטול", and the idea is filed in "רעיונות
  /// שנמחקו" for a month.
  Future<void> _confirmDelete(
    MatchIdea match,
    Person? female,
    Person? male,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final MatchRepository repository = context.read<MatchRepository>();
    final PersonRepository people = context.read<PersonRepository>();
    final OverlayState? overlay = AppNotice.capture(context);
    final String names = <String>[
      if (female != null) female.firstName,
      if (male != null) male.firstName,
    ].where((String name) => name.trim().isNotEmpty).join(' ו');
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'למחוק את הרעיון?',
      message: names.isEmpty
          ? 'הרעיון והיומן שלו יימחקו. אפשר לשחזר אותו מ"רעיונות שנמחקו" במשך חודש.'
          : 'הרעיון של $names והיומן שלו יימחקו. אפשר לשחזר אותו מ"רעיונות שנמחקו" במשך חודש.',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }
    final String id = match.id;
    await repository.deleteMatch(id);
    if (overlay == null || !overlay.mounted) {
      return;
    }
    AppNotice.showOn(
      overlay,
      'הרעיון נמחק',
      atBottom: true,
      actionLabel: 'ביטול',
      onAction: () {
        repository.restoreDeleted(
          id,
          personExists: (String personId) => people.getById(personId) != null,
        );
      },
    );
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
    // A name picked from the suggestions narrows the page to exactly that
    // person's ideas — not to whatever else the typed letters happen to match.
    final String? personFilter = _personFilterId;
    final List<MatchIdea> population = !searching
        ? matchRepository.getAll()
        : personFilter != null
        ? matchRepository.getByPersonId(personFilter)
        : matchRepository.search(query, personRepository);
    final Map<MatchCategory, List<MatchIdea>> groups = _groupMatches(
      population,
      personRepository,
    );
    final List<MatchIdea> dueReminders = searching
        ? const <MatchIdea>[]
        : _dueReminders(matchRepository.getAll());

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
            onSubmitted: (_) => _submitSearch(),
            onTap: _reopenSuggestions,
          ),
        ),
      ),
      // The results panel is laid over the page while there is a query, the
      // way it is on בית and המאגר שלי: the categories and the list underneath
      // still narrow, and the panel is the short way straight to one proposal.
      // See [SearchResultsPanel].
      body: Stack(
        children: <Widget>[
          _buildBody(
            theme,
            groups,
            dueReminders,
            personRepository,
            searching: searching,
          ),
          if (searching && _suggestionsOpen)
            _buildSearchPanel(
              query,
              matchRepository.search(query, personRepository),
              personRepository,
            ),
        ],
      ),
    );
  }

  /// The page under the search panel: the two banners, the pinned category
  /// row, and whichever list the category asks for — **all in one scroll
  /// view**.
  ///
  /// **The banners scroll away and the counts do not.** They used to sit
  /// together in a block outside the list, which pinned all of it: the two
  /// invitations at the head of the page stayed on screen through forty
  /// proposals, taking a third of the phone with them and saying nothing new
  /// after the first second. They are ordinary content now — first in the
  /// scroll view, above everything — and only the category row is pinned, so
  /// it rides up over them and parks against the search field the moment they
  /// have gone by. That is the one part of this header somebody scrolling a
  /// long list actually reaches for.
  ///
  /// One `CustomScrollView` rather than a column of a header and a list,
  /// because a pinned row *between* two scrolling things is exactly what a
  /// sliver is and nothing else does it.
  Widget _buildBody(
    ThemeData theme,
    Map<MatchCategory, List<MatchIdea>> groups,
    List<MatchIdea> dueReminders,
    PersonRepository personRepository, {
    required bool searching,
  }) {
    // "רעיונות שהמאגר מציע לך" is an invitation into this page, so it sits at
    // its head. (The couples-who-are-out strip moved to הלוח שלי on the home
    // screen.) It folds away with the category row while a proposal's actions
    // are open — see [_headerHidden].
    //
    // Not drawn during a search: what somebody typing a name wants is the
    // proposals that match it, not a banner above them.
    final List<Widget> banners = <Widget>[
      // Held back until the database is big enough to keep producing pairs —
      // below fifty friends the well runs dry and the row becomes a promise
      // the app cannot keep.
      if (!searching &&
          !_headerHidden &&
          personRepository.databaseCount > HomeConfig.databaseIdeasMinFriends)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: HomeHeroBand(
            onShowIdeas: () => AppNavigation.open(context, '/ideas/new'),
          ),
        ),
    ];

    return CustomScrollView(
      controller: _listScroll,
      slivers: <Widget>[
        if (banners.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(mainAxisSize: MainAxisSize.min, children: banners),
          ),
        // Drawn during a search too. Which kinds of proposal a person has —
        // two open, one closed — is exactly what somebody typing their name
        // wants to know, and hiding the split at the moment they ask was the
        // one time it mattered most.
        // Always pinned, including while a proposal's actions are open: it is
        // the way between the shelves, and it is one compact line.
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedCategories(
            // Opaque, because the banners pass underneath it.
            background: theme.scaffoldBackgroundColor,
            extent: _CategoryChips.heightFor(context),
            child: _CategoryChips(
              selected: _category,
              counts: <MatchCategory, int>{
                for (final MatchCategory category in MatchCategory.values)
                  category: groups[category]!.length,
              },
              onSelected: (MatchCategory category) =>
                  setState(() => _category = category),
            ),
          ),
        ),
        ..._categorySlivers(
          theme,
          groups,
          dueReminders,
          personRepository,
          searching: searching,
        ),
      ],
    );
  }

  /// Live results over the list, capped at half the screen.
  ///
  /// **A search that only filters is half an answer.** Typing a name used to
  /// narrow the five categories and leave the proposal somewhere inside
  /// whichever of them it belongs to — which still means finding it. Each row
  /// here opens that proposal directly.
  ///
  /// **Two kinds of answer, one under the other.** First the people whose
  /// name matches — choosing one narrows the page to every idea they are in —
  /// then the ideas themselves, each of which opens directly. Both follow the
  /// typing letter by letter; the search key still shows every match without
  /// choosing either.
  Widget _buildSearchPanel(
    String query,
    List<MatchIdea> matches,
    PersonRepository personRepository,
  ) {
    final String needle = query.trim().toLowerCase();
    final Map<String, Person> people = <String, Person>{};
    final Map<String, int> ideaCounts = <String, int>{};
    for (final MatchIdea match in matches) {
      for (final String id in <String>[match.personAId, match.personBId]) {
        final Person? person = personRepository.getById(id);
        if (person == null ||
            !MatchRepository.personMatchesQuery(person, needle)) {
          continue;
        }
        people[id] = person;
        ideaCounts[id] = (ideaCounts[id] ?? 0) + 1;
      }
    }
    final List<Person> named = people.values.toList()
      ..sort(
        (Person a, Person b) =>
            (ideaCounts[b.id] ?? 0).compareTo(ideaCounts[a.id] ?? 0),
      );

    return SearchResultsPanel(
      // A tap beside the suggestions is "show me the results", like the
      // search key — not "forget what I typed".
      onDismiss: _submitSearch,
      rows: <Widget>[
        if (named.isNotEmpty) const SearchSectionTitle('אנשים'),
        for (final Person person in named.take(6))
          SearchResultRow(
            leading: SearchResultRow.avatar(person),
            title: person.fullName,
            subtitle: ideaCounts[person.id] == 1
                ? 'רעיון אחד · הצגת הרעיון'
                : '${ideaCounts[person.id]} רעיונות · הצגת כל הרעיונות',
            onTap: () => _filterByPerson(person),
          ),
        if (matches.isNotEmpty) const SearchSectionTitle('רעיונות'),
        for (final MatchIdea match in matches)
          _searchRow(match, personRepository),
      ],
    );
  }

  /// A name chosen from the suggestions: the field says who, the panel closes,
  /// and the page underneath is every idea that person is in.
  void _filterByPerson(Person person) {
    FocusManager.instance.primaryFocus?.unfocus();
    final String name = person.fullName;
    // Set before the text, so the listener does not read the change as new
    // typing and let go of the person again.
    _lastQuery = name;
    _searchController.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    setState(() {
      _personFilterId = person.id;
      _suggestionsOpen = false;
    });
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
    setState(() => _personFilterId = null);
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

  /// Newest first. The proposal somebody followed a link to keeps its own
  /// place — the list is scrolled to it instead. See
  /// [MatchesScreen.focusMatchId].
  int _byFocusThenNewest(MatchIdea a, MatchIdea b) {
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
          !match.status.isArchived &&
          _takenOffTop[match.id] != date &&
          !ReminderAlerts.isTakenOffTop(match.id, date);
    }).toList();
    due.sort(
      (MatchIdea a, MatchIdea b) => a.reminderDate!.compareTo(b.reminderDate!),
    );
    return due;
  }

  // --- Lists --------------------------------------------------------------

  /// The list under the pinned category row, as slivers.
  ///
  /// Slivers rather than a `ListView` inside an `Expanded`: the row above has
  /// to pin against the search field while these scroll past it, and two
  /// scroll views cannot do that between them.
  List<Widget> _categorySlivers(
    ThemeData theme,
    Map<MatchCategory, List<MatchIdea>> groups,
    List<MatchIdea> dueReminders,
    PersonRepository personRepository, {
    required bool searching,
  }) {
    if (_category == MatchCategory.closed) {
      return _closedSlivers(
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
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: searching
              ? const EmptyState(
                  icon: Icons.search,
                  title: 'לא נמצאו תוצאות',
                  subtitle:
                      '{נסה|נסי} לחפש בשם אחר, או {בחר|בחרי} סוג אחר למעלה',
                )
              : _emptyState(_category),
        ),
      ];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        sliver: SliverList.list(
          children: <Widget>[
            if (showReminders) ...<Widget>[
              _RemindersHeader(count: dueReminders.length),
              // A sideways swipe takes one off the top and back to its own
              // place in the list below. The idea and its reminder are left
              // exactly as they were.
              for (final MatchIdea match in dueReminders)
                Dismissible(
                  key: ValueKey<String>('lifted-${match.id}'),
                  background: const _OffTopBackground(),
                  onDismissed: (_) => _takeOffTop(match),
                  child: _card(match, personRepository, isDueReminder: true),
                ),
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
            for (final MatchIdea match in matches)
              _card(match, personRepository),
          ],
        ),
      ),
    ];
  }

  List<Widget> _closedSlivers(
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

    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
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
      ),
      if (shown.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: _closedTab == _ClosedTab.rejected
                ? Icons.cancel_outlined
                : Icons.history,
            title: searching
                ? 'לא נמצאו תוצאות'
                : _closedTab == _ClosedTab.rejected
                ? 'אין רעיונות שנדחו'
                : 'אין זוגות שיצאו',
            subtitle: 'מה שיסתיים יופיע כאן',
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverList.list(
            children: <Widget>[
              for (final MatchIdea match in shown)
                _card(match, personRepository),
            ],
          ),
        ),
    ];
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
      key: match.id == widget.focusMatchId ? _focusKey : null,
      match: match,
      male: male,
      female: female,
      compact: false,
      highlighted: isDueReminder || match.id == widget.focusMatchId,
      onActionsOpenChanged: (bool open) => _handleCardActions(match.id, open),
      closeActions: _closeActions,
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
          MatchQuickActions.setPersonStatus(
            context,
            person,
            status,
            preferMatchId: match.id,
          ),
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

  /// The query as the suggestions last saw it — the controller also notifies
  /// on a caret move, which must not reopen a panel the reader just closed.
  String _lastQuery = '';

  /// Whether the suggestions are laid over the page.
  ///
  /// **Suggestions are a shortcut, not the search.** They open while typing,
  /// and the search key (or a tap outside them) closes them and leaves the
  /// query in place: the page underneath is then every idea that matches, the
  /// way a search works in any other app.
  bool _suggestionsOpen = false;

  /// The person chosen from the suggestions, while the field still holds
  /// their name. Any new typing lets go of them.
  String? _personFilterId;

  void _handleSearchChanged() {
    final String text = _searchController.text;
    if (text != _lastQuery) {
      _lastQuery = text;
      _suggestionsOpen = text.trim().isNotEmpty;
      _personFilterId = null;
    }
    setState(() {});
  }

  /// Enter / search: every matching idea, no panel over them.
  void _submitSearch() {
    FocusScope.of(context).unfocus();
    setState(() => _suggestionsOpen = false);
  }

  /// A tap back into a field that still holds a query shows its suggestions.
  void _reopenSuggestions() {
    if (_searchController.text.trim().isNotEmpty && !_suggestionsOpen) {
      setState(() => _suggestionsOpen = true);
    }
  }
}

/// The five categories on one compact line, each carrying its own count.
///
/// **Chips again, and all five on screen.** The row was a strip of chips that
/// scrolled sideways, which hid the last one or two on an ordinary phone, and
/// then five tall two-line buttons, which were a third of the header. Now each
/// chip is a share of the row, its name and count on one line and scaled down
/// rather than cut, so the whole map of the screen fits in one short line.
/// The pinned host for [_CategoryChips].
///
/// A `SliverPersistentHeader` has to be told its height in advance — a sliver
/// negotiates extent before it lays its child out — so the row's height is
/// computed from the text styles it is about to use rather than measured. See
/// [_CategoryChips.heightFor]; the row centres itself in whatever it is
/// given, so an over-estimate is a few spare pixels and never a clipped
/// button.
///
/// Opaque, because the two banners scroll underneath it.
class _PinnedCategories extends SliverPersistentHeaderDelegate {
  const _PinnedCategories({
    required this.child,
    required this.extent,
    required this.background,
  });

  final Widget child;
  final double extent;
  final Color background;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: background,
      // No shadow at rest and none while pinned: the row's own outlined
      // buttons already separate it from whatever is passing behind, and an
      // elevation that appears mid-scroll reads as a second app bar arriving.
      elevation: 0,
      child: SizedBox.expand(child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedCategories oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.extent != extent ||
        oldDelegate.background != background;
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  /// What [_PinnedCategories] has to promise the sliver protocol: two lines of
  /// type through the reader's own text scale, plus paddings and borders, with
  /// a little slack — a few spare pixels cost nothing, a few missing ones clip
  /// every button.
  static double heightFor(BuildContext context) {
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final double lines =
        scaler.scale(_labelSize) * 1.3 + scaler.scale(_countSize) * 1.3;
    // 6 + 6 around the row, 5 + 5 inside a button, 1 + 1 of border, 4 slack.
    return 28 + lines;
  }

  final MatchCategory selected;
  final Map<MatchCategory, int> counts;
  final ValueChanged<MatchCategory> onSelected;

  static const double _labelSize = 13;
  static const double _countSize = 13;

  /// Each shelf in the colour its cards wear: הכל and פתוחים blue, בהמתנה
  /// copper, יוצאים rose — and the closed pile deliberately quieter, in grey.
  static Color accentOf(MatchCategory category, ThemeData theme) {
    final bool dark = theme.brightness == Brightness.dark;
    switch (category) {
      case MatchCategory.all:
      case MatchCategory.open:
        return AppColors.matchState(MatchStatus.idea, dark: dark);
      case MatchCategory.waiting:
        return AppColors.matchState(MatchStatus.unavailable, dark: dark);
      case MatchCategory.dating:
        return AppColors.matchState(MatchStatus.dating, dark: dark);
      case MatchCategory.closed:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // One size for all five labels, worked out from the longest of them
        // against the narrowest button — so they shrink together on a small
        // phone and stay equal, rather than each shrinking to its own
        // leftovers.
        final double inner = (constraints.maxWidth - 24) / 5 - 4 - 10;
        double widest = 0;
        for (final MatchCategory category in MatchCategory.values) {
          final TextPainter painter = TextPainter(
            text: TextSpan(
              text: category.displayName,
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: _labelSize,
                fontWeight: FontWeight.w800,
              ),
            ),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          widest = widest > painter.width ? widest : painter.width;
          painter.dispose();
        }
        final double scale = widest <= 0 || inner <= 0 || inner >= widest
            ? 1
            : inner / widest;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final MatchCategory category in MatchCategory.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _CategoryChip(
                      label: category.displayName,
                      labelSize: _labelSize * scale,
                      count: counts[category] ?? 0,
                      isSelected: selected == category,
                      accent: accentOf(category, theme),
                      theme: theme,
                      onTap: () => onSelected(category),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One category: its name on the first line, its count on the second.
///
/// **Every button is the same shape and the same size, whatever its number.**
/// The button's size comes from the row — five equal fifths, one fixed height
/// — and never from what is written in it; a count of 128 scales itself down
/// inside its own line rather than widening the button it sits in.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.labelSize,
    required this.count,
    required this.isSelected,
    required this.accent,
    required this.theme,
    required this.onTap,
  });

  final String label;

  /// Decided once for the whole row — see [_CategoryChips]. Every button is
  /// handed the same figure.
  final double labelSize;

  final int count;
  final bool isSelected;

  /// This shelf's own colour — see [_CategoryChips.accentOf].
  final Color accent;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(12);

    // A breath of the shelf's colour at rest and a little more when chosen —
    // enough to tell the shelves apart at a glance, never a saturated block.
    return Material(
      color: Color.alphaBlend(
        accent.withValues(alpha: isSelected ? 0.16 : 0.05),
        theme.colorScheme.surface,
      ),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: accent.withValues(alpha: isSelected ? 0.6 : 0.28),
              width: isSelected ? 1.3 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: labelSize,
                  height: 1.3,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? accent : theme.colorScheme.onSurface,
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$count',
                    maxLines: 1,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: _CategoryChips._countSize,
                      height: 1.3,
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
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
/// What shows under a reminder card while it is swiped aside: where it is
/// going, not a bin — nothing is deleted.
class _OffTopBackground extends StatelessWidget {
  const _OffTopBackground();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.south_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            'חזרה למקום ברשימה',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

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
