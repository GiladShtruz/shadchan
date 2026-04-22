import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/core/constants/enums.dart';
import 'package:shadchan/core/services/contacts_import_service.dart';
import 'package:shadchan/data/repositories/person_repository.dart';
import 'package:shadchan/presentation/shared/widgets/empty_state.dart';

class ImportContactsScreen extends StatefulWidget {
  const ImportContactsScreen({super.key});

  @override
  State<ImportContactsScreen> createState() => _ImportContactsScreenState();
}

class _ImportContactsScreenState extends State<ImportContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedContactIds = <String>{};
  final Map<String, Gender> _selectedGenders = <String, Gender>{};

  bool _isLoading = true;
  bool _isImporting = false;
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('טוענים אנשי קשר...'),
          ],
        ),
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
        subtitle: 'מוצגים רק אנשי קשר עם שם ומספר טלפון',
      );
    }

    if (visibleCandidates.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'לא נמצאו תוצאות',
        subtitle: 'נסו לחפש בשם אחר או לפי מספר טלפון',
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: <Widget>[
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'חיפוש לפי שם או טלפון...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _searchController.clear,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              _SelectionSummaryCard(
                selectedCount: _selectedContactIds.length,
                missingGenderCount: _missingGenderCount,
                totalCount: _allCandidates.length,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            itemCount: visibleCandidates.length,
            itemBuilder: (BuildContext context, int index) {
              final ContactImportCandidate candidate = visibleCandidates[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ContactCandidateCard(
                  candidate: candidate,
                  isSelected: _selectedContactIds.contains(
                    candidate.deviceContactId,
                  ),
                  selectedGender: _selectedGenders[candidate.deviceContactId],
                  onToggleSelection: candidate.alreadyExists
                      ? null
                      : () => _toggleSelection(candidate),
                  onGenderChanged: (Gender gender) {
                    setState(() {
                      _selectedGenders[candidate.deviceContactId] = gender;
                    });
                  },
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
        onPressed: selectedCount == 0 || _missingGenderCount > 0 || _isImporting
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
    return _allCandidates
        .where(
          (ContactImportCandidate candidate) => candidate.matchesQuery(query),
        )
        .toList();
  }

  int get _missingGenderCount {
    return _selectedContactIds
        .where((String id) => !_selectedGenders.containsKey(id))
        .length;
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
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
    final List<ContactImportCandidate> candidates =
        await ContactsImportService.loadCandidates(personRepository);
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
      _selectedGenders.removeWhere(
        (String id, Gender _) => !candidates.any(
          (ContactImportCandidate candidate) => candidate.deviceContactId == id,
        ),
      );
      _isLoading = false;
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
        _selectedGenders.remove(candidate.deviceContactId);
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
            (ContactImportCandidate candidate) => ContactImportSelection(
              candidate: candidate,
              gender: _selectedGenders[candidate.deviceContactId]!,
            ),
          )
          .toList();

      final ContactImportResult result =
          await ContactsImportService.importSelections(
            selections,
            personRepository,
          );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('הייבוא הסתיים'),
            content: Text(
              result.skippedExistingCount == 0
                  ? 'נוספו ${result.addedCount} אנשים חדשים'
                  : 'נוספו ${result.addedCount} אנשים חדשים\n'
                        '${result.skippedExistingCount} אנשי קשר דולגו כי המספר כבר קיים',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('סגירה'),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      context.pop();
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

class _ContactCandidateCard extends StatelessWidget {
  const _ContactCandidateCard({
    required this.candidate,
    required this.isSelected,
    required this.selectedGender,
    required this.onToggleSelection,
    required this.onGenderChanged,
  });

  final ContactImportCandidate candidate;
  final bool isSelected;
  final Gender? selectedGender;
  final VoidCallback? onToggleSelection;
  final ValueChanged<Gender> onGenderChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDisabled = candidate.alreadyExists;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggleSelection,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Checkbox(
                    value: isSelected,
                    onChanged: isDisabled
                        ? null
                        : (_) => onToggleSelection?.call(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          candidate.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          candidate.phone,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (candidate.hasAdditionalPhones)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'לאיש קשר זה יש כמה מספרים. ייובא המספר הראשון.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isDisabled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('כבר קיים'),
                    ),
                ],
              ),
              if (isSelected) ...<Widget>[
                const Divider(height: 20),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('מגדר', style: theme.textTheme.labelLarge),
                ),
                const SizedBox(height: 8),
                SegmentedButton<Gender>(
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  segments: Gender.values.map((Gender gender) {
                    return ButtonSegment<Gender>(
                      value: gender,
                      label: Text(gender.displayName),
                    );
                  }).toList(),
                  selected: selectedGender == null
                      ? <Gender>{}
                      : <Gender>{selectedGender!},
                  onSelectionChanged: (Set<Gender> selection) {
                    final Gender? gender = selection.isEmpty
                        ? null
                        : selection.first;
                    if (gender != null) {
                      onGenderChanged(gender);
                    }
                  },
                ),
                if (selectedGender == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'יש לבחור מגדר לפני ההוספה',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
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
    required this.missingGenderCount,
    required this.totalCount,
  });

  final int selectedCount;
  final int missingGenderCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = selectedCount == 0
        ? 'בחרו אנשי קשר להוספה'
        : missingGenderCount == 0
        ? 'הכל מוכן לייבוא'
        : 'חסר מגדר עבור $missingGenderCount אנשי קשר';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'זמינים לייבוא: $totalCount',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text('נבחרו: $selectedCount', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: missingGenderCount == 0
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
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
