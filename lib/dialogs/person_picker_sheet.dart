import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
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
    this.religiousLevelOtherLabels = const <String>[],
    this.profileStatuses = const <ProfileStatus>[],
    this.candidatePredicate,
    this.emptySubtitle = 'נסו לחפש בשם אחר',
    this.allowCreateOutsideDatabase = false,
  });

  final Gender? filterGender;
  final Set<String> excludeIds;
  final String title;
  final int? minAge;
  final int? maxAge;
  final List<ReligiousLevel> religiousLevels;
  final List<String> religiousLevelOtherLabels;
  final List<ProfileStatus> profileStatuses;
  final PersonFilter? candidatePredicate;
  final String emptySubtitle;

  /// When true, the sheet shows an "add someone not in the database" action so
  /// a match can be opened with a person who has not been added yet.
  final bool allowCreateOutsideDatabase;

  static Future<Person?> show(
    BuildContext context, {
    required String title,
    Gender? filterGender,
    Set<String> excludeIds = const <String>{},
    int? minAge,
    int? maxAge,
    List<ReligiousLevel> religiousLevels = const <ReligiousLevel>[],
    List<String> religiousLevelOtherLabels = const <String>[],
    List<ProfileStatus> profileStatuses = const <ProfileStatus>[],
    PersonFilter? candidatePredicate,
    String emptySubtitle = 'נסו לחפש בשם אחר',
    bool allowCreateOutsideDatabase = false,
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
            religiousLevelOtherLabels: religiousLevelOtherLabels,
            profileStatuses: profileStatuses,
            candidatePredicate: candidatePredicate,
            emptySubtitle: emptySubtitle,
            allowCreateOutsideDatabase: allowCreateOutsideDatabase,
          ),
        );
      },
    );
  }

  /// Adds someone who is not in the database without going through the picker
  /// list first — used by the "התאמה עם אדם שאינו נמצא במאגר" shortcut. Returns
  /// the created person, or null when the flow was cancelled.
  static Future<Person?> addOutsideDatabase(
    BuildContext context, {
    required Gender gender,
  }) async {
    final _NewPersonChoice? choice = await showDialog<_NewPersonChoice>(
      context: context,
      builder: (BuildContext dialogContext) => _NewPersonDialog(gender: gender),
    );
    if (choice == null || !context.mounted) {
      return null;
    }

    final Person? person = await _persistNewPerson(context, choice, gender);
    if (person != null && choice.addToDatabase && context.mounted) {
      GoRouter.of(context).push('/people/${person.id}/edit');
    }
    return person;
  }

  @override
  State<PersonPickerSheet> createState() => _PersonPickerSheetState();
}

/// Creates and stores the person behind a "not in the database" choice. Adding
/// them to the database makes them visible in the lists; either way details are
/// missing, so they are flagged for review.
Future<Person?> _persistNewPerson(
  BuildContext context,
  _NewPersonChoice choice,
  Gender gender,
) async {
  final ({String first, String last}) name = _splitName(choice.name);
  final DateTime now = DateTime.now();
  final Person person = Person(
    id: const Uuid().v4(),
    firstName: name.first,
    lastName: name.last,
    gender: gender,
    hidden: !choice.addToDatabase,
    needsReview: true,
    createdAt: now,
    updatedAt: now,
  );

  await context.read<PersonRepository>().add(person);
  return person;
}

({String first, String last}) _splitName(String value) {
  final List<String> words = value.trim().split(RegExp(r'\s+'))
    ..removeWhere((String w) => w.isEmpty);
  if (words.isEmpty) {
    return (first: '', last: '');
  }
  if (words.length == 1) {
    return (first: words.first, last: '');
  }
  return (first: words.first, last: words.sublist(1).join(' '));
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
      if (person.needsReview || person.hidden) {
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

      final bool hasReligiousFilter =
          widget.religiousLevels.isNotEmpty ||
          widget.religiousLevelOtherLabels.isNotEmpty;
      if (hasReligiousFilter &&
          !widget.religiousLevels.contains(person.religiousLevel) &&
          !(person.religiousLevel == ReligiousLevel.other &&
              widget.religiousLevelOtherLabels.contains(
                person.religiousLevelOther?.trim(),
              ))) {
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

    final List<_PickerEntry> entries = _buildEntries(people, query);

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
                      itemCount: entries.length,
                      itemBuilder: (BuildContext context, int index) {
                        final _PickerEntry entry = entries[index];
                        final Person? person = entry.person;
                        if (person == null) {
                          return _PickerSectionLabel(
                            label: entry.sectionLabel!,
                          );
                        }
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
            if (widget.allowCreateOutsideDatabase)
              _NotFoundFooter(onTap: _createOutsideDatabase),
          ],
        ),
      ),
    );
  }

  /// Recently updated people lead the list so the ones being worked on right
  /// now are a tap away; the rest follow alphabetically. While searching the
  /// split is dropped and everything is listed alphabetically.
  List<_PickerEntry> _buildEntries(List<Person> people, String query) {
    int byName(Person a, Person b) =>
        a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());

    if (query.isNotEmpty || people.length <= _recentCount) {
      return (people.toList()..sort(byName)).map(_PickerEntry.person).toList();
    }

    final List<Person> byRecency = people.toList()
      ..sort((Person a, Person b) => b.updatedAt.compareTo(a.updatedAt));
    final List<Person> recent = byRecency.take(_recentCount).toList();
    final Set<String> recentIds = recent.map((Person p) => p.id).toSet();
    final List<Person> rest =
        people.where((Person p) => !recentIds.contains(p.id)).toList()
          ..sort(byName);

    return <_PickerEntry>[
      _PickerEntry.section('עודכנו לאחרונה'),
      ...recent.map(_PickerEntry.person),
      _PickerEntry.section('כל המאגר'),
      ...rest.map(_PickerEntry.person),
    ];
  }

  static const int _recentCount = 5;

  /// Prompts for a name, then whether to also add the new person to the
  /// database. In both cases a [Person] is created so the match can reference
  /// them, and the created person is returned to the caller; choosing to add
  /// them opens their form so the details can be completed right away.
  Future<void> _createOutsideDatabase() async {
    final Gender gender = widget.filterGender ?? Gender.unknown;
    final _NewPersonChoice? choice = await showDialog<_NewPersonChoice>(
      context: context,
      builder: (BuildContext dialogContext) => _NewPersonDialog(gender: gender),
    );
    if (choice == null || !mounted) {
      return;
    }

    final Person? person = await _persistNewPerson(context, choice, gender);
    if (person == null || !mounted) {
      return;
    }

    // The router outlives this sheet, so grab it before popping.
    final GoRouter router = GoRouter.of(context);
    Navigator.of(context).pop(person);
    if (choice.addToDatabase) {
      router.push('/people/${person.id}/edit');
    }
  }

  String _personSubtitle(Person person) {
    final List<String> parts = <String>[
      if (person.age != null) person.age!.toString(),
      if (person.religiousLevelLabel.isNotEmpty) person.religiousLevelLabel,
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ];

    return parts.join(' · ');
  }

  void _handleSearchChanged() {
    setState(() {});
  }
}

/// One row of the picker list: either a person or a section label.
class _PickerEntry {
  const _PickerEntry.person(this.person) : sectionLabel = null;
  const _PickerEntry.section(this.sectionLabel) : person = null;

  final Person? person;
  final String? sectionLabel;
}

class _PickerSectionLabel extends StatelessWidget {
  const _PickerSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The way out when the person being looked for is not in the database yet.
class _NotFoundFooter extends StatelessWidget {
  const _NotFoundFooter({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Divider(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 4),
          Text(
            'לא מצאת את מי שחיפשת?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('הוסף שם מחוץ למאגר'),
            ),
          ),
        ],
      ),
    );
  }
}

class MatchProposalFilters {
  const MatchProposalFilters({
    this.minAge,
    this.maxAge,
    this.religiousLevels = const <ReligiousLevel>[],
    this.religiousLevelOtherLabels = const <String>[],
    this.profileStatuses = const <ProfileStatus>[],
  });

  final int? minAge;
  final int? maxAge;
  final List<ReligiousLevel> religiousLevels;
  final List<String> religiousLevelOtherLabels;
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
      religiousLevelOtherLabels: _stringList(
        rawFilters['religiousLevelOtherLabels'],
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
      'religiousLevelOtherLabels': filters.religiousLevelOtherLabels,
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

  static List<String> _stringList(Object? values) {
    if (values is! Iterable) {
      return <String>[];
    }
    return values
        .whereType<String>()
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList();
  }

  @override
  State<MatchProposalFilterSheet> createState() =>
      _MatchProposalFilterSheetState();
}

class _MatchProposalFilterSheetState extends State<MatchProposalFilterSheet> {
  RangeValues? _ageRange;
  final List<ReligiousLevel> _religiousLevels = <ReligiousLevel>[];
  final List<String> _religiousLevelOtherLabels = <String>[];
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
    final List<ReligiousLevel> enabledReligiousLevels = context
        .watch<ReligiousLevelsProvider>()
        .enabledLevels;
    final List<String> enabledReligiousLevelOtherLabels = context
        .watch<ReligiousLevelsProvider>()
        .customLabels;
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
                children: <Widget>[
                  for (final ReligiousLevel level in enabledReligiousLevels)
                    FilterChip(
                      label: Text(level.displayName),
                      selected: _religiousLevels.contains(level),
                      onSelected: (bool value) {
                        setState(() {
                          if (value) {
                            _religiousLevels.add(level);
                          } else {
                            _religiousLevels.remove(level);
                          }
                        });
                      },
                    ),
                  for (final String label in enabledReligiousLevelOtherLabels)
                    FilterChip(
                      label: Text(label),
                      selected: _religiousLevelOtherLabels.contains(label),
                      onSelected: (bool value) {
                        setState(() {
                          if (value) {
                            _religiousLevelOtherLabels.add(label);
                          } else {
                            _religiousLevelOtherLabels.remove(label);
                          }
                        });
                      },
                    ),
                ],
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
                      religiousLevels: _religiousLevels
                          .where(enabledReligiousLevels.contains)
                          .toList(),
                      religiousLevelOtherLabels: _religiousLevelOtherLabels
                          .where(enabledReligiousLevelOtherLabels.contains)
                          .toList(),
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
                      _religiousLevelOtherLabels.clear();
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
    _religiousLevelOtherLabels
      ..clear()
      ..addAll(filters.religiousLevelOtherLabels);

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

/// Result of [_NewPersonDialog]: the entered name and whether to add the person
/// to the database (with details to fill later) or keep them out of it.
class _NewPersonChoice {
  const _NewPersonChoice({required this.name, required this.addToDatabase});

  final String name;
  final bool addToDatabase;
}

/// Collects a name for a person who is not in the database, then offers to add
/// them (for later completion) or use them for this match only.
class _NewPersonDialog extends StatefulWidget {
  const _NewPersonDialog({required this.gender});

  final Gender gender;

  @override
  State<_NewPersonDialog> createState() => _NewPersonDialogState();
}

class _NewPersonDialogState extends State<_NewPersonDialog> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// The dialog is two steps: type a name, then decide whether this person also
  /// joins the database.
  bool _askedForName = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = _nameController.text.trim();
    final bool hasName = name.isNotEmpty;
    final String who = widget.gender == Gender.female ? 'הבחורה' : 'הבחור';
    final String pronoun = widget.gender == Gender.female ? 'עליה' : 'עליו';
    final String alsoAdd = widget.gender == Gender.female ? 'אותה' : 'אותו';

    if (!_askedForName) {
      return AlertDialog(
        title: Text('הוספת $who'),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (hasName) {
              setState(() => _askedForName = true);
            }
          },
          decoration: const InputDecoration(labelText: 'שם'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: hasName
                ? () => setState(() => _askedForName = true)
                : null,
            child: const Text('המשך'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(name),
      content: Text(
        'רוצה להשלים $pronoun פרטים ולהוסיף $alsoAdd גם למאגר?',
        style: theme.textTheme.bodyMedium,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_NewPersonChoice(name: name, addToDatabase: false)),
          child: const Text('לא עכשיו'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_NewPersonChoice(name: name, addToDatabase: true)),
          child: const Text('הוספה למאגר'),
        ),
      ],
    );
  }
}
