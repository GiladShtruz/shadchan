import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

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
  });

  final Gender? filterGender;
  final Set<String> excludeIds;
  final String title;
  final int? minAge;
  final int? maxAge;
  final List<ReligiousLevel> religiousLevels;
  final List<ProfileStatus> profileStatuses;

  static Future<Person?> show(
    BuildContext context, {
    required String title,
    Gender? filterGender,
    Set<String> excludeIds = const <String>{},
    int? minAge,
    int? maxAge,
    List<ReligiousLevel> religiousLevels = const <ReligiousLevel>[],
    List<ProfileStatus> profileStatuses = const <ProfileStatus>[],
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
                  ? const EmptyState(
                      icon: Icons.search,
                      title: 'לא נמצאו תוצאות',
                      subtitle: 'נסו לחפש בשם אחר',
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
  const MatchProposalFilterSheet({super.key, required this.targetGender});

  final Gender targetGender;

  static const int _minAge = 18;
  static const int _maxAge = 50;
  static const RangeValues _defaultAgeRange = RangeValues(18, 50);

  static Future<MatchProposalFilters?> show(
    BuildContext context, {
    required Gender targetGender,
  }) {
    return showModalBottomSheet<MatchProposalFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return MatchProposalFilterSheet(targetGender: targetGender);
      },
    );
  }

  @override
  State<MatchProposalFilterSheet> createState() =>
      _MatchProposalFilterSheetState();
}

class _MatchProposalFilterSheetState extends State<MatchProposalFilterSheet> {
  RangeValues _ageRange = MatchProposalFilterSheet._defaultAgeRange;
  final List<ReligiousLevel> _religiousLevels = <ReligiousLevel>[];
  final List<ProfileStatus> _profileStatuses = <ProfileStatus>[
    ProfileStatus.available,
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasAgeFilter =
        _ageRange != MatchProposalFilterSheet._defaultAgeRange;

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
                'סינון ${widget.targetGender.displayName}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'טווח גילאים: ${_ageRange.start.round()}-${_ageRange.end.round()}',
                style: theme.textTheme.titleMedium,
              ),
              RangeSlider(
                min: MatchProposalFilterSheet._minAge.toDouble(),
                max: MatchProposalFilterSheet._maxAge.toDouble(),
                values: _ageRange,
                divisions: MatchProposalFilterSheet._maxAge -
                    MatchProposalFilterSheet._minAge,
                labels: RangeLabels(
                  _ageRange.start.round().toString(),
                  _ageRange.end.round().toString(),
                ),
                onChanged: (RangeValues value) {
                  setState(() => _ageRange = value);
                },
              ),
              const SizedBox(height: 12),
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
                children: <ProfileStatus>[
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
                  onPressed: () {
                    Navigator.of(context).pop(
                      MatchProposalFilters(
                        minAge: hasAgeFilter ? _ageRange.start.round() : null,
                        maxAge: hasAgeFilter ? _ageRange.end.round() : null,
                        religiousLevels: List<ReligiousLevel>.from(
                          _religiousLevels,
                        ),
                        profileStatuses: List<ProfileStatus>.from(
                          _profileStatuses,
                        ),
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
                      _ageRange = MatchProposalFilterSheet._defaultAgeRange;
                      _religiousLevels.clear();
                      _profileStatuses.clear();
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
