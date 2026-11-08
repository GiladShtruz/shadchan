import 'dart:async';
import 'package:shadchan/services/analytics_service.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
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
    // Coming back to the app is the moment the answer may have changed: the
    // matchmaker went to the device settings to allow access, or added a
    // contact in the phone's own app. Neither should need this screen closed
    // and reopened to show up.
    _lifecycle = AppLifecycleListener(onResume: _handleResumed);
  }

  /// A device read younger than this is not repeated on resume — a share
  /// sheet or the WhatsApp round trip from this screen should not walk the
  /// whole address book again.
  static const Duration _resumeRefreshAfter = Duration(seconds: 30);

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
  AppLifecycleListener? _lifecycle;

  /// Access has not been granted and the system question has not been put in
  /// this visit: the screen explains why it is needed first, and only a tap
  /// on "לאפשר גישה" raises the system dialog. A prompt that arrives with no
  /// explanation is the one people refuse.
  bool _awaitingPermissionRequest = false;

  /// Permission is granted but reading the address book failed. Distinct
  /// from "no permission" and from "no contacts", each of which has its own
  /// sentence and its own way out.
  bool _loadFailed = false;
  DateTime? _lastDeviceReadAt;

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
  bool get awaitingPermissionRequest => _awaitingPermissionRequest;
  bool get loadFailed => _loadFailed;

  /// True when the last device read returned no contacts at all — not "none
  /// of them fits", but an empty address book.
  bool get deviceHasNoContacts =>
      ContactsImportService.lastDeviceContactCount == 0;

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

  /// Contacts kept off the regular list automatically — by the name filter
  /// (businesses, titles…) or because they have no mobile number — so they
  /// can be reviewed and put back one by one.
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
    if ((candidate.isFilteredByName || candidate.isLandline) &&
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
    if (candidate.isFilteredByName || candidate.isLandline) {
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

  // ------------------------------------------------------------- selection

  /// The contacts ticked in the list view.
  ///
  /// Held here rather than inside the list because the screen around both views
  /// has to be able to answer one question: is there a selection right now? A
  /// back press with contacts ticked means "undo the ticking", not "leave" —
  /// losing a dozen deliberate taps to a stray back gesture is the kind of
  /// thing that stops people using multi-select at all. It also means a
  /// selection survives a switch to the swipe view and back.
  final Set<String> _selectedContactIds = <String>{};

  Set<String> get selectedContactIds =>
      Set<String>.unmodifiable(_selectedContactIds);

  bool get hasSelection => _selectedContactIds.isNotEmpty;

  bool isSelected(String deviceContactId) =>
      _selectedContactIds.contains(deviceContactId);

  void toggleSelected(String deviceContactId) {
    if (!_selectedContactIds.remove(deviceContactId)) {
      _selectedContactIds.add(deviceContactId);
    }
    _notify();
  }

  void clearSelection() {
    if (_selectedContactIds.isEmpty) {
      return;
    }
    _selectedContactIds.clear();
    _notify();
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

  /// Opens the screen: shows what it can without asking anything, and asks
  /// for access only after explaining why ([requestAccess]).
  Future<void> load() async {
    _isLoading = true;
    _isRefreshing = false;
    _loadFailed = false;
    _loadingProgress = null;
    _loadingMessage = 'בודקים גישה לאנשי קשר...';
    _notify();

    final ContactsPermissionState permissionState = await _safePermission(
      ContactsImportService.checkPermission,
    );
    if (_disposed) {
      return;
    }
    _permissionState = permissionState;
    if (permissionState == ContactsPermissionState.granted) {
      await _loadGranted();
      return;
    }
    // Not granted yet. A permanent refusal goes straight to the settings
    // explanation; anything else waits for the matchmaker to ask for it.
    _awaitingPermissionRequest =
        permissionState == ContactsPermissionState.denied;
    _isLoading = false;
    _notify();
  }

  /// Raises the system permission dialog, after the explanation was read.
  Future<void> requestAccess() async {
    _awaitingPermissionRequest = false;
    _isLoading = true;
    _loadFailed = false;
    _loadingMessage = 'מבקשים גישה לאנשי קשר...';
    _notify();

    Analytics.log(AnalyticsEvent.contacts_permission_requested);
    final ContactsPermissionState permissionState = await _safePermission(
      ContactsImportService.requestPermission,
    );
    Analytics.log(switch (permissionState) {
      ContactsPermissionState.granted =>
        AnalyticsEvent.contacts_permission_granted,
      ContactsPermissionState.denied =>
        AnalyticsEvent.contacts_permission_denied,
      ContactsPermissionState.permanentlyDenied =>
        AnalyticsEvent.contacts_permission_blocked,
    });
    if (_disposed) {
      return;
    }
    _permissionState = permissionState;
    if (permissionState != ContactsPermissionState.granted) {
      _isLoading = false;
      _notify();
      return;
    }
    await _loadGranted();
  }

  /// Reads the address book again in the background, keeping what is on the
  /// screen until the new list arrives. Used by the manual refresh and on
  /// return to the app.
  Future<void> refresh() async {
    if (_permissionState != ContactsPermissionState.granted || _isLoading) {
      return load();
    }
    if (_isRefreshing) {
      return;
    }
    _isRefreshing = true;
    _loadFailed = false;
    _notify();
    // The access may have been taken away in the device settings since the
    // last read. Reading without it returns nothing, which would look like
    // an empty address book; say what actually happened instead.
    final ContactsPermissionState state = await _safePermission(
      ContactsImportService.checkPermission,
    );
    if (_disposed) {
      return;
    }
    if (state != ContactsPermissionState.granted) {
      _permissionState = state;
      _awaitingPermissionRequest = state == ContactsPermissionState.denied;
      _isRefreshing = false;
      _notify();
      return;
    }
    await _readDevice();
  }

  Future<void> _loadGranted() async {
    _awaitingPermissionRequest = false;
    // First-time permission also enables reciprocal discovery for a
    // matchmaker who never visits the personal area. Do not block importing.
    if (FirebaseBootstrap.isReady) {
      unawaited(ContactHashUpload.run());
    }

    final Box<dynamic> box = await _openSkippedBox();
    _skippedPhones = _stringSet(box.get(_skippedSetKey));
    _revealedFilteredPhones = _stringSet(box.get(_revealedFilteredSetKey));
    if (_disposed) {
      return;
    }

    // Re-reading the address book walks every contact on the phone, so it
    // starts now and does not hold up the first frame: awaiting it *before*
    // publishing the cached list is what used to leave this screen blank for
    // several seconds even though the list it was going to show had been on
    // disk the whole time.
    final Future<List<ContactImportCandidate>?> deviceContacts = _fetchDevice(
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

    List<ContactImportCandidate> cached = const <ContactImportCandidate>[];
    try {
      cached = await ContactsImportService.loadCachedCandidates(_repository);
    } catch (error) {
      // A cache that cannot be read is only a slower first frame.
      debugPrint('CONTACTS cache read failed: $error');
    }
    if (_disposed) {
      return;
    }

    if (cached.isNotEmpty) {
      // On the screen immediately, favourites first and then by name — the
      // same order the fresh read will land in, so nothing jumps under the
      // finger when it arrives.
      ContactsImportService.sortByFavoriteThenName(cached);
      _allCandidates = cached;
      _isLoading = false;
      _isRefreshing = true;
      _captureProgressTotal();
      _notify();
    } else {
      _loadingMessage = 'טוענים אנשי קשר מהמכשיר...';
      _notify();
    }

    _applyDeviceRead(await deviceContacts);
  }

  Future<void> _readDevice() async {
    _applyDeviceRead(await _fetchDevice(_repository));
  }

  /// The device read, with a failure turned into null instead of an
  /// exception nobody awaits: an unhandled error here used to leave the
  /// screen on its spinner (or on a stale cache) for good.
  Future<List<ContactImportCandidate>?> _fetchDevice(
    PersonRepository repository, {
    void Function(ContactImportLoadProgress progress)? onProgress,
  }) async {
    try {
      final List<ContactImportCandidate> fresh =
          await ContactsImportService.loadCandidates(
            repository,
            onProgress: onProgress,
          );
      _lastDeviceReadAt = DateTime.now();
      // How many, as bands — never who. A sudden drop after a release is the
      // "contacts went missing" signal.
      Analytics.log(AnalyticsEvent.contacts_sync_completed, <String, Object?>{
        'device_band': Analytics.band(
          ContactsImportService.lastDeviceContactCount ?? 0,
        ),
        'usable_band': Analytics.band(
          fresh.where((ContactImportCandidate c) => !c.isLandline).length,
        ),
      });
      return fresh;
    } catch (error, stack) {
      debugPrint('CONTACTS device read failed: $error\n$stack');
      Analytics.log(AnalyticsEvent.contacts_sync_failed, <String, Object?>{
        'error_type': Analytics.errorCode(error),
      });
      return null;
    }
  }

  void _applyDeviceRead(List<ContactImportCandidate>? fresh) {
    if (_disposed) {
      return;
    }
    _isLoading = false;
    _isRefreshing = false;
    _loadingProgress = null;
    _loadingMessage = 'טוענים אנשי קשר...';
    if (fresh == null) {
      // A cached list already on screen stays there; the failure is still
      // reported, so the matchmaker knows it may be out of date.
      _loadFailed = true;
      _notify();
      return;
    }
    _loadFailed = false;
    ContactsImportService.sortByFavoriteThenName(fresh);
    _allCandidates = fresh;
    _captureProgressTotal();
    _notify();
  }

  Future<ContactsPermissionState> _safePermission(
    Future<ContactsPermissionState> Function() ask,
  ) async {
    try {
      return await ask();
    } catch (error) {
      // No plugin (tests) or a platform refusal: treat as not granted, which
      // always leaves a way forward on screen.
      debugPrint('CONTACTS permission call failed: $error');
      return ContactsPermissionState.denied;
    }
  }

  void _handleResumed() {
    if (_disposed || _isLoading) {
      return;
    }
    if (_permissionState != ContactsPermissionState.granted) {
      // Back from the device settings — or the access was granted some other
      // way. Check quietly; only a change is acted on.
      unawaited(_recheckAfterResume());
      return;
    }
    final DateTime? last = _lastDeviceReadAt;
    if (last == null ||
        DateTime.now().difference(last) >= _resumeRefreshAfter) {
      unawaited(refresh());
    }
  }

  Future<void> _recheckAfterResume() async {
    final ContactsPermissionState state = await _safePermission(
      ContactsImportService.checkPermission,
    );
    if (_disposed) {
      return;
    }
    if (state == ContactsPermissionState.granted) {
      _permissionState = state;
      _isLoading = true;
      _loadingMessage = 'טוענים אנשי קשר...';
      _notify();
      await _loadGranted();
    }
  }

  /// Opens the device settings. The answer is picked up when the app comes
  /// back to the foreground ([_handleResumed]); `openSettings` itself returns
  /// the moment the settings screen opens, long before anything was changed.
  Future<void> openSettingsAndRecheck() async {
    try {
      await ContactsImportService.openSettings();
    } catch (error) {
      debugPrint('CONTACTS open settings failed: $error');
    }
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
    _lifecycle?.dispose();
    _repository.removeListener(_handleRepositoryChanged);
    super.dispose();
  }
}
