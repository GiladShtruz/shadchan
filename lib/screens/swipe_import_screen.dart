import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/services/call_log_sort_service.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/widgets/empty_state.dart';

class SwipeImportScreen extends StatefulWidget {
  const SwipeImportScreen({
    super.key,
    this.embedded = false,
    this.onAddedCountChanged,
  });

  final bool embedded;

  /// Called whenever the number of contacts accepted in this session changes.
  final ValueChanged<int>? onAddedCountChanged;

  @override
  State<SwipeImportScreen> createState() => _SwipeImportScreenState();
}

enum _SwipeAction { accept, reject }

class _SwipeHistoryEntry {
  _SwipeHistoryEntry({
    required this.action,
    required this.candidate,
    this.importedCounted = false,
  });

  final _SwipeAction action;
  final ContactImportCandidate candidate;
  String? importedPersonId;
  bool importedCounted;
  bool wasUndone = false;
}

class _SwipeImportScreenState extends State<SwipeImportScreen> {
  static const String _skippedBoxName = 'swipe_skipped_phones';
  static const String _skippedSetKey = 'skipped_phones';

  final CardSwiperController _controller = CardSwiperController();

  bool _isLoading = true;
  ContactsPermissionState? _permissionState;
  double? _loadingProgress;
  String _loadingMessage = 'טוענים אנשי קשר...';
  List<ContactImportCandidate> _candidates = const <ContactImportCandidate>[];
  int _addedCount = 0;
  int _skippedCount = 0;
  int _remaining = 0;
  bool _isFinished = false;
  final List<_SwipeHistoryEntry> _history = <_SwipeHistoryEntry>[];
  Set<String> _skippedPhones = <String>{};

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _loadingProgress = null;
      _loadingMessage = 'מבקשים גישה לאנשי קשר...';
    });

    final ContactsPermissionState permissionState =
        await ContactsImportService.requestPermission();
    if (!mounted) return;

    if (permissionState != ContactsPermissionState.granted) {
      setState(() {
        _permissionState = permissionState;
        _isLoading = false;
      });
      return;
    }

    _skippedPhones = await _loadSkippedPhones();
    if (!mounted) return;

    final PersonRepository personRepository = context.read<PersonRepository>();
    final List<ContactImportCandidate> cachedCandidates =
        await ContactsImportService.loadCachedCandidates(personRepository);
    if (!mounted) return;

    if (cachedCandidates.isNotEmpty) {
      final List<ContactImportCandidate> sortedCachedCandidates =
          await _prepareCandidates(cachedCandidates);
      if (!mounted) return;

      setState(() {
        _permissionState = permissionState;
        _candidates = sortedCachedCandidates;
        _remaining = _candidates.length;
        _isLoading = false;
        _isFinished = _candidates.isEmpty;
      });

      unawaited(_refreshCandidatesCache(personRepository));
      return;
    }

    setState(() {
      _loadingMessage = 'טוענים אנשי קשר מהמכשיר...';
    });

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
    final List<ContactImportCandidate> sortedCandidates =
        await _prepareCandidates(candidates);
    if (!mounted) return;

    setState(() {
      _permissionState = permissionState;
      _candidates = sortedCandidates;
      _remaining = _candidates.length;
      _isLoading = false;
      _loadingProgress = null;
      _loadingMessage = 'טוענים אנשי קשר...';
      _isFinished = _candidates.isEmpty;
    });
  }

  Future<List<ContactImportCandidate>> _prepareCandidates(
    List<ContactImportCandidate> candidates,
  ) {
    return CallLogSortService.sortByRecentCalls(
      candidates
          .where(
            (ContactImportCandidate candidate) =>
                !candidate.isFilteredByName &&
                !_skippedPhones.contains(candidate.normalizedPhone),
          )
          .toList(),
    );
  }

  Future<void> _refreshCandidatesCache(
    PersonRepository personRepository,
  ) async {
    await ContactsImportService.loadCandidates(personRepository);
  }

  Future<void> _openSettings() async {
    await ContactsImportService.openSettings();
    if (!mounted) return;

    final ContactsPermissionState permissionState =
        await ContactsImportService.checkPermission();
    if (!mounted) return;

    if (permissionState == ContactsPermissionState.granted) {
      await _loadContacts();
      return;
    }

    setState(() {
      _permissionState = permissionState;
    });
  }

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    final ContactImportCandidate candidate = _candidates[previousIndex];
    if (direction == CardSwiperDirection.right) {
      _handleAccept(candidate);
    } else if (direction == CardSwiperDirection.left) {
      _handleReject(candidate);
    } else {
      return false;
    }
    return true;
  }

  bool _onUndo(
    int? previousIndex,
    int currentIndex,
    CardSwiperDirection direction,
  ) {
    if (_history.isEmpty) {
      return false;
    }

    final _SwipeHistoryEntry entry = _history.removeLast();
    if (entry.action == _SwipeAction.accept) {
      _undoAccept(entry);
    } else {
      _undoReject(entry);
    }
    return true;
  }

  void _handleAccept(ContactImportCandidate candidate) {
    final PersonRepository repo = context.read<PersonRepository>();
    final _SwipeHistoryEntry entry = _SwipeHistoryEntry(
      action: _SwipeAction.accept,
      candidate: candidate,
      importedCounted: true,
    );
    _history.add(entry);
    unawaited(_importAcceptedCandidate(candidate, repo, entry));
    setState(() {
      _addedCount++;
      _remaining = (_remaining - 1).clamp(0, _candidates.length);
    });
    _notifyAddedCount();
  }

  void _notifyAddedCount() {
    widget.onAddedCountChanged?.call(_addedCount);
  }

  Future<void> _importAcceptedCandidate(
    ContactImportCandidate candidate,
    PersonRepository repo,
    _SwipeHistoryEntry entry,
  ) async {
    try {
      final person = await ContactsImportService.importSingleCandidate(
        candidate,
        repo,
      );

      if (person == null) {
        _revertPendingAddedCount(entry);
        return;
      }

      entry.importedPersonId = person.id;
      if (entry.wasUndone) {
        await repo.delete(person.id);
      }
    } catch (_) {
      _revertPendingAddedCount(entry);
    }
  }

  void _revertPendingAddedCount(_SwipeHistoryEntry entry) {
    if (entry.wasUndone || !entry.importedCounted || !mounted) {
      return;
    }

    setState(() {
      entry.importedCounted = false;
      _addedCount = (_addedCount - 1).clamp(0, _candidates.length);
    });
    _notifyAddedCount();
  }

  void _undoAccept(_SwipeHistoryEntry entry) {
    entry.wasUndone = true;
    final String? personId = entry.importedPersonId;
    if (personId != null) {
      final PersonRepository repo = context.read<PersonRepository>();
      unawaited(repo.delete(personId));
    }
    setState(() {
      if (entry.importedCounted) {
        entry.importedCounted = false;
        _addedCount = (_addedCount - 1).clamp(0, _candidates.length);
      }
      _remaining = (_remaining + 1).clamp(0, _candidates.length);
      _isFinished = false;
    });
    _notifyAddedCount();
  }

  void _handleReject(ContactImportCandidate candidate) {
    _skippedPhones.add(candidate.normalizedPhone);
    unawaited(_saveSkippedPhones());
    _history.add(
      _SwipeHistoryEntry(action: _SwipeAction.reject, candidate: candidate),
    );
    setState(() {
      _skippedCount++;
      _remaining = (_remaining - 1).clamp(0, _candidates.length);
    });
  }

  void _undoReject(_SwipeHistoryEntry entry) {
    _skippedPhones.remove(entry.candidate.normalizedPhone);
    unawaited(_saveSkippedPhones());
    setState(() {
      _skippedCount = (_skippedCount - 1).clamp(0, _candidates.length);
      _remaining = (_remaining + 1).clamp(0, _candidates.length);
      _isFinished = false;
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

  void _onEnd() {
    setState(() {
      _isFinished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody(context);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('סריקת כרטיסים'), centerTitle: true),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return _LoadingContactsView(
        message: _loadingMessage,
        progress: _loadingProgress,
      );
    }

    final ContactsPermissionState? permissionState = _permissionState;
    if (permissionState == ContactsPermissionState.denied ||
        permissionState == ContactsPermissionState.permanentlyDenied) {
      final bool isPermanentlyDenied =
          permissionState == ContactsPermissionState.permanentlyDenied;
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
                onButtonPressed: isPermanentlyDenied
                    ? _openSettings
                    : _loadContacts,
              ),
              if (isPermanentlyDenied)
                TextButton(
                  onPressed: _loadContacts,
                  child: const Text('בדיקה מחדש'),
                ),
            ],
          ),
        ),
      );
    }

    if (_candidates.isEmpty) {
      return EmptyState(
        icon: Icons.done_all,
        title: 'אין אנשי קשר חדשים לסקור',
        subtitle: 'כל אנשי הקשר שלך כבר במאגר',
        buttonText: 'חזרה',
        onButtonPressed: () => Navigator.of(context).maybePop(),
      );
    }

    if (_isFinished) {
      return _buildSummary(context);
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _buildCounter(context),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: CardSwiper(
              controller: _controller,
              cardsCount: _candidates.length,
              numberOfCardsDisplayed: _candidates.length >= 3
                  ? 3
                  : _candidates.length,
              allowedSwipeDirection: const AllowedSwipeDirection.symmetric(
                horizontal: true,
              ),
              onSwipe: _onSwipe,
              onUndo: _onUndo,
              onEnd: _onEnd,
              cardBuilder:
                  (
                    BuildContext context,
                    int index,
                    int percentThresholdX,
                    int percentThresholdY,
                  ) {
                    return _NameCard(candidate: _candidates[index]);
                  },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _buildActionButtons(context),
        ),
      ],
    );
  }

  Widget _buildCounter(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = _candidates.length;
    final int done = total - _remaining;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text('${done + 1} / $total', style: theme.textTheme.titleMedium),
        Text(
          'נוספו $_addedCount · דולגו $_skippedCount',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _CircleActionButton(
          icon: Icons.favorite,
          color: theme.colorScheme.primary,
          tooltip: 'הוסף',
          onPressed: () => _controller.swipe(CardSwiperDirection.right),
        ),
        _CircleActionButton(
          icon: Icons.replay,
          color: theme.colorScheme.onSurfaceVariant,
          tooltip: 'ביטול',
          iconSize: 24,
          padding: 14,
          onPressed: _history.isEmpty ? null : () => _controller.undo(),
        ),
        _CircleActionButton(
          icon: Icons.close,
          color: theme.colorScheme.error,
          tooltip: 'דלג',
          onPressed: () => _controller.swipe(CardSwiperDirection.left),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.check_circle,
              size: 80,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('סיימנו!', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'נוספו $_addedCount אנשי קשר · דולגו $_skippedCount',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('חזרה'),
            ),
          ],
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

class _NameCard extends StatelessWidget {
  const _NameCard({required this.candidate});

  final ContactImportCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            candidate.displayName,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 32,
    this.padding = 18,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onPressed == null;
    final double effectiveAlpha = isDisabled ? 0.06 : 0.12;
    final Color effectiveColor = isDisabled
        ? color.withValues(alpha: 0.3)
        : color;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: effectiveAlpha),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Icon(icon, color: effectiveColor, size: iconSize),
          ),
        ),
      ),
    );
  }
}
