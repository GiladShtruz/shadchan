import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

typedef PersonFilter = bool Function(Person person);

class PersonPickerSheet extends StatefulWidget {
  const PersonPickerSheet({
    super.key,
    required this.title,
    this.filterGender,
    this.excludeIds = const <String>{},
    this.minAge,
    this.maxAge,
    this.religiousLevels = const <ReligiousLevel>[],
    this.profileStatuses = const <ProfileStatus>[],
    this.candidatePredicate,
    this.emptySubtitle = 'נסו לחפש בשם אחר',
  });

  final Gender? filterGender;
  final Set<String> excludeIds;
  final String title;
  final int? minAge;
  final int? maxAge;
  final List<ReligiousLevel> religiousLevels;
  final List<ProfileStatus> profileStatuses;
  final PersonFilter? candidatePredicate;
  final String emptySubtitle;

  static Future<Person?> show(
    BuildContext context, {
    required String title,
    Gender? filterGender,
    Set<String> excludeIds = const <String>{},
    int? minAge,
    int? maxAge,
    List<ReligiousLevel> religiousLevels = const <ReligiousLevel>[],
    List<ProfileStatus> profileStatuses = const <ProfileStatus>[],
    PersonFilter? candidatePredicate,
    String emptySubtitle = 'נסו לחפש בשם אחר',
  }) {
    return showModalBottomSheet<Person>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: PersonPickerSheet(
            title: title,
            filterGender: filterGender,
            excludeIds: excludeIds,
            minAge: minAge,
            maxAge: maxAge,
            religiousLevels: religiousLevels,
            profileStatuses: profileStatuses,
            candidatePredicate: candidatePredicate,
            emptySubtitle: emptySubtitle,
          ),
        );
      },
    );
  }

  @override
  State<PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends State<PersonPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

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
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final String query = _searchController.text.trim().toLowerCase();

    final List<Person> people = personRepository.getAll().where((
      Person person,
    ) {
      if (person.needsReview) {
        return false;
      }

      if (widget.filterGender != null && person.gender != widget.filterGender) {
        return false;
      }

      if (widget.excludeIds.contains(person.id)) {
        return false;
      }

      final int? personAge = person.age;
      if (widget.minAge != null &&
          (personAge == null || personAge < widget.minAge!)) {
        return false;
      }
      if (widget.maxAge != null &&
          (personAge == null || personAge > widget.maxAge!)) {
        return false;
      }

      if (widget.religiousLevels.isNotEmpty &&
          !widget.religiousLevels.contains(person.religiousLevel)) {
        return false;
      }

      if (widget.profileStatuses.isNotEmpty &&
          !widget.profileStatuses.contains(person.profileStatus)) {
        return false;
      }

      final PersonFilter? candidatePredicate = widget.candidatePredicate;
      if (candidatePredicate != null && !candidatePredicate(person)) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      return person.firstName.toLowerCase().contains(query) ||
          person.lastName.toLowerCase().contains(query) ||
          person.fullName.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'חיפוש לפי שם...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _searchController.clear,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: people.isEmpty
                  ? EmptyState(
                      icon: Icons.search,
                      title: 'לא נמצאו תוצאות',
                      subtitle: widget.emptySubtitle,
                    )
                  : ListView.builder(
                      itemCount: people.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Person person = people[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: PersonAvatar(person: person, radius: 22),
                          title: Text(
                            person.fullName.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _personSubtitle(person),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).pop(person),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _personSubtitle(Person person) {
    final List<String> parts = <String>[
      if (person.age != null) person.age!.toString(),
      if (person.religiousLevel != null) person.religiousLevel!.displayName,
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ];

    return parts.join(' · ');
  }

  void _handleSearchChanged() {
    setState(() {});
  }
}

class MatchProposalFilters {
  const MatchProposalFilters({
    this.minAge,
    this.maxAge,
    this.religiousLevels = const <ReligiousLevel>[],
    this.profileStatuses = const <ProfileStatus>[],
  });

  final int? minAge;
  final int? maxAge;
  final List<ReligiousLevel> religiousLevels;
  final List<ProfileStatus> profileStatuses;
}

class MatchProposalFilterSheet extends StatefulWidget {
  const MatchProposalFilterSheet({
    super.key,
    required this.targetGender,
    required this.sourcePersonId,
    this.initialFilters,
  });

  final Gender targetGender;
  final String sourcePersonId;
  final MatchProposalFilters? initialFilters;

  static Future<MatchProposalFilters?> show(
    BuildContext context, {
    required Gender targetGender,
    required String sourcePersonId,
    MatchProposalFilters? initialFilters,
  }) {
    return showModalBottomSheet<MatchProposalFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return MatchProposalFilterSheet(
          targetGender: targetGender,
          sourcePersonId: sourcePersonId,
          initialFilters: initialFilters,
        );
      },
    );
  }

  static const String settingsKeyPrefix = 'matchProposalFilters.';

  static MatchProposalFilters? savedFiltersFor(String sourcePersonId) {
    if (!Hive.isBoxOpen('settings')) {
      return null;
    }

    final Object? rawFilters = Hive.box<dynamic>(
      'settings',
    ).get('$settingsKeyPrefix$sourcePersonId');
    if (rawFilters is! Map) {
      return null;
    }

    return MatchProposalFilters(
      minAge: _readInt(rawFilters['minAge']),
      maxAge: _readInt(rawFilters['maxAge']),
      religiousLevels: _enumValuesFromNames<ReligiousLevel>(
        rawFilters['religiousLevels'],
        ReligiousLevel.values,
      ),
      profileStatuses: _enumValuesFromNames<ProfileStatus>(
        rawFilters['profileStatuses'],
        <ProfileStatus>[
          ProfileStatus.available,
          ProfileStatus.busy,
          ProfileStatus.onBreak,
        ],
      ),
    );
  }

  static Future<void> saveFiltersFor(
    String sourcePersonId,
    MatchProposalFilters filters,
  ) async {
    if (!Hive.isBoxOpen('settings')) {
      return;
    }

    await Hive.box<dynamic>(
      'settings',
    ).put('$settingsKeyPrefix$sourcePersonId', <String, Object?>{
      'minAge': filters.minAge,
      'maxAge': filters.maxAge,
      'religiousLevels': filters.religiousLevels
          .map((ReligiousLevel level) => level.name)
          .toList(),
      'profileStatuses': filters.profileStatuses
          .map((ProfileStatus status) => status.name)
          .toList(),
    });
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return null;
  }

  static List<T> _enumValuesFromNames<T extends Enum>(
    Object? names,
    List<T> values,
  ) {
    if (names is! Iterable) {
      return <T>[];
    }

    final Set<String> selectedNames = names.whereType<String>().toSet();
    return values
        .where((T value) => selectedNames.contains(value.name))
        .toList();
  }

  @override
  State<MatchProposalFilterSheet> createState() =>
      _MatchProposalFilterSheetState();
}

class _MatchProposalFilterSheetState extends State<MatchProposalFilterSheet> {
  RangeValues? _ageRange;
  final List<ReligiousLevel> _religiousLevels = <ReligiousLevel>[];
  final List<ProfileStatus> _profileStatuses = <ProfileStatus>[
    ProfileStatus.available,
  ];
  bool _loadedSavedFilters = false;

  @override
  void initState() {
    super.initState();
    if (!_loadSavedFilters() && widget.initialFilters != null) {
      _applyFilters(widget.initialFilters!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ({int min, int max})? ageBounds = _ageBounds(
      context.watch<PersonRepository>().getAll(),
    );
    final RangeValues? effectiveAgeRange = _effectiveAgeRange(ageBounds);
    final bool hasAgeFilter =
        ageBounds != null &&
        effectiveAgeRange != null &&
        (effectiveAgeRange.start.round() > ageBounds.min ||
            effectiveAgeRange.end.round() < ageBounds.max);

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
              Text('סינון:', style: theme.textTheme.titleLarge),
              if (_loadedSavedFilters) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'נטען הסינון האחרון לאיש הקשר הזה',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (ageBounds != null && effectiveAgeRange != null) ...<Widget>[
                Text(
                  'טווח גילאים: ${effectiveAgeRange.start.round()}-${effectiveAgeRange.end.round()}',
                  style: theme.textTheme.titleMedium,
                ),
                RangeSlider(
                  min: ageBounds.min.toDouble(),
                  max: ageBounds.max == ageBounds.min
                      ? (ageBounds.max + 1).toDouble()
                      : ageBounds.max.toDouble(),
                  values: effectiveAgeRange,
                  divisions: ageBounds.max == ageBounds.min
                      ? 1
                      : ageBounds.max - ageBounds.min,
                  labels: RangeLabels(
                    effectiveAgeRange.start.round().toString(),
                    effectiveAgeRange.end.round().toString(),
                  ),
                  onChanged: ageBounds.max == ageBounds.min
                      ? null
                      : (RangeValues value) {
                          setState(() => _ageRange = value);
                        },
                ),
                const SizedBox(height: 12),
              ],
              Text('סגנון דתי', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ReligiousLevel.values.map((ReligiousLevel level) {
                  final bool selected = _religiousLevels.contains(level);
                  return FilterChip(
                    label: Text(level.displayName),
                    selected: selected,
                    onSelected: (bool value) {
                      setState(() {
                        if (value) {
                          _religiousLevels.add(level);
                        } else {
                          _religiousLevels.remove(level);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text('סטטוס', style: theme.textTheme.titleMedium),
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
                      final bool selected = _profileStatuses.contains(status);
                      return FilterChip(
                        label: Text('${status.emoji} ${status.displayName}'),
                        selected: selected,
                        onSelected: (bool value) {
                          setState(() {
                            if (value) {
                              _profileStatuses.add(status);
                            } else {
                              _profileStatuses.remove(status);
                            }
                          });
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final MatchProposalFilters filters = MatchProposalFilters(
                      minAge: hasAgeFilter
                          ? effectiveAgeRange.start.round()
                          : null,
                      maxAge: hasAgeFilter
                          ? effectiveAgeRange.end.round()
                          : null,
                      religiousLevels: List<ReligiousLevel>.from(
                        _religiousLevels,
                      ),
                      profileStatuses: List<ProfileStatus>.from(
                        _profileStatuses,
                      ),
                    );
                    await MatchProposalFilterSheet.saveFiltersFor(
                      widget.sourcePersonId,
                      filters,
                    );
                    if (!context.mounted) {
                      return;
                    }

                    Navigator.of(context).pop(filters);
                  },
                  child: const Text('הצג תוצאות'),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _ageRange = null;
                      _religiousLevels.clear();
                      _profileStatuses.clear();
                      _loadedSavedFilters = false;
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

  bool _loadSavedFilters() {
    final MatchProposalFilters? filters =
        MatchProposalFilterSheet.savedFiltersFor(widget.sourcePersonId);
    if (filters == null) {
      return false;
    }

    _applyFilters(filters);
    _loadedSavedFilters = true;
    return true;
  }

  void _applyFilters(MatchProposalFilters filters) {
    final int? minAge = filters.minAge;
    final int? maxAge = filters.maxAge;
    if (minAge != null && maxAge != null && minAge <= maxAge) {
      _ageRange = RangeValues(minAge.toDouble(), maxAge.toDouble());
    } else {
      _ageRange = null;
    }

    _religiousLevels
      ..clear()
      ..addAll(filters.religiousLevels);

    _profileStatuses
      ..clear()
      ..addAll(filters.profileStatuses);
  }

  ({int min, int max})? _ageBounds(List<Person> people) {
    int? min;
    int? max;
    for (final Person person in people) {
      if (person.needsReview ||
          person.profileStatus.isArchived ||
          person.gender != widget.targetGender) {
        continue;
      }

      final int? age = person.age;
      if (age == null) {
        continue;
      }

      if (min == null || age < min) {
        min = age;
      }
      if (max == null || age > max) {
        max = age;
      }
    }

    if (min == null || max == null) {
      return null;
    }
    return (min: min, max: max);
  }

  RangeValues? _effectiveAgeRange(({int min, int max})? bounds) {
    if (bounds == null) {
      return null;
    }

    final RangeValues? range = _ageRange;
    if (range == null) {
      return RangeValues(bounds.min.toDouble(), bounds.max.toDouble());
    }

    return RangeValues(
      range.start.clamp(bounds.min.toDouble(), bounds.max.toDouble()),
      range.end.clamp(bounds.min.toDouble(), bounds.max.toDouble()),
    );
  }
}
