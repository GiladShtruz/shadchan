import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';
import 'package:shadchan/widgets/person_list_card.dart';
import 'package:shadchan/widgets/reminders_bell_button.dart';
import 'package:shadchan/widgets/sort_direction_toggle.dart';

enum PeopleSortOption { alphabetical, ageAscending, newest, recentlyUpdated }

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({
    super.key,
    this.initialShowArchived = false,
    this.initialProfileStatuses = const <ProfileStatus>[],
    this.initialSort = PeopleSortOption.alphabetical,
    this.importBatchId,
  });

  final bool initialShowArchived;
  final List<ProfileStatus> initialProfileStatuses;
  final PeopleSortOption initialSort;

  /// Show only the people one import just added, and nothing else.
  ///
  /// **A temporary view of the database, not a filter on it.** An import of
  /// forty contacts drops forty half-finished cards into a list of six hundred
  /// finished ones, and finding them again afterwards means remembering
  /// forty names. Landing on just those forty — openable, editable, and
  /// returnable-to — is the difference between an import somebody tidies up
  /// and one they abandon.
  ///
  /// It is deliberately not one of the saved filters: the batch stops being
  /// interesting the moment it has been gone through, and "לכל המאגר" leaves it
  /// for good rather than adding another chip to clear.
  final String? importBatchId;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final TextEditingController _searchController = TextEditingController();

  Gender? _selectedGender;
  RangeValues? _selectedAgeRange;
  List<ReligiousLevel> _selectedReligiousLevels = <ReligiousLevel>[];
  List<String> _selectedReligiousLevelOtherLabels = <String>[];
  List<ProfileStatus> _selectedProfileStatuses = <ProfileStatus>[];
  RangeValues? _selectedHeightRange;
  List<MaritalStatus> _selectedMaritalStatuses = <MaritalStatus>[];
  bool _showArchived = false;
  PeopleSortOption _sortOption = PeopleSortOption.alphabetical;

  /// Cleared by "לכל המאגר", which is the only way out of the batch view.
  String? _importBatchId;

  /// Sort direction applied on top of [_sortOption]. `true` keeps each option's
  /// natural order; `false` reverses it ("עולה" / "יורד").
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _showArchived = widget.initialShowArchived;
    _sortOption = widget.initialSort;
    _selectedProfileStatuses = List<ProfileStatus>.from(
      widget.initialProfileStatuses,
    );
    _importBatchId = widget.importBatchId;
    // Newest first inside the batch, so the order matches the order they were
    // read out of the file.
    if (_importBatchId != null) {
      _sortOption = PeopleSortOption.newest;
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
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();

    final int totalCount = personRepository.databaseCount;
    final List<Person> pendingContactDrafts = personRepository
        .getPendingContactDrafts();
    final List<Person> visiblePeople = _getVisiblePeople(personRepository);

    return Scaffold(
      appBar: AppBar(
        title: const Text('המאגר שלי'),
        centerTitle: true,
        actions: <Widget>[
          // The same bell, in the same slot, as בית and רעיונות. It leads the
          // group so the three screens agree on where it is; adding people is
          // this screen's own action and follows it, with the button in the
          // thumb's corner carrying most of that traffic anyway.
          const RemindersBellButton(),
          IconButton(
            tooltip: 'הוספת אנשי קשר',
            icon: const Icon(Icons.add),
            onPressed: () => AddPeopleDialog.show(context),
          ),
        ],
      ),
      // Adding a friend is the whole point of this screen, so it gets the
      // thumb's corner as well as the app bar. The icon in the bar stays: it is
      // where someone who already knows the app looks, and the two open exactly
      // the same sheet.
      floatingActionButton: FloatingActionButton(
        // `endFloat` in RTL is the bottom-left corner — the same place the
        // messaging apps everyone already uses put theirs.
        tooltip: 'הוספת חברים',
        onPressed: () => AddPeopleDialog.show(context),
        child: const Icon(Icons.add),
      ),
      // Only the search row is fixed; the banner, gender tabs and the list all
      // scroll together as one page.
      body: Column(
        children: <Widget>[
          if (_importBatchId != null)
            _JustAddedBar(
              count: visiblePeople.length,
              onShowAll: () => setState(() => _importBatchId = null),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _buildSearchRow(theme),
          ),
          Expanded(
            child: _buildContent(
              context: context,
              theme: theme,
              totalCount: totalCount,
              pendingContactDrafts: pendingContactDrafts,
              visiblePeople: visiblePeople,
            ),
          ),
        ],
      ),
    );
  }

  /// A single row: the search field, then the filter and sort buttons.
  Widget _buildSearchRow(ThemeData theme) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'חיפוש במאגר שלי',
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
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'סינון',
          onPressed: _openFiltersSheet,
          icon: Icon(
            _hasActiveFilters ? Icons.filter_list_alt : Icons.tune,
            color: _hasActiveFilters ? theme.colorScheme.primary : null,
          ),
        ),
        IconButton(
          tooltip: 'מיון',
          onPressed: _openSortSheet,
          icon: const Icon(Icons.sort),
        ),
      ],
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required ThemeData theme,
    required int totalCount,
    required List<Person> pendingContactDrafts,
    required List<Person> visiblePeople,
  }) {
    if (totalCount == 0 && pendingContactDrafts.isEmpty) {
      return _buildEmptyPeopleState(context, theme);
    }

    return CustomScrollView(
      slivers: <Widget>[
        if (pendingContactDrafts.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _PendingContactDraftsBanner(
                count: pendingContactDrafts.length,
                onTap: () =>
                    _completePendingContactDrafts(pendingContactDrafts),
              ),
            ),
          ),
        if (_hasActiveFilters)
          SliverToBoxAdapter(
            child: Padding(
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
          ),
        if (totalCount > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _MembersBanner(count: totalCount),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _GenderTabs(
              selected: _selectedGender,
              onChanged: (Gender? gender) {
                setState(() {
                  _selectedGender = gender;
                });
              },
            ),
          ),
        ),
        if (visiblePeople.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search,
              title: 'לא נמצאו תוצאות',
              subtitle: '{נסה|נסי} לשנות את החיפוש או את הסינון',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.builder(
              itemCount: visiblePeople.length,
              itemBuilder: (BuildContext context, int index) {
                final Person person = visiblePeople[index];
                return PersonListCard(
                  person: person,
                  onTap: () => context.push('/people/${person.id}'),
                  onLongPress: () => _showPersonActions(context, person),
                  onToggleFavorite: () => context
                      .read<PersonRepository>()
                      .toggleFavorite(person.id),
                  onOpenMatches: () => _openMatchSuggestions(context, person),
                  onOpenWhatsApp: () => _openWhatsApp(context, person),
                );
              },
            ),
          ),
      ],
    );
  }

  /// The heart on a row opens the same "התאמות" view the profile does — the
  /// suggestions list with its filter, quick card and accept/reject actions —
  /// but raised as a sheet over the list, so closing it puts the database back
  /// exactly where it was rather than walking back through a pushed page.
  Future<void> _openMatchSuggestions(
    BuildContext context,
    Person person,
  ) async {
    if (person.gender == Gender.unknown) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('יש לבחור מגדר לאיש הקשר לפני פתיחת התאמות'),
          ),
        );
      return;
    }
    await openSuggestionsSheet(context, person.id);
  }

  /// Walks the drafts left over from an older version of the app, one dialog
  /// each. Cancelling one drops it for good: a contact is either completed into
  /// the database or discarded, never left waiting for details.
  Future<void> _completePendingContactDrafts(
    List<Person> pendingContactDrafts,
  ) async {
    final PersonRepository repository = context.read<PersonRepository>();
    final List<Person> drafts = List<Person>.from(pendingContactDrafts);

    for (int index = 0; index < drafts.length; index++) {
      if (!mounted) {
        return;
      }
      final Person person = drafts[index];
      final QuickUpdateOutcome outcome = await QuickUpdateDialog.show(
        context,
        person,
        stepIndex: index + 1,
        stepCount: drafts.length,
      );
      if (!outcome.isAdded) {
        // The record itself is kept (it may be a contact that was only
        // soft-deleted) but stops waiting for anything.
        await repository.discardContactDraft(person, deleteRecord: false);
        return;
      }
      if (!mounted) {
        return;
      }
      try {
        await repository.activatePendingContactDraft(person);
        if (outcome == QuickUpdateOutcome.openFullEditor && mounted) {
          // The full card ends on that person's profile, so the rest of the
          // batch is left rather than resumed behind it.
          await openExtendedPersonEditor(context, person.id, isNewFriend: true);
          if (mounted) {
            context.push('/people/${person.id}');
          }
          return;
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('לא הצלחנו לשמור את הפרטים')),
            );
        }
        return;
      }
    }
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

    for (final String label in _selectedReligiousLevelOtherLabels) {
      chips.add(
        InputChip(
          label: Text(label),
          onDeleted: () {
            setState(() {
              _selectedReligiousLevelOtherLabels =
                  _selectedReligiousLevelOtherLabels
                      .where((String item) => item != label)
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

    final RangeValues? heightRange = _selectedHeightRange;
    if (heightRange != null) {
      chips.add(
        InputChip(
          label: Text(
            'גובה ${heightRange.start.round()}-${heightRange.end.round()}',
          ),
          onDeleted: () {
            setState(() {
              _selectedHeightRange = null;
            });
          },
        ),
      );
    }

    for (final MaritalStatus status in _selectedMaritalStatuses) {
      chips.add(
        InputChip(
          label: Text(status.filterLabel),
          onDeleted: () {
            setState(() {
              _selectedMaritalStatuses = _selectedMaritalStatuses
                  .where((MaritalStatus item) => item != status)
                  .toList();
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
      religiousLevelOtherLabels: _selectedReligiousLevelOtherLabels,
      profileStatuses: _selectedProfileStatuses,
      // Contacts still waiting for an update are part of the general list too.
      includePending: true,
    );

    final String normalizedSearch = _searchController.text.trim().toLowerCase();

    final String? batchId = _importBatchId;
    final List<Person> visiblePeople = filteredPeople.where((Person person) {
      // The batch view answers one question and ignores every other control on
      // the screen except the search box.
      if (batchId != null && person.importBatchId != batchId) {
        return false;
      }
      final bool matchesSearch =
          normalizedSearch.isEmpty ||
          person.firstName.toLowerCase().contains(normalizedSearch) ||
          person.lastName.toLowerCase().contains(normalizedSearch) ||
          person.fullName.toLowerCase().contains(normalizedSearch);

      final bool matchesArchive = _showArchived
          ? person.profileStatus.isArchived
          : !person.profileStatus.isArchived;

      // A height/marital filter also excludes people with nothing recorded —
      // otherwise "רק 170-180" would still list everyone with no height.
      final RangeValues? heightRange = _selectedHeightRange;
      final bool matchesHeight =
          heightRange == null ||
          (person.heightCm != null &&
              person.heightCm! >= heightRange.start.round() &&
              person.heightCm! <= heightRange.end.round());

      final bool matchesMaritalStatus =
          _selectedMaritalStatuses.isEmpty ||
          (person.maritalStatus != null &&
              _selectedMaritalStatuses.contains(person.maritalStatus));

      return matchesSearch &&
          matchesArchive &&
          matchesHeight &&
          matchesMaritalStatus;
    }).toList();

    _sortPeople(visiblePeople);
    return visiblePeople;
  }

  void _sortPeople(List<Person> people) {
    final Comparator<Person> base = _baseComparator();
    final int direction = _sortAscending ? 1 : -1;
    people.sort((Person a, Person b) => direction * base(a, b));
  }

  Comparator<Person> _baseComparator() {
    switch (_sortOption) {
      case PeopleSortOption.alphabetical:
        return _sortByName;
      case PeopleSortOption.ageAscending:
        return (Person a, Person b) {
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
        };
      case PeopleSortOption.newest:
        return (Person a, Person b) {
          final int comparison = b.createdAt.compareTo(a.createdAt);
          return comparison != 0 ? comparison : _sortByName(a, b);
        };
      case PeopleSortOption.recentlyUpdated:
        return (Person a, Person b) {
          final int comparison = b.updatedAt.compareTo(a.updatedAt);
          return comparison != 0 ? comparison : _sortByName(a, b);
        };
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
    final ({PeopleSortOption value, bool ascending})? selected =
        await showModalBottomSheet<({PeopleSortOption value, bool ascending})>(
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: SortDirectionToggle(
                      ascending: _sortAscending,
                      onChanged: (bool ascending) => Navigator.of(
                        sheetContext,
                      ).pop((value: _sortOption, ascending: ascending)),
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
                      onTap: () => Navigator.of(
                        sheetContext,
                      ).pop((value: option.value, ascending: _sortAscending)),
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
      _sortOption = selected.value;
      _sortAscending = selected.ascending;
    });
  }

  Future<void> _openFiltersSheet() async {
    final PersonRepository repository = context.read<PersonRepository>();
    final ({int min, int max})? bounds = repository.activeAgeBounds;
    const ({int min, int max}) heightBounds = (min: 120, max: 200);
    final PeopleFilterState? result =
        await showModalBottomSheet<PeopleFilterState>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.84,
          ),
          builder: (BuildContext context) {
            return PeopleFiltersSheet(
              initialGender: _selectedGender,
              initialAgeRange: _selectedAgeRange,
              ageBounds: bounds,
              initialReligiousLevels: _selectedReligiousLevels,
              initialReligiousLevelOtherLabels:
                  _selectedReligiousLevelOtherLabels,
              initialProfileStatuses: _selectedProfileStatuses,
              initialHeightRange: _selectedHeightRange,
              heightBounds: heightBounds,
              initialMaritalStatuses: _selectedMaritalStatuses,
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
      _selectedReligiousLevelOtherLabels = result.religiousLevelOtherLabels;
      _selectedProfileStatuses = result.profileStatuses;
      _selectedHeightRange = result.heightRange;
      _selectedMaritalStatuses = result.maritalStatuses;
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

  /// The quick gender tabs are a shortcut into the same gender filter, so they
  /// are deliberately left out of the "active filters" chip row.
  bool get _hasActiveFilters {
    return _selectedAgeRange != null ||
        _selectedReligiousLevels.isNotEmpty ||
        _selectedReligiousLevelOtherLabels.isNotEmpty ||
        _selectedProfileStatuses.isNotEmpty ||
        _selectedHeightRange != null ||
        _selectedMaritalStatuses.isNotEmpty;
  }

  void _handleSearchChanged() {
    setState(() {});
  }

  void _resetFilters() {
    _selectedAgeRange = null;
    _selectedReligiousLevels = <ReligiousLevel>[];
    _selectedReligiousLevelOtherLabels = <String>[];
    _selectedProfileStatuses = <ProfileStatus>[];
    _selectedHeightRange = null;
    _selectedMaritalStatuses = <MaritalStatus>[];
  }
}

class _PendingContactDraftsBanner extends StatelessWidget {
  const _PendingContactDraftsBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.pending_actions_outlined,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'מחכה למילוי פרטים שלך',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count אנשי קשר ייכנסו למאגר רק לאחר השלמת הפרטים',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onTap, child: const Text('מילוי פרטים')),
            ],
          ),
        ),
      ),
    );
  }
}

/// "יש לך כבר X חברים במאגר!" with a shortcut into the add-contacts flow.
class _MembersBanner extends StatelessWidget {
  const _MembersBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/people/import'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'יש לך כבר $count חברים במאגר!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'הוספת חברים נוספים',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Image.asset(
                'assets/match_icon.png',
                width: 56,
                height: 56,
                fit: BoxFit.contain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick split of the list: everyone / men only / women only. Feeds the same
/// gender filter used by the filters sheet.
class _GenderTabs extends StatelessWidget {
  const _GenderTabs({required this.selected, required this.onChanged});

  final Gender? selected;
  final ValueChanged<Gender?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          _tab(theme, label: 'הכל', value: null),
          _tab(theme, label: 'בנים', value: Gender.male),
          _tab(theme, label: 'בנות', value: Gender.female),
        ],
      ),
    );
  }

  Widget _tab(ThemeData theme, {required String label, Gender? value}) {
    final bool isSelected = selected == value;
    final Color background = value == null
        ? AppColors.primaryDark
        : AppColors.genderAccent(
            value,
            dark: theme.brightness == Brightness.dark,
          );

    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? background : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar above the list while it is showing one import's people.
///
/// It says what is being looked at and gives the one way out. No chip, no
/// dismiss "x": leaving is a decision worth a labelled button, because
/// everything else on the screen behaves differently while this is on.
class _JustAddedBar extends StatelessWidget {
  const _JustAddedBar({required this.count, required this.onShowAll});

  final int count;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color tone = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      color: tone.withValues(alpha: dark ? 0.16 : 0.10),
      child: Row(
        children: <Widget>[
          Icon(Icons.playlist_add_check_rounded, size: 20, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'האנשים שנוספו עכשיו',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '$count במאגר · אפשר להיכנס לכל אחד, לעדכן ולחזור לכאן',
                  maxLines: 2,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: onShowAll,
            style: TextButton.styleFrom(foregroundColor: tone),
            child: const Text('לכל המאגר'),
          ),
        ],
      ),
    );
  }
}
