import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/utils/enums.dart';

/// The result of the people-filters bottom sheet. Returned when the user taps
/// "הצג תוצאות"; `null` is returned when the sheet is dismissed.
class PeopleFilterState {
  const PeopleFilterState({
    required this.gender,
    required this.ageRange,
    required this.religiousLevels,
    required this.profileStatuses,
    this.heightRange,
    this.maritalStatuses = const <MaritalStatus>[],
  });

  final Gender? gender;
  final RangeValues? ageRange;
  final List<ReligiousLevel> religiousLevels;
  final List<ProfileStatus> profileStatuses;
  final RangeValues? heightRange;
  final List<MaritalStatus> maritalStatuses;
}

/// Bottom sheet used to filter the people list. The basic filters — gender,
/// age, religious level and availability — are always visible; height and
/// marital status live behind "סינון מורחב" because they only exist on cards
/// where those fields were actually filled in.
class PeopleFiltersSheet extends StatefulWidget {
  const PeopleFiltersSheet({
    super.key,
    required this.initialGender,
    required this.initialAgeRange,
    required this.ageBounds,
    required this.initialReligiousLevels,
    required this.initialProfileStatuses,
    this.initialHeightRange,
    this.heightBounds,
    this.initialMaritalStatuses = const <MaritalStatus>[],
  });

  final Gender? initialGender;
  final RangeValues? initialAgeRange;
  final ({int min, int max})? ageBounds;
  final List<ReligiousLevel> initialReligiousLevels;
  final List<ProfileStatus> initialProfileStatuses;
  final RangeValues? initialHeightRange;

  /// Min/max height across the people being filtered. Null when nobody has a
  /// height yet, which hides the slider instead of showing an empty one.
  final ({int min, int max})? heightBounds;
  final List<MaritalStatus> initialMaritalStatuses;

  @override
  State<PeopleFiltersSheet> createState() => _PeopleFiltersSheetState();
}

class _PeopleFiltersSheetState extends State<PeopleFiltersSheet> {
  Gender? tempGender;
  RangeValues? tempAgeRange;
  RangeValues? tempHeightRange;
  late List<ReligiousLevel> tempReligiousLevels;
  late List<ProfileStatus> tempProfileStatuses;
  late List<MaritalStatus> tempMaritalStatuses;

  /// Whether the extended section is open. It starts open when one of its
  /// filters is already applied, so an active filter is never hidden.
  late bool _advancedExpanded;

  @override
  void initState() {
    super.initState();
    tempGender = widget.initialGender;
    tempAgeRange = widget.initialAgeRange;
    tempHeightRange = widget.initialHeightRange;
    tempMaritalStatuses = List<MaritalStatus>.from(
      widget.initialMaritalStatuses,
    );
    tempReligiousLevels = List<ReligiousLevel>.from(
      widget.initialReligiousLevels,
    );
    tempProfileStatuses = List<ProfileStatus>.from(
      widget.initialProfileStatuses,
    );
    _advancedExpanded =
        widget.initialHeightRange != null ||
        widget.initialMaritalStatuses.isNotEmpty;
  }

  /// Only the styles enabled in settings are worth filtering by, plus any that
  /// people in the database already carry from before they were switched off.
  List<ReligiousLevel> _filterableLevels(BuildContext context) {
    final List<ReligiousLevel> enabled = context
        .watch<ReligiousLevelsProvider>()
        .enabledLevels;
    final List<ReligiousLevel> missing = tempReligiousLevels
        .where((ReligiousLevel level) => !enabled.contains(level))
        .toList();
    return <ReligiousLevel>[...enabled, ...missing];
  }

  RangeValues? _normalizedAgeRange() =>
      _normalizedRange(tempAgeRange, widget.ageBounds);

  RangeValues? _normalizedHeightRange() =>
      _normalizedRange(tempHeightRange, widget.heightBounds);

  /// A range that still covers the full span is the same as no filter at all,
  /// so it is reported as null and does not light up the "filter active" dot.
  static RangeValues? _normalizedRange(
    RangeValues? range,
    ({int min, int max})? bounds,
  ) {
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
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('סינון אנשים', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('מין', style: theme.textTheme.titleMedium),
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
                _RangeFilter(
                  bounds: widget.ageBounds!,
                  value: tempAgeRange,
                  labelBuilder: (RangeValues range) =>
                      'טווח גילאים: ${range.start.round()}-${range.end.round()}',
                  onChanged: (RangeValues value) {
                    setState(() {
                      tempAgeRange = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
              Text('סגנון דתי', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _filterableLevels(context).map((ReligiousLevel level) {
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
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _advancedExpanded = !_advancedExpanded;
                    });
                  },
                  icon: Icon(
                    _advancedExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: const Text('סינון מורחב'),
                ),
              ),
              if (_advancedExpanded) ...<Widget>[
                Text(
                  'שימו לב: יוצגו רק כרטיסים שבהם פרטים אלה עודכנו.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.heightBounds != null) ...<Widget>[
                  _RangeFilter(
                    bounds: widget.heightBounds!,
                    value: tempHeightRange,
                    labelBuilder: (RangeValues range) =>
                        'טווח גובה: ${range.start.round()}-${range.end.round()} ס״מ',
                    onChanged: (RangeValues value) {
                      setState(() {
                        tempHeightRange = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                Text('מצב משפחתי', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: MaritalStatus.values.map((MaritalStatus status) {
                    final bool isSelected = tempMaritalStatuses.contains(
                      status,
                    );
                    return FilterChip(
                      // Gender-neutral wording: the list can hold both.
                      label: Text(status.filterLabel),
                      selected: isSelected,
                      onSelected: (bool selected) {
                        setState(() {
                          if (selected) {
                            tempMaritalStatuses = <MaritalStatus>[
                              ...tempMaritalStatuses,
                              status,
                            ];
                          } else {
                            tempMaritalStatuses = tempMaritalStatuses
                                .where((MaritalStatus item) => item != status)
                                .toList();
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
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
                        heightRange: _normalizedHeightRange(),
                        maritalStatuses: tempMaritalStatuses,
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
                      tempHeightRange = null;
                      tempReligiousLevels = <ReligiousLevel>[];
                      tempProfileStatuses = <ProfileStatus>[];
                      tempMaritalStatuses = <MaritalStatus>[];
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

/// A titled range slider that degrades gracefully when every person shares the
/// same value (a slider with a single stop cannot be dragged).
class _RangeFilter extends StatelessWidget {
  const _RangeFilter({
    required this.bounds,
    required this.value,
    required this.labelBuilder,
    required this.onChanged,
  });

  final ({int min, int max}) bounds;
  final RangeValues? value;
  final String Function(RangeValues range) labelBuilder;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    final RangeValues effective =
        value ??
        RangeValues(bounds.min.toDouble(), bounds.max.toDouble());
    final bool sliderDisabled = bounds.min == bounds.max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          labelBuilder(effective),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        RangeSlider(
          min: bounds.min.toDouble(),
          max: sliderDisabled
              ? (bounds.max + 1).toDouble()
              : bounds.max.toDouble(),
          values: effective,
          divisions: sliderDisabled ? 1 : (bounds.max - bounds.min),
          labels: RangeLabels(
            effective.start.round().toString(),
            effective.end.round().toString(),
          ),
          onChanged: sliderDisabled ? null : onChanged,
        ),
      ],
    );
  }
}
