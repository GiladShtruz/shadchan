import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';
import 'package:shadchan/widgets/person_list_card.dart';

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
    this.emptySubtitle = '{נסה|נסי} לחפש בשם אחר',
    this.allowCreateOutsideDatabase = false,
    this.filterKey,
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

  /// Turns on the filter button, and is the key its choices are remembered
  /// under.
  ///
  /// Null on the pickers that already arrive pre-filtered — the התאמות flow
  /// hands this sheet a candidate list that is *already* the answer to a
  /// filter, and offering a second one there would be two filters fighting.
  /// Set on the open-a-proposal flow, where the alternative is scrolling the
  /// whole database by name.
  final String? filterKey;

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
    String emptySubtitle = '{נסה|נסי} לחפש בשם אחר',
    bool allowCreateOutsideDatabase = false,
    String? filterKey,
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
            filterKey: filterKey,
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

/// Creates and stores the person behind a "not in the database" choice.
///
/// Someone added to the database is a regular contact from that moment on, even
/// with only a name on their card: the app never keeps a visible person in a
/// "waiting for details" state, which would quietly leave them out of every
/// list and suggestion. Someone left outside the database stays hidden, and
/// keeps the review flag that asks them for their details over WhatsApp.
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
    needsReview: !choice.addToDatabase,
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

  /// The matchmaker's own narrowing, on top of whatever the caller already
  /// required. Restored from the last time this picker was used, because
  /// somebody opening proposals for a 27-year-old דתי לאומי is going to want
  /// the same window again in five minutes.
  MatchProposalFilters? _filters;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    final String? key = widget.filterKey;
    if (key != null) {
      _filters = MatchProposalFilterSheet.savedFiltersFor(key);
    }
  }

  bool get _hasFilters {
    final MatchProposalFilters? filters = _filters;
    return filters != null && !filters.isEmpty;
  }

  /// True when [person] survives the matchmaker's own filter. Deliberately the
  /// same shape as the caller-supplied constraints above it, so the two read as
  /// one list of reasons a candidate is not shown.
  bool _passesFilters(Person person) {
    final MatchProposalFilters? filters = _filters;
    if (filters == null) {
      return true;
    }

    final int? age = person.age;
    if (filters.minAge != null && (age == null || age < filters.minAge!)) {
      return false;
    }
    if (filters.maxAge != null && (age == null || age > filters.maxAge!)) {
      return false;
    }

    final bool hasReligiousFilter =
        filters.religiousLevels.isNotEmpty ||
        filters.religiousLevelOtherLabels.isNotEmpty;
    if (hasReligiousFilter &&
        !filters.religiousLevels.contains(person.religiousLevel) &&
        !(person.religiousLevel == ReligiousLevel.other &&
            filters.religiousLevelOtherLabels.contains(
              person.religiousLevelOther?.trim(),
            ))) {
      return false;
    }

    if (filters.profileStatuses.isNotEmpty &&
        !filters.profileStatuses.contains(person.profileStatus)) {
      return false;
    }

    // Height and marital status are only recorded on some cards, so filtering
    // on them also drops everyone who has nothing written down — the same rule
    // המאגר שלי applies, and the reason the sheet says so above the fields.
    if (!MatchProposalFilters.matchesHeight(person, filters)) {
      return false;
    }
    if (filters.maritalStatuses.isNotEmpty &&
        !filters.maritalStatuses.contains(person.maritalStatus)) {
      return false;
    }
    return true;
  }

  Future<void> _openFilters() async {
    final String? key = widget.filterKey;
    if (key == null) {
      return;
    }
    final MatchProposalFilters? picked = await MatchProposalFilterSheet.show(
      context,
      targetGender: widget.filterGender ?? Gender.unknown,
      sourcePersonId: key,
      initialFilters: _filters,
    );
    if (picked != null && mounted) {
      setState(() => _filters = picked);
    }
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

      if (!_passesFilters(person)) {
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
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            // The same row המאגר שלי puts above its list: one field, one
            // filter button that lights up when something is set.
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
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
                // Searching by name only works when you already know whose name
                // you want. Opening a proposal is the opposite: the matchmaker
                // is looking for whoever fits, so the same filters התאמות uses
                // are offered here too.
                if (widget.filterKey != null) ...<Widget>[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'סינון',
                    onPressed: _openFilters,
                    icon: Icon(
                      _hasFilters ? Icons.filter_list_alt : Icons.tune,
                      color: _hasFilters
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ],
              ],
            ),
            if (_hasFilters) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _filters = null),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('ניקוי הסינון'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
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
                        // The same row המאגר שלי draws, minus its two trailing
                        // buttons: a picker's row has exactly one thing to do.
                        // The hero is off because the list underneath the sheet
                        // is very often the same one, tagged the same way.
                        return PersonListCard(
                          person: person,
                          heroEnabled: false,
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
              label: const Text('הוספת שם מחוץ למאגר'),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the matchmaker narrowed a candidate list down to, and what is written
/// back under the person (or the side) it was chosen for.
class MatchProposalFilters {
  const MatchProposalFilters({
    this.minAge,
    this.maxAge,
    this.religiousLevels = const <ReligiousLevel>[],
    this.religiousLevelOtherLabels = const <String>[],
    this.profileStatuses = const <ProfileStatus>[],
    this.minHeight,
    this.maxHeight,
    this.maritalStatuses = const <MaritalStatus>[],
  });

  final int? minAge;
  final int? maxAge;
  final List<ReligiousLevel> religiousLevels;
  final List<String> religiousLevelOtherLabels;
  final List<ProfileStatus> profileStatuses;

  /// Height and marital status came with the shared filter sheet. They only
  /// ever match a candidate whose card *records* them — see the predicates in
  /// the picker and in the matches view.
  final int? minHeight;
  final int? maxHeight;
  final List<MaritalStatus> maritalStatuses;

  /// True when [person]'s height passes [filters] — false when a height window
  /// is set and their card has no height on it at all.
  static bool matchesHeight(Person person, MatchProposalFilters filters) {
    if (filters.minHeight == null && filters.maxHeight == null) {
      return true;
    }
    final int? height = person.heightCm;
    if (height == null) {
      return false;
    }
    return (filters.minHeight == null || height >= filters.minHeight!) &&
        (filters.maxHeight == null || height <= filters.maxHeight!);
  }

  bool get isEmpty =>
      minAge == null &&
      maxAge == null &&
      religiousLevels.isEmpty &&
      religiousLevelOtherLabels.isEmpty &&
      profileStatuses.isEmpty &&
      minHeight == null &&
      maxHeight == null &&
      maritalStatuses.isEmpty;
}

/// The candidate filter, which is the app's *one* filter sheet —
/// [PeopleFiltersSheet], the same surface "המאגר שלי" opens — plus the memory
/// of what was last chosen for a given person or side.
///
/// It used to be a second sheet of its own, with its own chips, its own slider
/// and its own buttons; two filters that narrow the same database by the same
/// fields should not look like two different features.
abstract final class MatchProposalFilterSheet {
  /// Opens the shared filter sheet and remembers the answer under
  /// [sourcePersonId]. Returns null when it was dismissed.
  static Future<MatchProposalFilters?> show(
    BuildContext context, {
    required Gender targetGender,
    required String sourcePersonId,
    MatchProposalFilters? initialFilters,
  }) async {
    final List<Person> people = context.read<PersonRepository>().getAll();
    final MatchProposalFilters initial =
        savedFiltersFor(sourcePersonId) ??
        initialFilters ??
        const MatchProposalFilters();
    final ({int min, int max})? ageBounds = _ageBounds(people, targetGender);
    const ({int min, int max}) heightBounds = (min: 120, max: 200);

    final PeopleFilterState?
    picked = await showModalBottomSheet<PeopleFilterState>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.84,
      ),
      builder: (BuildContext sheetContext) {
        return PeopleFiltersSheet(
          title: 'סינון מועמדים',
          showGender: false,
          initialGender: targetGender,
          initialAgeRange: _rangeIn(initial.minAge, initial.maxAge, ageBounds),
          ageBounds: ageBounds,
          initialReligiousLevels: initial.religiousLevels,
          initialReligiousLevelOtherLabels: initial.religiousLevelOtherLabels,
          initialProfileStatuses: initial.profileStatuses,
          initialHeightRange: _rangeIn(
            initial.minHeight,
            initial.maxHeight,
            heightBounds,
          ),
          heightBounds: heightBounds,
          initialMaritalStatuses: initial.maritalStatuses,
        );
      },
    );

    if (picked == null) {
      return null;
    }

    final MatchProposalFilters filters = MatchProposalFilters(
      minAge: picked.ageRange?.start.round(),
      maxAge: picked.ageRange?.end.round(),
      religiousLevels: picked.religiousLevels,
      religiousLevelOtherLabels: picked.religiousLevelOtherLabels,
      profileStatuses: picked.profileStatuses,
      minHeight: picked.heightRange?.start.round(),
      maxHeight: picked.heightRange?.end.round(),
      maritalStatuses: picked.maritalStatuses,
    );
    await saveFiltersFor(sourcePersonId, filters);
    return filters;
  }

  /// A saved pair as a slider range, clamped into [bounds].
  ///
  /// The clamp is what keeps a remembered window usable after the database has
  /// moved on: filters saved as 30–34 against a list whose oldest candidate is
  /// now 28 would otherwise hand `RangeSlider` values outside its own track.
  static RangeValues? _rangeIn(
    int? min,
    int? max,
    ({int min, int max})? bounds,
  ) {
    if (min == null || max == null || bounds == null || min > max) {
      return null;
    }
    final double low = bounds.min.toDouble();
    final double high = bounds.max.toDouble();
    return RangeValues(
      min.toDouble().clamp(low, high),
      max.toDouble().clamp(low, high),
    );
  }

  /// The age span the slider spans: the youngest and oldest candidate on the
  /// side being chosen, rather than a fixed product range that would leave most
  /// of the track empty.
  static ({int min, int max})? _ageBounds(
    List<Person> people,
    Gender targetGender,
  ) {
    int? min;
    int? max;
    for (final Person person in people) {
      if (person.needsReview ||
          person.profileStatus.isArchived ||
          person.gender != targetGender) {
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
      minHeight: _readInt(rawFilters['minHeight']),
      maxHeight: _readInt(rawFilters['maxHeight']),
      maritalStatuses: _enumValuesFromNames<MaritalStatus>(
        rawFilters['maritalStatuses'],
        MaritalStatus.values,
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
      'minHeight': filters.minHeight,
      'maxHeight': filters.maxHeight,
      'maritalStatuses': filters.maritalStatuses
          .map((MaritalStatus status) => status.name)
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
