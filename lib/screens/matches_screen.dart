import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/dialogs/person_whatsapp_menu.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/match_idea_card.dart';
import 'package:shadchan/widgets/reminders_bell_button.dart';

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

  MatchCategory _category = MatchCategory.all;
  _ClosedTab _closedTab = _ClosedTab.rejected;
  bool _searchVisible = false;
  bool _promptedShare = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
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
    super.dispose();
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

    // Reached by following a link to one proposal, this screen is a pushed page
    // rather than the tab — so the start edge has to carry the way back, and
    // "רעיון חדש" moves in beside the other actions. A page you cannot leave is
    // worse than a button you have to look for.
    final bool pushed = widget.focusMatchId != null;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('רעיונות'),
        // Adding leads, so it sits at the start edge — the top right in RTL —
        // and searching sits at the far end, the top left.
        leading: pushed
            ? null
            : IconButton(
                tooltip: 'רעיון חדש',
                icon: const Icon(Icons.add),
                onPressed: () => context.push('/matches/add'),
              ),
        actions: <Widget>[
          if (pushed)
            IconButton(
              tooltip: 'רעיון חדש',
              icon: const Icon(Icons.add),
              onPressed: () => context.push('/matches/add'),
            ),
          // The same bell, in the same slot, as בית and המאגר שלי.
          const RemindersBellButton(),
          IconButton(
            tooltip: _searchVisible ? 'סגירת חיפוש' : 'חיפוש',
            icon: Icon(_searchVisible ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _searchController.clear();
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_searchVisible)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'חיפוש לפי שם',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _searchController.clear,
                        ),
                ),
              ),
            ),
          // Drawn during a search too. Which kinds of proposal a person has —
          // two open, one closed — is exactly what somebody typing their name
          // wants to know, and hiding the split at the moment they ask was the
          // one time it mattered most.
          _CategoryButtons(
            selected: _category,
            counts: <MatchCategory, int>{
              for (final MatchCategory category in MatchCategory.values)
                category: groups[category]!.length,
            },
            onSelected: (MatchCategory category) =>
                setState(() => _category = category),
          ),
          if (searching)
            _NameSuggestions(
              query: query,
              matches: population,
              personRepository: personRepository,
              onPick: (String name) {
                _searchController
                  ..text = name
                  ..selection = TextSelection.collapsed(offset: name.length);
              },
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
    );
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
                label: Text('הצעות שנדחו (${rejected.length})'),
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
                      ? 'אין הצעות שנדחו'
                      : 'אין זוגות שיצאו',
                  subtitle: 'מה שיסתיים יופיע כאן',
                )
              : ListView(
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

    // A proposal that is over, or a couple already out, has nothing to promote:
    // the "יאללה לקדם!" row is simply absent rather than offering to forward a
    // card that would confuse whoever received it.
    final bool promotable =
        !match.status.isArchived && match.status != MatchStatus.dating;

    return MatchIdeaCard(
      match: match,
      male: male,
      female: female,
      compact: false,
      highlighted: isDueReminder || match.id == widget.focusMatchId,
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
      onPromote: promotable ? () => _promote(match, female, male) : null,
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
          title: 'עוד לא נסגרו הצעות',
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

/// The names behind the letters already typed, offered as chips.
///
/// **The same thing the home screen's search bar does.** Typing "אב" there
/// answers with the people it could mean; typing it here used to answer only
/// with whole proposal cards, so a matchmaker who could not remember whether
/// they had filed somebody as "אבי" or "אביחי" had to keep guessing letters.
/// Tapping a chip completes the query rather than filtering by id, so the
/// result is exactly what the reader would have typed themselves.
class _NameSuggestions extends StatelessWidget {
  const _NameSuggestions({
    required this.query,
    required this.matches,
    required this.personRepository,
    required this.onPick,
  });

  final String query;
  final List<MatchIdea> matches;
  final PersonRepository personRepository;
  final ValueChanged<String> onPick;

  /// Enough to be useful, few enough to stay one line of chips.
  static const int _limit = 8;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String needle = query.toLowerCase();
    final Set<String> names = <String>{};

    for (final MatchIdea match in matches) {
      for (final String id in <String>[match.personAId, match.personBId]) {
        final Person? person = personRepository.getById(id);
        final String name = person?.fullName.trim() ?? '';
        if (name.isEmpty || name.toLowerCase() == needle) {
          continue;
        }
        if (name.toLowerCase().contains(needle)) {
          names.add(name);
        }
      }
      if (names.length >= _limit) {
        break;
      }
    }

    if (names.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        children: <Widget>[
          for (final String name in names.take(_limit))
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(name),
                labelStyle: theme.textTheme.labelMedium,
                onPressed: () => onPick(name),
              ),
            ),
        ],
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
