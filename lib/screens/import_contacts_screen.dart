import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/call_log_sort_service.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/empty_state.dart';
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
  // Shared with the swipe view so an ✕ in either place hides the contact from
  // both the list and the swipe deck.
  static const String _skippedBoxName = 'swipe_skipped_phones';
  static const String _skippedSetKey = 'skipped_phones';

  final TextEditingController _searchController = TextEditingController();
  final Set<String> _importingIds = <String>{};

  /// Contacts the user already acted on in this session (added or removed).
  /// They drop out of the visible list immediately so the swipe-to-dismiss
  /// animation has something to remove.
  final Set<String> _handledIds = <String>{};

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _filterSuggestedNames = true;

  _ImportSortOption _sortOption = _ImportSortOption.alphabetical;
  bool _sortAscending = true;

  /// Multi-select mode for removing several contacts at once.
  bool _selectionMode = false;
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

    if (widget.embedded) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: _buildBody(theme, visibleCandidates),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('ייבוא מאנשי קשר'), centerTitle: true),
        body: SafeArea(child: _buildBody(theme, visibleCandidates)),
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    List<ContactImportCandidate> visibleCandidates,
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

    final bool searching = _searchController.text.trim().isNotEmpty;

    return Column(
      children: <Widget>[
        if (_isRefreshing) const LinearProgressIndicator(minHeight: 3),
        if (_selectionMode)
          _SelectionBar(
            count: _selectedIds.length,
            onCancel: _exitSelection,
            onSelectAll: () => _selectAllVisible(visibleCandidates),
            onRemove: _selectedIds.isEmpty ? null : _removeSelected,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            children: <Widget>[
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  hintText: 'חיפוש לפי שם או טלפון...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: _searchController.clear,
                        ),
                ),
              ),
              const SizedBox(height: 6),
              _NameFilterSwitch(
                value: _filterSuggestedNames,
                filteredCount: _nameFilteredCount,
                onChanged: (bool value) {
                  setState(() {
                    _filterSuggestedNames = value;
                  });
                },
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _openSortSheet,
                  icon: const Icon(Icons.sort, size: 18),
                  label: Text('מיון: ${_sortOptionLabel(_sortOption)}'),
                ),
              ),
              const SizedBox(height: 4),
              _Hint(searching: searching),
            ],
          ),
        ),
        Expanded(
          child: visibleCandidates.isEmpty
              ? const EmptyState(
                  icon: Icons.search,
                  title: 'לא נמצאו תוצאות',
                  subtitle: 'נסו לחפש בשם אחר או לבטל את הסינון',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: visibleCandidates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final ContactImportCandidate candidate =
                        visibleCandidates[index];
                    return _ImportCandidateRow(
                      key: ValueKey<String>(candidate.deviceContactId),
                      candidate: candidate,
                      busy: _importingIds.contains(candidate.deviceContactId),
                      selectionMode: _selectionMode,
                      selected: _selectedIds.contains(
                        candidate.deviceContactId,
                      ),
                      onHeart: () => _onHeart(candidate),
                      onRemove: () => _onSkip(candidate),
                      onLongPress: () => _enterSelection(candidate),
                      onSelectToggle: () => _toggleSelection(candidate),
                    );
                  },
                ),
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

      // Contacts acted on this session drop out of the list (for the dismiss
      // animation). Exception: while searching, a ✕-removed contact stays
      // findable so it can be re-added.
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

      // When searching, surface everyone — including ✕-removed (skipped) and
      // the automatically filtered names — so removed contacts can be re-added.
      if (searching) {
        return true;
      }

      if (skipped) {
        return false;
      }

      if (!_filterSuggestedNames) {
        return true;
      }

      return !candidate.isFilteredByName;
    }).toList();
  }

  int get _nameFilteredCount {
    return _allCandidates
        .where((ContactImportCandidate candidate) => candidate.isFilteredByName)
        .length;
  }

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

  Future<void> _openSortSheet() async {
    final ({_ImportSortOption value, bool ascending})? selected =
        await showModalBottomSheet<({_ImportSortOption value, bool ascending})>(
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
                        'מיון לפי',
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
                  for (final ({_ImportSortOption value, String label}) option
                      in const <({_ImportSortOption value, String label})>[
                        (value: _ImportSortOption.alphabetical, label: 'א-ת'),
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

  Future<void> _onHeart(ContactImportCandidate candidate) async {
    if (_importingIds.contains(candidate.deviceContactId)) {
      return;
    }

    setState(() {
      _importingIds.add(candidate.deviceContactId);
      _handledIds.add(candidate.deviceContactId);
      _skippedPhones.remove(candidate.normalizedPhone);
    });

    final PersonRepository repository = context.read<PersonRepository>();
    try {
      final Person? person = await ContactsImportService.importSingleCandidate(
        candidate,
        repository,
      );

      if (!mounted) {
        return;
      }
      setState(() => _importingIds.remove(candidate.deviceContactId));

      if (person != null) {
        await QuickUpdateDialog.show(context, person);
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

  Future<void> _onSkip(ContactImportCandidate candidate) async {
    setState(() {
      _handledIds.add(candidate.deviceContactId);
      _skippedPhones.add(candidate.normalizedPhone);
    });
    await _saveSkippedPhones();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${candidate.displayName} הוסר מהרשימה'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'ביטול',
            onPressed: () => _onRestore(candidate),
          ),
        ),
      );
  }

  Future<void> _onRestore(ContactImportCandidate candidate) async {
    setState(() {
      _handledIds.remove(candidate.deviceContactId);
      _skippedPhones.remove(candidate.normalizedPhone);
    });
    await _saveSkippedPhones();
  }

  void _enterSelection(ContactImportCandidate candidate) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(candidate.deviceContactId);
    });
  }

  void _toggleSelection(ContactImportCandidate candidate) {
    setState(() {
      if (!_selectedIds.remove(candidate.deviceContactId)) {
        _selectedIds.add(candidate.deviceContactId);
      }
      if (_selectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAllVisible(List<ContactImportCandidate> visibleCandidates) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(
          visibleCandidates.map(
            (ContactImportCandidate candidate) => candidate.deviceContactId,
          ),
        );
    });
  }

  Future<void> _removeSelected() async {
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
      _selectionMode = false;
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
          content: Text('${selected.length} אנשי קשר הוסרו מהרשימה'),
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

    _skippedPhones = await _loadSkippedPhones();
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

  Future<Set<String>> _loadSkippedPhones() async {
    final Box<dynamic> box = await _openSkippedBox();
    final Object? raw = box.get(_skippedSetKey);
    if (raw is List) {
      return raw.cast<String>().toSet();
    }
    return <String>{};
  }

  Future<void> _saveSkippedPhones() async {
    final Box<dynamic> box = await _openSkippedBox();
    await box.put(_skippedSetKey, _skippedPhones.toList());
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

/// A single importable contact rendered with [Dismissible]. A full swipe from
/// the start side (right, in RTL) removes the contact; a full swipe from the
/// end side (left) adds it. The revealed background always matches the action
/// it triggers, and a partial swipe snaps back without resting open.
class _ImportCandidateRow extends StatelessWidget {
  const _ImportCandidateRow({
    super.key,
    required this.candidate,
    required this.busy,
    required this.selectionMode,
    required this.selected,
    required this.onHeart,
    required this.onRemove,
    required this.onLongPress,
    required this.onSelectToggle,
  });

  final ContactImportCandidate candidate;
  final bool busy;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onHeart;
  final VoidCallback onRemove;
  final VoidCallback onLongPress;
  final VoidCallback onSelectToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Dismissible(
      key: ValueKey<String>(candidate.deviceContactId),
      // Swiping is disabled while multi-selecting so taps only toggle marks.
      direction: busy || selectionMode
          ? DismissDirection.none
          : DismissDirection.horizontal,
      // Require a near-full swipe: a small drag snaps back instead of resting
      // half-open to reveal the action underneath.
      dismissThresholds: const <DismissDirection, double>{
        DismissDirection.startToEnd: 0.6,
        DismissDirection.endToStart: 0.6,
      },
      movementDuration: const Duration(milliseconds: 200),
      // Swiping from the start side (right, in RTL) reveals and triggers the
      // remove action with a black ✕.
      background: const _SwipeActionBackground(
        backgroundColor: AppColors.statusUnavailable,
        foregroundColor: AppColors.onPrimary,
        icon: Icons.close,
        label: 'הסרה',
        alignment: AlignmentDirectional.centerStart,
      ),
      // Swiping from the end side (left, in RTL) reveals and triggers the
      // heart / add action.
      secondaryBackground: _SwipeActionBackground(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        icon: Icons.favorite,
        label: 'הוספה',
        alignment: AlignmentDirectional.centerEnd,
      ),
      onDismissed: (DismissDirection direction) {
        if (direction == DismissDirection.startToEnd) {
          onRemove();
        } else {
          onHeart();
        }
      },
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: selectionMode && selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          // Tap toggles selection while multi-selecting; long-press enters it.
          onTap: selectionMode ? onSelectToggle : null,
          onLongPress: selectionMode ? null : onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                if (selectionMode)
                  Checkbox(value: selected, onChanged: (_) => onSelectToggle())
                else
                  IconButton(
                    tooltip: 'הוספה ועדכון מהיר',
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.favorite,
                            color: theme.colorScheme.primary,
                          ),
                    onPressed: busy ? null : onHeart,
                  ),
                Expanded(
                  child: Padding(
                    // Comfortable breathing room so long, wrapped names never
                    // crowd the heart / ✕ buttons.
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      candidate.displayName,
                      textAlign: TextAlign.center,
                      // Long / business names wrap onto extra lines as needed
                      // instead of being cut off after one line.
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (!selectionMode)
                  IconButton(
                    tooltip: 'הסרה מהרשימה',
                    icon: const Icon(Icons.close, color: Colors.black),
                    onPressed: busy ? null : onRemove,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The action bar shown while multiple contacts are selected for removal.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onSelectAll,
    required this.onRemove,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'ביטול בחירה',
              icon: const Icon(Icons.close),
              onPressed: onCancel,
            ),
            Expanded(
              child: Text(
                '$count נבחרו',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(onPressed: onSelectAll, child: const Text('בחר הכל')),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('הסרה'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The colored pane revealed behind a [_ImportCandidateRow] while swiping. The
/// icon + label is pinned to [alignment] so it appears on the side being
/// uncovered.
class _SwipeActionBackground extends StatelessWidget {
  const _SwipeActionBackground({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final String label;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: foregroundColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        searching
            ? 'בחיפוש מוצגים כל אנשי הקשר, כולל מסוננים ומוסרים'
            : 'הקש ❤️ להוספה ועדכון מהיר או ✕ להסרה · אפשר גם להחליק',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
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
              child: LinearProgressIndicator(value: progress),
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

class _NameFilterSwitch extends StatelessWidget {
  const _NameFilterSwitch({
    required this.value,
    required this.filteredCount,
    required this.onChanged,
  });

  final bool value;
  final int filteredCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              filteredCount == 0
                  ? 'סינון אנשי קשר לא רלוונטיים'
                  : 'סינון אנשי קשר לא רלוונטיים (מוסתרים: $filteredCount)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
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
