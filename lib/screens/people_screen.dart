import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/widgets/app_drawer.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

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
  static const int _minFilterAge = 18;
  static const int _maxFilterAge = 50;
  static const RangeValues _defaultAgeRange = RangeValues(18, 50);

  final TextEditingController _searchController = TextEditingController();

  Gender? _selectedGender;
  RangeValues _selectedAgeRange = _defaultAgeRange;
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
    final List<Person> visiblePeople = _getVisiblePeople(personRepository);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(title: const Text('אנשים'), centerTitle: true),
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
      return _PeopleTable(people: visiblePeople);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: visiblePeople.length,
      itemBuilder: (BuildContext context, int index) {
        final Person person = visiblePeople[index];
        final bool hasPhone = PhoneUtils.toWhatsAppNumber(person.phone) != null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsetsDirectional.only(
                start: 16,
                end: 4,
                top: 8,
                bottom: 8,
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (person.isFavorite)
                    Icon(Icons.star, color: theme.colorScheme.secondary),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: hasPhone ? 'וואטסאפ' : 'אין מספר טלפון תקין',
                    icon: FaIcon(
                      FontAwesomeIcons.whatsapp,
                      size: 20,
                      color: hasPhone
                          ? const Color(0xFF25D366)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: hasPhone
                        ? () => _openWhatsApp(context, person)
                        : null,
                  ),
                ],
              ),
              onTap: () => context.push('/people/${person.id}'),
              onLongPress: () => _showPersonActions(context, person),
            ),
          ),
        );
      },
    );
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
    final bool hasAgeFilter = _selectedAgeRange != _defaultAgeRange;
    final List<Person> filteredPeople = repository.filter(
      gender: _selectedGender,
      minAge: hasAgeFilter ? _selectedAgeRange.start.round() : null,
      maxAge: hasAgeFilter ? _selectedAgeRange.end.round() : null,
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

  Future<void> _openFiltersSheet() async {
    final _PeopleFilterState? result =
        await showModalBottomSheet<_PeopleFilterState>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          builder: (BuildContext context) {
            return _PeopleFiltersSheet(
              initialGender: _selectedGender,
              initialAgeRange: _selectedAgeRange,
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
        _selectedProfileStatuses.isNotEmpty ||
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
    _selectedProfileStatuses = <ProfileStatus>[];
    _cityFilter = '';
    _favoritesOnly = false;
  }
}

class _PersonSubtitle extends StatelessWidget {
  const _PersonSubtitle({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final List<String> missingInfo = <String>[
      if (person.gender == Gender.unknown) 'מגדר',
      if (person.age == null) 'גיל',
    ];
    final List<String> parts = <String>[
      if (person.age != null) person.age!.toString(),
      if (person.religiousLevel != null) person.religiousLevel!.displayName,
    ];

    if (missingInfo.isEmpty) {
      return Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (parts.isNotEmpty) ...<Widget>[
          Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: missingInfo.map((String label) {
            return _MissingInfoTag(label: 'חסר $label');
          }).toList(),
        ),
      ],
    );
  }
}

class _MissingInfoTag extends StatelessWidget {
  const _MissingInfoTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PeopleFiltersSheet extends StatefulWidget {
  const _PeopleFiltersSheet({
    required this.initialGender,
    required this.initialAgeRange,
    required this.initialReligiousLevels,
    required this.initialProfileStatuses,
    required this.initialCity,
    required this.initialFavoritesOnly,
  });

  final Gender? initialGender;
  final RangeValues initialAgeRange;
  final List<ReligiousLevel> initialReligiousLevels;
  final List<ProfileStatus> initialProfileStatuses;
  final String initialCity;
  final bool initialFavoritesOnly;

  @override
  State<_PeopleFiltersSheet> createState() => _PeopleFiltersSheetState();
}

class _PeopleFiltersSheetState extends State<_PeopleFiltersSheet> {
  Gender? tempGender;
  late RangeValues tempAgeRange;
  late List<ReligiousLevel> tempReligiousLevels;
  late List<ProfileStatus> tempProfileStatuses;
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
    tempProfileStatuses = List<ProfileStatus>.from(
      widget.initialProfileStatuses,
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
                    })
                    .toList(),
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
              Text(
                'סטטוס פנוי',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    <ProfileStatus>[
                      ProfileStatus.available,
                      ProfileStatus.busy,
                      ProfileStatus.onBreak,
                    ].map((ProfileStatus status) {
                      final bool isSelected = tempProfileStatuses.contains(
                        status,
                      );
                      return FilterChip(
                        label: Text(status.displayName),
                        selected: isSelected,
                        onSelected: (bool selected) {
                          setState(() {
                            if (selected) {
                              tempProfileStatuses = <ProfileStatus>[
                                ...tempProfileStatuses,
                                status,
                              ];
                            } else {
                              tempProfileStatuses = tempProfileStatuses
                                  .where((ProfileStatus item) => item != status)
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
                        profileStatuses: tempProfileStatuses,
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
                      tempProfileStatuses = <ProfileStatus>[];
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
    required this.profileStatuses,
    required this.city,
    required this.favoritesOnly,
  });

  final Gender? gender;
  final RangeValues ageRange;
  final List<ReligiousLevel> religiousLevels;
  final List<ProfileStatus> profileStatuses;
  final String city;
  final bool favoritesOnly;
}

class _PeopleTable extends StatefulWidget {
  const _PeopleTable({required this.people});

  final List<Person> people;

  @override
  State<_PeopleTable> createState() => _PeopleTableState();
}

class _PeopleTableState extends State<_PeopleTable> {
  static const double _minAge = 10;
  static const double _maxAge = 120;

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
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                columnSpacing: 18,
                horizontalMargin: 8,
                columns: <DataColumn>[
                  const DataColumn(label: Text('שם')),
                  DataColumn(
                    label: _TableFilterHeader(
                      label: 'מגדר',
                      isActive: _selectedGenders.isNotEmpty,
                      onTap: _openGenderFilter,
                    ),
                  ),
                  DataColumn(
                    numeric: true,
                    label: _TableFilterHeader(
                      label: 'גיל',
                      isActive: _selectedAgeRange != null,
                      onTap: _openAgeFilter,
                    ),
                  ),
                  DataColumn(
                    label: _TableFilterHeader(
                      label: 'סגנון דתי',
                      isActive: _selectedReligiousLevels.isNotEmpty,
                      onTap: _openReligiousLevelFilter,
                    ),
                  ),
                  DataColumn(
                    label: _TableFilterHeader(
                      label: 'סטטוס',
                      isActive: _selectedProfileStatuses.isNotEmpty,
                      onTap: _openProfileStatusFilter,
                    ),
                  ),
                ],
                rows: filteredPeople.map((Person person) {
                  void openDetail() => context.push('/people/${person.id}');
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(
                        Text(
                          person.fullName.trim(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: openDetail,
                      ),
                      DataCell(
                        _GenderDropdown(person: person, repository: repository),
                      ),
                      DataCell(
                        Text(person.displayAge),
                        onTap: person.birthDate != null
                            ? openDetail
                            : () => _editAge(context, person, repository),
                      ),
                      DataCell(
                        _ReligiousLevelDropdown(
                          person: person,
                          repository: repository,
                        ),
                      ),
                      DataCell(
                        _ProfileStatusDropdown(
                          person: person,
                          repository: repository,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        if (filteredPeople.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Text(
              'אין אנשים שמתאימים לסינון הטבלה',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
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
    RangeValues tempRange = _selectedAgeRange ?? const RangeValues(23, 27);

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
                      min: _minAge,
                      max: _maxAge,
                      values: tempRange,
                      divisions: (_maxAge - _minAge).round(),
                      labels: RangeLabels(
                        tempRange.start.round().toString(),
                        tempRange.end.round().toString(),
                      ),
                      onChanged: (RangeValues value) {
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

    setState(() {
      _selectedAgeRange = result.range;
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: TextStyle(color: color)),
            const SizedBox(width: 4),
            Icon(
              isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
              size: 16,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _editAge(
  BuildContext context,
  Person person,
  PersonRepository repository,
) async {
  final TextEditingController controller = TextEditingController(
    text: person.manualAge?.toString() ?? '',
  );
  String? errorText;

  final int? result = await showDialog<int?>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialogState) {
          return AlertDialog(
            title: Text('עריכת גיל – ${person.fullName.trim()}'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'גיל (הערכה)',
                errorText: errorText,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('ביטול'),
              ),
              if (person.manualAge != null)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(-1),
                  child: const Text('ניקוי'),
                ),
              FilledButton(
                onPressed: () {
                  final String trimmed = controller.text.trim();
                  if (trimmed.isEmpty) {
                    Navigator.of(dialogContext).pop(-1);
                    return;
                  }
                  final int? parsed = int.tryParse(trimmed);
                  if (parsed == null || parsed < 10 || parsed > 120) {
                    setDialogState(() {
                      errorText = 'יש להזין גיל בין 10 ל-120';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(parsed);
                },
                child: const Text('שמור'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == null) {
    return;
  }
  await repository.updateManualAge(person.id, result == -1 ? null : result);
}

class _GenderDropdown extends StatelessWidget {
  const _GenderDropdown({required this.person, required this.repository});

  final Person person;
  final PersonRepository repository;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<Gender>(
      value: person.gender,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: Gender.values.map((Gender g) {
        return DropdownMenuItem<Gender>(value: g, child: Text(g.displayName));
      }).toList(),
      onChanged: (Gender? value) {
        if (value == null) return;
        repository.updateGender(person.id, value);
      },
    );
  }
}

class _ReligiousLevelDropdown extends StatelessWidget {
  const _ReligiousLevelDropdown({
    required this.person,
    required this.repository,
  });

  final Person person;
  final PersonRepository repository;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<ReligiousLevel?>(
      value: person.religiousLevel,
      isDense: true,
      underline: const SizedBox.shrink(),
      hint: const Text('—'),
      items: <DropdownMenuItem<ReligiousLevel?>>[
        const DropdownMenuItem<ReligiousLevel?>(value: null, child: Text('—')),
        ...ReligiousLevel.values.map((ReligiousLevel level) {
          return DropdownMenuItem<ReligiousLevel?>(
            value: level,
            child: Text(level.displayName),
          );
        }),
      ],
      onChanged: (ReligiousLevel? value) {
        repository.updateReligiousLevel(person.id, value);
      },
    );
  }
}

class _ProfileStatusDropdown extends StatelessWidget {
  const _ProfileStatusDropdown({
    required this.person,
    required this.repository,
  });

  final Person person;
  final PersonRepository repository;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<ProfileStatus>(
      value: person.profileStatus,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: ProfileStatus.values.map((ProfileStatus status) {
        return DropdownMenuItem<ProfileStatus>(
          value: status,
          child: Text('${status.emoji} ${status.displayName}'),
        );
      }).toList(),
      onChanged: (ProfileStatus? value) {
        if (value == null) return;
        repository.updateProfileStatus(person.id, value);
      },
    );
  }
}
