import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/dialogs/bulk_details_request_sheet.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/search_navigation.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';
import 'package:shadchan/widgets/person_list_card.dart';
import 'package:shadchan/widgets/search_results_panel.dart';
import 'package:shadchan/widgets/shadchan_app_bar.dart';
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

  /// Who is ticked for a joint "בקשת פרטים" — null when the screen is not in
  /// selection mode at all.
  ///
  /// Entered from one person's long-press menu and never from a tap, so the
  /// list keeps behaving exactly as it always has until somebody deliberately
  /// asks for the multi-select.
  Set<String>? _detailsSelection;

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

    final Set<String>? selection = _detailsSelection;

    return Scaffold(
      // **The bar says "המאגר שלי", and the search row is part of it.** The
      // page used to open with a banner reading "שדכן", a heading line under it
      // reading "המאגר שלי", and a search row under that — three strips before
      // the first friend, two of which scrolled away. The name is in the banner
      // now and the field is pinned to it, which is one strip instead of three
      // and the only one of them that had to stay.
      appBar: selection != null
          ? _buildSelectionAppBar(selection)
          : ShadchanAppBar(
              title: 'המאגר שלי',
              // The bell, the "+" and the overflow menu — the same three, in
              // the same order, as בית and רעיונות. See [ShadchanTabActions];
              // this page's "+" goes straight to adding friends, because on
              // המאגר שלי there is nothing else it could mean.
              actions: <Widget>[
                ShadchanTabActions(
                  add: ShadchanAddButton(
                    tooltip: 'הוספת אנשי קשר',
                    onPressed: () => AddPeopleDialog.show(context),
                  ),
                ),
              ],
              bottom: ShadchanSearchBottom(child: _buildSearchRow(theme)),
            ),
      // Adding a friend is the whole point of this screen, so it gets the
      // thumb's corner as well as the app bar. The icon in the bar stays: it is
      // where someone who already knows the app looks, and the two open exactly
      // the same sheet.
      //
      // While friends are being ticked the corner is empty and the send control
      // is a full-width bar along the bottom instead — see
      // [_DetailsRequestBar]. A round button in a corner is for starting
      // something; finishing a selection of nine friends is a labelled button
      // the width of the thumb's whole travel.
      floatingActionButton: selection != null
          ? null
          : FloatingActionButton(
              // `endFloat` in RTL is the bottom-left corner — the same place
              // the messaging apps everyone already uses put theirs.
              tooltip: 'הוספת חברים',
              onPressed: () => AddPeopleDialog.show(context),
              child: const Icon(Icons.add),
            ),
      // The name and the search row are the bar; everything under it — the
      // gender tabs, the filter chips and the list — scrolls as one page.
      //
      // The results panel is laid over all of it while there is a query, the
      // way it is on בית: filtering the list underneath is what happens *as
      // well*, not instead. See [SearchResultsPanel].
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              if (_importBatchId != null)
                _JustAddedBar(
                  count: visiblePeople.length,
                  onShowAll: () => setState(() => _importBatchId = null),
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
          if (selection == null) _buildSearchPanel(personRepository),
          if (selection != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _DetailsRequestBar(
                count: selection.length,
                onSend: _sendDetailsRequests,
              ),
            ),
        ],
      ),
    );
  }

  /// A single row: the search field, then the filter and sort buttons.
  ///
  /// The field itself is the one the home screen and רעיונות use — a rounded
  /// row on the page's own paper. The two buttons beside it are this screen's
  /// alone and stay where they were.
  Widget _buildSearchRow(ThemeData theme) {
    return ShadchanSearchField(
      controller: _searchController,
      hintText: 'חיפוש במאגר שלי',
      onCleared: _closeSearch,
      trailing: <Widget>[
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

  /// Live results over the list, capped at half the screen.
  ///
  /// **Every row goes straight to the person.** Narrowing the list is useful
  /// but it is not an answer: it still leaves somebody scanning a column for
  /// the name they have just finished typing. These rows open the profile.
  ///
  /// Deliberately searched over the *whole* database rather than over the
  /// filtered list: somebody who types a name is asking for that person, and a
  /// filter chip left on from an hour ago is not a reason to answer "no such
  /// friend". The list underneath still obeys every filter on the screen.
  Widget _buildSearchPanel(PersonRepository repository) {
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Person> people =
        repository
            .getAll()
            .where((Person p) => !p.hidden)
            .where(
              (Person p) =>
                  p.fullName.toLowerCase().contains(query) ||
                  (p.phone ?? '').contains(query),
            )
            .toList()
          ..sort(
            (Person a, Person b) =>
                a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
          );

    return SearchResultsPanel(
      onDismiss: _closeSearch,
      rows: <Widget>[
        for (final Person person in people)
          SearchResultRow(
            leading: SearchResultRow.avatar(person),
            title: person.fullName,
            subtitle: _personSummary(person),
            onTap: () {
              _closeSearch();
              pushLeavingSearch(context, '/people/${person.id}');
            },
          ),
      ],
    );
  }

  /// One quiet line under a name in the results: whatever of age, city and
  /// state is actually recorded, and nothing where nothing is.
  static String? _personSummary(Person person) {
    final List<String> parts = <String>[
      if (person.age != null) '${person.age}',
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
      if (person.profileStatus != ProfileStatus.available)
        person.profileStatus.displayName,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Leaves search: the panel and the keyboard.
  void _closeSearch() {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() {});
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
                final Set<String>? selection = _detailsSelection;
                if (selection != null) {
                  return PersonListCard(
                    person: person,
                    selected: selection.contains(person.id),
                    // A tap ticks instead of opening, and a long press does the
                    // same: while a group is being put together there is no
                    // second meaning for either gesture.
                    onTap: () => _toggleDetailsSelection(person),
                    onLongPress: () => _toggleDetailsSelection(person),
                  );
                }
                return PersonListCard(
                  person: person,
                  // Through the same helper the results panel uses: with the
                  // keyboard up, pushing straight away makes the avatar's hero
                  // measure a viewport that is a keyboard shorter than the one
                  // the profile ends up in, and it lands stretched. See
                  // [pushLeavingSearch] — with nothing focused it is an
                  // ordinary push.
                  onTap: () =>
                      pushLeavingSearch(context, '/people/${person.id}'),
                  // **A long press ticks, it does not ask.** It used to raise a
                  // sheet whose middle row was "בקשת פרטים בוואטסאפ" — a menu
                  // between the gesture and the only thing the gesture is for.
                  // Pressing a friend now selects them and turns the list into
                  // a picker; everything else that sheet offered is on the
                  // friend's own profile, one tap away.
                  onLongPress: () => _startDetailsSelection(person),
                  onToggleFavorite: () => context
                      .read<PersonRepository>()
                      .toggleFavorite(person.id),
                  onOpenMatches: () => _openMatchSuggestions(context, person),
                  onOpenWhatsApp: () => _openWhatsApp(context, person),
                  // The same call the proposal cards make, so a status set from
                  // here moves the person's open proposals to "בהמתנה" and asks
                  // when to look again exactly as it does anywhere else.
                  onStatusPicked: (Person person, ProfileStatus status) =>
                      MatchQuickActions.setPersonStatus(
                        context,
                        person,
                        status,
                      ),
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
      AppNotice.show(context, 'יש לבחור מגדר לאיש הקשר לפני פתיחת התאמות');
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
          AppNotice.show(context, 'לא הצלחנו לשמור את הפרטים');
        }
        return;
      }
    }
  }

  Future<void> _openWhatsApp(BuildContext context, Person person) async {
    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && context.mounted) {
      AppNotice.show(context, 'לא הצלחנו לפתוח את וואטסאפ');
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

  // --- Joint "בקשת פרטים" ---------------------------------------------------

  /// The bar shown while friends are being ticked: how many, and the way out.
  AppBar _buildSelectionAppBar(Set<String> selection) {
    return AppBar(
      leading: IconButton(
        tooltip: 'ביטול',
        icon: const Icon(Icons.close),
        onPressed: () => setState(() => _detailsSelection = null),
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            selection.length == 1
                ? 'נבחר חבר אחד'
                : 'נבחרו ${selection.length} חברים',
          ),
          Text(
            'בקשת פרטים בהודעת וואטסאפ אחת',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
      centerTitle: true,
    );
  }

  /// Long-press → "בקשת פרטים בוואטסאפ": the person who was pressed is already
  /// ticked, and the list turns into a picker for anybody else.
  void _startDetailsSelection(Person person) {
    setState(() => _detailsSelection = <String>{person.id});
  }

  void _toggleDetailsSelection(Person person) {
    final Set<String>? selection = _detailsSelection;
    if (selection == null) {
      return;
    }
    setState(() {
      if (!selection.remove(person.id)) {
        selection.add(person.id);
      }
      // Unticking the last one leaves the picker rather than stranding an empty
      // bar with nothing to send.
      if (selection.isEmpty) {
        _detailsSelection = null;
      }
    });
  }

  /// Sends the request to everybody who was ticked.
  ///
  /// One friend goes straight into their own chat with their own gendered
  /// wording, exactly as the button on their profile does. Several open a queue
  /// — one tap per friend, each landing in that friend's own chat with the
  /// message already typed — because no link and no share target can deliver to
  /// several numbers at once, and the one thing worth avoiding is making the
  /// matchmaker find the same nine people again inside WhatsApp.
  ///
  /// Anybody without a usable number is dropped and named, rather than being
  /// silently counted as asked.
  Future<void> _sendDetailsRequests() async {
    final Set<String>? selection = _detailsSelection;
    if (selection == null || selection.isEmpty) {
      return;
    }
    final PersonRepository repository = context.read<PersonRepository>();
    final List<Person> chosen = <Person>[
      for (final String id in selection)
        if (repository.getById(id) case final Person person) person,
    ];
    final List<Person> reachable = chosen
        .where(
          (Person person) => PhoneUtils.toWhatsAppNumber(person.phone) != null,
        )
        .toList();
    final int unreachable = chosen.length - reachable.length;

    if (reachable.isEmpty) {
      _showSnackBar('אין מספר טלפון תקין לאף אחד מהחברים שנבחרו');
      return;
    }

    // Stamped before leaving for WhatsApp, while this route is still fully
    // active — the same reason the single-person path persists first.
    for (final Person person in reachable) {
      await repository.touch(person.id);
    }
    if (!mounted) {
      return;
    }

    if (reachable.length == 1) {
      final bool launched = await WhatsAppUtils.openDetailsRequest(
        reachable.first,
      );
      if (!launched && mounted) {
        _showSnackBar('לא הצלחנו לפתוח את WhatsApp');
        return;
      }
    } else {
      // The queue, not the share sheet: one tap per friend, straight into
      // their own chat with the message already written. See
      // [BulkDetailsRequestSheet].
      await BulkDetailsRequestSheet.show(context, reachable);
    }

    if (!mounted) {
      return;
    }
    setState(() => _detailsSelection = null);
    if (unreachable > 0) {
      _showSnackBar(
        unreachable == 1
            ? 'חבר אחד נותר בחוץ — אין לו מספר טלפון תקין'
            : '$unreachable חברים נותרו בחוץ — אין להם מספר טלפון תקין',
      );
    }
  }

  void _showSnackBar(String message) {
    AppNotice.show(context, message);
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

/// The bar along the bottom while friends are being ticked for a joint request.
///
/// Full width and labelled with the actual action, because that is what it is:
/// the end of a deliberate selection, not a shortcut to start one. It sits over
/// the list rather than under it so the list keeps its whole height, and it
/// carries the count so the number of people about to be written to is visible
/// at the moment of pressing send.
class _DetailsRequestBar extends StatelessWidget {
  const _DetailsRequestBar({required this.count, required this.onSend});

  final int count;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSend,
              icon: const Icon(Icons.chat_outlined, size: 20),
              label: Text(
                count == 1
                    ? 'בקשת פרטים בוואטסאפ'
                    : 'בקשת פרטים בוואטסאפ ($count)',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
