import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/contacts_added_celebration.dart';
import 'package:shadchan/dialogs/hidden_contacts_dialog.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/call_log_sort_service.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/add_contacts_common.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/initials_avatar.dart';
import 'package:shadchan/widgets/sort_direction_toggle.dart';

/// Sort options for the import contacts list.
enum _ImportSortOption { alphabetical, recentCalls, nameLength, wordCount }

class ImportContactsScreen extends StatefulWidget {
  const ImportContactsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ImportContactsScreen> createState() => _ImportContactsScreenState();
}

class _ImportContactsScreenState extends State<ImportContactsScreen> {
  // Shared with the swipe view so a contact marked "לא רלוונטי" in either place
  // disappears from both the list and the swipe deck.
  static const String _skippedBoxName = 'swipe_skipped_phones';
  static const String _skippedSetKey = 'skipped_phones';
  static const String _revealedFilteredSetKey = 'revealed_filtered_phones';

  final TextEditingController _searchController = TextEditingController();
  final Set<String> _importingIds = <String>{};

  /// Contacts the user already acted on in this session (added or removed).
  /// They drop out of the visible list immediately.
  final Set<String> _handledIds = <String>{};

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _filterSuggestedNames = true;

  _ImportSortOption _sortOption = _ImportSortOption.alphabetical;
  bool _sortAscending = true;

  /// Contacts ticked for a batch action. A plain set literal keeps insertion
  /// order, so a multi-add walks through people in the order they were picked.
  final Set<String> _selectedIds = <String>{};

  /// Normalized phone -> recency index (0 = most recent) from the device call
  /// log, loaded the first time the user picks the "recent calls" sort.
  Map<String, int> _recentCallOrder = const <String, int>{};
  double? _loadingProgress;
  String _loadingMessage = 'טוענים אנשי קשר...';
  ContactsPermissionState? _permissionState;
  List<ContactImportCandidate> _allCandidates =
      const <ContactImportCandidate>[];
  Set<String> _skippedPhones = <String>{};
  Set<String> _revealedFilteredPhones = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadContacts();
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
    // Watch the repository so contacts added elsewhere (e.g. the swipe view)
    // drop out of this list automatically and can't be imported twice.
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final Set<String> existingPhones = personRepository.getNormalizedPhones();
    final List<ContactImportCandidate> visibleCandidates =
        _visibleCandidatesFor(existingPhones);
    _sortCandidates(visibleCandidates);

    final Widget body = _buildBody(
      theme,
      visibleCandidates,
      personRepository.databaseCount,
    );

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

  Widget _buildBody(
    ThemeData theme,
    List<ContactImportCandidate> visibleCandidates,
    int databaseCount,
  ) {
    if (_isLoading) {
      return _LoadingContactsView(
        message: _loadingMessage,
        progress: _loadingProgress,
      );
    }

    final ContactsPermissionState? permissionState = _permissionState;
    if (permissionState == ContactsPermissionState.denied ||
        permissionState == ContactsPermissionState.permanentlyDenied) {
      return _PermissionStateView(
        isPermanentlyDenied:
            permissionState == ContactsPermissionState.permanentlyDenied,
        onRetry: _loadContacts,
        onOpenSettings: _openSettings,
      );
    }

    if (_allCandidates.isEmpty) {
      return const EmptyState(
        icon: Icons.contact_phone_outlined,
        title: 'לא נמצאו אנשי קשר מתאימים',
        subtitle: 'מוצגים רק אנשי קשר חדשים עם שם ומספר טלפון',
      );
    }

    return Column(
      children: <Widget>[
        if (_isRefreshing) const LinearProgressIndicator(minHeight: 3),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AddContactsProgressHeader(addedToDatabase: databaseCount),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _SearchField(controller: _searchController),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _FilterSortButton(
              label: 'מיון: ${_sortOptionLabel(_sortOption)}',
              highlighted: !_filterSuggestedNames,
              onPressed: _openFilterSortSheet,
            ),
          ),
        ),
        Expanded(
          child: visibleCandidates.isEmpty
              ? const EmptyState(
                  icon: Icons.search,
                  title: 'לא נמצאו תוצאות',
                  subtitle: 'נסו לחפש בשם אחר או לשנות את הסינון',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: visibleCandidates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final ContactImportCandidate candidate =
                        visibleCandidates[index];
                    return _ContactRow(
                      key: ValueKey<String>(candidate.deviceContactId),
                      candidate: candidate,
                      busy: _importingIds.contains(candidate.deviceContactId),
                      selected: _selectedIds.contains(
                        candidate.deviceContactId,
                      ),
                      onToggleSelection: () => _toggleSelection(candidate),
                      onAdd: () => _addSingle(candidate),
                    );
                  },
                ),
        ),
        _SelectionActionBar(
          count: _selectedIds.length,
          onMarkIrrelevant: _markSelectedIrrelevant,
          onAdd: _addSelected,
        ),
      ],
    );
  }

  List<ContactImportCandidate> _visibleCandidatesFor(
    Set<String> existingPhones,
  ) {
    final String query = _searchController.text.trim();
    final bool searching = query.isNotEmpty;

    return _allCandidates.where((ContactImportCandidate candidate) {
      final bool skipped = _skippedPhones.contains(candidate.normalizedPhone);

      // Contacts acted on this session drop out of the list. Exception: while
      // searching, one marked "לא רלוונטי" stays findable so it can come back.
      if (_handledIds.contains(candidate.deviceContactId) &&
          !(searching && skipped)) {
        return false;
      }

      // Already in the repository (e.g. just added from the swipe view) — hide
      // it everywhere, even while searching, to avoid duplicate imports.
      if (existingPhones.contains(candidate.normalizedPhone)) {
        return false;
      }

      if (!candidate.matchesQuery(query)) {
        return false;
      }

      // When searching, surface everyone — including the ones marked as not
      // relevant and the automatically filtered names — so they can be re-added.
      if (searching) {
        return true;
      }

      if (skipped) {
        return false;
      }

      if (!_filterSuggestedNames || !_isCandidateHidden(candidate)) {
        return true;
      }

      return false;
    }).toList();
  }

  bool _isCandidateHidden(ContactImportCandidate candidate) {
    return candidate.isFilteredByName &&
        !_revealedFilteredPhones.contains(candidate.normalizedPhone);
  }

  List<ContactImportCandidate> get _hiddenCandidates {
    return _allCandidates
        .where(
          (ContactImportCandidate candidate) =>
              _isCandidateHidden(candidate) &&
              !_skippedPhones.contains(candidate.normalizedPhone) &&
              !_handledIds.contains(candidate.deviceContactId),
        )
        .toList()
      ..sort(_compareName);
  }

  int get _nameFilteredCount => _hiddenCandidates.length;

  bool _recentCallLoaded = false;

  void _sortCandidates(List<ContactImportCandidate> candidates) {
    final int dir = _sortAscending ? 1 : -1;
    switch (_sortOption) {
      case _ImportSortOption.alphabetical:
        candidates.sort((a, b) => dir * _compareName(a, b));
      case _ImportSortOption.nameLength:
        candidates.sort((a, b) {
          final int c = a.displayName.trim().length.compareTo(
            b.displayName.trim().length,
          );
          return dir * (c != 0 ? c : _compareName(a, b));
        });
      case _ImportSortOption.wordCount:
        candidates.sort((a, b) {
          final int c = _wordCount(
            a.displayName,
          ).compareTo(_wordCount(b.displayName));
          return dir * (c != 0 ? c : _compareName(a, b));
        });
      case _ImportSortOption.recentCalls:
        // Recency has a natural order (most recent first); the direction
        // toggle doesn't apply here.
        candidates.sort(_compareRecentCalls);
    }
  }

  int _compareName(ContactImportCandidate a, ContactImportCandidate b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

  int _wordCount(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    return trimmed.split(RegExp(r'\s+')).length;
  }

  int _compareRecentCalls(ContactImportCandidate a, ContactImportCandidate b) {
    final int? rankA = _recentCallOrder[a.normalizedPhone];
    final int? rankB = _recentCallOrder[b.normalizedPhone];
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
  Future<void> _openFilterSortSheet() async {
    final ({_ImportSortOption value, bool ascending})? selected =
        await showModalBottomSheet<({_ImportSortOption value, bool ascending})>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext sheetContext) {
            final ThemeData sheetTheme = Theme.of(sheetContext);
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setSheetState) {
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
                          subtitle: _nameFilteredCount == 0
                              ? null
                              : Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: <Widget>[
                                    Text('מוסתרים כרגע: $_nameFilteredCount'),
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
                                        await _showHiddenContacts(sheetContext);
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

  /// The per-row `+`: stages one contact and only adds it to the database after
  /// the required quick details are confirmed.
  Future<void> _addSingle(ContactImportCandidate candidate) async {
    if (_importingIds.contains(candidate.deviceContactId)) {
      return;
    }

    setState(() {
      _importingIds.add(candidate.deviceContactId);
      _handledIds.add(candidate.deviceContactId);
      _selectedIds.remove(candidate.deviceContactId);
      _skippedPhones.remove(candidate.normalizedPhone);
    });

    final PersonRepository repository = context.read<PersonRepository>();
    try {
      final Person? person = await ContactsImportService.stageSingleCandidate(
        candidate,
        repository,
      );

      if (!mounted) {
        return;
      }
      setState(() => _importingIds.remove(candidate.deviceContactId));

      if (person == null) {
        return;
      }

      final bool confirmed = await QuickUpdateDialog.show(context, person);
      if (!mounted) {
        return;
      }
      if (confirmed) {
        await repository.activatePendingContactDraft(person);
      } else {
        setState(() => _handledIds.remove(candidate.deviceContactId));
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _importingIds.remove(candidate.deviceContactId);
        _handledIds.remove(candidate.deviceContactId);
      });
      _showSnackBar('לא הצלחנו להוסיף את איש הקשר');
    }
  }

  void _toggleSelection(ContactImportCandidate candidate) {
    setState(() {
      if (!_selectedIds.remove(candidate.deviceContactId)) {
        _selectedIds.add(candidate.deviceContactId);
      }
    });
  }

  /// Adds every ticked contact one after the other: import, fill in the details
  /// in the usual dialog ("2 מתוך 4"), then straight on to the next one.
  Future<void> _addSelected() async {
    final Map<String, ContactImportCandidate> byId =
        <String, ContactImportCandidate>{
          for (final ContactImportCandidate candidate in _allCandidates)
            candidate.deviceContactId: candidate,
        };
    final List<ContactImportCandidate> selected = _selectedIds
        .map((String id) => byId[id])
        .whereType<ContactImportCandidate>()
        .toList();
    if (selected.isEmpty) {
      return;
    }

    setState(() {
      for (final ContactImportCandidate candidate in selected) {
        _handledIds.add(candidate.deviceContactId);
        _skippedPhones.remove(candidate.normalizedPhone);
      }
      _selectedIds.clear();
    });
    await _saveSkippedPhones();
    if (!mounted) {
      return;
    }

    final PersonRepository repository = context.read<PersonRepository>();
    int addedCount = 0;
    for (int index = 0; index < selected.length; index++) {
      final ContactImportCandidate candidate = selected[index];
      Person? person;
      try {
        person = await ContactsImportService.stageSingleCandidate(
          candidate,
          repository,
        );
      } catch (_) {
        person = null;
      }
      if (!mounted) {
        return;
      }
      // A null person means the contact was already in the database — there is
      // nothing to fill in, so the run moves on.
      if (person == null) {
        continue;
      }

      final bool confirmed = await QuickUpdateDialog.show(
        context,
        person,
        stepIndex: index + 1,
        stepCount: selected.length,
      );
      if (!mounted) {
        return;
      }
      if (confirmed) {
        await repository.activatePendingContactDraft(person);
        addedCount++;
      } else {
        setState(() => _handledIds.remove(candidate.deviceContactId));
      }
    }

    if (addedCount == 0 || !mounted) {
      return;
    }
    await ContactsAddedCelebration.show(context, count: addedCount);
  }

  /// Marks every ticked contact as not relevant. They are written to the shared
  /// skip list, so they stay out of both the list and the swipe deck.
  Future<void> _markSelectedIrrelevant() async {
    final List<ContactImportCandidate> selected = _allCandidates
        .where(
          (ContactImportCandidate candidate) =>
              _selectedIds.contains(candidate.deviceContactId),
        )
        .toList();
    if (selected.isEmpty) {
      return;
    }

    setState(() {
      for (final ContactImportCandidate candidate in selected) {
        _handledIds.add(candidate.deviceContactId);
        _skippedPhones.add(candidate.normalizedPhone);
      }
      _selectedIds.clear();
    });
    await _saveSkippedPhones();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            selected.length == 1
                ? '${selected.first.displayName} סומן כלא רלוונטי'
                : '${selected.length} אנשי קשר סומנו כלא רלוונטיים',
          ),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'ביטול',
            onPressed: () => _restoreMany(selected),
          ),
        ),
      );
  }

  Future<void> _restoreMany(List<ContactImportCandidate> candidates) async {
    setState(() {
      for (final ContactImportCandidate candidate in candidates) {
        _handledIds.remove(candidate.deviceContactId);
        _skippedPhones.remove(candidate.normalizedPhone);
      }
    });
    await _saveSkippedPhones();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _isRefreshing = false;
      _loadingProgress = null;
      _loadingMessage = 'מבקשים גישה לאנשי קשר...';
    });

    final ContactsPermissionState permissionState =
        await ContactsImportService.requestPermission();
    if (!mounted) {
      return;
    }

    if (permissionState != ContactsPermissionState.granted) {
      setState(() {
        _permissionState = permissionState;
        _isLoading = false;
      });
      return;
    }

    final Box<dynamic> hiddenStateBox = await _openSkippedBox();
    _skippedPhones = _stringSet(hiddenStateBox.get(_skippedSetKey));
    _revealedFilteredPhones = _stringSet(
      hiddenStateBox.get(_revealedFilteredSetKey),
    );
    if (!mounted) {
      return;
    }

    final PersonRepository personRepository = context.read<PersonRepository>();
    final List<ContactImportCandidate> cachedCandidates =
        await ContactsImportService.loadCachedCandidates(personRepository);
    if (!mounted) {
      return;
    }

    if (cachedCandidates.isNotEmpty) {
      setState(() {
        _permissionState = permissionState;
        _allCandidates = cachedCandidates;
        _isLoading = false;
        _isRefreshing = true;
      });
    } else {
      setState(() {
        _loadingMessage = 'טוענים אנשי קשר מהמכשיר...';
      });
    }

    final List<ContactImportCandidate>
    candidates = await ContactsImportService.loadCandidates(
      personRepository,
      onProgress: (ContactImportLoadProgress progress) {
        if (!mounted) {
          return;
        }

        setState(() {
          _loadingProgress = progress.value;
          _loadingMessage =
              'מסננים אנשי קשר (${progress.processedCount}/${progress.totalCount})...';
        });
      },
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _permissionState = permissionState;
      _allCandidates = candidates;
      _isLoading = false;
      _isRefreshing = false;
      _loadingProgress = null;
      _loadingMessage = 'טוענים אנשי קשר...';
    });
  }

  Future<void> _openSettings() async {
    await ContactsImportService.openSettings();
    if (!mounted) {
      return;
    }

    final ContactsPermissionState permissionState =
        await ContactsImportService.checkPermission();
    if (!mounted) {
      return;
    }

    setState(() {
      _permissionState = permissionState;
    });
  }

  Set<String> _stringSet(Object? raw) {
    if (raw is List) {
      return raw.whereType<String>().toSet();
    }
    return <String>{};
  }

  Future<void> _saveSkippedPhones() async {
    final Box<dynamic> box = await _openSkippedBox();
    await box.put(_skippedSetKey, _skippedPhones.toList());
  }

  Future<void> _showHiddenContacts(BuildContext dialogContext) {
    return HiddenContactsDialog.show(
      dialogContext,
      candidates: _hiddenCandidates,
      onRestore: _restoreFilteredCandidate,
    );
  }

  Future<void> _restoreFilteredCandidate(
    ContactImportCandidate candidate,
  ) async {
    setState(() {
      _revealedFilteredPhones.add(candidate.normalizedPhone);
      _handledIds.remove(candidate.deviceContactId);
    });
    final Box<dynamic> box = await _openSkippedBox();
    await box.put(_revealedFilteredSetKey, _revealedFilteredPhones.toList());
  }

  Future<Box<dynamic>> _openSkippedBox() async {
    if (Hive.isBoxOpen(_skippedBoxName)) {
      return Hive.box<dynamic>(_skippedBoxName);
    }
    return Hive.openBox<dynamic>(_skippedBoxName);
  }

  void _handleSearchChanged() {
    setState(() {});
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

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

/// One compact contact row: pastel initials on the leading side, the name, a
/// small `+` for an immediate single add, and a tick box for batch actions.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    super.key,
    required this.candidate,
    required this.busy,
    required this.selected,
    required this.onToggleSelection,
    required this.onAdd,
  });

  final ContactImportCandidate candidate;
  final bool busy;
  final bool selected;
  final VoidCallback onToggleSelection;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.brightness == Brightness.dark
        ? theme.colorScheme.primary
        : AppColors.primaryDark;

    return Container(
      decoration: softCardDecoration(
        context,
        radius: 14,
        color: selected
            ? Color.alphaBlend(
                accent.withValues(alpha: 0.10),
                theme.colorScheme.surface,
              )
            : null,
        borderColor: selected ? accent.withValues(alpha: 0.5) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggleSelection,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 4, 6),
            child: Row(
              children: <Widget>[
                InitialsAvatar(name: candidate.displayName, diameter: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    candidate.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _AddButton(busy: busy, color: accent, onPressed: onAdd),
                SizedBox.square(
                  dimension: 36,
                  child: Checkbox(
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    onChanged: (_) => onToggleSelection(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The small `+` that adds a single contact without going through a selection.
class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.busy,
    required this.color,
    required this.onPressed,
  });

  final bool busy;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'הוספה ועדכון מהיר',
      child: Material(
        color: color.withValues(alpha: 0.10),
        shape: CircleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onPressed,
          child: SizedBox.square(
            dimension: 30,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(7),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(Icons.add, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// The bar that slides in along the bottom once at least one contact is ticked.
class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.count,
    required this.onMarkIrrelevant,
    required this.onAdd,
  });

  final int count;
  final VoidCallback onMarkIrrelevant;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.brightness == Brightness.dark
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: softCardDecoration(context, radius: 18),
                child: Row(
                  children: <Widget>[
                    Text(
                      'נבחרו $count',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onMarkIrrelevant,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: const Icon(Icons.close, size: 17),
                      label: const Text('לא רלוונטי'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: onAdd,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: theme.brightness == Brightness.dark
                            ? AppColors.onSurface
                            : AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('הוספה'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
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
              buttonText: isPermanentlyDenied ? 'פתח הגדרות' : 'נסה שוב',
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
