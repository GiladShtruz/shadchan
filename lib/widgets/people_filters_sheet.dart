import 'package:flutter/material.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/person_tags_editor.dart';

/// The result of the people-filters bottom sheet. Returned when the user taps
/// "הצג תוצאות"; `null` is returned when the sheet is dismissed.
class PeopleFilterState {
  const PeopleFilterState({
    required this.gender,
    required this.ageRange,
    required this.religiousLevels,
    this.religiousLevelOtherLabels = const <String>[],
    required this.profileStatuses,
    this.heightRange,
    this.maritalStatuses = const <MaritalStatus>[],
    this.regions = const <Region>[],
    this.tags = const <String>[],
  });

  final Gender? gender;
  final RangeValues? ageRange;
  final List<ReligiousLevel> religiousLevels;
  final List<String> religiousLevelOtherLabels;
  final List<ProfileStatus> profileStatuses;
  final RangeValues? heightRange;
  final List<MaritalStatus> maritalStatuses;

  /// Regions of the country: a person matches when theirs is any of these.
  /// Like height, only a card that records a region can match.
  final List<Region> regions;

  /// The matchmaker's own tags: a person matches when they carry any of them.
  final List<String> tags;
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
    this.initialReligiousLevelOtherLabels = const <String>[],
    required this.initialProfileStatuses,
    this.initialHeightRange,
    this.heightBounds,
    this.initialMaritalStatuses = const <MaritalStatus>[],
    this.initialRegions = const <Region>[],
    this.availableTags = const <String>[],
    this.initialTags = const <String>[],
    this.title = 'סינון אנשים',
    this.showGender = true,
  });

  /// What the sheet calls itself. The one filter surface serves both the
  /// database and the candidate pickers, and each says whose list it narrows.
  final String title;

  /// Whether the "מין" card is offered. The pickers arrive with the side
  /// already decided by the flow that opened them, and changing it there could
  /// only ever produce an empty list, so they hide the card and the sheet
  /// returns [initialGender] untouched.
  final bool showGender;

  final Gender? initialGender;
  final RangeValues? initialAgeRange;
  final ({int min, int max})? ageBounds;
  final List<ReligiousLevel> initialReligiousLevels;
  final List<String> initialReligiousLevelOtherLabels;
  final List<ProfileStatus> initialProfileStatuses;
  final RangeValues? initialHeightRange;

  /// Fixed product range for height filtering: 120–200 cm.
  final ({int min, int max})? heightBounds;
  final List<MaritalStatus> initialMaritalStatuses;
  final List<Region> initialRegions;

  /// Every tag in use in the database. Empty hides the "תגיות" card.
  final List<String> availableTags;
  final List<String> initialTags;

  @override
  State<PeopleFiltersSheet> createState() => _PeopleFiltersSheetState();
}

class _PeopleFiltersSheetState extends State<PeopleFiltersSheet> {
  Gender? tempGender;
  RangeValues? tempAgeRange;
  RangeValues? tempHeightRange;
  late List<ReligiousLevel> tempReligiousLevels;
  late List<String> tempReligiousLevelOtherLabels;
  late List<ProfileStatus> tempProfileStatuses;
  late List<MaritalStatus> tempMaritalStatuses;
  late List<Region> tempRegions;
  late List<String> tempTags;

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
    tempTags = List<String>.from(widget.initialTags);
    tempRegions = List<Region>.from(widget.initialRegions);
    tempReligiousLevels = List<ReligiousLevel>.from(
      widget.initialReligiousLevels,
    );
    tempReligiousLevelOtherLabels = List<String>.from(
      widget.initialReligiousLevelOtherLabels,
    );
    tempProfileStatuses = List<ProfileStatus>.from(
      widget.initialProfileStatuses,
    );
    _advancedExpanded =
        widget.initialHeightRange != null ||
        widget.initialMaritalStatuses.isNotEmpty ||
        widget.initialRegions.isNotEmpty;
  }

  /// The one global list, every time.
  List<ReligiousLevel> _filterableLevels(BuildContext context) {
    return ReligiousLevels.global;
  }

  /// Custom "אחר" labels are no longer offered; one already inside a saved
  /// filter stays visible so it can be taken off.
  List<String> _filterableCustomLabels(BuildContext context) {
    return widget.initialReligiousLevelOtherLabels;
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
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (widget.showGender) ...<Widget>[
                      _FilterSectionCard(
                        title: 'מין',
                        child: _ChipWrap(
                          children: <Widget>[
                            _FilterPill(
                              label: 'הכל',
                              selected: tempGender == null,
                              onTap: () => setState(() {
                                tempGender = null;
                              }),
                            ),
                            _FilterPill(
                              label: Gender.male.displayName,
                              selected: tempGender == Gender.male,
                              onTap: () => setState(() {
                                tempGender = Gender.male;
                              }),
                            ),
                            _FilterPill(
                              label: Gender.female.displayName,
                              selected: tempGender == Gender.female,
                              onTap: () => setState(() {
                                tempGender = Gender.female;
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (widget.ageBounds != null) ...<Widget>[
                      _FilterSectionCard(
                        title: 'גיל',
                        child: _RangeFilter(
                          bounds: widget.ageBounds!,
                          value: tempAgeRange,
                          startLabel: 'מגיל',
                          endLabel: 'עד',
                          onChanged: (RangeValues value) {
                            setState(() {
                              tempAgeRange = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _FilterSectionCard(
                      title: 'סגנון דתי',
                      child: _ChipWrap(
                        children: <Widget>[
                          for (final ReligiousLevel level in _filterableLevels(
                            context,
                          ))
                            _FilterPill(
                              label: level.displayName,
                              selected: tempReligiousLevels.contains(level),
                              onTap: () {
                                setState(() {
                                  if (tempReligiousLevels.contains(level)) {
                                    tempReligiousLevels = tempReligiousLevels
                                        .where(
                                          (ReligiousLevel item) =>
                                              item != level,
                                        )
                                        .toList();
                                  } else {
                                    tempReligiousLevels = <ReligiousLevel>[
                                      ...tempReligiousLevels,
                                      level,
                                    ];
                                  }
                                });
                              },
                            ),
                          for (final String label in _filterableCustomLabels(
                            context,
                          ))
                            _FilterPill(
                              label: label,
                              selected: tempReligiousLevelOtherLabels.contains(
                                label,
                              ),
                              onTap: () {
                                setState(() {
                                  if (tempReligiousLevelOtherLabels.contains(
                                    label,
                                  )) {
                                    tempReligiousLevelOtherLabels =
                                        tempReligiousLevelOtherLabels
                                            .where(
                                              (String item) => item != label,
                                            )
                                            .toList();
                                  } else {
                                    tempReligiousLevelOtherLabels = <String>[
                                      ...tempReligiousLevelOtherLabels,
                                      label,
                                    ];
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _FilterSectionCard(
                      title: 'סטטוס',
                      child: _ChipWrap(
                        children: <Widget>[
                          for (final ProfileStatus status in <ProfileStatus>[
                            ProfileStatus.available,
                            ProfileStatus.busy,
                            ProfileStatus.onBreak,
                          ])
                            _FilterPill(
                              label: status.displayName,
                              selected: tempProfileStatuses.contains(status),
                              onTap: () {
                                setState(() {
                                  if (tempProfileStatuses.contains(status)) {
                                    tempProfileStatuses = tempProfileStatuses
                                        .where(
                                          (ProfileStatus item) =>
                                              item != status,
                                        )
                                        .toList();
                                  } else {
                                    tempProfileStatuses = <ProfileStatus>[
                                      ...tempProfileStatuses,
                                      status,
                                    ];
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    if (widget.availableTags.isNotEmpty ||
                        tempTags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      _FilterSectionCard(
                        title: 'תגיות',
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 150),
                          child: SingleChildScrollView(
                            child: _ChipWrap(
                              children: <Widget>[
                                for (final String tag in <String>{
                                  ...tempTags,
                                  ...widget.availableTags,
                                })
                                  _FilterPill(
                                    label: tag,
                                    selected: tempTags.contains(tag),
                                    onTap: () => setState(() {
                                      tempTags = tempTags.contains(tag)
                                          ? tempTags
                                                .where((String t) => t != tag)
                                                .toList()
                                          : <String>[...tempTags, tag];
                                    }),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _AdvancedFilterCard(
                      expanded: _advancedExpanded,
                      onTap: () {
                        setState(() {
                          _advancedExpanded = !_advancedExpanded;
                        });
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'יוצגו רק כרטיסים שבהם הפרטים האלה עודכנו.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'גובה',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _RangeFilter(
                            bounds: widget.heightBounds ?? (min: 120, max: 200),
                            value: tempHeightRange,
                            startLabel: 'מגובה',
                            endLabel: 'עד',
                            suffix: 'ס״מ',
                            onChanged: (RangeValues value) {
                              setState(() {
                                tempHeightRange = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'אזור בארץ',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _ChipWrap(
                            children: <Widget>[
                              for (final Region region in <Region>{
                                ...Regions.selectable,
                                ...tempRegions,
                              })
                                _FilterPill(
                                  label: region.displayName,
                                  selected: tempRegions.contains(region),
                                  onTap: () => setState(() {
                                    tempRegions = tempRegions.contains(region)
                                        ? tempRegions
                                              .where((Region r) => r != region)
                                              .toList()
                                        : <Region>[...tempRegions, region];
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'מצב משפחתי',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _ChipWrap(
                            children: MaritalStatus.values.map((
                              MaritalStatus status,
                            ) {
                              return _FilterPill(
                                label: status.filterLabel,
                                selected: tempMaritalStatuses.contains(status),
                                onTap: () {
                                  setState(() {
                                    if (tempMaritalStatuses.contains(status)) {
                                      tempMaritalStatuses = tempMaritalStatuses
                                          .where(
                                            (MaritalStatus item) =>
                                                item != status,
                                          )
                                          .toList();
                                    } else {
                                      tempMaritalStatuses = <MaritalStatus>[
                                        ...tempMaritalStatuses,
                                        status,
                                      ];
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _FilterActionsBar(
              onApply: () {
                Navigator.of(context).pop(
                  PeopleFilterState(
                    gender: tempGender,
                    ageRange: _normalizedAgeRange(),
                    religiousLevels: tempReligiousLevels
                        .where(_filterableLevels(context).contains)
                        .toList(),
                    religiousLevelOtherLabels: tempReligiousLevelOtherLabels
                        .where(_filterableCustomLabels(context).contains)
                        .toList(),
                    profileStatuses: tempProfileStatuses,
                    heightRange: _normalizedHeightRange(),
                    maritalStatuses: tempMaritalStatuses,
                    regions: tempRegions,
                    tags: tempTags,
                  ),
                );
              },
              onClear: () {
                setState(() {
                  // A hidden gender is not the user's to clear: it is the side
                  // the flow is already choosing.
                  if (widget.showGender) {
                    tempGender = null;
                  }
                  tempAgeRange = null;
                  tempHeightRange = null;
                  tempReligiousLevels = <ReligiousLevel>[];
                  tempReligiousLevelOtherLabels = <String>[];
                  tempProfileStatuses = <ProfileStatus>[];
                  tempMaritalStatuses = <MaritalStatus>[];
                  tempRegions = <Region>[];
                  tempTags = <String>[];
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One group of the sheet: a small heading and its chips, on paper.
///
/// **Compact on purpose.** The groups were tall cards of large chips, and the
/// sheet scrolled for a screenful before its last filter; the same choices now
/// read at a glance, in the tag style the rest of the app uses.
class _FilterSectionCard extends StatelessWidget {
  const _FilterSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// The chips of one group, wrapping at the reading start.
class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, children: children);
  }
}

/// One choice — the same small outlined chip the tags are drawn with.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TagChip(label: label, selected: selected, onTap: onTap);
  }
}

class _AdvancedFilterCard extends StatelessWidget {
  const _AdvancedFilterCard({
    required this.expanded,
    required this.onTap,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'סינון מורחב',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: child,
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _FilterActionsBar extends StatelessWidget {
  const _FilterActionsBar({required this.onApply, required this.onClear});

  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: FilledButton(
              onPressed: onApply,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('הצגת תוצאות'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: OutlinedButton(
              onPressed: onClear,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                side: BorderSide(color: theme.colorScheme.secondary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('נקה'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A range slider with compact minimum/maximum value boxes.
class _RangeFilter extends StatelessWidget {
  const _RangeFilter({
    required this.bounds,
    required this.value,
    required this.startLabel,
    required this.endLabel,
    required this.onChanged,
    this.suffix,
  });

  final ({int min, int max}) bounds;
  final RangeValues? value;
  final String startLabel;
  final String endLabel;
  final ValueChanged<RangeValues> onChanged;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final RangeValues effective =
        value ?? RangeValues(bounds.min.toDouble(), bounds.max.toDouble());
    final bool sliderDisabled = bounds.min == bounds.max;

    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: theme.colorScheme.primary,
            inactiveTrackColor: theme.colorScheme.outlineVariant,
            thumbColor: theme.colorScheme.primary,
            overlayColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            trackHeight: 5,
          ),
          child: RangeSlider(
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
        ),
        const SizedBox(height: 2),
        Row(
          children: <Widget>[
            Text(startLabel, style: theme.textTheme.bodyMedium),
            const SizedBox(width: 8),
            _RangeValueBox(value: effective.start.round()),
            const Spacer(),
            Text(endLabel, style: theme.textTheme.bodyMedium),
            const SizedBox(width: 8),
            _RangeValueBox(value: effective.end.round()),
            if (suffix != null) ...<Widget>[
              const SizedBox(width: 6),
              Text(suffix!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ],
    );
  }
}

class _RangeValueBox extends StatelessWidget {
  const _RangeValueBox({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        value.toString(),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
