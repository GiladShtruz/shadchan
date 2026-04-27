import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/widgets/empty_state.dart';

class ImportContactsScreen extends StatefulWidget {
  const ImportContactsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ImportContactsScreen> createState() => _ImportContactsScreenState();
}

class _ImportContactsScreenState extends State<ImportContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedContactIds = <String>{};

  bool _isLoading = true;
  bool _isImporting = false;
  bool _isRefreshing = false;
  bool _filterSuggestedNames = true;
  double? _loadingProgress;
  String _loadingMessage = 'טוענים אנשי קשר...';
  ContactsPermissionState? _permissionState;
  List<ContactImportCandidate> _allCandidates =
      const <ContactImportCandidate>[];

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
    final List<ContactImportCandidate> visibleCandidates = _visibleCandidates;

    if (widget.embedded) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: <Widget>[
            Expanded(child: _buildBody(theme, visibleCandidates)),
            if (_buildBottomBar() != null) _buildBottomBar()!,
          ],
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('ייבוא מאנשי קשר'), centerTitle: true),
        body: SafeArea(child: _buildBody(theme, visibleCandidates)),
        bottomNavigationBar: _buildBottomBar(),
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

    return Column(
      children: <Widget>[
        if (_isRefreshing) const LinearProgressIndicator(minHeight: 3),
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
              const SizedBox(height: 6),
              _SelectionSummaryCard(
                selectedCount: _selectedContactIds.length,
                totalCount: visibleCandidates.length,
              ),
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
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  itemCount: visibleCandidates.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ContactImportCandidate candidate =
                        visibleCandidates[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ContactCandidateCard(
                        candidate: candidate,
                        isSelected: _selectedContactIds.contains(
                          candidate.deviceContactId,
                        ),
                        onToggleSelection: () => _toggleSelection(candidate),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget? _buildBottomBar() {
    final int selectedCount = _selectedContactIds.length;
    if (_isLoading || _permissionState != ContactsPermissionState.granted) {
      return null;
    }

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: FilledButton(
        onPressed: selectedCount == 0 || _isImporting
            ? null
            : _importSelectedContacts,
        child: _isImporting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Text(
                selectedCount == 0
                    ? 'בחרו אנשי קשר להוספה'
                    : 'הוספת $selectedCount אנשי קשר',
              ),
      ),
    );
  }

  List<ContactImportCandidate> get _visibleCandidates {
    final String query = _searchController.text.trim();
    return _allCandidates.where((ContactImportCandidate candidate) {
      if (!candidate.matchesQuery(query)) {
        return false;
      }

      if (query.isNotEmpty || !_filterSuggestedNames) {
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
      _selectedContactIds.removeWhere(
        (String id) => !candidates.any(
          (ContactImportCandidate candidate) => candidate.deviceContactId == id,
        ),
      );
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

  void _toggleSelection(ContactImportCandidate candidate) {
    final bool isSelected = _selectedContactIds.contains(
      candidate.deviceContactId,
    );
    if (isSelected) {
      setState(() {
        _selectedContactIds.remove(candidate.deviceContactId);
      });
      return;
    }

    final ContactImportCandidate? conflictingCandidate =
        _selectedCandidateWithPhone(candidate.normalizedPhone);
    if (conflictingCandidate != null) {
      _showSnackBar('כבר בחרתם איש קשר עם אותו מספר טלפון');
      return;
    }

    setState(() {
      _selectedContactIds.add(candidate.deviceContactId);
    });
  }

  ContactImportCandidate? _selectedCandidateWithPhone(String normalizedPhone) {
    for (final ContactImportCandidate candidate in _allCandidates) {
      if (!_selectedContactIds.contains(candidate.deviceContactId)) {
        continue;
      }

      if (candidate.normalizedPhone == normalizedPhone) {
        return candidate;
      }
    }

    return null;
  }

  Future<void> _importSelectedContacts() async {
    setState(() {
      _isImporting = true;
    });

    try {
      final PersonRepository personRepository = context
          .read<PersonRepository>();
      final List<ContactImportSelection> selections = _selectedContactIds
          .map(_candidateById)
          .whereType<ContactImportCandidate>()
          .map(
            (ContactImportCandidate candidate) =>
                ContactImportSelection(candidate: candidate),
          )
          .toList();

      await ContactsImportService.importSelections(
        selections,
        personRepository,
      );

      if (!mounted) {
        return;
      }

      context.go('/people');
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showSnackBar('לא הצלחנו לייבא את אנשי הקשר');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  ContactImportCandidate? _candidateById(String id) {
    for (final ContactImportCandidate candidate in _allCandidates) {
      if (candidate.deviceContactId == id) {
        return candidate;
      }
    }

    return null;
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

class _ContactCandidateCard extends StatelessWidget {
  const _ContactCandidateCard({
    required this.candidate,
    required this.isSelected,
    required this.onToggleSelection,
  });

  final ContactImportCandidate candidate;
  final bool isSelected;
  final VoidCallback onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggleSelection,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: <Widget>[
              Checkbox(
                value: isSelected,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => onToggleSelection(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  candidate.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionSummaryCard extends StatelessWidget {
  const _SelectionSummaryCard({
    required this.selectedCount,
    required this.totalCount,
  });

  final int selectedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = selectedCount == 0
        ? 'בחרו אנשי קשר להוספה'
        : 'הכל מוכן לייבוא';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Text(
            'זמינים: $totalCount',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'נבחרו: $selectedCount',
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
          Flexible(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
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
