import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/app_drawer.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

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
  bool _showArchived = false;
  final Set<MatchStatus> _statusFilter = <MatchStatus>{};

  static const List<MatchStatus> _activeStatuses = <MatchStatus>[
    MatchStatus.idea,
    MatchStatus.checking,
    MatchStatus.unavailable,
    MatchStatus.dating,
  ];

  static const List<MatchStatus> _archivedStatuses = <MatchStatus>[
    MatchStatus.rejected,
    MatchStatus.dated,
    MatchStatus.married,
  ];

  List<MatchStatus> get _currentViewStatuses =>
      _showArchived ? _archivedStatuses : _activeStatuses;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _showArchived = widget.initialShowArchived;
    _statusFilter.addAll(widget.initialStatuses);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.read<PersonRepository>();

    final String query = _searchController.text.trim();
    final List<MatchIdea> matches = _getMatches(
      matchRepository: matchRepository,
      personRepository: personRepository,
      query: query,
    );

    final bool filterActive = _statusFilter.isNotEmpty;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(_showArchived ? 'ארכיון' : 'הצעות'),
        centerTitle: true,
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'חיפוש הצעה...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _searchController.clear,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.tune),
                        color: theme.colorScheme.onPrimary,
                        tooltip: 'סינון לפי סטטוס',
                        onPressed: () => _openFilterSheet(context),
                      ),
                      if (filterActive)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onPrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? _EmptyMatchesState(
                    isArchived: _showArchived,
                    isSearchResult: query.isNotEmpty,
                    isFiltered: filterActive,
                    onCreate: () => context.push('/matches/add'),
                    onClearFilter: () => setState(_statusFilter.clear),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: matches.length,
                    itemBuilder: (BuildContext context, int index) {
                      final MatchIdea match = matches[index];
                      final Person? personA = personRepository.getById(
                        match.personAId,
                      );
                      final Person? personB = personRepository.getById(
                        match.personBId,
                      );

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MatchCard(
                          match: match,
                          personA: personA,
                          personB: personB,
                          onTap: () => context.push('/matches/${match.id}'),
                          theme: theme,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/matches/add'),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        'סינון לפי סטטוס',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_statusFilter.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(_statusFilter.clear);
                            setSheetState(() {});
                          },
                          child: const Text('נקה הכל'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _currentViewStatuses.map((MatchStatus status) {
                      final bool selected = _statusFilter.contains(status);
                      final Color statusColor = AppColors.statusColor(
                        status.name,
                      );
                      return FilterChip(
                        label: Text('${status.icon} ${status.displayName}'),
                        selected: selected,
                        selectedColor: statusColor.withValues(alpha: 0.2),
                        checkmarkColor: statusColor,
                        labelStyle: TextStyle(
                          color: selected
                              ? statusColor
                              : Theme.of(ctx).colorScheme.onSurface,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: selected
                              ? statusColor
                              : Theme.of(ctx).colorScheme.outline,
                        ),
                        onSelected: (bool value) {
                          setState(() {
                            if (value) {
                              _statusFilter.add(status);
                            } else {
                              _statusFilter.remove(status);
                            }
                          });
                          setSheetState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  if (_statusFilter.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'לא נבחר סינון – מוצגות כל ההצעות',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<MatchIdea> _getMatches({
    required MatchRepository matchRepository,
    required PersonRepository personRepository,
    required String query,
  }) {
    final List<MatchIdea> baseMatches = query.isNotEmpty
        ? matchRepository.search(query, personRepository)
        : matchRepository.getAll();

    return baseMatches.where((MatchIdea match) {
      final Person? a = personRepository.getById(match.personAId);
      final Person? b = personRepository.getById(match.personBId);
      final bool archived =
          match.status.isArchived ||
          (a?.profileStatus.isArchived ?? false) ||
          (b?.profileStatus.isArchived ?? false);

      if (_showArchived ? !archived : archived) {
        return false;
      }

      if (_statusFilter.isNotEmpty && !_statusFilter.contains(match.status)) {
        return false;
      }

      return true;
    }).toList();
  }

  void _handleSearchChanged() {
    setState(() {});
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.personA,
    required this.personB,
    required this.onTap,
    required this.theme,
  });

  final MatchIdea match;
  final Person? personA;
  final Person? personB;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = AppColors.statusColor(match.status.name);
    final String personAName = personA?.fullName.trim().isNotEmpty == true
        ? personA!.fullName.trim()
        : 'אדם נמחק';
    final String personBName = personB?.fullName.trim().isNotEmpty == true
        ? personB!.fullName.trim()
        : 'אדם נמחק';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(right: BorderSide(width: 4, color: statusColor)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _AvatarOrDeleted(person: personA),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        personAName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      ' ↔ ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        personBName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AvatarOrDeleted(person: personB),
                  ],
                ),
                const SizedBox(height: 10),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${match.status.icon} ${match.status.displayName}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'נפתח: ${AppDateUtils.formatDateShort(match.createdAt)} · עודכן: ${AppDateUtils.timeAgo(match.updatedAt)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        match.reminderDate != null
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                        color: match.reminderDate != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'תזכורת',
                      onPressed: () => _showReminderDialog(context, match),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showReminderDialog(
    BuildContext context,
    MatchIdea match,
  ) async {
    final MatchRepository repository = context.read<MatchRepository>();
    final TextEditingController noteController = TextEditingController(
      text: match.reminderNote,
    );
    DateTime? selectedDate = match.reminderDate;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('תזכורת להצעה'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('תאריך תזכורת'),
                    subtitle: Text(
                      selectedDate != null
                          ? AppDateUtils.formatDateShort(selectedDate!)
                          : 'לא נבחר תאריך',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'הערה (אופציונלי)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              actions: <Widget>[
                if (match.reminderDate != null)
                  TextButton(
                    onPressed: () async {
                      match.reminderDate = null;
                      match.reminderNote = null;
                      await repository.update(match);
                      if (context.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    child: Text(
                      'מחק תזכורת',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('ביטול'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (selectedDate != null) {
                      match.reminderDate = selectedDate;
                      match.reminderNote = noteController.text.trim().isEmpty
                          ? null
                          : noteController.text.trim();
                      await repository.update(match);
                    }
                    if (context.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('שמור'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AvatarOrDeleted extends StatelessWidget {
  const _AvatarOrDeleted({required this.person});

  final Person? person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (person == null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.person_off_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return PersonAvatar(person: person!, radius: 18);
  }
}

class _EmptyMatchesState extends StatelessWidget {
  const _EmptyMatchesState({
    required this.isArchived,
    required this.isSearchResult,
    required this.isFiltered,
    required this.onCreate,
    required this.onClearFilter,
  });

  final bool isArchived;
  final bool isSearchResult;
  final bool isFiltered;
  final VoidCallback onCreate;
  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    if (isSearchResult) {
      return const EmptyState(
        icon: Icons.search,
        title: 'לא נמצאו תוצאות',
        subtitle: 'נסו לחפש בשם אחר',
      );
    }

    if (isFiltered) {
      return EmptyState(
        icon: Icons.filter_list_off,
        title: 'אין הצעות בסינון זה',
        subtitle: 'נסו לשנות או לנקות את הסינון',
        buttonText: 'נקה סינון',
        onButtonPressed: onClearFilter,
      );
    }

    if (isArchived) {
      return const EmptyState(
        icon: Icons.archive_outlined,
        title: 'הארכיון ריק',
        subtitle: 'הצעות שנדחו או לא פנויות יופיעו כאן',
      );
    }

    return EmptyState(
      icon: Icons.favorite_border,
      title: 'אין הצעות פעילות',
      subtitle: 'צרו הצעה חדשה בין שני אנשים',
      buttonText: 'הצעה חדשה',
      onButtonPressed: onCreate,
    );
  }
}
