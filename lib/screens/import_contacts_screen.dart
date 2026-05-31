import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
import 'package:shadchan/models/person.dart';
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
    final List<ContactImportCandidate> visibleCandidates = _visibleCandidates;

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
              : SlidableAutoCloseBehavior(
                  child: ListView.separated(
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
                        onHeart: () => _onHeart(candidate),
                        onRemove: () => _onSkip(candidate),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  List<ContactImportCandidate> get _visibleCandidates {
    final String query = _searchController.text.trim();
    final bool searching = query.isNotEmpty;

    return _allCandidates.where((ContactImportCandidate candidate) {
      if (_handledIds.contains(candidate.deviceContactId)) {
        return false;
      }

      if (!candidate.matchesQuery(query)) {
        return false;
      }

      // When searching, surface everyone — including ✕-skipped and the
      // automatically filtered names.
      if (searching) {
        return true;
      }

      if (_skippedPhones.contains(candidate.normalizedPhone)) {
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

/// A single importable contact rendered with [Slidable]: the name is centered,
/// a ❤️ sits on the right and a (black) ✕ on the left. Swiping reveals the same
/// action underneath the card and a full swipe triggers it.
class _ImportCandidateRow extends StatelessWidget {
  const _ImportCandidateRow({
    super.key,
    required this.candidate,
    required this.busy,
    required this.onHeart,
    required this.onRemove,
  });

  final ContactImportCandidate candidate;
  final bool busy;
  final VoidCallback onHeart;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Slidable(
      key: ValueKey<String>(candidate.deviceContactId),
      enabled: !busy,
      // Right side (start, in RTL): the heart / add action.
      startActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.4,
        dismissible: DismissiblePane(onDismissed: onHeart),
        children: <Widget>[
          SlidableAction(
            onPressed: (_) => onHeart(),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            icon: Icons.favorite,
            label: 'הוספה',
            borderRadius: BorderRadius.circular(16),
          ),
        ],
      ),
      // Left side (end, in RTL): the remove action with a black ✕.
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.4,
        dismissible: DismissiblePane(onDismissed: onRemove),
        children: <Widget>[
          SlidableAction(
            onPressed: (_) => onRemove(),
            backgroundColor: const Color(0xFFE0E0E0),
            foregroundColor: Colors.black,
            icon: Icons.close,
            label: 'הסרה',
            borderRadius: BorderRadius.circular(16),
          ),
        ],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: 'הוספה ועדכון מהיר',
                icon: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.favorite, color: theme.colorScheme.primary),
                onPressed: busy ? null : onHeart,
              ),
              Expanded(
                child: Text(
                  candidate.displayName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'הסרה מהרשימה',
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: busy ? null : onRemove,
              ),
            ],
          ),
        ),
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
