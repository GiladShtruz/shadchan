import 'package:flutter/material.dart';
import 'package:shadchan/utils/enums.dart';

/// The result of the people-filters bottom sheet. Returned when the user taps
/// "הצג תוצאות"; `null` is returned when the sheet is dismissed.
class PeopleFilterState {
  const PeopleFilterState({
    required this.gender,
    required this.ageRange,
    required this.religiousLevels,
    required this.profileStatuses,
    required this.city,
    required this.favoritesOnly,
  });

  final Gender? gender;
  final RangeValues? ageRange;
  final List<ReligiousLevel> religiousLevels;
  final List<ProfileStatus> profileStatuses;
  final String city;
  final bool favoritesOnly;
}

/// Shared bottom sheet used to filter a list of people by gender, age range,
/// religious level, profile status and favorites. Used by both the people
/// screen and the home screen so the filtering experience stays identical.
class PeopleFiltersSheet extends StatefulWidget {
  const PeopleFiltersSheet({
    super.key,
    required this.initialGender,
    required this.initialAgeRange,
    required this.ageBounds,
    required this.initialReligiousLevels,
    required this.initialProfileStatuses,
    required this.initialCity,
    required this.initialFavoritesOnly,
  });

  final Gender? initialGender;
  final RangeValues? initialAgeRange;
  final ({int min, int max})? ageBounds;
  final List<ReligiousLevel> initialReligiousLevels;
  final List<ProfileStatus> initialProfileStatuses;
  final String initialCity;
  final bool initialFavoritesOnly;

  @override
  State<PeopleFiltersSheet> createState() => _PeopleFiltersSheetState();
}

class _PeopleFiltersSheetState extends State<PeopleFiltersSheet> {
  Gender? tempGender;
  RangeValues? tempAgeRange;
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

  RangeValues? _normalizedAgeRange() {
    final RangeValues? range = tempAgeRange;
    final ({int min, int max})? bounds = widget.ageBounds;
    if (range == null || bounds == null) {
      return null;
    }
    if (range.start.round() <= bounds.min && range.end.round() >= bounds.max) {
      return null;
    }
    return range;
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
              if (widget.ageBounds != null) ...<Widget>[
                Builder(
                  builder: (BuildContext context) {
                    final ({int min, int max}) bounds = widget.ageBounds!;
                    final RangeValues effective =
                        tempAgeRange ??
                        RangeValues(
                          bounds.min.toDouble(),
                          bounds.max.toDouble(),
                        );
                    final bool sliderDisabled = bounds.min == bounds.max;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'טווח גילאים: ${effective.start.round()}-${effective.end.round()}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        RangeSlider(
                          min: bounds.min.toDouble(),
                          max: sliderDisabled
                              ? (bounds.max + 1).toDouble()
                              : bounds.max.toDouble(),
                          values: effective,
                          divisions: sliderDisabled
                              ? 1
                              : (bounds.max - bounds.min),
                          labels: RangeLabels(
                            effective.start.round().toString(),
                            effective.end.round().toString(),
                          ),
                          onChanged: sliderDisabled
                              ? null
                              : (RangeValues value) {
                                  setState(() {
                                    tempAgeRange = value;
                                  });
                                },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
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
                      PeopleFilterState(
                        gender: tempGender,
                        ageRange: _normalizedAgeRange(),
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
                      tempAgeRange = null;
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
