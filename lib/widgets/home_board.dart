import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/board_add_sheet.dart';
import 'package:shadchan/dialogs/home_board_actions.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/dialogs/support_chat_sheet.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/support_inbox_provider.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_navigation.dart';
import 'package:shadchan/utils/card_updates_seen.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/home_board_feed.dart';
import 'package:shadchan/utils/home_open_ideas.dart';
import 'package:shadchan/utils/idea_recency.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/utils/new_idea_suggestions.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/widgets/accent_stripe.dart';
import 'package:shadchan/widgets/board_row.dart';
import 'package:shadchan/widgets/card_inbox_list.dart';
import 'package:shadchan/widgets/card_invite.dart';
import 'package:shadchan/widgets/home_panels.dart';
import 'package:shadchan/widgets/home_section.dart';

/// "הלוח שלי": everything the matchmaker is working on, as one mixed feed.
///
/// **One feed, five shelves to look through it.** The rows are cards and
/// access (friends whose card is shared with the matchmaker, and friends who
/// wrote one and have not shared it yet), alerts (reminders that came due,
/// the bell's notices, whatever was pinned), every open proposal with its
/// next step, and pairs the database suggests. "הכל" mixes every shelf the
/// matchmaker chose to see there — newest activity first, then what asks
/// most of them, never one shelf for long (see [HomeBoardFeed.arrange]); each
/// shelf's own chip shows all of it.
///
/// **The bell and the board both show a notice, deliberately.** The bell is
/// where notices are kept; the board is where work is done. A notice opened
/// from either goes to the very thing it is about.
///
/// **"הסרה מהלוח שלי" takes a row off the board and nothing else.** The
/// friend, the card, the proposal and the notice stay exactly as they were,
/// and a row whose subject moves again comes back (see [HomeBoardStore.hide]).
///
/// **A framed window that scrolls inside itself**, three and a half rows
/// high, so its bottom edge is always on screen; a thumb that reaches either
/// end of it carries on scrolling the page rather than getting stuck.
class HomeBoardSection extends StatefulWidget {
  const HomeBoardSection({
    super.key,
    required this.focusKey,
    required this.entries,
    required this.openIdeas,
    required this.personRepository,
    required this.matchRepository,
    required this.refresh,
  });

  final Key focusKey;

  /// The pinned entries, newest first.
  final List<HomeBoardEntry> entries;

  /// Every proposal that is open right now. See [HomeOpenIdeas].
  final List<HomeOpenIdea> openIdeas;

  final PersonRepository personRepository;
  final MatchRepository matchRepository;

  /// Bumped by a tap on the wordmark: back to the top of the board.
  final int refresh;

  @override
  State<HomeBoardSection> createState() => _HomeBoardSectionState();
}

T? _maybeWatch<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

class _HomeBoardSectionState extends State<HomeBoardSection> {
  /// How many whole rows the window shows before it scrolls; half a row more
  /// peeks out under them, so the list plainly goes on.
  static const int _windowRows = 3;

  /// One row: a two-line card plus the gap under it.
  static const double _rowExtent = AccentBar.rowHeight + 6;

  /// A notice already read stays on the board this long.
  static const Duration _readNoticeFor = Duration(days: 7);

  final ScrollController _listScroll = ScrollController();

  BoardCategory _chip = BoardCategory.all;

  /// The database's own pairs, worked out once per state of the database.
  String? _pairsKey;
  List<NewIdeaSuggestion> _pairs = const <NewIdeaSuggestion>[];

  @override
  void didUpdateWidget(covariant HomeBoardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refresh != oldWidget.refresh && _listScroll.hasClients) {
      _listScroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _listScroll.dispose();
    super.dispose();
  }

  void _select(BoardCategory chip) {
    if (chip == _chip) {
      return;
    }
    setState(() => _chip = chip);
    if (_listScroll.hasClients) {
      _listScroll.jumpTo(0);
    }
  }

  List<NewIdeaSuggestion> _loadPairs(
    List<Person> everyone,
    List<MatchIdea> matches,
  ) {
    DateTime latest = DateTime(2000);
    for (final Person p in everyone) {
      if (p.updatedAt.isAfter(latest)) {
        latest = p.updatedAt;
      }
    }
    for (final MatchIdea m in matches) {
      if (m.updatedAt.isAfter(latest)) {
        latest = m.updatedAt;
      }
    }
    final String key =
        '${everyone.length}|${matches.length}|'
        '${latest.millisecondsSinceEpoch}|'
        '${DateUtils.dateOnly(DateTime.now())}';
    if (key != _pairsKey) {
      _pairsKey = key;
      final List<List<NewIdeaSuggestion>> rounds = NewIdeaSuggestions.batches(
        NewIdeaSuggestions.build(
          people: everyone,
          matches: matches,
          dismissedFor: SuggestionDismissals.dismissedFor,
        ),
      );
      _pairs = rounds.isEmpty ? const <NewIdeaSuggestion>[] : rounds.first;
    }
    return _pairs;
  }

  /// Every row the board could show, unplaced.
  List<BoardFeedEntry<_BoardItem>> _collect(BuildContext context) {
    final DateTime now = DateTime.now();
    final HomeBoardStore store = HomeBoardStore.instance;
    final PersonRepository people = widget.personRepository;
    final MatchRepository matches = widget.matchRepository;
    final InboxProvider? inbox = _maybeWatch<InboxProvider>(context);
    final CardAccessProvider? access = _maybeWatch<CardAccessProvider>(context);
    final SupportInboxProvider? support = _maybeWatch<SupportInboxProvider>(
      context,
    );
    final bool supportAdmin =
        _maybeWatch<AccountProvider>(context)?.isSupportAdmin ?? false;

    // Taken off with "הסרה מהלוח שלי": stays off until something new
    // happens in it.
    bool removed(String key, DateTime activityAt) {
      final DateTime? at = store.hiddenAt(key);
      return at != null && !activityAt.isAfter(at);
    }

    final List<BoardFeedEntry<_BoardItem>> out = <BoardFeedEntry<_BoardItem>>[];
    final List<PersonEvent> events = people.getAllEvents();
    final List<MatchIdea> allMatches = matches.getAll();

    // --- Cards and access -------------------------------------------------
    final Map<String, PersonEvent> lastCardEvent = <String, PersonEvent>{};
    for (final PersonEvent e in events) {
      if (e.type != PersonEventType.cardSynced) {
        continue;
      }
      final PersonEvent? known = lastCardEvent[e.personId];
      if (known == null || e.createdAt.isAfter(known.createdAt)) {
        lastCardEvent[e.personId] = e;
      }
    }
    final Set<String> linkedOwners = <String>{};
    for (final Person person in people.getAll()) {
      final String? owner = person.cardOwnerUid;
      if (owner == null || person.hidden) {
        continue;
      }
      linkedOwners.add(owner);
      final PersonEvent? last = lastCardEvent[person.id];
      final DateTime at = last?.createdAt ?? person.updatedAt;
      final String key = 'card:${person.id}';
      if (removed(key, at)) {
        continue;
      }
      final bool updated = CardUpdatesSeen.fresh(
        events.where((PersonEvent e) => e.personId == person.id),
        person.id,
        now: now,
      ).isNotEmpty;
      out.add(
        BoardFeedEntry<_BoardItem>(
          value: _BoardItem.sharedCard(
            key: key,
            person: person,
            line: updated && last != null
                ? last.text
                : 'יש לך גישה לכרטיס · {הוא מעדכן|היא מעדכנת} אותו בעצמ{ו|ה}'
                      .forGender(person.gender),
            fresh: updated && BoardSeen.isNew(key, at),
          ),
          category: BoardCategory.cards,
          priority: BoardPriority.cardChange,
          activityAt: at,
        ),
      );
    }

    final Set<String> announced = <String>{};
    for (final InboxItem item in inbox?.items ?? const <InboxItem>[]) {
      final DateTime at = item.createdAt ?? now;
      final String key = 'inbox:${item.id}';
      if (item.kind == 'accessApproved') {
        // The friend whose card it is stands on the board in its place.
        continue;
      }
      if (item.kind == 'cardCreated') {
        final String? owner = item.ownerUid;
        if (owner == null ||
            linkedOwners.contains(owner) ||
            !announced.add(owner) ||
            removed(key, at)) {
          continue;
        }
        final CardAccess? standing = access?.accessTo(owner);
        if (standing?.status == CardAccessStatus.approved ||
            standing?.status == CardAccessStatus.blocked) {
          continue;
        }
        final bool asked = standing?.status == CardAccessStatus.pending;
        final String? hash = item.ownerPhoneHash;
        final Person? person =
            people.findByCardOwner(owner) ??
            (hash == null || hash.isEmpty
                ? null
                : people.findByPhoneHash(hash));
        out.add(
          BoardFeedEntry<_BoardItem>(
            value: _BoardItem.newCard(
              key: key,
              notice: item,
              person: person,
              asked: asked,
              fresh: !asked && !item.read && BoardSeen.isNew(key, at),
            ),
            category: BoardCategory.cards,
            priority: asked ? BoardPriority.cardChange : BoardPriority.action,
            activityAt: at,
          ),
        );
        continue;
      }
      if (item.read && now.difference(at) > _readNoticeFor) {
        continue;
      }
      if (removed(key, at)) {
        continue;
      }
      out.add(
        BoardFeedEntry<_BoardItem>(
          value: _BoardItem.notice(key: key, notice: item, fresh: !item.read),
          category: BoardCategory.alerts,
          priority: !item.read && item.offersWhatsApp
              ? BoardPriority.action
              : BoardPriority.alert,
          activityAt: at,
        ),
      );
    }

    for (final SupportThread thread
        in support?.threads ?? const <SupportThread>[]) {
      if (!thread.unread) {
        continue;
      }
      final DateTime at =
          thread.report.lastMessageAt ?? thread.report.createdAt;
      final String key = 'support:${thread.report.id}';
      if (removed(key, at)) {
        continue;
      }
      out.add(
        BoardFeedEntry<_BoardItem>(
          value: _BoardItem.support(
            key: key,
            report: thread.report,
            asAdmin: supportAdmin,
          ),
          category: BoardCategory.alerts,
          priority: BoardPriority.alert,
          activityAt: at,
        ),
      );
    }

    // --- Reminders, pins and open ideas ----------------------------------
    final Map<String, DateTime> pinnedAt = <String, DateTime>{
      for (final HomeBoardEntry e in widget.entries)
        HomeBoardStore.itemKey(e.kind, e.targetId): e.addedAt,
    };
    final Map<String, DateTime> recency = IdeaRecency.of(
      matches: allMatches,
      statusEvents: matches.getAllStatusEvents(),
      personEvents: events,
    );
    final Set<String> placed = <String>{};

    for (final HomeOpenIdea open in widget.openIdeas) {
      final MatchIdea match = open.match;
      final String key = HomeBoardStore.itemKey(HomeItemKind.idea, match.id);
      final DateTime? reminder = match.reminderDate;
      final bool due = reminder != null && !reminder.isAfter(now);
      DateTime at = recency[match.id] ?? match.createdAt;
      for (final DateTime? moved in <DateTime?>[
        match.askedMaleAt,
        match.askedFemaleAt,
        match.lastShareAt,
        if (due) reminder,
        pinnedAt[key],
      ]) {
        if (moved != null && moved.isAfter(at) && !moved.isAfter(now)) {
          at = moved;
        }
      }
      placed.add(key);
      if (removed(key, at)) {
        continue;
      }
      out.add(
        BoardFeedEntry<_BoardItem>(
          value: _BoardItem.record(
            key: key,
            kind: HomeItemKind.idea,
            targetId: match.id,
            reminder: due ? (match.reminderNote ?? '') : null,
            pinned: pinnedAt.containsKey(key),
            fresh: due && BoardSeen.isNew(key, reminder),
          ),
          category: due ? BoardCategory.alerts : BoardCategory.openIdeas,
          alsoIn: due
              ? const <BoardCategory>{BoardCategory.openIdeas}
              : const <BoardCategory>{},
          priority: due ? BoardPriority.alert : BoardPriority.openIdea,
          activityAt: at,
        ),
      );
    }

    // A reminder that came due on a friend, or on an idea that is not open.
    final List<(HomeItemKind, String, DateTime, String)> due =
        <(HomeItemKind, String, DateTime, String)>[];
    PersonReminders.all().forEach((String personId, DateTime at) {
      if (!at.isAfter(now) && people.getById(personId) != null) {
        due.add((
          HomeItemKind.person,
          personId,
          at,
          PersonReminders.noteFor(personId) ?? '',
        ));
      }
    });
    for (final MatchIdea match in allMatches) {
      final DateTime? at = match.reminderDate;
      if (at != null && !at.isAfter(now)) {
        due.add((HomeItemKind.idea, match.id, at, match.reminderNote ?? ''));
      }
    }
    for (final (HomeItemKind kind, String id, DateTime at, String note)
        in due) {
      final String key = HomeBoardStore.itemKey(kind, id);
      if (!placed.add(key) || removed(key, at)) {
        continue;
      }
      out.add(
        BoardFeedEntry<_BoardItem>(
          value: _BoardItem.record(
            key: key,
            kind: kind,
            targetId: id,
            reminder: note,
            pinned: pinnedAt.containsKey(key),
            fresh: BoardSeen.isNew(key, at),
          ),
          category: BoardCategory.alerts,
          priority: BoardPriority.alert,
          activityAt: at,
        ),
      );
    }

    // Whatever was pinned by hand and is not on the board already.
    for (final HomeBoardEntry pin in widget.entries) {
      final String key = HomeBoardStore.itemKey(pin.kind, pin.targetId);
      final bool exists = pin.kind == HomeItemKind.person
          ? people.getById(pin.targetId) != null
          : matches.getById(pin.targetId) != null;
      if (!exists || !placed.add(key)) {
        continue;
      }
      out.add(
        BoardFeedEntry<_BoardItem>(
          value: _BoardItem.record(
            key: key,
            kind: pin.kind,
            targetId: pin.targetId,
            pinned: true,
          ),
          category: BoardCategory.alerts,
          priority: BoardPriority.alert,
          activityAt: pin.addedAt,
        ),
      );
    }

    // --- What the database suggests --------------------------------------
    final List<Person> everyone = people.getAll();
    for (final NewIdeaSuggestion pair in _loadPairs(everyone, allMatches)) {
      final String key = HomeBoardStore.pairKey(pair.male.id, pair.female.id);
      final DateTime? hidden = store.hiddenAt(key);
      if (matches.findExisting(pair.male.id, pair.female.id) != null ||
          SuggestionDismissals.isDismissed(pair.male.id, pair.female.id) ||
          (hidden != null &&
              now.difference(hidden) < const Duration(days: 30))) {
        continue;
      }
      // A pair became possible when the newer of the two joined.
      final DateTime at = pair.male.createdAt.isAfter(pair.female.createdAt)
          ? pair.male.createdAt
          : pair.female.createdAt;
      out.add(
        BoardFeedEntry<_BoardItem>(
          value: _BoardItem.pair(key: key, pair: pair),
          category: BoardCategory.suggestions,
          priority: BoardPriority.suggestion,
          activityAt: at,
        ),
      );
    }
    return out;
  }

  double _windowHeight(BuildContext context, int rows) {
    final double shown = rows > _windowRows
        ? _windowRows + 0.5
        : rows.toDouble();
    return homeScaled(context, _rowExtent * shown);
  }

  /// The inner list reached an end under the finger: the page carries on
  /// instead, so a thumb is never stuck inside the board.
  bool _handOver(OverscrollNotification note) {
    if (note.dragDetails == null) {
      return false;
    }
    final ScrollableState? page = Scrollable.maybeOf(context);
    if (page == null) {
      return false;
    }
    final ScrollPosition position = page.position;
    final double target = (position.pixels + note.overscroll).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) {
      position.jumpTo(target);
    }
    return true;
  }

  Future<void> _customise() async {
    final Set<BoardCategory>? chosen = await showDialog<Set<BoardCategory>>(
      context: context,
      builder: (BuildContext context) =>
          _CustomiseDialog(initial: BoardAllCategories.shown),
    );
    if (chosen == null || !mounted) {
      return;
    }
    BoardAllCategories.shown = chosen;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    // Nothing to put on a board before the first friend.
    if (widget.personRepository.databaseCount == 0 && widget.entries.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final List<BoardFeedEntry<_BoardItem>> arranged = HomeBoardFeed.arrange(
      _collect(context),
      now: DateTime.now(),
    );
    final Set<BoardCategory> inAll = BoardAllCategories.shown;
    final List<BoardFeedEntry<_BoardItem>> shown = HomeBoardFeed.forChip(
      arranged,
      _chip,
      inAll: inAll,
    );
    final int datingCount = widget.matchRepository
        .getAll()
        .where((MatchIdea match) => match.status == MatchStatus.dating)
        .length;
    final Color warm = dark ? AppColors.secondaryDarkDm : AppColors.secondary;

    return SliverToBoxAdapter(
      child: Column(
        key: widget.focusKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const HomeSectionHeader(
            title: 'הלוח שלי',
            subtitle: 'כרטיסים, התראות ורעיונות – הכל במקום אחד',
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: homeHorizontalInset(context),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  warm.withValues(alpha: dark ? 0.14 : 0.13),
                  theme.scaffoldBackgroundColor,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: warm.withValues(alpha: 0.55),
                  width: 1.4,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _ChipRow(
                      selected: _chip,
                      onSelected: _select,
                      onCustomise: _customise,
                      allNarrowed: inAll.length < BoardCategory.kinds.length,
                    ),
                    const SizedBox(height: 6),
                    if (datingCount > 0 && _chip == BoardCategory.all)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: DatingCouplesStrip(
                          count: datingCount,
                          compact: true,
                          onTap: () => context.go('/matches?statuses=dating'),
                        ),
                      ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Text(
                          _chip == BoardCategory.all && inAll.isEmpty
                              ? 'כל הקטגוריות כבויות בתצוגת „הכל”'
                              : _chip.emptyLine,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    else
                      SizedBox(
                        height: _windowHeight(context, shown.length),
                        child: NotificationListener<OverscrollNotification>(
                          onNotification: _handOver,
                          child: Scrollbar(
                            controller: _listScroll,
                            thumbVisibility: shown.length > _windowRows,
                            child: ListView.builder(
                              controller: _listScroll,
                              physics: const ClampingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: shown.length,
                              itemBuilder: (BuildContext context, int i) =>
                                  _BoardRow(
                                    key: ValueKey<String>(shown[i].value.key),
                                    item: shown[i].value,
                                    personRepository: widget.personRepository,
                                    matchRepository: widget.matchRepository,
                                    onChanged: () => setState(() {}),
                                  ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              homeHorizontalInset(context),
              4,
              homeHorizontalInset(context),
              0,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => BoardAddSheet.show(context),
                style: TextButton.styleFrom(
                  foregroundColor: dark
                      ? AppColors.secondaryDarkDm
                      : AppColors.secondaryInk,
                  visualDensity: VisualDensity.compact,
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('הוספה ללוח'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shelves across the top of the board, and "התאמת הלוח שלי" at its end.
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.selected,
    required this.onSelected,
    required this.onCustomise,
    required this.allNarrowed,
  });

  final BoardCategory selected;
  final ValueChanged<BoardCategory> onSelected;
  final VoidCallback onCustomise;

  /// "הכל" leaves something out — the tune icon says so with a dot.
  final bool allNarrowed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.secondaryDarkDm : AppColors.secondaryInk;
    return Row(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final BoardCategory chip in BoardCategory.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: _Chip(
                      label: chip.label,
                      selected: chip == selected,
                      ink: ink,
                      onTap: () => onSelected(chip),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 34,
          height: 34,
          child: IconButton(
            tooltip: 'התאמת הלוח שלי',
            padding: EdgeInsets.zero,
            onPressed: onCustomise,
            icon: Badge(
              isLabelVisible: allNarrowed,
              smallSize: 7,
              backgroundColor: ink,
              child: Icon(Icons.tune_rounded, size: 20, color: ink),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: selected ? ink : theme.colorScheme.surface,
      shape: StadiumBorder(
        side: BorderSide(color: ink.withValues(alpha: selected ? 1 : 0.35)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? theme.colorScheme.surface : ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// "התאמת הלוח שלי": which shelves "הכל" mixes.
class _CustomiseDialog extends StatefulWidget {
  const _CustomiseDialog({required this.initial});

  final Set<BoardCategory> initial;

  @override
  State<_CustomiseDialog> createState() => _CustomiseDialogState();
}

class _CustomiseDialogState extends State<_CustomiseDialog> {
  late final Set<BoardCategory> _on = <BoardCategory>{...widget.initial};

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('התאמת הלוח שלי'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'מה יופיע בתצוגת „הכל”?',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final BoardCategory c in BoardCategory.kinds)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _on.contains(c),
                title: Text(c.label),
                onChanged: (bool? value) => setState(() {
                  if (value ?? false) {
                    _on.add(c);
                  } else {
                    _on.remove(c);
                  }
                }),
              ),
            const SizedBox(height: 4),
            Text(
              'כיבוי רק מסתיר מ„הכל”: שום דבר לא נמחק, ההתראות ממשיכות, '
              'והקטגוריה עדיין מוצגת בלשונית שלה.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_on),
          child: const Text('שמירה'),
        ),
      ],
    );
  }
}

enum _ItemType { record, sharedCard, newCard, notice, support, pair }

/// One row of the board, whatever it is about.
class _BoardItem {
  const _BoardItem._({
    required this.type,
    required this.key,
    this.kind,
    this.targetId,
    this.reminder,
    this.pinned = false,
    this.fresh = false,
    this.person,
    this.line,
    this.notice,
    this.asked = false,
    this.report,
    this.asAdmin = false,
    this.pair,
  });

  /// A friend or a proposal; [reminder] is non-null when one came due.
  const _BoardItem.record({
    required String key,
    required HomeItemKind kind,
    required String targetId,
    String? reminder,
    bool pinned = false,
    bool fresh = false,
  }) : this._(
         type: _ItemType.record,
         key: key,
         kind: kind,
         targetId: targetId,
         reminder: reminder,
         pinned: pinned,
         fresh: fresh,
       );

  /// A friend whose card is shared with the matchmaker.
  const _BoardItem.sharedCard({
    required String key,
    required Person person,
    required String line,
    required bool fresh,
  }) : this._(
         type: _ItemType.sharedCard,
         key: key,
         person: person,
         line: line,
         fresh: fresh,
       );

  /// A friend who wrote a card of their own and has not shared it yet.
  const _BoardItem.newCard({
    required String key,
    required InboxItem notice,
    required Person? person,
    required bool asked,
    required bool fresh,
  }) : this._(
         type: _ItemType.newCard,
         key: key,
         notice: notice,
         person: person,
         asked: asked,
         fresh: fresh,
       );

  /// One of the bell's notices.
  const _BoardItem.notice({
    required String key,
    required InboxItem notice,
    required bool fresh,
  }) : this._(type: _ItemType.notice, key: key, notice: notice, fresh: fresh);

  /// A support conversation that moved.
  const _BoardItem.support({
    required String key,
    required SupportReport report,
    required bool asAdmin,
  }) : this._(
         type: _ItemType.support,
         key: key,
         report: report,
         asAdmin: asAdmin,
         fresh: true,
       );

  /// A pair "רעיונות שהמאגר מציע לך" offers.
  const _BoardItem.pair({required String key, required NewIdeaSuggestion pair})
    : this._(type: _ItemType.pair, key: key, pair: pair);

  final _ItemType type;

  /// What "הסרה מהלוח שלי" and "seen" are recorded under.
  final String key;

  final HomeItemKind? kind;
  final String? targetId;
  final String? reminder;
  final bool pinned;
  final bool fresh;
  final Person? person;
  final String? line;
  final InboxItem? notice;
  final bool asked;
  final SupportReport? report;
  final bool asAdmin;
  final NewIdeaSuggestion? pair;
}

/// One row, drawn the way the app draws a row: one accent bar for a person
/// in their own colour, two for a couple — the man's blue at the reading
/// start (the right), the woman's pink at the end, in the order of the names
/// and the faces.
class _BoardRow extends StatelessWidget {
  const _BoardRow({
    super.key,
    required this.item,
    required this.personRepository,
    required this.matchRepository,
    required this.onChanged,
  });

  final _BoardItem item;
  final PersonRepository personRepository;
  final MatchRepository matchRepository;

  /// Something about the board changed without a repository noticing.
  final VoidCallback onChanged;

  void _seen() => BoardSeen.mark(item.key);

  @override
  Widget build(BuildContext context) {
    return switch (item.type) {
      _ItemType.record => _record(context),
      _ItemType.sharedCard => _sharedCard(context),
      _ItemType.newCard => _newCard(context),
      _ItemType.notice => _notice(context),
      _ItemType.support => _support(context),
      _ItemType.pair => _pair(context),
    };
  }

  Widget _row(
    BuildContext context, {
    required Widget leading,
    required String title,
    required Color startAccent,
    required VoidCallback onTap,
    required List<_MenuChoice> menu,
    Color? endAccent,
    String? subtitle,
    IconData? mark,
    Widget? action,
  }) {
    final Widget menuButton = _MenuButton(choices: menu);
    return BoardRow(
      leading: leading,
      title: title,
      startAccent: startAccent,
      endAccent: endAccent,
      subtitle: subtitle,
      mark: mark,
      boldTitle: false,
      fresh: item.fresh,
      onTap: onTap,
      onLongPress: (BuildContext anchor) => _MenuButton.open(anchor, menu),
      menu: action == null
          ? menuButton
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[action, menuButton],
            ),
    );
  }

  _MenuChoice _removeChoice(BuildContext context) => _MenuChoice(
    'הסרה מהלוח שלי',
    () => HomeBoardActions.removeFromBoard(context, item.key),
  );

  // --- A friend or a proposal --------------------------------------------

  Widget _record(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final HomeItemKind kind = item.kind!;
    final String targetId = item.targetId!;
    final String? note = HomeBoardStore.instance
        .noteFor(kind, targetId)
        ?.trim();
    final String? reminder = item.reminder?.trim();
    final String? reminderLine = reminder == null
        ? null
        : reminder.isEmpty
        ? 'הגיע מועד התזכורת'
        : 'תזכורת: $reminder';
    final IconData? mark = item.pinned
        ? Icons.push_pin
        : reminder != null
        ? Icons.notifications_active_outlined
        : null;
    final bool hasReminder = kind == HomeItemKind.person
        ? personRepository.personReminderFor(targetId) != null
        : matchRepository.getById(targetId)?.reminderDate != null;
    final bool hasNote = note != null && note.isNotEmpty;
    final List<_MenuChoice> menu = <_MenuChoice>[
      _MenuChoice(
        hasReminder ? 'עריכת תזכורת' : 'הוספת תזכורת',
        () => HomeBoardActions.editReminder(context, kind, targetId),
      ),
      _MenuChoice(
        hasNote ? 'עריכת הערה' : 'הוספת הערה',
        () => HomeBoardActions.editNote(context, kind, targetId),
      ),
      if (HomeBoardStore.instance.contains(kind, targetId))
        _MenuChoice(
          'הסרת הצמדה',
          () => HomeBoardActions.remove(context, kind, targetId),
        )
      else
        _MenuChoice('הצמדה', () => HomeBoardStore.instance.add(kind, targetId)),
      _removeChoice(context),
    ];

    if (kind == HomeItemKind.person) {
      final Person? person = personRepository.getById(targetId);
      if (person == null) {
        return const SizedBox.shrink();
      }
      return _row(
        context,
        leading: HomeCardAvatar(person: person, radius: 18),
        title: person.fullName.trim(),
        subtitle: (note != null && note.isNotEmpty) ? note : reminderLine,
        mark: mark,
        startAccent: AppColors.genderAccent(person.gender, dark: dark),
        onTap: () {
          _seen();
          AppNavigation.open(context, '/people/${person.id}');
        },
        menu: menu,
      );
    }

    final MatchIdea? match = matchRepository.getById(targetId);
    if (match == null) {
      return const SizedBox.shrink();
    }
    final Person? personA = personRepository.getById(match.personAId);
    final Person? personB = personRepository.getById(match.personBId);
    final bool swap =
        personA?.gender == Gender.female || personB?.gender == Gender.male;
    final Person? male = swap ? personB : personA;
    final Person? female = swap ? personA : personB;
    final MatchNextStep? step = MatchStages.nextStep(match);
    final String? stepLine = step == null
        ? null
        : MatchStages.shortLabel(step, male: male, female: female);
    return _row(
      context,
      leading: HomeCardCoupleAvatars(
        personA: male,
        personB: female,
        radius: 15,
      ),
      title: '${_firstName(male)} & ${_firstName(female)}',
      // What the matchmaker wrote wins the line, then the reminder, then the
      // next step the ideas page would offer.
      subtitle: (note != null && note.isNotEmpty)
          ? note
          : reminderLine ?? stepLine,
      mark: mark,
      startAccent: AppColors.genderAccent(Gender.male, dark: dark),
      endAccent: AppColors.genderAccent(Gender.female, dark: dark),
      onTap: () {
        _seen();
        AppNavigation.open(context, '/matches/${match.id}');
      },
      menu: menu,
    );
  }

  // --- Cards and access ----------------------------------------------------

  Widget _sharedCard(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Person person = item.person!;
    return _row(
      context,
      leading: HomeCardAvatar(person: person, radius: 18),
      title: person.fullName.trim(),
      subtitle: item.line,
      mark: Icons.badge_outlined,
      startAccent: AppColors.genderAccent(person.gender, dark: dark),
      onTap: () {
        _seen();
        AppNavigation.open(context, '/people/${person.id}?focus=card');
      },
      menu: <_MenuChoice>[_removeChoice(context)],
    );
  }

  Widget _newCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final InboxItem notice = item.notice!;
    final Person? person = item.person;
    final String name = person?.fullName.trim() ?? notice.title;
    final Gender gender = person?.gender ?? Gender.unknown;
    final String line = item.asked
        ? 'הבקשה לגישה נשלחה · ממתינה לאישור'
        : person == null
        ? notice.body
        : '{יצר|יצרה} כרטיס אישי · אפשר לבקש גישה'.forGender(gender);
    final String? ownerUid = notice.ownerUid;
    final String? hash = notice.ownerPhoneHash;
    final bool canAsk =
        !item.asked &&
        person != null &&
        ownerUid != null &&
        hash != null &&
        hash.isNotEmpty;

    Future<void> ask() async {
      _seen();
      await context.read<InboxProvider>().markRead(notice);
      if (!context.mounted) {
        return;
      }
      await CardInviteFlow.requestAccess(
        context,
        person!,
        ownerUid: ownerUid!,
        ownerPhoneHash: hash!,
      );
      onChanged();
    }

    return _row(
      context,
      leading: person != null
          ? HomeCardAvatar(person: person, radius: 18)
          : CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.badge_outlined, size: 18),
            ),
      title: name,
      subtitle: line,
      startAccent: AppColors.genderAccent(gender, dark: dark),
      onTap: () {
        _seen();
        CardInboxList.openItem(context, notice);
      },
      action: canAsk
          ? TextButton(
              onPressed: ask,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('בקשת גישה'),
            )
          : null,
      menu: <_MenuChoice>[
        if (canAsk) _MenuChoice('בקשת גישה לכרטיס', ask),
        _removeChoice(context),
      ],
    );
  }

  // --- Notices ------------------------------------------------------------

  Widget _notice(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final InboxItem notice = item.notice!;
    final String? owner = notice.ownerUid;
    final String? hash = notice.ownerPhoneHash;
    final Person? person =
        (owner == null ? null : personRepository.findByCardOwner(owner)) ??
        (hash == null || hash.isEmpty
            ? null
            : personRepository.findByPhoneHash(hash));
    return _row(
      context,
      leading: person != null
          ? HomeCardAvatar(person: person, radius: 18)
          : CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                notice.kind == 'birthday'
                    ? Icons.cake_outlined
                    : Icons.notifications_none_rounded,
                size: 18,
              ),
            ),
      title: notice.title,
      subtitle: notice.body,
      mark: Icons.notifications_active_outlined,
      startAccent: person == null
          ? (dark ? AppColors.secondaryDarkDm : AppColors.secondary)
          : AppColors.genderAccent(person.gender, dark: dark),
      onTap: () {
        _seen();
        CardInboxList.openItem(context, notice);
      },
      menu: <_MenuChoice>[
        if (notice.offersWhatsApp)
          _MenuChoice(
            'שליחת ברכה בוואטסאפ',
            () => CardInboxList.sendGreeting(context, notice),
          ),
        _removeChoice(context),
      ],
    );
  }

  Widget _support(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final SupportReport report = item.report!;
    final String title;
    if (item.asAdmin) {
      final String who = report.authorName.trim().isEmpty
          ? 'שולח לא מזוהה'
          : report.authorName.trim();
      title = 'שיחה עם $who';
    } else {
      title = report.lastMessageFromAdmin
          ? 'תשובה מצוות שדכן'
          : 'הפנייה שלך — שיחה פתוחה';
    }
    return _row(
      context,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.forum_outlined, size: 18),
      ),
      title: title,
      subtitle: report.text,
      mark: Icons.notifications_active_outlined,
      startAccent: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
      onTap: () {
        _seen();
        SupportChatSheet.show(context, report, asAdmin: item.asAdmin);
      },
      menu: <_MenuChoice>[_removeChoice(context)],
    );
  }

  // --- What the database suggests --------------------------------------------

  Widget _pair(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final NewIdeaSuggestion pair = item.pair!;
    return _row(
      context,
      leading: HomeCardCoupleAvatars(
        personA: pair.male,
        personB: pair.female,
        radius: 15,
      ),
      title: '${_firstName(pair.male)} & ${_firstName(pair.female)}',
      subtitle: pair.reasons.isEmpty
          ? 'רעיון שהמאגר מציע לך'
          : 'הצעה מהמאגר · ${pair.reasons.join(' · ')}',
      startAccent: AppColors.genderAccent(Gender.male, dark: dark),
      endAccent: AppColors.genderAccent(Gender.female, dark: dark),
      onTap: () => _considerPair(context, pair),
      menu: <_MenuChoice>[
        _MenuChoice('פתיחת רעיון', () => _considerPair(context, pair)),
        _MenuChoice('לא מתאים', () async {
          await SuggestionDismissals.dismiss(pair.male.id, pair.female.id);
          onChanged();
        }),
        _removeChoice(context),
      ],
    );
  }

  /// The two cards facing each other, and a proposal if the matchmaker agrees
  /// — the same route "רעיונות שהמאגר מציע לך" takes.
  Future<void> _considerPair(
    BuildContext context,
    NewIdeaSuggestion pair,
  ) async {
    final bool? open = await openMatchComparison(
      context,
      source: pair.male,
      candidate: pair.female,
    );
    if (open != true || !context.mounted) {
      return;
    }
    final MatchIdea? created = await matchRepository.create(
      pair.male.id,
      pair.female.id,
    );
    if (created == null || !context.mounted) {
      return;
    }
    await MatchQuickActions.promote(
      context,
      created,
      female: pair.female,
      male: pair.male,
    );
  }
}

/// One line of a row's menu.
class _MenuChoice {
  const _MenuChoice(this.label, this.run);

  final String label;
  final VoidCallback run;
}

/// A row's "⋯" — and the same menu, hung from the row, on a long press. A
/// long press never removes anything by itself: it only opens this.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.choices});

  final List<_MenuChoice> choices;

  static Future<void> open(
    BuildContext anchor,
    List<_MenuChoice> choices,
  ) async {
    final RenderBox? box = anchor.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize) {
      return;
    }
    final ThemeData theme = Theme.of(anchor);
    final Offset topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final int? picked = await showMenu<int>(
      context: anchor,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          topLeft.dx,
          topLeft.dy + box.size.height,
          box.size.width,
          0,
        ),
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: 190),
      color: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      items: <PopupMenuEntry<int>>[
        for (int i = 0; i < choices.length; i++)
          PopupMenuItem<int>(value: i, child: Text(choices[i].label)),
      ],
    );
    if (picked != null && anchor.mounted) {
      choices[picked].run();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (BuildContext anchor) => IconButton(
        tooltip: 'פעולות',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.more_horiz, size: 20),
        onPressed: () => open(anchor, choices),
      ),
    );
  }
}

String _firstName(Person? person) {
  if (person == null) {
    return '—';
  }
  final String first = person.firstName.trim();
  return first.isNotEmpty ? first : person.fullName.trim();
}
