import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/contacts_added_celebration.dart';
import 'package:shadchan/dialogs/hidden_contacts_dialog.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/add_contacts_session.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/services/call_log_sort_service.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/add_contacts_common.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/initials_avatar.dart';
import 'package:shadchan/widgets/sort_direction_toggle.dart';

/// Sort options for the import contacts list.
enum _ImportSortOption { alphabetical, recentCalls, nameLength, wordCount }

/// The list half of the add-friends screen.
///
/// Every contact here is one plain, tappable row: a tap picks the person, a
/// second tap unpicks them, and the actions live in one bottom banner rather
/// than being repeated on each line. The data itself — who is left, how many
/// were added, what is removed — comes from [AddContactsSession], which the
/// swipe view reads too, so the two can never show different numbers.
class ImportContactsScreen extends StatefulWidget {
  const ImportContactsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ImportContactsScreen> createState() => _ImportContactsScreenState();
}

class _ImportContactsScreenState extends State<ImportContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _importingIds = <String>{};

  bool _filterSuggestedNames = true;

  /// True once the list has been scrolled at all. The top banner is a greeting,
  /// not a permanent fixture: it steps aside the moment the matchmaker starts
  /// working through the list, while the search field stays put.
  bool _headerCollapsed = false;

  _ImportSortOption _sortOption = _ImportSortOption.alphabetical;
  bool _sortAscending = true;

  /// Contacts picked for a batch action. A plain set literal keeps insertion
  /// order, so a multi-add walks through people in the order they were picked.

  /// Normalized phone -> recency index (0 = most recent) from the device call
  /// log, loaded the first time the user picks the "recent calls" sort.
  Map<String, int> _recentCallOrder = const <String, int>{};
  bool _recentCallLoaded = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final double offset = _scrollController.position.pixels;
    final bool collapsed = _headerCollapsed ? offset > 2 : offset > 8;
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }
  }

  void _handleSearchChanged() {
    setState(() {});
  }

  String get _query => _searchController.text.trim();
  bool get _isSearching => _query.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AddContactsSession session = context.watch<AddContactsSession>();
    // Watched so a friend added anywhere else drops out of this list at once.
    context.watch<PersonRepository>();

    final Widget body = _buildBody(theme, session);

    if (widget.embedded) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: body,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('ייבוא מאנשי קשר'), centerTitle: true),
        body: SafeArea(child: body),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, AddContactsSession session) {
    if (session.isLoading) {
      return _LoadingContactsView(
        message: session.loadingMessage,
        progress: session.loadingProgress,
      );
    }

    final ContactsPermissionState? permissionState = session.permissionState;
    if (permissionState == ContactsPermissionState.denied ||
        permissionState == ContactsPermissionState.permanentlyDenied) {
      return _PermissionStateView(
        isPermanentlyDenied:
            permissionState == ContactsPermissionState.permanentlyDenied,
        onRetry: session.load,
        onOpenSettings: session.openSettingsAndRecheck,
      );
    }

    if (!session.hasAnyCandidate) {
      return const EmptyState(
        icon: Icons.contact_phone_outlined,
        title: 'לא נמצאו אנשי קשר מתאימים',
        subtitle: 'מוצגים רק אנשי קשר חדשים עם שם ומספר טלפון',
      );
    }

    final List<ContactCandidateEntry> rows = _rowsFor(session);
    // The selection lives on the session, not here, so the screen around this
    // one can answer a back press with "clear the ticks" instead of leaving.
    final int selectedCount = session.selectedContactIds.length;

    return Column(
      children: <Widget>[
        if (session.isRefreshing) const LinearProgressIndicator(minHeight: 3),
        // The banner is the only part that leaves on scroll; the search field
        // below it is outside the scroll view, which is what keeps it sticky.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _headerCollapsed
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: AddContactsProgressHeader(
                    addedToDatabase: session.databaseCount,
                    remaining: session.remainingCount,
                    total: session.progressTotal,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _SearchField(controller: _searchController),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Row(
            children: <Widget>[
              _FilterSortButton(
                label: 'מיון: ${_sortOptionLabel(_sortOption)}',
                highlighted: !_filterSuggestedNames,
                onPressed: () => _openFilterSortSheet(session),
              ),
            ],
          ),
        ),
        // The explanation is only ever needed before the first pick; once the
        // bottom banner is up it would just repeat what the banner says.
        if (selectedCount == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: Text(
              'אפשר לבחור חבר אחד או יותר ולהוסיף אותם למאגר.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? EmptyState(
                  icon: Icons.search,
                  title: _isSearching
                      ? 'לא נמצאו תוצאות'
                      : 'אין אנשי קשר חדשים לסקור',
                  subtitle: _isSearching
                      ? '{נסה|נסי} לחפש בשם אחר או לשנות את הסינון'
                      : 'כל אנשי הקשר שלך כבר במאגר או הוסרו מהרשימה',
                )
              : ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final ContactCandidateEntry entry = rows[index];
                    return _ContactRow(
                      key: ValueKey<String>(entry.candidate.deviceContactId),
                      entry: entry,
                      busy: _importingIds.contains(
                        entry.candidate.deviceContactId,
                      ),
                      selected: session.isSelected(
                        entry.candidate.deviceContactId,
                      ),
                      onTap: () => _handleRowTap(session, entry),
                    );
                  },
                ),
        ),
        _SelectionActionBar(
          count: selectedCount,
          onAdd: () => _addSelected(session),
          onRemove: () => _removeSelected(session),
          onClear: session.clearSelection,
        ),
      ],
    );
  }

  /// The regular list is only what is still to be decided on. Search is the
  /// wider view: it reaches every contact, including friends already in the
  /// database and people removed from the list, each carrying its own tag.
  List<ContactCandidateEntry> _rowsFor(AddContactsSession session) {
    final List<ContactCandidateEntry> entries;
    if (_isSearching) {
      // Everything matching, including contacts the name heuristics hide from
      // the regular list — the matchmaker asked for this person by name.
      entries = session.search(_query);
    } else {
      entries = session.availableCandidates
          .map(
            (ContactImportCandidate candidate) => ContactCandidateEntry(
              candidate: candidate,
              status: ContactCandidateStatus.available,
            ),
          )
          .toList();
      if (!_filterSuggestedNames) {
        entries.addAll(
          session.nameFilteredCandidates.map(
            (ContactImportCandidate candidate) => ContactCandidateEntry(
              candidate: candidate,
              status: ContactCandidateStatus.available,
            ),
          ),
        );
      }
    }
    _sortEntries(entries);
    return entries;
  }

  void _handleRowTap(AddContactsSession session, ContactCandidateEntry entry) {
    switch (entry.status) {
      case ContactCandidateStatus.inDatabase:
        _openExistingCard(session, entry.candidate);
      case ContactCandidateStatus.removedFromList:
        _openRemovedContactSheet(session, entry.candidate);
      case ContactCandidateStatus.available:
      case ContactCandidateStatus.hiddenByFilter:
        session.toggleSelected(entry.candidate.deviceContactId);
    }
  }

  void _openExistingCard(
    AddContactsSession session,
    ContactImportCandidate candidate,
  ) {
    final Person? person = session.personFor(candidate);
    if (person == null) {
      return;
    }
    context.push('/people/${person.id}');
  }

  /// A contact taken off the list is not gone: they can come straight back, or
  /// be added to the database from here.
  Future<void> _openRemovedContactSheet(
    AddContactsSession session,
    ContactImportCandidate candidate,
  ) async {
    final _RemovedContactAction? action =
        await showModalBottomSheet<_RemovedContactAction>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext sheetContext) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        candidate.displayName,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.undo),
                    title: const Text('החזר לרשימה'),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_RemovedContactAction.restore),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_add_alt),
                    title: const Text('הוספה למאגר'),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_RemovedContactAction.addToDatabase),
                  ),
                ],
              ),
            );
          },
        );

    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _RemovedContactAction.restore:
        await session.restoreToList(candidate);
      case _RemovedContactAction.addToDatabase:
        await session.clearRemoval(candidate);
        if (mounted) {
          await _addOne(session, candidate);
        }
    }
  }

  void _sortEntries(List<ContactCandidateEntry> entries) {
    final int dir = _sortAscending ? 1 : -1;
    switch (_sortOption) {
      case _ImportSortOption.alphabetical:
        entries.sort((a, b) => dir * _compareName(a, b));
      case _ImportSortOption.nameLength:
        entries.sort((a, b) {
          final int c = a.candidate.displayName.trim().length.compareTo(
            b.candidate.displayName.trim().length,
          );
          return dir * (c != 0 ? c : _compareName(a, b));
        });
      case _ImportSortOption.wordCount:
        entries.sort((a, b) {
          final int c = _wordCount(
            a.candidate.displayName,
          ).compareTo(_wordCount(b.candidate.displayName));
          return dir * (c != 0 ? c : _compareName(a, b));
        });
      case _ImportSortOption.recentCalls:
        // Recency has a natural order (most recent first); the direction
        // toggle doesn't apply here.
        entries.sort(_compareRecentCalls);
    }
  }

  int _compareName(ContactCandidateEntry a, ContactCandidateEntry b) => a
      .candidate
      .displayName
      .toLowerCase()
      .compareTo(b.candidate.displayName.toLowerCase());

  int _wordCount(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    return trimmed.split(RegExp(r'\s+')).length;
  }

  int _compareRecentCalls(ContactCandidateEntry a, ContactCandidateEntry b) {
    final int? rankA = _recentCallOrder[a.candidate.normalizedPhone];
    final int? rankB = _recentCallOrder[b.candidate.normalizedPhone];
    if (rankA != null && rankB != null && rankA != rankB) {
      return rankA.compareTo(rankB);
    }
    if (rankA != null && rankB == null) {
      return -1;
    }
    if (rankA == null && rankB != null) {
      return 1;
    }
    return _compareName(a, b);
  }

  String _sortOptionLabel(_ImportSortOption option) {
    switch (option) {
      case _ImportSortOption.alphabetical:
        return 'א-ת';
      case _ImportSortOption.recentCalls:
        return 'שיחות אחרונות';
      case _ImportSortOption.nameLength:
        return 'אורך שם';
      case _ImportSortOption.wordCount:
        return 'מספר מילים';
    }
  }

  /// Filtering and sorting share one small sheet so neither of them needs a
  /// permanent row above the list. The "hide irrelevant" switch applies live;
  /// picking a sort option closes the sheet.
  Future<void> _openFilterSortSheet(AddContactsSession session) async {
    final ({_ImportSortOption value, bool ascending})? selected =
        await showModalBottomSheet<({_ImportSortOption value, bool ascending})>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext sheetContext) {
            final ThemeData sheetTheme = Theme.of(sheetContext);
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setSheetState) {
                final int hiddenCount = session.nameFilteredCandidates.length;
                return SafeArea(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              'סינון ומיון',
                              style: sheetTheme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          value: _filterSuggestedNames,
                          title: const Text('הסתרת אנשי קשר לא רלוונטיים'),
                          subtitle: hiddenCount == 0
                              ? null
                              : Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: <Widget>[
                                    Text('מוסתרים כרגע: $hiddenCount'),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () async {
                                        await HiddenContactsDialog.show(
                                          sheetContext,
                                          candidates:
                                              session.nameFilteredCandidates,
                                          onRestore: session.revealFiltered,
                                        );
                                        if (sheetContext.mounted) {
                                          setSheetState(() {});
                                        }
                                      },
                                      child: const Text('צפייה במוסתרים'),
                                    ),
                                  ],
                                ),
                          onChanged: (bool value) {
                            setState(() => _filterSuggestedNames = value);
                            setSheetState(() {});
                          },
                        ),
                        const Divider(height: 24),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              'מיון לפי',
                              style: sheetTheme.textTheme.titleMedium,
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
                        for (final ({_ImportSortOption value, String label})
                            option
                            in const <
                              ({_ImportSortOption value, String label})
                            >[
                              (
                                value: _ImportSortOption.alphabetical,
                                label: 'א-ת',
                              ),
                              (
                                value: _ImportSortOption.recentCalls,
                                label: 'שיחות אחרונות',
                              ),
                              (
                                value: _ImportSortOption.nameLength,
                                label: 'אורך שם (קצר ↔ ארוך)',
                              ),
                              (
                                value: _ImportSortOption.wordCount,
                                label: 'מספר מילים בשם',
                              ),
                            ])
                          ListTile(
                            title: Text(option.label),
                            trailing: _sortOption == option.value
                                ? Icon(
                                    Icons.check,
                                    color: sheetTheme.colorScheme.primary,
                                  )
                                : null,
                            onTap: () => Navigator.of(sheetContext).pop((
                              value: option.value,
                              ascending: _sortAscending,
                            )),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );

    if (selected == null) {
      return;
    }

    // Loading the call log may prompt for the READ_CALL_LOG permission, which
    // is acceptable here in the add-contacts flow.
    if (selected.value == _ImportSortOption.recentCalls && !_recentCallLoaded) {
      final Map<String, int> order =
          await CallLogSortService.loadRecentCallOrderRequestingPermission();
      if (!mounted) {
        return;
      }
      _recentCallOrder = order;
      _recentCallLoaded = true;
    }

    setState(() {
      _sortOption = selected.value;
      _sortAscending = selected.ascending;
    });
  }

  /// Stages one contact and only adds it to the database after the required
  /// quick details are confirmed.
  Future<void> _addOne(
    AddContactsSession session,
    ContactImportCandidate candidate,
  ) async {
    if (_importingIds.contains(candidate.deviceContactId)) {
      return;
    }

    setState(() => _importingIds.add(candidate.deviceContactId));

    final PersonRepository repository = context.read<PersonRepository>();
    try {
      final StagedContact? staged =
          await ContactsImportService.stageSingleCandidate(
            candidate,
            repository,
          );

      if (!mounted) {
        return;
      }
      setState(() => _importingIds.remove(candidate.deviceContactId));

      if (staged == null) {
        return;
      }

      final QuickUpdateOutcome outcome = await QuickUpdateDialog.show(
        context,
        staged.person,
      );
      if (outcome.isAdded) {
        await repository.activatePendingContactDraft(staged.person);
        session.recordAdded();
        if (outcome == QuickUpdateOutcome.openFullEditor && mounted) {
          await _continueToFullCard(staged.person.id);
        }
        return;
      }

      // Cancelling means the contact was not added — the draft is thrown away
      // rather than parked in a "waiting for details" list.
      await ContactsImportService.discardStagedCandidate(staged, repository);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _importingIds.remove(candidate.deviceContactId));
      _showSnackBar('לא הצלחנו להוסיף את איש הקשר');
    }
  }

  /// Adds every picked contact one after the other: stage, fill in the details
  /// in the usual dialog ("2 מתוך 4"), then straight on to the next one.
  Future<void> _addSelected(AddContactsSession session) async {
    final List<ContactImportCandidate> selected = _selectedCandidates(session);
    if (selected.isEmpty) {
      return;
    }

    session.clearSelection();
    // Adding someone previously taken off the list also un-removes them, so a
    // new friend is never marked as removed underneath.
    for (final ContactImportCandidate candidate in selected) {
      await session.clearRemoval(candidate);
    }
    if (!mounted) {
      return;
    }

    final PersonRepository repository = context.read<PersonRepository>();
    int addedCount = 0;
    for (int index = 0; index < selected.length; index++) {
      final ContactImportCandidate candidate = selected[index];
      StagedContact? staged;
      try {
        staged = await ContactsImportService.stageSingleCandidate(
          candidate,
          repository,
        );
      } catch (_) {
        staged = null;
      }
      if (!mounted) {
        return;
      }
      // A null result means the contact was already in the database — there is
      // nothing to fill in, so the run moves on.
      if (staged == null) {
        continue;
      }

      final QuickUpdateOutcome outcome = await QuickUpdateDialog.show(
        context,
        staged.person,
        stepIndex: index + 1,
        stepCount: selected.length,
      );
      if (outcome.isAdded) {
        await repository.activatePendingContactDraft(staged.person);
        addedCount++;
        if (outcome == QuickUpdateOutcome.openFullEditor && mounted) {
          // Filling in a full card ends on that person's profile, so the rest
          // of the batch is abandoned rather than resumed behind it.
          session.recordAdded(addedCount);
          await _continueToFullCard(staged.person.id);
          return;
        }
        continue;
      }

      // Skipped: the draft is discarded, never left waiting for details.
      await ContactsImportService.discardStagedCandidate(staged, repository);
      if (!mounted) {
        return;
      }
    }

    if (addedCount == 0 || !mounted) {
      return;
    }
    session.recordAdded(addedCount);
    // A long multi-add is a large import too, however many dialogs it took to
    // confirm. Past the notice threshold the community note replaces the
    // celebration rather than following it — one word about the moment, not
    // two. Below it, nothing has changed.
    CommunityProfileStore.noteBulkImport(addedCount);
    if (addedCount < CommunityProfileStore.bulkImportNoticeFrom) {
      ContactsAddedCelebration.show(context, count: addedCount);
    }
  }

  /// Continues from the quick details into the full card, and finishes on the
  /// new friend's profile rather than back here — the matchmaker who asked for
  /// the whole card is working on that one person, not on the queue.
  Future<void> _continueToFullCard(String personId) async {
    await openExtendedPersonEditor(context, personId, isNewFriend: true);
    if (!mounted) {
      return;
    }
    context.push('/people/$personId');
  }

  /// Takes the picked contacts off the add-friends list. They keep their place
  /// in the phone's contacts and stay findable through search.
  Future<void> _removeSelected(AddContactsSession session) async {
    final List<ContactImportCandidate> selected = _selectedCandidates(session);
    if (selected.isEmpty) {
      return;
    }
    session.clearSelection();
    await session.removeFromList(selected);
  }

  List<ContactImportCandidate> _selectedCandidates(AddContactsSession session) {
    final Map<String, ContactImportCandidate> byId =
        <String, ContactImportCandidate>{
          for (final ContactImportCandidate candidate in session.allCandidates)
            candidate.deviceContactId: candidate,
        };
    return session.selectedContactIds
        .map((String id) => byId[id])
        .whereType<ContactImportCandidate>()
        .toList();
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }
}

enum _RemovedContactAction { restore, addToDatabase }

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintText: 'חיפוש לפי שם או טלפון...',
        prefixIcon: const Icon(Icons.search, size: 20),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
        suffixIcon: controller.text.trim().isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: controller.clear,
              ),
      ),
    );
  }
}

/// The single small entry point to filtering and sorting, so neither of them
/// takes a row of its own above the list.
class _FilterSortButton extends StatelessWidget {
  const _FilterSortButton({
    required this.label,
    required this.highlighted,
    required this.onPressed,
  });

  final String label;

  /// True while the default "hide irrelevant contacts" filter is switched off.
  final bool highlighted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = theme.brightness == Brightness.dark
        ? theme.colorScheme.primary
        : AppColors.primaryDark;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.tune, size: 17, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (highlighted) ...<Widget>[
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One contact row: pastel initials, the name, and — only in search results —
/// a small tag saying why this person is not in the regular list.
///
/// There is deliberately nothing else on the line. Picking someone is the tap
/// itself, and the picked state is carried by a soft blue wash and a slightly
/// firmer name rather than by a tick.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    super.key,
    required this.entry,
    required this.busy,
    required this.selected,
    required this.onTap,
  });

  final ContactCandidateEntry entry;
  final bool busy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark
        ? theme.colorScheme.primary
        : AppColors.primaryDark;
    final Color selectedSurface = dark
        ? accent.withValues(alpha: 0.18)
        : AppColors.softBlue;

    return Container(
      decoration: softCardDecoration(
        context,
        radius: 14,
        color: selected ? selectedSurface : null,
        borderColor: selected ? accent.withValues(alpha: 0.45) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
            child: Row(
              children: <Widget>[
                InitialsAvatar(name: entry.candidate.displayName, diameter: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.candidate.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (busy)
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                else
                  _StatusTag(status: entry.status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Says why a searched contact is not in the regular list. Nothing is drawn for
/// a contact that simply hasn't been decided on yet.
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});

  final ContactCandidateStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String label;
    final Color color;
    switch (status) {
      case ContactCandidateStatus.inDatabase:
        label = 'במאגר';
        color = theme.brightness == Brightness.dark
            ? AppColors.femaleAccentDm
            : AppColors.femaleAccent;
      case ContactCandidateStatus.removedFromList:
        label = 'הוסר מהרשימה';
        color = theme.colorScheme.onSurfaceVariant;
      case ContactCandidateStatus.available:
      case ContactCandidateStatus.hiddenByFilter:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The banner along the bottom, present for as long as anyone is picked.
///
/// It carries all three answers to "and now what?" in one place: the main one
/// filled and full width, the removal quieter beside a plain way out.
class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.count,
    required this.onAdd,
    required this.onRemove,
    required this.onClear,
  });

  final int count;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = dark
        ? theme.colorScheme.primary
        : AppColors.primaryDark;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: count == 0
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                decoration: softCardDecoration(context, radius: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onAdd,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: dark
                              ? AppColors.onSurface
                              : AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: Text(_addLabel(count)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextButton(
                            onPressed: onRemove,
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  theme.colorScheme.onSurfaceVariant,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: Text(
                              _removeLabel(count),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: onClear,
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text('נקה בחירה'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  static String _addLabel(int count) =>
      count == 1 ? 'הוספת חבר אחד למאגר' : 'הוספת $count חברים למאגר';

  static String _removeLabel(int count) =>
      count == 1 ? 'הסרת חבר אחד מהרשימה' : 'הסרת $count חברים מהרשימה';
}

class _LoadingContactsView extends StatelessWidget {
  const _LoadingContactsView({required this.message, required this.progress});

  final String message;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: progress, minHeight: 6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionStateView extends StatelessWidget {
  const _PermissionStateView({
    required this.isPermanentlyDenied,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final bool isPermanentlyDenied;
  final Future<void> Function() onRetry;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            EmptyState(
              icon: Icons.contact_phone_outlined,
              title: 'אין גישה לאנשי הקשר',
              subtitle: isPermanentlyDenied
                  ? 'כדי לייבא אנשי קשר צריך לאשר גישה בהגדרות המכשיר'
                  : 'כדי לייבא אנשי קשר צריך לאשר גישה לספר הטלפונים',
              buttonText: isPermanentlyDenied ? 'פתיחת הגדרות' : 'לנסות שוב',
              onButtonPressed: isPermanentlyDenied ? onOpenSettings : onRetry,
            ),
            if (isPermanentlyDenied)
              TextButton(onPressed: onRetry, child: const Text('בדיקה מחדש')),
          ],
        ),
      ),
    );
  }
}
