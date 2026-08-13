import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/services/call_log_sort_service.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/add_contacts_common.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/initials_avatar.dart';

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

enum _SwipeAction { accept, reject, defer }

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
  static const String _revealedFilteredSetKey = 'revealed_filtered_phones';

  /// Remembers that the swipe hint was already shown, so it only ever greets a
  /// first-time user.
  static const String _settingsBoxName = 'settings';
  static const String _hintSeenKey = 'swipeImportHintSeen';

  final CardSwiperController _controller = CardSwiperController();

  bool _isLoading = true;
  ContactsPermissionState? _permissionState;
  double? _loadingProgress;
  String _loadingMessage = 'טוענים אנשי קשר...';
  List<ContactImportCandidate> _candidates = const <ContactImportCandidate>[];
  int _addedCount = 0;
  int _skippedCount = 0;
  int _remaining = 0;
  int _progressTotal = 0;
  bool _isFinished = false;
  bool _hintSeen = true;
  final List<_SwipeHistoryEntry> _history = <_SwipeHistoryEntry>[];
  Set<String> _skippedPhones = <String>{};
  Set<String> _revealedFilteredPhones = <String>{};

  /// Contacts the user chose to come back to later this session ("דילוג"). They
  /// are neither imported nor permanently skipped; once the main deck is done
  /// they can be reviewed again.
  final List<ContactImportCandidate> _deferredCandidates =
      <ContactImportCandidate>[];

  /// Bumped whenever the deck contents change (e.g. reviewing deferred cards) so
  /// the [CardSwiper] is rebuilt from scratch instead of reusing a stale index.
  int _deckGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadHintSeen();
    _loadContacts();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _loadHintSeen() {
    if (!Hive.isBoxOpen(_settingsBoxName)) {
      return;
    }
    final bool seen =
        Hive.box<dynamic>(_settingsBoxName).get(_hintSeenKey) == true;
    _hintSeen = seen;
  }

  /// Called the first time the user acts on a card — by swipe or by button —
  /// after which the hint never comes back.
  void _markHintSeen() {
    if (_hintSeen) {
      return;
    }
    setState(() => _hintSeen = true);
    if (Hive.isBoxOpen(_settingsBoxName)) {
      unawaited(Hive.box<dynamic>(_settingsBoxName).put(_hintSeenKey, true));
    }
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
    _revealedFilteredPhones = await _loadRevealedFilteredPhones();
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
        _progressTotal =
            personRepository.databaseCount + sortedCachedCandidates.length;
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
      _progressTotal = personRepository.databaseCount + sortedCandidates.length;
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
                (!candidate.isFilteredByName ||
                    _revealedFilteredPhones.contains(
                      candidate.normalizedPhone,
                    )) &&
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
    } else if (direction == CardSwiperDirection.top) {
      _handleDefer(candidate);
    } else {
      return false;
    }
    _markHintSeen();
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
    switch (entry.action) {
      case _SwipeAction.accept:
        _undoAccept(entry);
      case _SwipeAction.reject:
        _undoReject(entry);
      case _SwipeAction.defer:
        _undoDefer(entry);
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
      final StagedContact? staged =
          await ContactsImportService.stageSingleCandidate(candidate, repo);

      if (staged == null) {
        _revertPendingAddedCount(entry);
        return;
      }

      if (entry.wasUndone) {
        // The swipe was taken back before the details were even asked for.
        await ContactsImportService.discardStagedCandidate(staged, repo);
        return;
      }

      if (!mounted) {
        await ContactsImportService.discardStagedCandidate(staged, repo);
        return;
      }

      final bool confirmed = await QuickUpdateDialog.show(
        context,
        staged.person,
      );
      if (confirmed && !entry.wasUndone) {
        await repo.activatePendingContactDraft(staged.person);
        entry.importedPersonId = staged.person.id;
        return;
      }

      // Cancelled (or undone meanwhile): the draft is thrown away instead of
      // being parked as a contact waiting for details. The candidate itself
      // goes back to the review-later pile, so the deck can offer them again.
      await ContactsImportService.discardStagedCandidate(staged, repo);
      if (!mounted || entry.wasUndone) {
        return;
      }
      _revertPendingAddedCount(entry);
      if (!_deferredCandidates.any(
        (ContactImportCandidate deferred) =>
            deferred.normalizedPhone == candidate.normalizedPhone,
      )) {
        setState(() => _deferredCandidates.add(candidate));
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

  void _handleDefer(ContactImportCandidate candidate) {
    // Not persisted anywhere: the candidate simply moves to a "review later"
    // pile that is offered again once the main deck is finished.
    _deferredCandidates.add(candidate);
    _history.add(
      _SwipeHistoryEntry(action: _SwipeAction.defer, candidate: candidate),
    );
    setState(() {
      _remaining = (_remaining - 1).clamp(0, _candidates.length);
    });
  }

  void _undoDefer(_SwipeHistoryEntry entry) {
    _deferredCandidates.removeWhere(
      (ContactImportCandidate c) =>
          c.normalizedPhone == entry.candidate.normalizedPhone,
    );
    setState(() {
      _remaining = (_remaining + 1).clamp(0, _candidates.length);
      _isFinished = false;
    });
  }

  /// Reloads the deck with the deferred contacts so the user can decide on them.
  void _reviewDeferred() {
    if (_deferredCandidates.isEmpty) {
      return;
    }
    setState(() {
      _candidates = List<ContactImportCandidate>.from(_deferredCandidates);
      _deferredCandidates.clear();
      _history.clear();
      _remaining = _candidates.length;
      _isFinished = false;
      _deckGeneration++;
    });
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

  Future<Set<String>> _loadRevealedFilteredPhones() async {
    final Box<dynamic> box = await _openSkippedBox();
    final Object? raw = box.get(_revealedFilteredSetKey);
    if (raw is List) {
      return raw.whereType<String>().toSet();
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
                buttonText: isPermanentlyDenied ? 'פתיחת הגדרות' : 'לנסות שוב',
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

    final int databaseCount = context.watch<PersonRepository>().databaseCount;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AddContactsProgressHeader(
            addedToDatabase: databaseCount,
            remaining: _remaining,
            total: _progressTotal,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _buildStats(context),
        ),
        Expanded(child: _buildDeck(context)),
        if (!_hintSeen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: const _SwipeHint(),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: _buildActionButtons(context),
        ),
      ],
    );
  }

  Widget _buildStats(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AddContactsStatsRow(
      stats: <AddContactsStat>[
        AddContactsStat(
          icon: Icons.favorite,
          label: 'הוספתי',
          value: _addedCount,
          color: theme.brightness == Brightness.dark
              ? AppColors.femaleAccentDm
              : AppColors.femaleAccent,
        ),
        AddContactsStat(
          icon: Icons.schedule,
          label: 'דילגתי',
          value: _deferredCandidates.length,
          color: theme.colorScheme.secondary,
        ),
        AddContactsStat(
          icon: Icons.close,
          label: 'לא רלוונטיים',
          value: _skippedCount,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  /// The card stack, deliberately kept small so the screen doesn't turn into a
  /// large empty white rectangle.
  Widget _buildDeck(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double deckWidth = math.min(constraints.maxWidth * 0.8, 300);
        // The swiper draws inside its own padding and lets the cards behind
        // peek out below, so the box it lives in is taller than the card.
        final double deckHeight = math.min(
          constraints.maxHeight,
          deckWidth * 1.15 + 54,
        );
        // Keep the circle proportional to whichever dimension is tighter, so a
        // short screen doesn't push the name off the card.
        final double avatarDiameter = math
            .min(deckWidth * 0.38, (deckHeight - 150) * 0.55)
            .clamp(56.0, 108.0);

        return Center(
          child: SizedBox(
            width: deckWidth,
            height: deckHeight,
            child: CardSwiper(
              key: ValueKey<int>(_deckGeneration),
              controller: _controller,
              cardsCount: _candidates.length,
              numberOfCardsDisplayed: _candidates.length >= 3
                  ? 3
                  : _candidates.length,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 30),
              scale: 0.94,
              backCardOffset: const Offset(0, 18),
              // Right = add, left = not relevant, up = review later ("דילוג").
              allowedSwipeDirection: const AllowedSwipeDirection.only(
                left: true,
                right: true,
                up: true,
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
                    return _NameCard(
                      candidate: _candidates[index],
                      avatarDiameter: avatarDiameter,
                    );
                  },
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        // The primary action: filled, largest, and first in reading order.
        _SwipeActionButton(
          icon: Icons.favorite,
          label: 'הוספה',
          diameter: 62,
          iconSize: 28,
          filled: true,
          color: dark ? theme.colorScheme.primary : AppColors.primaryDark,
          foregroundColor: dark ? AppColors.onSurface : AppColors.onPrimary,
          onPressed: () => _controller.swipe(CardSwiperDirection.right),
        ),
        // Come back to this contact once the deck is done.
        _SwipeActionButton(
          icon: Icons.schedule,
          label: 'דילוג',
          diameter: 48,
          iconSize: 21,
          color: theme.colorScheme.secondary,
          onPressed: () => _controller.swipe(CardSwiperDirection.top),
        ),
        // The quietest control — it only ever repairs a mistake.
        _SwipeActionButton(
          icon: Icons.replay,
          label: 'חזרה',
          diameter: 42,
          iconSize: 18,
          color: theme.colorScheme.onSurfaceVariant,
          onPressed: _history.isEmpty ? null : () => _controller.undo(),
        ),
        _SwipeActionButton(
          icon: Icons.close,
          label: 'לא רלוונטי',
          diameter: 58,
          iconSize: 26,
          color: theme.colorScheme.error,
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
              size: 72,
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.primary
                  : AppColors.primaryDark,
            ),
            const SizedBox(height: 16),
            Text('סיימנו!', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'הוספת $_addedCount חברים למאגר · $_skippedCount סומנו כלא רלוונטיים',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_deferredCandidates.isNotEmpty) ...<Widget>[
              FilledButton.icon(
                onPressed: _reviewDeferred,
                icon: const Icon(Icons.schedule),
                label: Text('חזרה לדילוגים (${_deferredCandidates.length})'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.tonal(
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

/// Shown once, to a first-time user, so the buttons and the swipes are both
/// discoverable.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.swipe_outlined,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'החליקו או השתמשו בכפתורים למטה',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// A single deck card: a pastel initials circle with the contact's name below.
class _NameCard extends StatelessWidget {
  const _NameCard({required this.candidate, required this.avatarDiameter});

  final ContactImportCandidate candidate;
  final double avatarDiameter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: softCardDecoration(context, radius: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          InitialsAvatar(name: candidate.displayName, diameter: avatarDiameter),
          const SizedBox(height: 20),
          Flexible(
            child: Text(
              candidate.displayName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the four deck actions: a circular button with its name underneath, so
/// none of them relies on the icon alone.
class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    required this.diameter,
    required this.iconSize,
    this.filled = false,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final double diameter;
  final double iconSize;

  /// The primary action is a solid disc; the rest are soft tints of [color].
  final bool filled;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool disabled = onPressed == null;
    final Color background = filled
        ? (disabled ? color.withValues(alpha: 0.4) : color)
        : color.withValues(alpha: disabled ? 0.05 : 0.12);
    final Color foreground = filled
        ? (foregroundColor ?? theme.colorScheme.onPrimary)
        : (disabled ? color.withValues(alpha: 0.35) : color);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: background,
          shape: const CircleBorder(),
          elevation: filled && !disabled ? 2 : 0,
          shadowColor: AppColors.onSurface.withValues(alpha: 0.25),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: diameter,
              child: Icon(icon, color: foreground, size: iconSize),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: disabled
                ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
