import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/call_log_sort_service.dart';
import 'package:shadchan/services/contacts_import_service.dart';

/// Where one device contact stands in the add-friends flow.
enum ContactCandidateStatus {
  /// Still waiting to be decided on: shown in the regular list and in the deck.
  available,

  /// Already a friend in the matchmaker's database.
  inDatabase,

  /// Explicitly removed from the add-friends list. Never removed from the
  /// phone's contacts — only from this flow.
  removedFromList,

  /// Filtered out automatically by the name heuristics (businesses, titles...).
  hiddenByFilter,
}

/// One candidate together with the status it currently has. Search results carry
/// this so a row can be tagged `במאגר` / `הוסר מהרשימה` without every caller
/// recomputing the rule.
class ContactCandidateEntry {
  const ContactCandidateEntry({required this.candidate, required this.status});

  final ContactImportCandidate candidate;
  final ContactCandidateStatus status;

  bool get isAvailable => status == ContactCandidateStatus.available;
}

/// The single source of truth behind both add-friends views.
///
/// The list and the swipe deck are two ways of looking at the *same* contacts:
/// the same people are left, the same number was added, the same progress bar,
/// and an action taken in one view is visible in the other immediately. Keeping
/// that in one place is the only way the two can't drift apart — before this
/// each screen loaded its own copy of the device contacts and its own copy of
/// the skip list, so a contact removed on one side stayed on the other until
/// the screen was reopened.
///
/// Nothing here decides *how* a contact is presented; that is the only
/// difference between the two views.
class AddContactsSession extends ChangeNotifier {
  AddContactsSession(this._repository) {
    _repository.addListener(_handleRepositoryChanged);
  }

  /// Shared with the swipe deck since the very first version: a contact removed
  /// in either place stays out of both.
  static const String _skippedBoxName = 'swipe_skipped_phones';
  static const String _skippedSetKey = 'skipped_phones';
  static const String _revealedFilteredSetKey = 'revealed_filtered_phones';

  final PersonRepository _repository;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _disposed = false;
  double? _loadingProgress;
  String _loadingMessage = 'טוענים אנשי קשר...';
  ContactsPermissionState? _permissionState;

  /// Every usable device contact, including the ones already in the database
  /// and the ones removed from the list — search reaches all of them.
  List<ContactImportCandidate> _allCandidates =
      const <ContactImportCandidate>[];

  Set<String> _skippedPhones = <String>{};
  Set<String> _revealedFilteredPhones = <String>{};

  /// Stable denominator for the progress bar: people already in the database
  /// plus the contacts that were still to be decided on when the screen opened.
  /// Recomputing it live would move the goalposts with every add.
  int _progressTotal = 0;

  /// Friends added to the database during this visit, counted for the closing
  /// celebration and the swipe view's own tally.
  int _addedThisSession = 0;

  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  double? get loadingProgress => _loadingProgress;
  String get loadingMessage => _loadingMessage;
  ContactsPermissionState? get permissionState => _permissionState;
  bool get hasAnyCandidate => _allCandidates.isNotEmpty;

  /// Every usable device contact, whatever its status.
  List<ContactImportCandidate> get allCandidates =>
      List<ContactImportCandidate>.unmodifiable(_allCandidates);
  int get progressTotal => _progressTotal;
  int get addedThisSession => _addedThisSession;
  int get databaseCount => _repository.databaseCount;

  /// The contacts still waiting to be decided on, in the order the deck uses.
  List<ContactImportCandidate> get availableCandidates {
    final Set<String> existingPhones = _repository.getNormalizedPhones();
    return _allCandidates
        .where(
          (ContactImportCandidate candidate) =>
              _statusFor(candidate, existingPhones) ==
              ContactCandidateStatus.available,
        )
        .toList();
  }

  int get remainingCount => availableCandidates.length;

  /// Contacts hidden only by the automatic name filter, so they can be reviewed
  /// and put back one by one.
  List<ContactImportCandidate> get nameFilteredCandidates {
    final Set<String> existingPhones = _repository.getNormalizedPhones();
    return _allCandidates
        .where(
          (ContactImportCandidate candidate) =>
              _statusFor(candidate, existingPhones) ==
              ContactCandidateStatus.hiddenByFilter,
        )
        .toList()
      ..sort(_compareName);
  }

  /// Every contact matching [query], with the status each one has.
  ///
  /// Search deliberately reaches past the regular list: someone already in the
  /// database and someone removed from the list are both findable, tagged, and
  /// actionable from here.
  List<ContactCandidateEntry> search(String query) {
    final Set<String> existingPhones = _repository.getNormalizedPhones();
    final List<ContactCandidateEntry> entries = <ContactCandidateEntry>[];
    for (final ContactImportCandidate candidate in _allCandidates) {
      if (!candidate.matchesQuery(query)) {
        continue;
      }
      entries.add(
        ContactCandidateEntry(
          candidate: candidate,
          status: _statusFor(candidate, existingPhones),
        ),
      );
    }
    return entries;
  }

  ContactCandidateStatus statusOf(ContactImportCandidate candidate) {
    return _statusFor(candidate, _repository.getNormalizedPhones());
  }

  /// The friend already in the database behind a `במאגר` row, so tapping it can
  /// open their existing card.
  Person? personFor(ContactImportCandidate candidate) {
    return _repository.findByPhone(candidate.phone);
  }

  ContactCandidateStatus _statusFor(
    ContactImportCandidate candidate,
    Set<String> existingPhones,
  ) {
    if (existingPhones.contains(candidate.normalizedPhone)) {
      return ContactCandidateStatus.inDatabase;
    }
    if (_skippedPhones.contains(candidate.normalizedPhone)) {
      return ContactCandidateStatus.removedFromList;
    }
    if (candidate.isFilteredByName &&
        !_revealedFilteredPhones.contains(candidate.normalizedPhone)) {
      return ContactCandidateStatus.hiddenByFilter;
    }
    return ContactCandidateStatus.available;
  }

  // ---------------------------------------------------------------- actions

  /// Removes contacts from the add-friends list only. They stay in the phone
  /// and stay findable through search, where they can be put back.
  Future<void> removeFromList(Iterable<ContactImportCandidate> candidates) {
    for (final ContactImportCandidate candidate in candidates) {
      _skippedPhones.add(candidate.normalizedPhone);
    }
    _notify();
    return _persistSkipped();
  }

  /// Puts a removed contact back into both views.
  Future<void> restoreToList(ContactImportCandidate candidate) {
    _skippedPhones.remove(candidate.normalizedPhone);
    // A contact that the name filter would swallow again is revealed too,
    // otherwise "החזר לרשימה" would appear to do nothing.
    if (candidate.isFilteredByName) {
      _revealedFilteredPhones.add(candidate.normalizedPhone);
    }
    _notify();
    return Future.wait(<Future<void>>[
      _persistSkipped(),
      _persistRevealed(),
    ]).then((_) {});
  }

  /// Brings a contact the name filter hid back into the list.
  Future<void> revealFiltered(ContactImportCandidate candidate) {
    _revealedFilteredPhones.add(candidate.normalizedPhone);
    _notify();
    return _persistRevealed();
  }

  /// Clears any removal, so a contact about to be added is not also marked as
  /// removed underneath.
  Future<void> clearRemoval(ContactImportCandidate candidate) {
    if (!_skippedPhones.remove(candidate.normalizedPhone)) {
      return Future<void>.value();
    }
    _notify();
    return _persistSkipped();
  }

  void recordAdded([int count = 1]) {
    _addedThisSession += count;
    _notify();
  }

  void recordAddUndone([int count = 1]) {
    _addedThisSession = (_addedThisSession - count).clamp(0, 1 << 30);
    _notify();
  }

  // ---------------------------------------------------------------- loading

  Future<void> load() async {
    _isLoading = true;
    _isRefreshing = false;
    _loadingProgress = null;
    _loadingMessage = 'מבקשים גישה לאנשי קשר...';
    _notify();

    final ContactsPermissionState permissionState =
        await ContactsImportService.requestPermission();
    if (_disposed) {
      return;
    }
    _permissionState = permissionState;
    if (permissionState != ContactsPermissionState.granted) {
      _isLoading = false;
      _notify();
      return;
    }

    final Box<dynamic> box = await _openSkippedBox();
    _skippedPhones = _stringSet(box.get(_skippedSetKey));
    _revealedFilteredPhones = _stringSet(box.get(_revealedFilteredSetKey));
    if (_disposed) {
      return;
    }

    final List<ContactImportCandidate> cached =
        await ContactsImportService.loadCachedCandidates(_repository);
    if (_disposed) {
      return;
    }

    if (cached.isNotEmpty) {
      _allCandidates = await _orderForDeck(cached);
      if (_disposed) {
        return;
      }
      _isLoading = false;
      _isRefreshing = true;
      _captureProgressTotal();
      _notify();
    } else {
      _loadingMessage = 'טוענים אנשי קשר מהמכשיר...';
      _notify();
    }

    final List<ContactImportCandidate>
    fresh = await ContactsImportService.loadCandidates(
      _repository,
      onProgress: (ContactImportLoadProgress progress) {
        if (_disposed || !_isLoading) {
          return;
        }
        _loadingProgress = progress.value;
        _loadingMessage =
            'מסננים אנשי קשר (${progress.processedCount}/${progress.totalCount})...';
        _notify();
      },
    );
    if (_disposed) {
      return;
    }

    _allCandidates = await _orderForDeck(fresh);
    if (_disposed) {
      return;
    }
    _isLoading = false;
    _isRefreshing = false;
    _loadingProgress = null;
    _loadingMessage = 'טוענים אנשי קשר...';
    _captureProgressTotal();
    _notify();
  }

  Future<void> openSettingsAndRecheck() async {
    await ContactsImportService.openSettings();
    final ContactsPermissionState permissionState =
        await ContactsImportService.checkPermission();
    if (_disposed) {
      return;
    }
    if (permissionState == ContactsPermissionState.granted) {
      await load();
      return;
    }
    _permissionState = permissionState;
    _notify();
  }

  /// Ordered by the device call log where it is available, so the people the
  /// matchmaker actually talks to come first.
  Future<List<ContactImportCandidate>> _orderForDeck(
    List<ContactImportCandidate> candidates,
  ) {
    return CallLogSortService.sortByRecentCalls(candidates);
  }

  void _captureProgressTotal() {
    // Only ever grows within a visit; a stable denominator is what stops the
    // bar from resetting each time a friend is added.
    final int total = _repository.databaseCount + remainingCount;
    if (total > _progressTotal) {
      _progressTotal = total;
    }
  }

  int _compareName(ContactImportCandidate a, ContactImportCandidate b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

  Set<String> _stringSet(Object? raw) {
    if (raw is List) {
      return raw.whereType<String>().toSet();
    }
    return <String>{};
  }

  Future<void> _persistSkipped() async {
    final Box<dynamic> box = await _openSkippedBox();
    await box.put(_skippedSetKey, _skippedPhones.toList());
  }

  Future<void> _persistRevealed() async {
    final Box<dynamic> box = await _openSkippedBox();
    await box.put(_revealedFilteredSetKey, _revealedFilteredPhones.toList());
  }

  Future<Box<dynamic>> _openSkippedBox() async {
    if (Hive.isBoxOpen(_skippedBoxName)) {
      return Hive.box<dynamic>(_skippedBoxName);
    }
    return Hive.openBox<dynamic>(_skippedBoxName);
  }

  void _handleRepositoryChanged() {
    // A friend added anywhere changes what is left here, so both views redraw.
    _notify();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _repository.removeListener(_handleRepositoryChanged);
    super.dispose();
  }
}
