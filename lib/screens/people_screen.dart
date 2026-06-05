import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/match_suggestion_flow.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';
import 'package:shadchan/widgets/person_list_card.dart';

enum PeopleSortOption { alphabetical, ageAscending, newest, recentlyUpdated }

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({
    super.key,
    this.initialShowArchived = false,
    this.initialProfileStatuses = const <ProfileStatus>[],
    this.initialTableView = false,
    this.initialSort = PeopleSortOption.alphabetical,
  });

  final bool initialShowArchived;
  final List<ProfileStatus> initialProfileStatuses;
  final bool initialTableView;
  final PeopleSortOption initialSort;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final TextEditingController _searchController = TextEditingController();

  Gender? _selectedGender;
  RangeValues? _selectedAgeRange;
  List<ReligiousLevel> _selectedReligiousLevels = <ReligiousLevel>[];
  List<ProfileStatus> _selectedProfileStatuses = <ProfileStatus>[];
  String _cityFilter = '';
  bool _favoritesOnly = false;
  bool _showArchived = false;
  bool _tableView = false;
  PeopleSortOption _sortOption = PeopleSortOption.alphabetical;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _showArchived = widget.initialShowArchived;
    _tableView = widget.initialTableView;
    _sortOption = widget.initialSort;
    _selectedProfileStatuses = List<ProfileStatus>.from(
      widget.initialProfileStatuses,
    );
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
    final PersonRepository personRepository = context.watch<PersonRepository>();

    final int activeCount = personRepository.activeCount;
    final int pendingCount = personRepository.pendingCount;
    final List<Person> visiblePeople = _getVisiblePeople(personRepository);

    return Scaffold(
      appBar: AppBar(
        title: const Text('אנשים'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            tooltip: _tableView ? 'תצוגת רשימה' : 'תצוגת טבלה',
            icon: Icon(
              _tableView
                  ? Icons.view_list_outlined
                  : Icons.table_chart_outlined,
            ),
            onPressed: () {
              setState(() {
                _tableView = !_tableView;
              });
            },
          ),
          IconButton(
            tooltip: 'מיין לפי',
            icon: const Icon(Icons.sort),
            onPressed: _openSortSheet,
          ),
          IconButton(
            tooltip: 'בהמתנה לעדכון',
            icon: Badge.count(
              count: pendingCount,
              isLabelVisible: pendingCount > 1,
              child: const Icon(Icons.inbox_outlined),
            ),
            onPressed: () => context.push('/people/pending'),
          ),
          IconButton(
            tooltip: 'הגדרות',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _buildSearchSection(theme),
          ),
          if (_hasActiveFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _buildActiveFilterChips(),
                ),
              ),
            ),
          Expanded(
            child: _buildBody(
              context: context,
              activeCount: activeCount,
              visiblePeople: visiblePeople,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'הוספה',
        onPressed: () => context.push('/people/import'),
        icon: const Icon(Icons.add),
        label: const Text('הוסף'),
        shape: const StadiumBorder(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildSearchSection(ThemeData theme) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'חיפוש לפי שם...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _searchController.clear,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
          child: IconButton(
            icon: const Icon(Icons.tune),
            color: theme.colorScheme.onPrimary,
            tooltip: 'סינון',
            onPressed: _openFiltersSheet,
          ),
        ),
      ],
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required int activeCount,
    required List<Person> visiblePeople,
  }) {
    final ThemeData theme = Theme.of(context);

    if (activeCount == 0) {
      return _buildEmptyPeopleState(context, theme);
    }

    if (visiblePeople.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'לא נמצאו תוצאות',
        subtitle: 'נסו לשנות את החיפוש או את הסינון',
      );
    }

    if (_tableView) {
      return _PeopleTable(
        people: visiblePeople,
        onOpenMatches: (Person person) =>
            _openMatchSuggestions(context, person),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: visiblePeople.length,
      itemBuilder: (BuildContext context, int index) {
        final Person person = visiblePeople[index];
        return PersonListCard(
          person: person,
          onTap: () => context.push('/people/${person.id}'),
          onLongPress: () => _showPersonActions(context, person),
          onOpenMatches: () => _openMatchSuggestions(context, person),
          onOpenWhatsApp: () => _openWhatsApp(context, person),
        );
      },
    );
  }

  Future<void> _openMatchSuggestions(
    BuildContext context,
    Person person,
  ) async {
    await MatchSuggestionFlow.open(context, sourcePerson: person);
  }

  Future<void> _openWhatsApp(BuildContext context, Person person) async {
    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('לא הצלחנו לפתוח את וואטסאפ')),
        );
    }
  }

  Widget _buildEmptyPeopleState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.people_outline,
              size: 80,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'אין אנשים עדיין',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'אפשר להוסיף ידנית או לייבא במהירות מאנשי הקשר',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/people/import'),
                icon: const Icon(Icons.contact_phone_outlined),
                label: const Text('הוספה מאנשי קשר'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.push('/people/add'),
              child: const Text('הוספה ידנית'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActiveFilterChips() {
    final List<Widget> chips = <Widget>[];

    if (_selectedGender != null) {
      chips.add(
        InputChip(
          label: Text(_selectedGender!.displayName),
          onDeleted: () {
            setState(() {
              _selectedGender = null;
            });
          },
        ),
      );
    }

    final RangeValues? ageRange = _selectedAgeRange;
    if (ageRange != null) {
      chips.add(
        InputChip(
          label: Text('גיל ${ageRange.start.round()}-${ageRange.end.round()}'),
          onDeleted: () {
            setState(() {
              _selectedAgeRange = null;
            });
          },
        ),
      );
    }

    for (final ReligiousLevel level in _selectedReligiousLevels) {
      chips.add(
        InputChip(
          label: Text(level.displayName),
          onDeleted: () {
            setState(() {
              _selectedReligiousLevels = _selectedReligiousLevels
                  .where((ReligiousLevel item) => item != level)
                  .toList();
            });
          },
        ),
      );
    }

    for (final ProfileStatus status in _selectedProfileStatuses) {
      chips.add(
        InputChip(
          label: Text(status.displayName),
          onDeleted: () {
            setState(() {
              _selectedProfileStatuses = _selectedProfileStatuses
                  .where((ProfileStatus item) => item != status)
                  .toList();
            });
          },
        ),
      );
    }

    if (_cityFilter.trim().isNotEmpty) {
      chips.add(
        InputChip(
          label: Text(_cityFilter.trim()),
          onDeleted: () {
            setState(() {
              _cityFilter = '';
            });
          },
        ),
      );
    }

    if (_favoritesOnly) {
      chips.add(
        InputChip(
          label: const Text('מועדפים'),
          onDeleted: () {
            setState(() {
              _favoritesOnly = false;
            });
          },
        ),
      );
    }

    chips.add(
      ActionChip(
        avatar: const Icon(Icons.close, size: 18),
        label: const Text('נקה הכל'),
        onPressed: () {
          setState(_resetFilters);
        },
      ),
    );

    return chips;
  }

  List<Person> _getVisiblePeople(PersonRepository repository) {
    final RangeValues? ageRange = _selectedAgeRange;
    final List<Person> filteredPeople = repository.filter(
      gender: _selectedGender,
      minAge: ageRange?.start.round(),
      maxAge: ageRange?.end.round(),
      religiousLevels: _selectedReligiousLevels,
      profileStatuses: _selectedProfileStatuses,
      favoritesOnly: _favoritesOnly ? true : null,
    );

    final String normalizedSearch = _searchController.text.trim().toLowerCase();
    final String normalizedCity = _cityFilter.trim().toLowerCase();

    final List<Person> visiblePeople = filteredPeople.where((Person person) {
      final bool matchesSearch =
          normalizedSearch.isEmpty ||
          person.firstName.toLowerCase().contains(normalizedSearch) ||
          person.lastName.toLowerCase().contains(normalizedSearch) ||
          person.fullName.toLowerCase().contains(normalizedSearch);

      final bool matchesCity =
          normalizedCity.isEmpty ||
          (person.city ?? '').trim().toLowerCase().contains(normalizedCity);

      final bool matchesArchive = _showArchived
          ? person.profileStatus.isArchived
          : !person.profileStatus.isArchived;

      return matchesSearch && matchesCity && matchesArchive;
    }).toList();

    _sortPeople(visiblePeople);
    return visiblePeople;
  }

  void _sortPeople(List<Person> people) {
    switch (_sortOption) {
      case PeopleSortOption.alphabetical:
        people.sort(_sortByName);
        return;
      case PeopleSortOption.ageAscending:
        people.sort((Person a, Person b) {
          final int? ageA = a.age;
          final int? ageB = b.age;

          if (ageA == null && ageB == null) {
            return _sortByName(a, b);
          }
          if (ageA == null) {
            return 1;
          }
          if (ageB == null) {
            return -1;
          }

          final int ageComparison = ageA.compareTo(ageB);
          return ageComparison != 0 ? ageComparison : _sortByName(a, b);
        });
        return;
      case PeopleSortOption.newest:
        people.sort((Person a, Person b) {
          final int comparison = b.createdAt.compareTo(a.createdAt);
          return comparison != 0 ? comparison : _sortByName(a, b);
        });
        return;
      case PeopleSortOption.recentlyUpdated:
        people.sort((Person a, Person b) {
          final int comparison = b.updatedAt.compareTo(a.updatedAt);
          return comparison != 0 ? comparison : _sortByName(a, b);
        });
        return;
    }
  }

  int _sortByName(Person a, Person b) {
    final int firstNameComparison = a.firstName.toLowerCase().compareTo(
      b.firstName.toLowerCase(),
    );
    if (firstNameComparison != 0) {
      return firstNameComparison;
    }

    return a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
  }

  Future<void> _openSortSheet() async {
    final PeopleSortOption? selected =
        await showModalBottomSheet<PeopleSortOption>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext sheetContext) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'מיין לפי',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  for (final ({PeopleSortOption value, String label}) option
                      in const <({PeopleSortOption value, String label})>[
                        (value: PeopleSortOption.alphabetical, label: 'א-ב'),
                        (
                          value: PeopleSortOption.ageAscending,
                          label: 'לפי גיל',
                        ),
                        (value: PeopleSortOption.newest, label: 'חדשים'),
                        (
                          value: PeopleSortOption.recentlyUpdated,
                          label: 'עודכנו לאחרונה',
                        ),
                      ])
                    ListTile(
                      title: Text(option.label),
                      trailing: _sortOption == option.value
                          ? Icon(
                              Icons.check,
                              color: Theme.of(sheetContext).colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(option.value),
                    ),
                ],
              ),
            );
          },
        );

    if (selected == null) {
      return;
    }
    setState(() {
      _sortOption = selected;
    });
  }

  Future<void> _openFiltersSheet() async {
    final ({int min, int max})? bounds = context
        .read<PersonRepository>()
        .activeAgeBounds;
    final PeopleFilterState? result =
        await showModalBottomSheet<PeopleFilterState>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          builder: (BuildContext context) {
            return PeopleFiltersSheet(
              initialGender: _selectedGender,
              initialAgeRange: _selectedAgeRange,
              ageBounds: bounds,
              initialReligiousLevels: _selectedReligiousLevels,
              initialProfileStatuses: _selectedProfileStatuses,
              initialCity: _cityFilter,
              initialFavoritesOnly: _favoritesOnly,
            );
          },
        );

    if (result == null) {
      return;
    }

    setState(() {
      _selectedGender = result.gender;
      _selectedAgeRange = result.ageRange;
      _selectedReligiousLevels = result.religiousLevels;
      _selectedProfileStatuses = result.profileStatuses;
      _cityFilter = result.city.trim();
      _favoritesOnly = result.favoritesOnly;
    });
  }

  Future<void> _showPersonActions(BuildContext context, Person person) async {
    final PersonRepository repository = context.read<PersonRepository>();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.favorite_outline),
                title: const Text('התאמות'),
                onTap: () {
                  Navigator.of(bottomSheetContext).pop();
                  _openMatchSuggestions(context, person);
                },
              ),
              ListTile(
                leading: Icon(
                  person.isFavorite ? Icons.star_outline : Icons.star,
                ),
                title: Text(
                  person.isFavorite ? 'הסר ממועדפים' : 'הוסף למועדפים',
                ),
                onTap: () async {
                  Navigator.of(bottomSheetContext).pop();
                  await repository.toggleFavorite(person.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('מחיקה'),
                textColor: Theme.of(context).colorScheme.error,
                iconColor: Theme.of(context).colorScheme.error,
                onTap: () async {
                  Navigator.of(bottomSheetContext).pop();
                  final bool shouldDelete = await _confirmDelete(
                    context,
                    person,
                  );
                  if (shouldDelete) {
                    await repository.delete(person.id);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context, Person person) async {
    final MatchRepository matchRepository = context.read<MatchRepository>();
    final int activeMatches = matchRepository
        .getByPersonId(person.id)
        .where((MatchIdea match) => !match.status.isArchived)
        .length;
    final String warning = activeMatches > 0
        ? '\n\nלאדם זה יש $activeMatches הצעות פעילות. ההצעות לא יימחקו.'
        : '';

    return ConfirmDialog.show(
      context,
      title: 'למחוק את האדם?',
      message: 'האם למחוק את ${person.fullName.trim()}?$warning',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
  }

  bool get _hasActiveFilters {
    return _selectedGender != null ||
        _selectedAgeRange != null ||
        _selectedReligiousLevels.isNotEmpty ||
        _selectedProfileStatuses.isNotEmpty ||
        _cityFilter.trim().isNotEmpty ||
        _favoritesOnly;
  }

  void _handleSearchChanged() {
    setState(() {});
  }

  void _resetFilters() {
    _selectedGender = null;
    _selectedAgeRange = null;
    _selectedReligiousLevels = <ReligiousLevel>[];
    _selectedProfileStatuses = <ProfileStatus>[];
    _cityFilter = '';
    _favoritesOnly = false;
  }
}

class _PeopleTable extends StatefulWidget {
  const _PeopleTable({required this.people, required this.onOpenMatches});

  final List<Person> people;
  final ValueChanged<Person> onOpenMatches;

  @override
  State<_PeopleTable> createState() => _PeopleTableState();
}

class _PeopleTableState extends State<_PeopleTable> {
  final Set<Gender> _selectedGenders = <Gender>{};
  final Set<ReligiousLevel?> _selectedReligiousLevels = <ReligiousLevel?>{};
  final Set<ProfileStatus> _selectedProfileStatuses = <ProfileStatus>{};
  RangeValues? _selectedAgeRange;
  bool _isPreparing = true;
  int _loadingGeneration = 0;

  bool get _hasActiveFilters =>
      _selectedGenders.isNotEmpty ||
      _selectedAgeRange != null ||
      _selectedReligiousLevels.isNotEmpty ||
      _selectedProfileStatuses.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _finishPreparingSoon();
  }

  void _finishPreparingSoon() {
    final int generation = ++_loadingGeneration;
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || generation != _loadingGeneration) {
        return;
      }
      setState(() {
        _isPreparing = false;
      });
    });
  }

  void _pulseLoading() {
    setState(() {
      _isPreparing = true;
    });
    _finishPreparingSoon();
  }

  static const double _nameWidth = 130;
  static const double _genderWidth = 60;
  static const double _ageWidth = 50;
  static const double _religiousWidth = 110;
  static const double _statusWidth = 60;
  static const double _actionsWidth = 48;
  static const double _rowHeight = 48;
  static const double _tableWidth =
      _nameWidth +
      _genderWidth +
      _ageWidth +
      _religiousWidth +
      _statusWidth +
      _actionsWidth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository repository = context.read<PersonRepository>();
    final List<Person> filteredPeople = _filteredPeople;

    if (_isPreparing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('טוענים טבלה...'),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        if (_hasActiveFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ActionChip(
                    avatar: const Icon(Icons.close, size: 18),
                    label: const Text('נקה סינון טבלה'),
                    onPressed: () {
                      setState(() {
                        _selectedGenders.clear();
                        _selectedAgeRange = null;
                        _selectedReligiousLevels.clear();
                        _selectedProfileStatuses.clear();
                      });
                      _pulseLoading();
                    },
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: _tableWidth,
              child: Column(
                children: <Widget>[
                  _buildHeader(theme),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  Expanded(
                    child: filteredPeople.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'אין אנשים שמתאימים לסינון הטבלה',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: filteredPeople.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              color: theme.colorScheme.outlineVariant,
                            ),
                            itemBuilder: (BuildContext context, int index) {
                              return _buildRow(
                                theme: theme,
                                person: filteredPeople[index],
                                repository: repository,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      height: _rowHeight,
      color: theme.colorScheme.surface,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _nameWidth,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Text(
                'שם',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(
            width: _genderWidth,
            child: _TableFilterHeader(
              label: 'מגדר',
              isActive: _selectedGenders.isNotEmpty,
              onTap: _openGenderFilter,
            ),
          ),
          SizedBox(
            width: _ageWidth,
            child: _TableFilterHeader(
              label: 'גיל',
              isActive: _selectedAgeRange != null,
              onTap: _openAgeFilter,
            ),
          ),
          SizedBox(
            width: _religiousWidth,
            child: _TableFilterHeader(
              label: 'סגנון דתי',
              isActive: _selectedReligiousLevels.isNotEmpty,
              onTap: _openReligiousLevelFilter,
            ),
          ),
          SizedBox(
            width: _statusWidth,
            child: _TableFilterHeader(
              label: 'סטטוס',
              isActive: _selectedProfileStatuses.isNotEmpty,
              onTap: _openProfileStatusFilter,
            ),
          ),
          const SizedBox(width: _actionsWidth),
        ],
      ),
    );
  }

  Widget _buildRow({
    required ThemeData theme,
    required Person person,
    required PersonRepository repository,
  }) {
    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _nameWidth,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Text(
                person.fullName.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(
            width: _genderWidth,
            child: Text(
              person.gender.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          SizedBox(
            width: _ageWidth,
            child: Text(person.displayAge, style: theme.textTheme.bodyMedium),
          ),
          SizedBox(
            width: _religiousWidth,
            child: Text(
              person.religiousLevel?.displayName ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          SizedBox(
            width: _statusWidth,
            child: PopupMenuButton<ProfileStatus>(
              tooltip: person.profileStatus.displayName,
              initialValue: person.profileStatus,
              padding: EdgeInsets.zero,
              position: PopupMenuPosition.under,
              onSelected: (ProfileStatus value) {
                repository.updateProfileStatus(person.id, value);
              },
              itemBuilder: (BuildContext context) {
                return ProfileStatus.values.map((ProfileStatus status) {
                  return PopupMenuItem<ProfileStatus>(
                    value: status,
                    child: Text('${status.emoji} ${status.displayName}'),
                  );
                }).toList();
              },
              child: Center(
                child: Text(
                  person.profileStatus.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
          SizedBox(
            width: _actionsWidth,
            child: IconButton(
              tooltip: 'התאמות',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.favorite_outline,
                color: theme.colorScheme.primary,
              ),
              onPressed: () => widget.onOpenMatches(person),
            ),
          ),
        ],
      ),
    );
  }

  List<Person> get _filteredPeople {
    return widget.people.where((Person person) {
      if (_selectedGenders.isNotEmpty &&
          !_selectedGenders.contains(person.gender)) {
        return false;
      }

      final RangeValues? ageRange = _selectedAgeRange;
      if (ageRange != null) {
        final int? age = person.age;
        if (age == null ||
            age < ageRange.start.round() ||
            age > ageRange.end.round()) {
          return false;
        }
      }

      if (_selectedReligiousLevels.isNotEmpty &&
          !_selectedReligiousLevels.contains(person.religiousLevel)) {
        return false;
      }

      if (_selectedProfileStatuses.isNotEmpty &&
          !_selectedProfileStatuses.contains(person.profileStatus)) {
        return false;
      }

      return true;
    }).toList();
  }

  Future<void> _openGenderFilter() async {
    final Set<Gender>? result = await _showMultiSelectSheet<Gender>(
      title: 'סינון לפי מגדר',
      options: Gender.values,
      selectedValues: _selectedGenders,
      labelFor: (Gender value) => value.displayName,
    );

    if (result == null) {
      return;
    }

    setState(() {
      _selectedGenders
        ..clear()
        ..addAll(result);
    });
    _pulseLoading();
  }

  Future<void> _openReligiousLevelFilter() async {
    final Set<ReligiousLevel?>? result =
        await _showMultiSelectSheet<ReligiousLevel?>(
          title: 'סינון לפי סגנון דתי',
          options: <ReligiousLevel?>[...ReligiousLevel.values, null],
          selectedValues: _selectedReligiousLevels,
          labelFor: (ReligiousLevel? value) => value?.displayName ?? 'לא מוגדר',
        );

    if (result == null) {
      return;
    }

    setState(() {
      _selectedReligiousLevels
        ..clear()
        ..addAll(result);
    });
    _pulseLoading();
  }

  Future<void> _openProfileStatusFilter() async {
    final Set<ProfileStatus>? result =
        await _showMultiSelectSheet<ProfileStatus>(
          title: 'סינון לפי סטטוס',
          options: ProfileStatus.values,
          selectedValues: _selectedProfileStatuses,
          labelFor: (ProfileStatus value) =>
              '${value.emoji} ${value.displayName}',
        );

    if (result == null) {
      return;
    }

    setState(() {
      _selectedProfileStatuses
        ..clear()
        ..addAll(result);
    });
    _pulseLoading();
  }

  Future<void> _openAgeFilter() async {
    final ({int min, int max})? bounds = context
        .read<PersonRepository>()
        .activeAgeBounds;
    if (bounds == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('אין גילאים זמינים לסינון')),
        );
      return;
    }

    final double minAge = bounds.min.toDouble();
    final double maxAge = bounds.max.toDouble();
    final bool sliderDisabled = bounds.min == bounds.max;
    final double sliderMax = sliderDisabled ? maxAge + 1 : maxAge;
    RangeValues tempRange = _selectedAgeRange ?? RangeValues(minAge, maxAge);

    final _AgeFilterResult?
    result = await showModalBottomSheet<_AgeFilterResult>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'סינון לפי גיל',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'גילאי ${tempRange.start.round()}-${tempRange.end.round()}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    RangeSlider(
                      min: minAge,
                      max: sliderMax,
                      values: tempRange,
                      divisions: sliderDisabled ? 1 : (maxAge - minAge).round(),
                      labels: RangeLabels(
                        tempRange.start.round().toString(),
                        tempRange.end.round().toString(),
                      ),
                      onChanged: sliderDisabled
                          ? null
                          : (RangeValues value) {
                              setSheetState(() {
                                tempRange = value;
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(
                          sheetContext,
                        ).pop(_AgeFilterResult(tempRange)),
                        child: const Text('הצג תוצאות'),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () => Navigator.of(
                          sheetContext,
                        ).pop(const _AgeFilterResult(null)),
                        child: const Text('נקה סינון גיל'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) {
      return;
    }

    final RangeValues? chosen = result.range;
    setState(() {
      if (chosen != null &&
          chosen.start.round() <= bounds.min &&
          chosen.end.round() >= bounds.max) {
        _selectedAgeRange = null;
      } else {
        _selectedAgeRange = chosen;
      }
    });
    _pulseLoading();
  }

  Future<Set<T>?> _showMultiSelectSheet<T>({
    required String title,
    required List<T> options,
    required Set<T> selectedValues,
    required String Function(T value) labelFor,
  }) {
    final Set<T> tempSelected = Set<T>.from(selectedValues);

    return showModalBottomSheet<Set<T>>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: options.map((T option) {
                        final bool selected = tempSelected.contains(option);
                        return FilterChip(
                          label: Text(labelFor(option)),
                          selected: selected,
                          onSelected: (bool value) {
                            setSheetState(() {
                              if (value) {
                                tempSelected.add(option);
                              } else {
                                tempSelected.remove(option);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(
                          sheetContext,
                        ).pop(Set<T>.from(tempSelected)),
                        child: const Text('הצג תוצאות'),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(<T>{}),
                        child: const Text('נקה סינון'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AgeFilterResult {
  const _AgeFilterResult(this.range);

  final RangeValues? range;
}

class _TableFilterHeader extends StatelessWidget {
  const _TableFilterHeader({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color),
                ),
                const SizedBox(width: 2),
                Icon(
                  isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
                  size: 14,
                  color: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
