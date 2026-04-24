import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  static const int _minFilterAge = 18;
  static const int _maxFilterAge = 50;
  static const RangeValues _defaultAgeRange = RangeValues(18, 50);

  final TextEditingController _searchController = TextEditingController();

  Gender? _selectedGender;
  RangeValues _selectedAgeRange = _defaultAgeRange;
  List<ReligiousLevel> _selectedReligiousLevels = <ReligiousLevel>[];
  String _cityFilter = '';
  bool _favoritesOnly = false;
  bool _showArchived = false;
  _PeopleSortOption _sortOption = _PeopleSortOption.alphabetical;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
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

    final List<Person> allPeople = personRepository.getAll();
    final List<Person> visiblePeople = _getVisiblePeople(personRepository);

    return Scaffold(
      appBar: AppBar(
        title: const Text('אנשים'),
        centerTitle: true,
        actions: <Widget>[
          PopupMenuButton<_PeopleSortOption>(
            icon: const Icon(Icons.sort),
            tooltip: 'מיון',
            initialValue: _sortOption,
            onSelected: (_PeopleSortOption value) {
              setState(() {
                _sortOption = value;
              });
            },
            itemBuilder: (BuildContext context) {
              return <PopupMenuEntry<_PeopleSortOption>>[
                const PopupMenuItem<_PeopleSortOption>(
                  value: _PeopleSortOption.alphabetical,
                  child: Text('א-ב'),
                ),
                const PopupMenuItem<_PeopleSortOption>(
                  value: _PeopleSortOption.ageAscending,
                  child: Text('לפי גיל'),
                ),
                const PopupMenuItem<_PeopleSortOption>(
                  value: _PeopleSortOption.newest,
                  child: Text('חדשים'),
                ),
                const PopupMenuItem<_PeopleSortOption>(
                  value: _PeopleSortOption.recentlyUpdated,
                  child: Text('עודכנו לאחרונה'),
                ),
              ];
            },
          ),
          IconButton(
            icon: Icon(_showArchived ? Icons.list : Icons.archive_outlined),
            tooltip: _showArchived ? 'חזרה לפעילות' : 'ארכיון (מזל טוב)',
            onPressed: () {
              setState(() {
                _showArchived = !_showArchived;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.contact_phone_outlined),
            tooltip: 'ייבוא מאנשי קשר',
            onPressed: () => context.push('/people/import'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'הגדרות',
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
              allPeople: allPeople,
              visiblePeople: visiblePeople,
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton.small(
            heroTag: 'fab-swipe',
            tooltip: 'סריקת כרטיסים',
            onPressed: () => context.push('/people/swipe'),
            child: const Icon(Icons.style),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'fab-add',
            onPressed: () => context.push('/people/add'),
            child: const Icon(Icons.add),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
          child: IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'סינון',
            onPressed: _openFiltersSheet,
          ),
        ),
      ],
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required List<Person> allPeople,
    required List<Person> visiblePeople,
  }) {
    final ThemeData theme = Theme.of(context);

    if (allPeople.isEmpty) {
      return _buildEmptyPeopleState(context, theme);
    }

    if (visiblePeople.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'לא נמצאו תוצאות',
        subtitle: 'נסו לשנות את החיפוש או את הסינון',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: visiblePeople.length,
      itemBuilder: (BuildContext context, int index) {
        final Person person = visiblePeople[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Hero(
                tag: 'person-${person.id}',
                child: PersonAvatar(person: person, radius: 24),
              ),
              title: Row(
                children: <Widget>[
                  Text(person.profileStatus.emoji),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      person.fullName.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: _PersonSubtitle(person: person),
              trailing: person.isFavorite
                  ? Icon(Icons.star, color: theme.colorScheme.secondary)
                  : null,
              onTap: () => context.push('/people/${person.id}'),
              onLongPress: () => _showPersonActions(context, person),
            ),
          ),
        );
      },
    );
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
                label: const Text('ייבוא מאנשי קשר'),
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

    if (_selectedAgeRange != _defaultAgeRange) {
      chips.add(
        InputChip(
          label: Text(
            'גיל ${_selectedAgeRange.start.round()}-${_selectedAgeRange.end.round()}',
          ),
          onDeleted: () {
            setState(() {
              _selectedAgeRange = _defaultAgeRange;
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
    final bool hasAgeFilter = _selectedAgeRange != _defaultAgeRange;
    final List<Person> filteredPeople = repository.filter(
      gender: _selectedGender,
      minAge: hasAgeFilter ? _selectedAgeRange.start.round() : null,
      maxAge: hasAgeFilter ? _selectedAgeRange.end.round() : null,
      religiousLevels: _selectedReligiousLevels,
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
      case _PeopleSortOption.alphabetical:
        people.sort(_sortByName);
        return;
      case _PeopleSortOption.ageAscending:
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
      case _PeopleSortOption.newest:
        people.sort((Person a, Person b) {
          final int comparison = b.createdAt.compareTo(a.createdAt);
          return comparison != 0 ? comparison : _sortByName(a, b);
        });
        return;
      case _PeopleSortOption.recentlyUpdated:
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

  Future<void> _openFiltersSheet() async {
    final _PeopleFilterState? result =
        await showModalBottomSheet<_PeopleFilterState>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext context) {
            return _PeopleFiltersSheet(
              initialGender: _selectedGender,
              initialAgeRange: _selectedAgeRange,
              initialReligiousLevels: _selectedReligiousLevels,
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
        _selectedAgeRange != _defaultAgeRange ||
        _selectedReligiousLevels.isNotEmpty ||
        _cityFilter.trim().isNotEmpty ||
        _favoritesOnly;
  }

  void _handleSearchChanged() {
    setState(() {});
  }

  void _resetFilters() {
    _selectedGender = null;
    _selectedAgeRange = _defaultAgeRange;
    _selectedReligiousLevels = <ReligiousLevel>[];
    _cityFilter = '';
    _favoritesOnly = false;
  }
}

class _PersonSubtitle extends StatelessWidget {
  const _PersonSubtitle({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final List<String> parts = <String>[
      if (person.age != null) person.age!.toString(),
      if (person.religiousLevel != null) person.religiousLevel!.displayName,
    ];

    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _PeopleFiltersSheet extends StatefulWidget {
  const _PeopleFiltersSheet({
    required this.initialGender,
    required this.initialAgeRange,
    required this.initialReligiousLevels,
    required this.initialCity,
    required this.initialFavoritesOnly,
  });

  final Gender? initialGender;
  final RangeValues initialAgeRange;
  final List<ReligiousLevel> initialReligiousLevels;
  final String initialCity;
  final bool initialFavoritesOnly;

  @override
  State<_PeopleFiltersSheet> createState() => _PeopleFiltersSheetState();
}

class _PeopleFiltersSheetState extends State<_PeopleFiltersSheet> {
  Gender? tempGender;
  late RangeValues tempAgeRange;
  late List<ReligiousLevel> tempReligiousLevels;
  late bool tempFavoritesOnly;
  late final TextEditingController cityController;

  @override
  void initState() {
    super.initState();
    tempGender = widget.initialGender;
    tempAgeRange = widget.initialAgeRange;
    tempReligiousLevels = List<ReligiousLevel>.from(
      widget.initialReligiousLevels,
    );
    tempFavoritesOnly = widget.initialFavoritesOnly;
    cityController = TextEditingController(text: widget.initialCity);
  }

  @override
  void dispose() {
    cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'סינון אנשים',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text('מגדר', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: Gender.values
                    .where((Gender g) => g != Gender.unknown)
                    .map((Gender gender) {
                  final bool isSelected = tempGender == gender;
                  return ChoiceChip(
                    label: Text(gender.displayName),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        tempGender = isSelected ? null : gender;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text(
                'טווח גילאים: ${tempAgeRange.start.round()}-${tempAgeRange.end.round()}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              RangeSlider(
                min: _PeopleScreenState._minFilterAge.toDouble(),
                max: _PeopleScreenState._maxFilterAge.toDouble(),
                values: tempAgeRange,
                divisions:
                    _PeopleScreenState._maxFilterAge -
                    _PeopleScreenState._minFilterAge,
                labels: RangeLabels(
                  tempAgeRange.start.round().toString(),
                  tempAgeRange.end.round().toString(),
                ),
                onChanged: (RangeValues value) {
                  setState(() {
                    tempAgeRange = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              Text('סגנון דתי', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ReligiousLevel.values.map((ReligiousLevel level) {
                  final bool isSelected = tempReligiousLevels.contains(level);
                  return FilterChip(
                    label: Text(level.displayName),
                    selected: isSelected,
                    onSelected: (bool selected) {
                      setState(() {
                        if (selected) {
                          tempReligiousLevels = <ReligiousLevel>[
                            ...tempReligiousLevels,
                            level,
                          ];
                        } else {
                          tempReligiousLevels = tempReligiousLevels
                              .where((ReligiousLevel item) => item != level)
                              .toList();
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('מועדפים בלבד'),
                value: tempFavoritesOnly,
                onChanged: (bool value) {
                  setState(() {
                    tempFavoritesOnly = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _PeopleFilterState(
                        gender: tempGender,
                        ageRange: tempAgeRange,
                        religiousLevels: tempReligiousLevels,
                        city: cityController.text,
                        favoritesOnly: tempFavoritesOnly,
                      ),
                    );
                  },
                  child: const Text('הצג תוצאות'),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      tempGender = null;
                      tempAgeRange = _PeopleScreenState._defaultAgeRange;
                      tempReligiousLevels = <ReligiousLevel>[];
                      tempFavoritesOnly = false;
                      cityController.clear();
                    });
                  },
                  child: const Text('נקה הכל'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeopleFilterState {
  const _PeopleFilterState({
    required this.gender,
    required this.ageRange,
    required this.religiousLevels,
    required this.city,
    required this.favoritesOnly,
  });

  final Gender? gender;
  final RangeValues ageRange;
  final List<ReligiousLevel> religiousLevels;
  final String city;
  final bool favoritesOnly;
}

enum _PeopleSortOption { alphabetical, ageAscending, newest, recentlyUpdated }
