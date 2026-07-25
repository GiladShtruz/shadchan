import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/reminders_panel.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/match_idea_card.dart';

/// The four buckets a proposal can be looked at through. Order is the reading
/// order of the chips: open, waiting, dating, archive.
enum MatchCategory { open, waiting, dating, archive }

extension on MatchCategory {
  String get displayName {
    switch (this) {
      case MatchCategory.open:
        return 'פתוחים';
      case MatchCategory.waiting:
        return 'בהמתנה';
      case MatchCategory.dating:
        return 'יוצאים';
      case MatchCategory.archive:
        return 'ארכיון';
    }
  }
}

/// Which half of the archive is showing.
enum _ArchiveTab { rejected, dated }

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    this.initialShowArchived = false,
    this.initialStatuses = const <MatchStatus>[],
  });

  final bool initialShowArchived;
  final List<MatchStatus> initialStatuses;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  final TextEditingController _searchController = TextEditingController();

  MatchCategory _category = MatchCategory.open;
  _ArchiveTab _archiveTab = _ArchiveTab.rejected;
  bool _searchVisible = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _category = widget.initialShowArchived
        ? MatchCategory.archive
        : _categoryFor(widget.initialStatuses);
    if (widget.initialStatuses.contains(MatchStatus.dated) ||
        widget.initialStatuses.contains(MatchStatus.married)) {
      _archiveTab = _ArchiveTab.dated;
    }
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
      return MatchCategory.open;
    }
    switch (statuses.first) {
      case MatchStatus.dating:
        return MatchCategory.dating;
      case MatchStatus.unavailable:
        return MatchCategory.waiting;
      case MatchStatus.rejected:
      case MatchStatus.dated:
      case MatchStatus.married:
        return MatchCategory.archive;
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

    final List<MatchIdea> allMatches = matchRepository.getAll();
    final Map<MatchCategory, List<MatchIdea>> groups = _groupMatches(
      allMatches,
    );
    final List<MatchIdea> dueReminders = _dueReminders(allMatches);
    final String query = _searchController.text.trim();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('רעיונות'),
            SizedBox(width: 8),
            Icon(Icons.favorite, size: 18),
          ],
        ),
        leading: IconButton(
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
        actions: <Widget>[
          IconButton(
            tooltip: 'תזכורות',
            icon: Badge.count(
              count: dueReminders.length,
              isLabelVisible: dueReminders.isNotEmpty,
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () => RemindersPanel.show(context),
          ),
          IconButton(
            tooltip: 'רעיון חדש',
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/matches/add'),
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
          if (query.isEmpty)
            _CategoryChips(
              selected: _category,
              counts: <MatchCategory, int>{
                for (final MatchCategory category in MatchCategory.values)
                  category: groups[category]!.length,
              },
              onSelected: (MatchCategory category) =>
                  setState(() => _category = category),
            ),
          Expanded(
            child: query.isNotEmpty
                ? _buildSearchResults(
                    matchRepository.search(query, personRepository),
                    personRepository,
                  )
                : _buildCategory(theme, groups, dueReminders, personRepository),
          ),
        ],
      ),
    );
  }

  // --- Grouping -----------------------------------------------------------

  /// Newest first inside every category.
  Map<MatchCategory, List<MatchIdea>> _groupMatches(List<MatchIdea> matches) {
    final Map<MatchCategory, List<MatchIdea>> groups =
        <MatchCategory, List<MatchIdea>>{
          for (final MatchCategory category in MatchCategory.values)
            category: <MatchIdea>[],
        };

    for (final MatchIdea match in matches) {
      switch (match.status) {
        case MatchStatus.idea:
        case MatchStatus.checking:
          groups[MatchCategory.open]!.add(match);
        case MatchStatus.unavailable:
          groups[MatchCategory.waiting]!.add(match);
        case MatchStatus.dating:
          groups[MatchCategory.dating]!.add(match);
        case MatchStatus.rejected:
        case MatchStatus.dated:
        case MatchStatus.married:
          groups[MatchCategory.archive]!.add(match);
      }
    }

    for (final List<MatchIdea> group in groups.values) {
      group.sort(
        (MatchIdea a, MatchIdea b) => b.createdAt.compareTo(a.createdAt),
      );
    }
    return groups;
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
    PersonRepository personRepository,
  ) {
    if (_category == MatchCategory.archive) {
      return _buildArchive(groups[MatchCategory.archive]!, personRepository);
    }

    final List<MatchIdea> matches = groups[_category]!;
    // The due-reminder list sits at the top of "פתוחים" whatever the proposals'
    // own status is; they keep their place in their own category too.
    final bool showReminders =
        _category == MatchCategory.open && dueReminders.isNotEmpty;

    if (matches.isEmpty && !showReminders) {
      return _emptyState(_category);
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
            'כל הרעיונות הפתוחים (${matches.length})',
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

  Widget _buildArchive(
    List<MatchIdea> archived,
    PersonRepository personRepository,
  ) {
    final List<MatchIdea> rejected = archived
        .where((MatchIdea m) => m.status == MatchStatus.rejected)
        .toList();
    final List<MatchIdea> dated = archived
        .where(
          (MatchIdea m) =>
              m.status == MatchStatus.dated || m.status == MatchStatus.married,
        )
        .toList();
    final List<MatchIdea> shown = _archiveTab == _ArchiveTab.rejected
        ? rejected
        : dated;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<_ArchiveTab>(
            showSelectedIcon: false,
            segments: <ButtonSegment<_ArchiveTab>>[
              ButtonSegment<_ArchiveTab>(
                value: _ArchiveTab.rejected,
                label: Text('הצעות שנדחו (${rejected.length})'),
              ),
              ButtonSegment<_ArchiveTab>(
                value: _ArchiveTab.dated,
                label: Text('זוגות שיצאו (${dated.length})'),
              ),
            ],
            selected: <_ArchiveTab>{_archiveTab},
            onSelectionChanged: (Set<_ArchiveTab> selection) =>
                setState(() => _archiveTab = selection.first),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? EmptyState(
                  icon: _archiveTab == _ArchiveTab.rejected
                      ? Icons.cancel_outlined
                      : Icons.history,
                  title: _archiveTab == _ArchiveTab.rejected
                      ? 'אין הצעות שנדחו'
                      : 'אין זוגות שיצאו',
                  subtitle: 'מה שיסתיים יופיע כאן',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  children: <Widget>[
                    for (final MatchIdea match in shown)
                      _card(match, personRepository, showStatusTag: true),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(
    List<MatchIdea> results,
    PersonRepository personRepository,
  ) {
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'לא נמצאו תוצאות',
        subtitle: 'נסו לחפש בשם אחר',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        for (final MatchIdea match in results)
          _card(match, personRepository, showStatusTag: true, compact: true),
      ],
    );
  }

  Widget _card(
    MatchIdea match,
    PersonRepository personRepository, {
    bool isDueReminder = false,
    bool showStatusTag = false,
    bool compact = false,
  }) {
    final Person? personA = personRepository.getById(match.personAId);
    final Person? personB = personRepository.getById(match.personBId);

    Person? male = personA;
    Person? female = personB;
    if (personA?.gender == Gender.female || personB?.gender == Gender.male) {
      male = personB;
      female = personA;
    }

    // The card is now a quiet summary: no last-updated line, no reminder or
    // status-update buttons — those all live on the proposal-detail screen.
    // The only card action kept is "טופל" while a reminder is actually due.
    return MatchIdeaCard(
      match: match,
      male: male,
      female: female,
      compact: compact,
      showStatusTag: showStatusTag || isDueReminder,
      onTap: () => context.push('/matches/${match.id}'),
      onOpenWhatsApp: _openWhatsApp,
      onMarkReminderHandled: isDueReminder
          ? () => context.read<MatchRepository>().setReminder(match.id, null)
          : null,
    );
  }

  Widget _emptyState(MatchCategory category) {
    switch (category) {
      case MatchCategory.open:
        return EmptyState(
          icon: Icons.favorite_border,
          title: 'אין רעיונות פתוחים',
          subtitle: 'צרו רעיון חדש בין שני חברים',
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
      case MatchCategory.archive:
        return const EmptyState(
          icon: Icons.archive_outlined,
          title: 'הארכיון ריק',
          subtitle: 'מה שיסתיים יופיע כאן',
        );
    }
  }

  // --- Actions ------------------------------------------------------------

  Future<void> _openWhatsApp(Person person) async {
    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('לא הצלחנו לפתוח את וואטסאפ')),
        );
    }
  }

  void _handleSearchChanged() {
    setState(() {});
  }
}

/// The four category chips, each carrying its own count.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: <Widget>[
          for (final MatchCategory category
              in MatchCategory.values) ...<Widget>[
            _CategoryChip(
              label: category.displayName,
              count: counts[category] ?? 0,
              isSelected: selected == category,
              // The archive is deliberately quieter than the live categories.
              isMuted: category == MatchCategory.archive,
              theme: theme,
              onTap: () => onSelected(category),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? accent : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
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
