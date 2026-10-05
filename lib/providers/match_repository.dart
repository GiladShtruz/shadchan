import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/backup_service.dart';
import 'package:shadchan/services/deleted_matches_store.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/dating_check_in.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/reminder_alerts.dart';
import 'package:shadchan/services/dating_status_memory.dart';
import 'package:shadchan/services/notification_service.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:uuid/uuid.dart';

/// Which side (if any) ended a proposal, used to phrase the journal and both
/// candidates' history when a proposal is rejected or the couple stopped.
enum MatchOutcomeParty { him, her, mutual, unknown }

/// How a proposal closed by "מהבירור עלה שזה פחות מתאים" is written down —
/// in the proposal's journal and in both candidates' history alike, so the two
/// records say the same thing.
const String _inquiryOutcomeLine = 'מהבירור עלה כי לא מתאים';

class MatchRepository extends ChangeNotifier {
  /// [_statusEventBox] is optional for the same reason `PersonRepository`'s
  /// event box is: a test that only needs proposals should not have to open a
  /// third box and register a third adapter to get one. Without it the ledger
  /// simply is not written, and everything else behaves identically.
  MatchRepository(this._matchBox, this._noteBox, [this._statusEventBox]) {
    // Pending notifications do not survive a reinstall or a device restart on
    // every Android build, so the whole set is re-scheduled on startup.
    _refreshNotifications();
  }

  final Box<MatchIdea> _matchBox;
  final Box<MatchNote> _noteBox;
  final Box<MatchStatusEvent>? _statusEventBox;
  final Uuid _uuid = const Uuid();

  /// Every recorded status move, in no particular order.
  ///
  /// This is the ledger `ActivityStats` counts from. Before it existed a status
  /// change had to be inferred from the automatic journal notes, which only
  /// some transitions write, and person events had to be de-duplicated against
  /// them by a time window. Both guesses are gone.
  List<MatchStatusEvent> getAllStatusEvents() =>
      _statusEventBox?.values.toList() ?? const <MatchStatusEvent>[];

  /// One proposal's own moves, oldest first.
  List<MatchStatusEvent> getStatusEventsForMatch(String matchId) {
    final List<MatchStatusEvent> events =
        _statusEventBox?.values
            .where((MatchStatusEvent event) => event.matchId == matchId)
            .toList() ??
        <MatchStatusEvent>[];
    events.sort(
      (MatchStatusEvent a, MatchStatusEvent b) =>
          a.createdAt.compareTo(b.createdAt),
    );
    return events;
  }

  /// Records a move. Called from every place a proposal's status is written —
  /// there are three, and adding a fourth without calling this is the one way
  /// to make the activity figures wrong again.
  ///
  /// [automatic] marks a move the app made itself, which is history worth
  /// keeping but not work the matchmaker did.
  Future<void> _logStatusChange({
    required String matchId,
    required MatchStatus? from,
    required MatchStatus to,
    required DateTime at,
    bool automatic = false,
  }) async {
    final Box<MatchStatusEvent>? box = _statusEventBox;
    if (box == null || from == to) {
      return;
    }
    final MatchStatusEvent event = MatchStatusEvent(
      id: _uuid.v4(),
      matchId: matchId,
      fromStatus: from,
      toStatus: to,
      createdAt: at,
      automatic: automatic,
    );
    await box.put(event.id, event);
  }

  int get count => _matchBox.length;

  List<MatchIdea> getAll() {
    final List<MatchIdea> matches = _matchBox.values.toList();
    matches.sort(_sortByUpdatedAtDesc);
    return matches;
  }

  List<MatchIdea> getActive() {
    final List<MatchIdea> matches = _matchBox.values
        .where((MatchIdea match) => !match.status.isArchived)
        .toList();
    matches.sort(_sortByUpdatedAtDesc);
    return matches;
  }

  List<MatchIdea> getArchived() {
    final List<MatchIdea> matches = _matchBox.values
        .where((MatchIdea match) => match.status.isArchived)
        .toList();
    matches.sort(_sortByUpdatedAtDesc);
    return matches;
  }

  MatchIdea? getById(String id) {
    return _matchBox.get(id);
  }

  bool containsMatchId(String id) {
    return _matchBox.containsKey(id);
  }

  bool containsNoteId(String id) {
    return _noteBox.containsKey(id);
  }

  List<MatchIdea> getByPersonId(String personId) {
    final List<MatchIdea> matches = _matchBox.values.where((MatchIdea match) {
      return match.personAId == personId || match.personBId == personId;
    }).toList();

    matches.sort(_sortByUpdatedAtDesc);
    return matches;
  }

  List<MatchIdea> search(String query, PersonRepository personRepo) {
    final String normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return getAll();
    }

    final List<MatchIdea> matches = _matchBox.values.where((MatchIdea match) {
      final Person? personA = personRepo.getById(match.personAId);
      final Person? personB = personRepo.getById(match.personBId);

      return personMatchesQuery(personA, normalizedQuery) ||
          personMatchesQuery(personB, normalizedQuery);
    }).toList();

    matches.sort(_sortByUpdatedAtDesc);
    return matches;
  }

  bool isDuplicate(String personAId, String personBId) {
    return findExisting(personAId, personBId) != null;
  }

  MatchIdea? findExisting(String personAId, String personBId) {
    for (final MatchIdea match in _matchBox.values) {
      final bool isSameDirection =
          match.personAId == personAId && match.personBId == personBId;
      final bool isReverseDirection =
          match.personAId == personBId && match.personBId == personAId;

      if (isSameDirection || isReverseDirection) {
        return match;
      }
    }

    return null;
  }

  Future<MatchIdea?> create(String personAId, String personBId) async {
    if (isDuplicate(personAId, personBId)) {
      return null;
    }

    final DateTime now = DateTime.now();
    final MatchIdea match = MatchIdea(
      id: _uuid.v4(),
      personAId: personAId,
      personBId: personBId,
      status: MatchStatus.idea,
      currentHandler: CurrentHandler.me,
      createdAt: now,
      updatedAt: now,
    );
    // **Every idea that is not closed is looked at once a month** unless the
    // matchmaker says otherwise — see [defaultReminderFrom].
    match
      ..reminderDate = defaultReminderFrom(now)
      ..reminderNote = defaultReminderNote;

    await _matchBox.put(match.id, match);
    // The journal opens with the proposal. It used to start empty on purpose,
    // back when it was only a place for the matchmaker's own free notes; it is
    // now the proposal's whole record — every status move, reminder, contact
    // and card sent is filed here — and a record whose first line is missing
    // reads as though the proposal appeared from nowhere.
    await _createNote(
      matchId: match.id,
      text: 'הרעיון נפתח',
      createdAt: now,
      isAutomatic: true,
    );

    final Person? Function(String)? resolve = resolvePerson;
    // The fallback only stands in for a record that vanished between the
    // proposal being made and this line being written, so it is deliberately
    // the one word that fits either side.
    // Full names: a candidate's history is read months later, and "נפתח רעיון
    // עם אהבה" leaves the reader to guess which אהבה.
    final String nameA = _fullName(resolve?.call(personAId), 'הצד השני');
    final String nameB = _fullName(resolve?.call(personBId), 'הצד השני');
    await logPersonEvent?.call(
      personAId,
      PersonEventType.proposalOpened,
      'נפתח רעיון עם $nameB',
      relatedPersonId: personBId,
      relatedMatchId: match.id,
    );
    await logPersonEvent?.call(
      personBId,
      PersonEventType.proposalOpened,
      'נפתח רעיון עם $nameA',
      relatedPersonId: personAId,
      relatedMatchId: match.id,
    );

    _recordActivity(match.id, HomeActivityAction.createdIdea);
    notifyListeners();
    _refreshNotifications();
    return match;
  }

  Future<void> update(MatchIdea match) async {
    match.updatedAt = DateTime.now();
    await match.save();
    notifyListeners();
    _refreshNotifications();
  }

  /// Moves a proposal to [newStatus].
  ///
  /// [journal] is false only for a caller that writes a fuller line of its own
  /// — [recordOutcome] knows *who* ended the idea and why, and "הרעיון
  /// נסגר" directly above "הרעיון נדחה (מי: שרה)" says the same thing twice
  /// and dates it twice.
  /// Keeps [MatchIdea.datingStartedAt] and [MatchIdea.datingEndedAt] true to
  /// a move from [from] to [to], so a couple's card can say how long they have
  /// been — or were — going out.
  ///
  /// Going out starts the clock. Stopping — closed, separated, married, put
  /// on hold — stops it and keeps the start. Going back out within a day of
  /// stopping (an undo, a mis-tap put right) carries on the same stretch.
  /// A couple who went out before these fields existed get their start from
  /// the status ledger when they stop.
  void noteDatingSpan(
    MatchIdea match, {
    required MatchStatus from,
    required MatchStatus to,
    required DateTime at,
  }) {
    if (from == to) {
      return;
    }
    if (to == MatchStatus.dating) {
      final DateTime? ended = match.datingEndedAt;
      final bool resumed =
          match.datingStartedAt != null &&
          ended != null &&
          at.difference(ended) < DatingHistory.mistakeWindow;
      if (!resumed) {
        match.datingStartedAt = at;
      }
      match.datingEndedAt = null;
    } else if (from == MatchStatus.dating) {
      match.datingStartedAt ??= DatingCheckIn.startedAt(
        match,
        events: getAllStatusEvents(),
      );
      match.datingEndedAt = at;
    }
  }

  Future<void> updateStatus(
    String matchId,
    MatchStatus newStatus, {
    bool journal = true,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }

    final DateTime now = DateTime.now();
    final MatchStatus previous = match.status;
    noteDatingSpan(match, from: previous, to: newStatus, at: now);
    match
      ..status = newStatus
      ..updatedAt = now;
    // A deliberate pause only lasts as long as the proposal is waiting.
    if (newStatus != MatchStatus.unavailable) {
      match.waitingReason = null;
    }
    // A closed idea has nothing left to be reminded about; one that comes back
    // to life gets its monthly check back.
    if (newStatus.isArchived) {
      match
        ..reminderDate = null
        ..reminderNote = null;
    } else if (newStatus != MatchStatus.dating &&
        (match.reminderDate == null || match.reminderDate!.isBefore(now))) {
      match
        ..reminderDate = defaultReminderFrom(now)
        ..reminderNote = defaultReminderNote;
    }
    await match.save();
    await _logStatusChange(
      matchId: matchId,
      from: previous,
      to: newStatus,
      at: now,
    );
    // A couple that starts dating is no longer available to anyone else.
    if (newStatus == MatchStatus.dating) {
      // Before the status is overwritten, not after. What each side was is the
      // only thing that can say where to put them back when the couple stop
      // seeing each other — see [DatingStatusMemory].
      for (final String personId in <String>[
        match.personAId,
        match.personBId,
      ]) {
        final ProfileStatus? before = resolvePerson
            ?.call(personId)
            ?.profileStatus;
        if (before != null) {
          await DatingStatusMemory.remember(
            matchId: matchId,
            personId: personId,
            status: before,
          );
        }
      }
      await markPersonBusy?.call(match.personAId, matchId);
      await markPersonBusy?.call(match.personBId, matchId);
      await _createNote(
        matchId: matchId,
        text: 'התחילו לצאת',
        createdAt: now,
        isAutomatic: true,
      );
      // **The first week is the one that gets forgotten.** A couple who have
      // just started is the moment a matchmaker's call is worth most and the
      // moment nothing in the app was asking for one: the proposal left the
      // "רעיונות פתוחים" row, stopped being nudged, and simply sat there. So
      // going out books its own check-in, a week out, and the dating panel
      // books the next one each time somebody actually checks — see
      // [DatingCheckIn] and [recordDatingCheckIn].
      //
      // Only when nothing is already booked: a reminder the matchmaker set by
      // hand is a decision, and overwriting it here would silently undo it.
      // The default monthly check is not a decision anybody made, so going
      // out replaces it with the first-week one.
      if (match.reminderDate == null ||
          match.reminderDate!.isBefore(now) ||
          match.reminderNote == defaultReminderNote) {
        await setReminder(
          matchId,
          now.add(DatingCheckIn.first),
          note: 'לבדוק איך הולך לזוג',
          journal: false,
        );
      }
    } else if (newStatus == MatchStatus.married) {
      // Nothing to put back for a couple who married.
      await DatingStatusMemory.forget(
        matchId: matchId,
        personId: match.personAId,
      );
      await DatingStatusMemory.forget(
        matchId: matchId,
        personId: match.personBId,
      );
      await markPersonMazelTov?.call(match.personAId, matchId);
      await markPersonMazelTov?.call(match.personBId, matchId);
      await _createNote(
        matchId: matchId,
        text: 'מזל טוב — התחתנו',
        createdAt: now,
        isAutomatic: true,
      );
    } else if (previous == MatchStatus.dating) {
      // The mirror of the branch above: the couple who were out are not a
      // couple any more, so the "תפוס" this proposal put on both cards comes
      // back off. Only this proposal's own doing is undone — a side who is
      // "בהפסקה", already "מזל טוב", or out with somebody else is left alone.
      await _releaseFromDating(match);
    }

    // Every other move is written down too. The journal is the proposal's
    // whole history now that there is no screen of its own to read it from —
    // see [addNote] — and a status that changed with no line under it is the
    // one gap a matchmaker notices, because it is the change they most want to
    // be able to date afterwards. The three transitions above write their own,
    // warmer sentence; this covers the rest.
    if (journal &&
        newStatus != MatchStatus.dating &&
        newStatus != MatchStatus.married &&
        previous != newStatus) {
      await _createNote(
        matchId: matchId,
        text: _statusLine(from: previous, to: newStatus),
        createdAt: now,
        isAutomatic: true,
      );
    }

    _recordActivity(matchId, HomeActivityAction.changedStatus);
    notifyListeners();
    _refreshNotifications();
  }

  /// How a plain status move reads in the journal.
  ///
  /// Named for the destination rather than written as "X ← Y": the line is read
  /// in a list that is already in order, so where it came from is the line
  /// above it, and a sentence beats an arrow.
  static String _statusLine({
    required MatchStatus from,
    required MatchStatus to,
  }) {
    switch (to) {
      case MatchStatus.idea:
        return from.isArchived ? 'הרעיון נפתח מחדש' : 'הרעיון חזר להיות פתוח';
      case MatchStatus.checking:
        return 'הרעיון בבדיקה';
      case MatchStatus.unavailable:
        return 'הרעיון עבר להמתנה';
      case MatchStatus.rejected:
        return 'הרעיון נסגר';
      case MatchStatus.dated:
        return 'יצאו ולא המשיכו';
      case MatchStatus.dating:
      case MatchStatus.married:
        // Both write their own line at the call site, in warmer words.
        return to.displayName;
    }
  }

  /// Puts both sides of a proposal that has left "יוצאים" back where they were.
  ///
  /// The guard is the whole point. "תפוס" is not owned by one proposal: the
  /// matchmaker can set it by hand, and somebody can be out with a second
  /// candidate. So a side is only freed when they are still "תפוס" *and* no
  /// other proposal of theirs is dating; anything else is somebody else's
  /// decision to undo.
  ///
  /// **Back to what they were, not always to "פנוי".** Almost everybody was
  /// available before the couple went out and this is the same thing it always
  /// did — but a candidate who was "בהפסקה" when the proposal moved is put back
  /// on their break rather than quietly returned to the pool. See
  /// [DatingStatusMemory].
  Future<void> _releaseFromDating(MatchIdea match) async {
    for (final String personId in <String>[match.personAId, match.personBId]) {
      if (resolvePerson?.call(personId)?.profileStatus != ProfileStatus.busy) {
        // Whatever they are now, it is not this proposal's to undo — but the
        // note about what they used to be is dead either way.
        await DatingStatusMemory.forget(matchId: match.id, personId: personId);
        continue;
      }
      if (_isDatingElsewhere(personId, excludingMatchId: match.id)) {
        continue;
      }
      final ProfileStatus restored = DatingStatusMemory.restoreFor(
        matchId: match.id,
        personId: personId,
      );
      await DatingStatusMemory.forget(matchId: match.id, personId: personId);
      await restorePersonStatus?.call(personId, restored, match.id);
    }
  }

  bool _isDatingElsewhere(String personId, {required String excludingMatchId}) {
    return _matchBox.values.any(
      (MatchIdea other) =>
          other.id != excludingMatchId &&
          other.status == MatchStatus.dating &&
          (other.personAId == personId || other.personBId == personId),
    );
  }

  /// Marks a person as "תפוס". Wired to [PersonRepository] in `main.dart`.
  ///
  /// The proposal's id travels with it so the person's history records *why*
  /// their status changed — and so the activity count knows this was the same
  /// act as the proposal's own move rather than a second one.
  Future<void> Function(String personId, String matchId)? markPersonBusy;

  /// Marks both people as "מזל טוב" when the proposal becomes a wedding.
  Future<void> Function(String personId, String matchId)? markPersonMazelTov;

  /// Puts a person back to the status they held before this proposal marked
  /// them "תפוס" — usually "פנוי", sometimes "בהפסקה". Called only through
  /// [_releaseFromDating], which owns the decision about whether freeing them
  /// is this proposal's to make.
  Future<void> Function(String personId, ProfileStatus status, String matchId)?
  restorePersonStatus;

  /// Records a history event on a person. Wired to
  /// [PersonRepository.logEvent] in `main.dart` so proposal outcomes are logged
  /// on both candidates without this repository owning the person store.
  Future<void> Function(
    String personId,
    PersonEventType type,
    String text, {
    String? relatedPersonId,
    String? relatedMatchId,
    DateTime? createdAt,
  })?
  logPersonEvent;

  /// Deletes what a proposal wrote into its candidates' histories from a given
  /// moment on. Wired to [PersonRepository.deleteMatchEventsSince] in
  /// `main.dart`; used only by [undoClose].
  Future<void> Function(String matchId, DateTime since)?
  deletePersonEventsSince;

  /// Takes every history line a proposal wrote on its candidates, returning
  /// them for a later restore. Wired to [PersonRepository.takeMatchEvents].
  Future<List<Map<String, dynamic>>> Function(String matchId)? takePersonEvents;

  /// Puts back lines taken by [takePersonEvents]. Wired to
  /// [PersonRepository.restoreEvents].
  Future<void> Function(List<Map<String, dynamic>> events)? restorePersonEvents;

  /// Takes back a closing made a moment ago — "ביטול" on "הרעיון עבר לארכיון".
  ///
  /// **As though it never happened, not as a second move.** Reopening would
  /// leave "הרעיון נסגר" and "הרעיון נפתח מחדש" one above the other in the
  /// journal, two status moves in the activity ledger and a closing line on
  /// both candidates. So the status is put back through [updateStatus] — which
  /// is what re-marks a dating couple "תפוס" — and then everything written from
  /// [since] on is removed: journal lines, status events and history events,
  /// including the ones that put-back itself just wrote.
  Future<void> undoClose(
    String matchId, {
    required MatchStatus previousStatus,
    required DateTime previousUpdatedAt,
    required DateTime since,
    String? waitingReason,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }
    await updateStatus(matchId, previousStatus, journal: false);

    bool written(DateTime at) => !at.isBefore(since);
    final List<dynamic> noteKeys = _noteBox.keys.where((dynamic key) {
      final MatchNote? note = _noteBox.get(key);
      return note != null && note.matchId == matchId && written(note.createdAt);
    }).toList();
    await _noteBox.deleteAll(noteKeys);

    final Box<MatchStatusEvent>? statusEvents = _statusEventBox;
    if (statusEvents != null) {
      final List<dynamic> eventKeys = statusEvents.keys.where((dynamic key) {
        final MatchStatusEvent? event = statusEvents.get(key);
        return event != null &&
            event.matchId == matchId &&
            written(event.createdAt);
      }).toList();
      await statusEvents.deleteAll(eventKeys);
    }
    await deletePersonEventsSince?.call(matchId, since);

    match
      ..updatedAt = previousUpdatedAt
      ..waitingReason = previousStatus == MatchStatus.unavailable
          ? waitingReason
          : match.waitingReason;
    await match.save();
    notifyListeners();
  }

  /// Sets (or clears, with a null [date]) the reminder on a proposal. Clearing
  /// is also how a due reminder is marked as handled, which takes the proposal
  /// off the "ביקשת שנזכיר לך" list.
  Future<void> setReminder(
    String matchId,
    DateTime? date, {
    String? note,
    bool journal = true,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }

    // An emptied note is no note. Storing the empty string instead of null
    // left the reminder carrying a note that reads as absent everywhere in the
    // app except the notification, which prints `reminderNote ?? '...'` and so
    // fired with an empty body.
    final String trimmedNote = (note ?? '').trim();
    final DateTime? previous = match.reminderDate;
    final DateTime now = DateTime.now();
    match
      ..reminderDate = date
      ..reminderNote = date == null || trimmedNote.isEmpty ? null : trimmedNote
      ..updatedAt = now;
    await match.save();

    // Setting a reminder is a decision about the proposal, so it is filed like
    // one. Clearing it is the same decision in reverse and is worth a line for
    // the same reason: six months on, "handled it" and "gave up on it" look
    // identical unless the journal says which.
    if (journal && date != previous) {
      await _createNote(
        matchId: matchId,
        text: date == null
            ? 'התזכורת בוטלה'
            : 'נקבעה תזכורת ל־${_journalDate(date)}'
                  '${trimmedNote.isEmpty ? '' : ' — $trimmedNote'}',
        createdAt: now,
        isAutomatic: true,
      );
    }
    notifyListeners();
    _refreshNotifications();
  }

  /// A date as the journal writes it: dd.MM.yyyy, the same shape everywhere.
  static String _journalDate(DateTime date) {
    final String day = date.day.toString().padLeft(2, '0');
    final String month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  /// Records that a card went out of this proposal — the "יאללה לקדם!" row.
  ///
  /// **Two things happen at once, and they belong together.** The proposal
  /// remembers what was last sent, which is what turns that row from a prompt
  /// into a report; and the journal gains the line, because the whole point of
  /// the journal is that a matchmaker can see what has actually been done.
  ///
  /// The status moves to "בבדיקה" only from "רעיון" — a proposal that is
  /// waiting, out, or closed is not put back into circulation by somebody
  /// forwarding a card from it.
  Future<void> recordCardShared(
    String matchId,
    String label, {
    bool journal = true,
  }) async {
    final MatchIdea? match = getById(matchId);
    final String trimmed = label.trim();
    if (match == null || trimmed.isEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    final MatchStatus previous = match.status;
    match
      ..lastShareLabel = trimmed
      ..lastShareAt = now
      ..updatedAt = now;
    if (previous == MatchStatus.idea) {
      match.status = MatchStatus.checking;
    }
    await match.save();
    if (match.status != previous) {
      await _logStatusChange(
        matchId: matchId,
        from: previous,
        to: match.status,
        at: now,
      );
    }
    if (journal) {
      await _createNote(
        matchId: matchId,
        text: trimmed,
        createdAt: now,
        isAutomatic: true,
      );
    }
    _recordActivity(matchId, HomeActivityAction.changedStatus);
    notifyListeners();
    _refreshNotifications();
  }

  /// Moves a proposal to "בהמתנה" with the reason the matchmaker picked, and
  /// optionally when to look at it again.
  /// The reason is optional: a matchmaker may simply want the proposal to
  /// wait, and being forced to justify it is what makes people avoid the
  /// action altogether.
  Future<void> setWaiting(
    String matchId, {
    String? reason,
    DateTime? checkAgainOn,
    String? reminderNote,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }

    final DateTime now = DateTime.now();
    final MatchStatus previous = match.status;
    final String trimmedReason = (reason ?? '').trim();
    final String note = (reminderNote ?? '').trim();
    noteDatingSpan(match, from: previous, to: MatchStatus.unavailable, at: now);
    match
      ..status = MatchStatus.unavailable
      ..waitingReason = trimmedReason.isEmpty ? null : trimmedReason
      ..reminderDate = checkAgainOn
      ..reminderNote = checkAgainOn == null
          ? null
          : (note.isNotEmpty
                ? note
                : (trimmedReason.isEmpty ? null : trimmedReason))
      ..updatedAt = now;
    await match.save();
    await _logStatusChange(
      matchId: matchId,
      from: previous,
      to: MatchStatus.unavailable,
      at: now,
    );
    await _createNote(
      matchId: matchId,
      text: <String>[
        trimmedReason.isEmpty
            ? 'הרעיון עבר להמתנה'
            : 'הרעיון בהמתנה — $trimmedReason',
        if (checkAgainOn != null) 'לבדוק שוב ב־${_journalDate(checkAgainOn)}',
      ].join(' · '),
      createdAt: now,
      isAutomatic: true,
    );
    notifyListeners();
    _refreshNotifications();
  }

  /// Records that one side has been approached about this proposal.
  ///
  /// **This is what "יאללה לקדם" leaves behind.** Opening a chat is the act;
  /// this is the app remembering that the act happened, so the button can name
  /// the *next* step rather than the same one for ever. It writes the date on
  /// the proposal, files a line in the journal, and — from "רעיון" only —
  /// moves the status to "בבדיקה", exactly as sending a card already does.
  ///
  /// Idempotent by date: asking the same side twice keeps the first date,
  /// because the useful fact is when they were first told, and overwriting it
  /// would quietly reset the "nothing has moved in a week" clock every time
  /// somebody reopened a chat.
  Future<void> markSideAsked(
    String matchId,
    Gender side, {
    String? note,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null || side == Gender.unknown) {
      return;
    }
    final bool male = side == Gender.male;
    if ((male ? match.askedMaleAt : match.askedFemaleAt) != null) {
      // Already recorded. The chat still opened, and the journal still wants
      // the line if the caller had one, but the stage does not move.
      if (note != null && note.trim().isNotEmpty) {
        await _createNote(
          matchId: matchId,
          text: note.trim(),
          createdAt: DateTime.now(),
          isAutomatic: true,
        );
        notifyListeners();
      }
      return;
    }

    final DateTime now = DateTime.now();
    final MatchStatus previous = match.status;
    if (male) {
      match.askedMaleAt = now;
    } else {
      match.askedFemaleAt = now;
    }
    match.updatedAt = now;
    if (previous == MatchStatus.idea) {
      match.status = MatchStatus.checking;
    }
    await match.save();
    if (match.status != previous) {
      await _logStatusChange(
        matchId: matchId,
        from: previous,
        to: match.status,
        at: now,
      );
    }
    await _createNote(
      matchId: matchId,
      text: (note ?? '').trim().isNotEmpty
          ? note!.trim()
          : (male ? 'פניתי אל הבחור' : 'פניתי אל הבחורה'),
      createdAt: now,
      isAutomatic: true,
    );
    _recordActivity(matchId, HomeActivityAction.changedStatus);
    notifyListeners();
    _refreshNotifications();
  }

  /// Sets the proposal's stage by hand, from the little menu beside the button.
  ///
  /// **Backwards as well as forwards.** Most matchmaking happens on a phone
  /// call the app never sees, so a stage that could only be advanced through
  /// the one button would be wrong on half the list and unfixable. Setting
  /// "רעיון חדש" genuinely clears both dates — it is the answer to "I marked
  /// the wrong proposal", and a clear that leaves one date behind is not a
  /// clear.
  ///
  /// "מתחילים לצאת" is not handled here: it is a status change with a
  /// candidate's availability, a memory of what to put back and a community
  /// figure hanging off it, and it goes through [updateStatus] like every
  /// other one. The caller routes it there.
  Future<void> setStage(
    String matchId, {
    required DateTime? askedMaleAt,
    required DateTime? askedFemaleAt,
    required String label,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }
    if (match.askedMaleAt == askedMaleAt &&
        match.askedFemaleAt == askedFemaleAt) {
      return;
    }

    final DateTime now = DateTime.now();
    final MatchStatus previous = match.status;
    match
      ..askedMaleAt = askedMaleAt
      ..askedFemaleAt = askedFemaleAt
      ..updatedAt = now;
    // Back to a brand-new idea, so the status goes back with it: a proposal
    // nobody has been asked about is not "בבדיקה".
    if (askedMaleAt == null &&
        askedFemaleAt == null &&
        previous == MatchStatus.checking) {
      match.status = MatchStatus.idea;
    } else if (previous == MatchStatus.idea &&
        (askedMaleAt != null || askedFemaleAt != null)) {
      match.status = MatchStatus.checking;
    }
    await match.save();
    if (match.status != previous) {
      await _logStatusChange(
        matchId: matchId,
        from: previous,
        to: match.status,
        at: now,
      );
    }
    await _createNote(
      matchId: matchId,
      text: 'שלב הרעיון עודכן — $label',
      createdAt: now,
      isAutomatic: true,
    );
    _recordActivity(matchId, HomeActivityAction.changedStatus);
    notifyListeners();
    _refreshNotifications();
  }

  /// The matchmaker checked in on a couple who are out.
  ///
  /// Files the line and books the next check at this proposal's own cadence —
  /// a week for the first one, then [DatingCheckIn.defaultEveryDays] or
  /// whatever the matchmaker set instead. This is what makes the reminder a
  /// rhythm rather than a single alarm that goes off once and never again.
  Future<void> recordDatingCheckIn(
    String matchId, {
    required DateTime startedAt,
    String? note,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }
    final DateTime now = DateTime.now();
    final DateTime next = DatingCheckIn.nextCheckAt(
      match,
      startedAt: startedAt,
      now: now,
    );
    final String line = (note ?? '').trim();
    await _createNote(
      matchId: matchId,
      text: line.isEmpty ? 'בדקתי איך הולך לזוג' : line,
      createdAt: now,
      isAutomatic: true,
    );
    await setReminder(
      matchId,
      next,
      note: 'לבדוק איך הולך לזוג',
      journal: false,
    );
    _recordActivity(matchId, HomeActivityAction.changedStatus);
  }

  /// How often to be reminded about a couple who are out. See `DatingCheckIn`.
  Future<void> setCheckInFrequency(String matchId, int days) async {
    final MatchIdea? match = getById(matchId);
    if (match == null || match.checkInEveryDays == days) {
      return;
    }
    final DateTime now = DateTime.now();
    match
      ..checkInEveryDays = days
      ..updatedAt = now;
    await match.save();
    notifyListeners();
  }

  /// Legacy progress storage retained for older data/imports. The detail screen
  /// no longer exposes this duplicate state and technical changes are not
  /// written into the proposal journal.
  Future<void> setProgress(
    String matchId,
    MatchProgress progress, {
    String? other,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }

    final DateTime now = DateTime.now();
    match
      ..progress = progress
      ..progressOther = progress == MatchProgress.other ? other?.trim() : null
      ..updatedAt = now;
    await match.save();

    notifyListeners();
    _refreshNotifications();

    // Both sides agreed — move straight to dating.
    if (progress == MatchProgress.bothInterested &&
        match.status != MatchStatus.dating) {
      await updateStatus(matchId, MatchStatus.dating);
    }
  }

  /// Closes a proposal as rejected or "יצאו" with who ended it and an optional
  /// note. Writes the proposal journal and both candidates' personal history in
  /// phrasing suited to who ended it and whether they had already gone out.
  Future<void> recordOutcome(
    String matchId, {
    required MatchStatus newStatus,
    required MatchOutcomeParty party,
    String? note,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }

    final Person? Function(String)? resolve = resolvePerson;
    final Person? personA = resolve?.call(match.personAId);
    final Person? personB = resolve?.call(match.personBId);
    final Person? male = personA?.gender == Gender.male ? personA : personB;
    final Person? female = personA?.gender == Gender.female ? personA : personB;
    final String maleName = _shortName(male, 'הבחור');
    final String femaleName = _shortName(female, 'הבחורה');
    final String trimmedNote = (note ?? '').trim();
    final bool dated = newStatus == MatchStatus.dated;

    // Move the status first. Its own generic line is suppressed: the summary
    // written just below names who ended it and why, and dates the same act.
    await updateStatus(matchId, newStatus, journal: false);

    // A human-readable summary line for the proposal journal.
    // "שני הצדדים" on a proposal that never got off the ground is not two
    // people who each said no — it is the one answer the dialog offers for
    // "מהבירור עלה שזה פחות מתאים", and six months from now that is the fact
    // worth reading back. So it is written as the sentence rather than as a
    // name slotted into the generic rejection line.
    final bool fromInquiry = !dated && party == MatchOutcomeParty.mutual;
    // **One event, one line.** "הזוג נפרדו" and, under it, why — were two
    // entries for one moment. The reason now finishes the sentence it belongs
    // to.
    final String journalText = dated
        ? switch (party) {
            MatchOutcomeParty.him => '$maleName החליט להיפרד',
            MatchOutcomeParty.her => '$femaleName החליטה להיפרד',
            MatchOutcomeParty.mutual => 'הזוג החליטו להיפרד',
            MatchOutcomeParty.unknown => 'הזוג נפרדו',
          }
        : fromInquiry
        ? _inquiryOutcomeLine
        : switch (party) {
            MatchOutcomeParty.him => 'הרעיון נסגר — $maleName לא רצה להמשיך',
            MatchOutcomeParty.her => 'הרעיון נסגר — $femaleName לא רצתה להמשיך',
            _ => 'הרעיון נסגר',
          };
    await addNote(
      matchId,
      trimmedNote.isEmpty ? journalText : '$journalText — $trimmedNote',
      isAutomatic: true,
    );

    // Each candidate's own history, phrased from their perspective.
    final PersonEventType eventType = dated
        ? PersonEventType.dated
        : PersonEventType.rejected;
    await _logOutcomeHistory(
      person: male,
      otherPerson: female,
      otherName: _fullName(female, 'הבחורה'),
      selfIsMale: true,
      eventType: eventType,
      party: party,
      dated: dated,
      note: trimmedNote,
      matchId: match.id,
    );
    await _logOutcomeHistory(
      person: female,
      otherPerson: male,
      otherName: _fullName(male, 'הבחור'),
      selfIsMale: false,
      eventType: eventType,
      party: party,
      dated: dated,
      note: trimmedNote,
      matchId: match.id,
    );
  }

  /// Writes one candidate's side of a closing as **two** history entries: the
  /// closing itself ("נסגר רעיון עם שושנה") and, on its own line, why
  /// ("שושנה דחתה כי הוא תורני מדי עבורה"). Keeping them apart means the
  /// history reads as a sequence of events rather than one long sentence, and
  /// the closing line stays uniform whatever the reason was.
  Future<void> _logOutcomeHistory({
    required Person? person,
    required Person? otherPerson,
    required String otherName,
    required bool selfIsMale,
    required PersonEventType eventType,
    required MatchOutcomeParty party,
    required bool dated,
    required String note,
    required String matchId,
  }) async {
    if (person == null) {
      return;
    }

    // The history feed sorts on createdAt, and both lines are written inside
    // the same millisecond often enough that letting them default would let
    // the reason drift away from the closing it explains. Stamping them a
    // millisecond apart keeps the pair together and in order.
    final DateTime closedAt = DateTime.now();

    await logPersonEvent?.call(
      person.id,
      eventType,
      'נסגר רעיון עם $otherName',
      relatedPersonId: otherPerson?.id,
      relatedMatchId: matchId,
      createdAt: closedAt,
    );

    final String? reason = _outcomeReasonLine(
      selfIsMale: selfIsMale,
      otherName: otherName,
      party: party,
      dated: dated,
      note: note,
    );
    if (reason == null) {
      return;
    }

    await logPersonEvent?.call(
      person.id,
      eventType,
      reason,
      relatedPersonId: otherPerson?.id,
      relatedMatchId: matchId,
      createdAt: closedAt.add(const Duration(milliseconds: 1)),
    );
  }

  /// The "why" line that follows a closing, or null when the closing line
  /// already says everything there is to say.
  ///
  /// With a reason it reads as the closing line's follow-up, so the object is
  /// left out — "שושנה דחתה כי הוא תורני מדי עבורה". Without one it has to
  /// stand on its own, so it keeps "את הרעיון". The other side is the opposite
  /// gender by definition, which is what picks the verb form.
  String? _outcomeReasonLine({
    required bool selfIsMale,
    required String otherName,
    required MatchOutcomeParty party,
    required bool dated,
    required String note,
  }) {
    final bool selfEnded =
        (selfIsMale && party == MatchOutcomeParty.him) ||
        (!selfIsMale && party == MatchOutcomeParty.her);
    final bool otherEnded =
        (selfIsMale && party == MatchOutcomeParty.her) ||
        (!selfIsMale && party == MatchOutcomeParty.him);
    final String because = note.isEmpty ? '' : ' כי $note';

    if (dated) {
      if (selfEnded) {
        return selfIsMale ? 'יצא ולא המשיך$because' : 'יצאה ולא המשיכה$because';
      }
      if (otherEnded) {
        return selfIsMale
            ? '$otherName יצאה ולא המשיכה$because'
            : '$otherName יצא ולא המשיך$because';
      }
      return 'יצאו ולא המשיכו$because';
    }

    if (party == MatchOutcomeParty.mutual) {
      return '$_inquiryOutcomeLine$because';
    }
    if (selfEnded) {
      final String verb = selfIsMale ? 'דחה' : 'דחתה';
      return note.isEmpty ? '$verb את הרעיון' : '$verb$because';
    }
    if (otherEnded) {
      final String verb = selfIsMale ? 'דחתה' : 'דחה';
      return note.isEmpty
          ? '$otherName $verb את הרעיון'
          : '$otherName $verb$because';
    }

    // Nobody recorded who ended it: the closing line covers that, so only a
    // written reason is worth a second entry.
    return note.isEmpty ? null : 'הסיבה: $note';
  }

  String _shortName(Person? person, String fallback) {
    final String name = (person?.firstName ?? '').trim();
    return name.isEmpty ? fallback : name;
  }

  /// The name a candidate's own history uses for the other side.
  String _fullName(Person? person, String fallback) {
    final String name = (person?.fullName ?? '').trim();
    return name.isEmpty ? fallback : name;
  }

  /// Attaches a contact (from the device address book) to a proposal.
  Future<void> addRelatedContact(String matchId, MatchContact contact) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }
    final DateTime now = DateTime.now();
    match
      ..relatedContacts = <MatchContact>[...match.relatedContacts, contact]
      ..updatedAt = now;
    await match.save();
    await _createNote(
      matchId: matchId,
      text:
          'נוסף איש קשר לרעיון: ${contact.name}'
          '${(contact.description ?? '').trim().isEmpty ? '' : ' '
                    '(${contact.description!.trim()})'}',
      createdAt: now,
      isAutomatic: true,
    );
    notifyListeners();
  }

  Future<void> removeRelatedContact(String matchId, int index) async {
    final MatchIdea? match = getById(matchId);
    if (match == null || index < 0 || index >= match.relatedContacts.length) {
      return;
    }
    final MatchContact removed = match.relatedContacts[index];
    final List<MatchContact> updated = <MatchContact>[...match.relatedContacts]
      ..removeAt(index);
    final DateTime now = DateTime.now();
    match
      ..relatedContacts = updated
      ..updatedAt = now;
    await match.save();
    await _createNote(
      matchId: matchId,
      text: 'הוסר איש קשר מהרעיון: ${removed.name}',
      createdAt: now,
      isAutomatic: true,
    );
    notifyListeners();
  }

  /// Keeps a person's proposals in step with their availability: an open
  /// proposal ("רעיון"/"בבדיקה") moves to [MatchStatus.unavailable] ("בהמתנה")
  /// once either side is busy or on a break, and a waiting proposal moves back
  /// to [MatchStatus.idea] once both sides are free again. Proposals that have
  /// progressed further (dating, archived, etc.) are left untouched.
  ///
  /// [resolvePerson] is injected by `main.dart` so this repository can read the
  /// other side's status without depending on [PersonRepository].
  Person? Function(String personId)? resolvePerson;

  Future<void> syncMatchesForPerson(String personId) async {
    // **"מזל טוב" closes everything.** A friend who is getting married is not a
    // candidate any more, and their open ideas are not ideas — they were
    // already invisible on רעיונות (see `matchProposalTabFor`, which drops a
    // proposal with an archived side), which meant a matchmaker could neither
    // see them nor close them. So marking somebody "מזל טוב" now files every
    // idea they are in: a couple who were out are recorded as having gone out,
    // everything else is simply closed. The wedding's own proposal is already
    // archived by the time this runs, so it is left exactly as it is.
    if (resolvePerson?.call(personId)?.profileStatus.isArchived ?? false) {
      for (final MatchIdea match in _matchBox.values.toList()) {
        final bool involves =
            match.personAId == personId || match.personBId == personId;
        if (!involves || match.status.isArchived) {
          continue;
        }
        // Through `updateStatus` rather than written here, so a couple who
        // were out are released and the journal reads the same as it does when
        // an idea is closed by hand.
        await updateStatus(
          match.id,
          match.status == MatchStatus.dating
              ? MatchStatus.dated
              : MatchStatus.rejected,
        );
      }
      return;
    }

    final DateTime now = DateTime.now();
    bool changed = false;

    for (final MatchIdea match in _matchBox.values) {
      final bool involvesPerson =
          match.personAId == personId || match.personBId == personId;
      if (!involvesPerson) {
        continue;
      }

      final MatchStatus? target = _availabilityStatusFor(match);
      if (target == null || target == match.status) {
        continue;
      }

      final MatchStatus previous = match.status;
      noteDatingSpan(match, from: previous, to: target, at: now);
      match.status = target;
      match.updatedAt = now;
      await match.save();
      // Recorded, but marked automatic: one decision about a person's
      // availability can move five proposals, and that is one action, not six.
      await _logStatusChange(
        matchId: match.id,
        from: previous,
        to: target,
        at: now,
        automatic: true,
      );
      changed = true;
    }

    if (changed) {
      notifyListeners();
      _refreshNotifications();
    }
  }

  /// The status this proposal should have based purely on both sides being
  /// available, or null when availability should not drive it.
  MatchStatus? _availabilityStatusFor(MatchIdea match) {
    final Person? Function(String personId)? resolve = resolvePerson;
    if (resolve == null) {
      return null;
    }

    final bool eitherPaused =
        (resolve(match.personAId)?.profileStatus.pausesMatches ?? false) ||
        (resolve(match.personBId)?.profileStatus.pausesMatches ?? false);

    switch (match.status) {
      case MatchStatus.idea:
      case MatchStatus.checking:
        return eitherPaused ? MatchStatus.unavailable : null;
      case MatchStatus.unavailable:
        // A pause the matchmaker set by hand (with a reason) is theirs to undo.
        if (match.waitingReason != null) {
          return null;
        }
        return eitherPaused ? null : MatchStatus.idea;
      case MatchStatus.rejected:
      case MatchStatus.dating:
      case MatchStatus.dated:
      case MatchStatus.married:
        return null;
    }
  }

  Future<void> updateHandler(
    String matchId,
    CurrentHandler handler, {
    String? handlerName,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }

    match.currentHandler = handler;
    match.handlerName = handlerName;
    match.updatedAt = DateTime.now();
    await match.save();
    notifyListeners();
  }

  /// Erases every proposal, note and status event on this device.
  ///
  /// The twin of `PersonRepository.clearAll`, and called only from the same
  /// place: the account changing. See the note there for why records leaving
  /// with the account is the point rather than a side effect.
  Future<void> clearAll() async {
    for (final String id in _matchBox.keys.cast<String>().toList()) {
      await ReminderAlerts.forget(id);
      await DatingCountExclusions.forget(id);
    }
    await _matchBox.clear();
    await _noteBox.clear();
    await _statusEventBox?.clear();
    notifyListeners();
    // Rescheduled from an empty database, which cancels everything that was
    // pending — a reminder about a proposal that no longer exists here would
    // otherwise arrive on the next matchmaker's phone.
    _refreshNotifications();
  }

  Future<void> deleteMatch(String matchId, {bool keepInTrash = true}) async {
    // A snapshot first, so "ביטול" and "רעיונות שנמחקו" can put the idea back
    // exactly as it was — journal and ledger included.
    final MatchIdea? doomed = getById(matchId);
    // An idea deleted without ever being closed was, as far as its two
    // candidates are concerned, never opened: its lines leave their histories
    // with it (and come back if it is restored). One that was closed first
    // keeps its history — that closing really happened.
    final List<Map<String, dynamic>> personEvents =
        doomed != null && !doomed.status.isArchived
        ? await takePersonEvents?.call(matchId) ??
              const <Map<String, dynamic>>[]
        : const <Map<String, dynamic>>[];
    if (keepInTrash && doomed != null) {
      DeletedMatchesStore.instance.add(
        DeletedMatch(
          matchId: matchId,
          deletedAt: DateTime.now(),
          match: <String, dynamic>{
            ...BackupService.matchToJson(doomed),
            'askedMaleAt': doomed.askedMaleAt?.toIso8601String(),
            'askedFemaleAt': doomed.askedFemaleAt?.toIso8601String(),
            'checkInEveryDays': doomed.checkInEveryDays,
            'datingStartedAt': doomed.datingStartedAt?.toIso8601String(),
            'datingEndedAt': doomed.datingEndedAt?.toIso8601String(),
          },
          notes: <Map<String, dynamic>>[
            for (final MatchNote note in getNotesForMatch(matchId))
              BackupService.matchNoteToJson(note),
          ],
          events: <Map<String, dynamic>>[
            for (final MatchStatusEvent event
                in _statusEventBox?.values.where(
                      (MatchStatusEvent e) => e.matchId == matchId,
                    ) ??
                    const <MatchStatusEvent>[])
              BackupService.matchStatusEventToJson(event),
          ],
          personEvents: personEvents,
        ),
      );
    }

    final List<dynamic> noteKeys = _noteBox.keys.where((dynamic key) {
      final MatchNote? note = _noteBox.get(key);
      return note?.matchId == matchId;
    }).toList();

    if (noteKeys.isNotEmpty) {
      await _noteBox.deleteAll(noteKeys);
    }

    // The ledger describes a proposal that no longer exists, so it goes with
    // it — and the activity figures stop counting work on a deleted record.
    final Box<MatchStatusEvent>? statusEvents = _statusEventBox;
    if (statusEvents != null) {
      final List<dynamic> eventKeys = statusEvents.keys.where((dynamic key) {
        return statusEvents.get(key)?.matchId == matchId;
      }).toList();
      if (eventKeys.isNotEmpty) {
        await statusEvents.deleteAll(eventKeys);
      }
    }

    await _matchBox.delete(matchId);
    HomeBoardStore.instance.forget(HomeItemKind.idea, matchId);
    RecentActivityStore.instance.forget(HomeItemKind.idea, matchId);
    await ReminderAlerts.forget(matchId);
    // The historic dating count is built from proposals that still exist, so a
    // deleted one drops out of it on its own — this only stops its exclusion
    // key outliving it.
    await DatingCountExclusions.forget(matchId);
    notifyListeners();
    _refreshNotifications();
  }

  /// Puts a deleted idea back from "רעיונות שנמחקו". False when it is no
  /// longer in the trash, or when one of its two people has since been
  /// deleted — an idea about somebody who is gone cannot be restored.
  Future<bool> restoreDeleted(
    String matchId, {
    bool Function(String personId)? personExists,
  }) async {
    final DeletedMatchesStore trash = DeletedMatchesStore.instance;
    final DeletedMatch? peek = trash.all
        .where((DeletedMatch e) => e.matchId == matchId)
        .firstOrNull;
    if (peek == null) {
      return false;
    }
    if (personExists != null &&
        (!personExists(peek.personAId) || !personExists(peek.personBId))) {
      return false;
    }
    final MatchIdea? match = BackupService.matchFromJson(peek.match);
    if (match == null) {
      return false;
    }
    match
      ..askedMaleAt = DateTime.tryParse(
        peek.match['askedMaleAt'] as String? ?? '',
      )
      ..askedFemaleAt = DateTime.tryParse(
        peek.match['askedFemaleAt'] as String? ?? '',
      )
      ..checkInEveryDays = peek.match['checkInEveryDays'] as int?
      ..datingStartedAt = DateTime.tryParse(
        peek.match['datingStartedAt'] as String? ?? '',
      )
      ..datingEndedAt = DateTime.tryParse(
        peek.match['datingEndedAt'] as String? ?? '',
      );
    trash.take(matchId);
    await _matchBox.put(match.id, match);
    for (final Map<String, dynamic> raw in peek.notes) {
      final MatchNote? note = BackupService.matchNoteFromJson(raw);
      if (note != null) {
        await _noteBox.put(note.id, note);
      }
    }
    final Box<MatchStatusEvent>? events = _statusEventBox;
    if (events != null) {
      for (final Map<String, dynamic> raw in peek.events) {
        final MatchStatusEvent? event = BackupService.matchStatusEventFromJson(
          raw,
        );
        if (event != null) {
          await events.put(event.id, event);
        }
      }
    }
    await restorePersonEvents?.call(peek.personEvents);
    notifyListeners();
    _refreshNotifications();
    return true;
  }

  List<MatchNote> getNotesForMatch(String matchId) {
    final List<MatchNote> notes = _noteBox.values
        .where((MatchNote note) => note.matchId == matchId)
        .toList();
    notes.sort(
      (MatchNote a, MatchNote b) => a.createdAt.compareTo(b.createdAt),
    );
    return notes;
  }

  List<MatchNote> getAllNotes() {
    final List<MatchNote> notes = _noteBox.values.toList();
    notes.sort(
      (MatchNote a, MatchNote b) => a.createdAt.compareTo(b.createdAt),
    );
    return notes;
  }

  Future<void> addNote(
    String matchId,
    String text, {
    bool isAutomatic = false,
  }) async {
    final DateTime now = DateTime.now();
    await _createNote(
      matchId: matchId,
      text: text,
      createdAt: now,
      isAutomatic: isAutomatic,
    );
    await _touchMatch(matchId, now);
    if (!isAutomatic) {
      _recordActivity(matchId, HomeActivityAction.addedNote);
    }
    notifyListeners();
  }

  Future<void> updateNote(String noteId, String text) async {
    final MatchNote? note = _noteBox.get(noteId);
    final String trimmed = text.trim();
    if (note == null || trimmed.isEmpty) {
      return;
    }

    note.text = trimmed;
    await note.save();
    notifyListeners();
  }

  Future<void> deleteNote(String noteId) async {
    await _noteBox.delete(noteId);
    notifyListeners();
  }

  /// Writes a deleted note back exactly as it was, so a delete can be undone
  /// straight from the snackbar instead of asking to confirm beforehand.
  Future<void> restoreNote(MatchNote note) async {
    await _noteBox.put(
      note.id,
      MatchNote(
        id: note.id,
        matchId: note.matchId,
        text: note.text,
        createdAt: note.createdAt,
        isAutomatic: note.isAutomatic,
        // Restored *as it was*. Dropping this turned an undone delete of a
        // congratulation into an ordinary journal line with nobody behind it.
        mazelTovFrom: note.mazelTovFrom,
      ),
    );
    notifyListeners();
  }

  Future<void> addImportedMatch(MatchIdea match) async {
    await _matchBox.put(match.id, match);
  }

  Future<void> addImportedNote(MatchNote note) async {
    await _noteBox.put(note.id, note);
  }

  bool containsStatusEventId(String id) {
    return _statusEventBox?.containsKey(id) ?? false;
  }

  Future<void> addImportedStatusEvent(MatchStatusEvent event) async {
    await _statusEventBox?.put(event.id, event);
  }

  Future<void> finishImport() async {
    notifyListeners();
  }

  /// Whether [person]'s name contains [query] — already trimmed and
  /// lower-cased. The one rule [search] and the ideas page's suggestions share.
  static bool personMatchesQuery(Person? person, String query) {
    if (person == null) {
      return false;
    }

    return person.firstName.toLowerCase().contains(query) ||
        person.lastName.toLowerCase().contains(query) ||
        person.fullName.toLowerCase().contains(query);
  }

  /// Writes one line into a proposal's journal, **strictly after the line
  /// before it**.
  ///
  /// ⚠️ **The timestamp is nudged forward when it would tie.** The journal is
  /// ordered by `createdAt` alone (see [getNotesForMatch]), and `List.sort` is
  /// not promised to be stable — the input order is `Box.values`, which is by
  /// uuid, so it is effectively random. Two lines written in the same
  /// millisecond therefore came out in an arbitrary order, and a *different*
  /// arbitrary order after the next restart. That was always possible and is
  /// now routine: one action can write two lines, and moving a couple to
  /// "יוצאים" writes three.
  ///
  /// A millisecond of drift is invisible — the journal prints to the minute —
  /// and it makes "the order things happened in" a fact the file holds rather
  /// than one the reader has to hope for.
  Future<void> _createNote({
    required String matchId,
    required String text,
    required DateTime createdAt,
    required bool isAutomatic,
    String? mazelTovFrom,
  }) async {
    // **One act, one line.** A single tap can write several automatic lines
    // within the same moment — a status move, the reminder it books, the
    // availability it changes. Those are one event, so a line written within
    // [sameEventWindow] of the previous automatic line is folded into it
    // rather than stacked under it, and a line that says nothing new is
    // dropped.
    if (isAutomatic && mazelTovFrom == null) {
      MatchNote? last;
      for (final MatchNote existing in _noteBox.values) {
        if (existing.matchId == matchId &&
            (last == null || existing.createdAt.isAfter(last.createdAt))) {
          last = existing;
        }
      }
      final String line = text.trim();
      if (last != null &&
          last.isAutomatic &&
          last.mazelTovFrom == null &&
          createdAt.difference(last.createdAt).abs() < sameEventWindow) {
        if (!last.text.contains(line)) {
          last.text = '${last.text} — $line';
          await last.save();
        }
        return;
      }
    }

    DateTime at = createdAt;
    for (final MatchNote existing in _noteBox.values) {
      if (existing.matchId == matchId && !existing.createdAt.isBefore(at)) {
        at = existing.createdAt.add(const Duration(milliseconds: 1));
      }
    }
    final MatchNote note = MatchNote(
      id: _uuid.v4(),
      matchId: matchId,
      text: text,
      createdAt: at,
      isAutomatic: isAutomatic,
      mazelTovFrom: mazelTovFrom,
    );
    await _noteBox.put(note.id, note);
  }

  /// Files a "מזל טוב" from another matchmaker into this proposal's journal.
  ///
  /// **The journal is the inbox.** The alternative was a message list
  /// somewhere else in the app, with its own unread state and its own empty
  /// screen for the ninety-nine per cent of matchmakers who never receive one.
  /// A congratulation is about one couple, it arrives once, and the place
  /// somebody would go to read it is the same place they already read
  /// everything else about that couple.
  ///
  /// Returns false when the proposal is not on this device — a message for a
  /// proposal that has since been deleted is dropped rather than filed against
  /// nothing.
  ///
  /// Not counted as activity: being congratulated is not work, and a matchmaker
  /// whose score moved because other people were kind would be the wrong kind
  /// of scoreboard entirely.
  Future<bool> addMazelTov({
    required String matchId,
    required String text,
    required String fromName,
    DateTime? at,
  }) async {
    if (getById(matchId) == null) {
      return false;
    }
    await _createNote(
      matchId: matchId,
      text: text.trim(),
      createdAt: at ?? DateTime.now(),
      isAutomatic: true,
      // Never empty: a nameless sender is still a person, and the journal
      // says so rather than leaving the line looking self-written.
      mazelTovFrom: fromName.trim().isEmpty ? 'שדכן מהקהילה' : fromName.trim(),
    );
    notifyListeners();
    return true;
  }

  /// How close together two automatic lines must be to count as one event.
  ///
  /// Settable only so a test can write one line per call and read each on its
  /// own; the app never changes it.
  @visibleForTesting
  static Duration sameEventWindow = const Duration(seconds: 3);

  static const String defaultReminderNote = 'לבדוק מה קורה עם הרעיון';

  /// **Every idea that is not closed is looked at once a month.** A proposal
  /// with no date on it is one nobody comes back to; the default is a month
  /// from [from], and the matchmaker can move it from the card.
  static DateTime defaultReminderFrom(DateTime from) =>
      DateTime(from.year, from.month + 1, from.day, 10);

  Future<void> _touchMatch(String matchId, DateTime updatedAt) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }

    match.updatedAt = updatedAt;
    await match.save();
  }

  int _sortByUpdatedAtDesc(MatchIdea a, MatchIdea b) {
    return b.updatedAt.compareTo(a.updatedAt);
  }

  void _refreshNotifications() {
    final List<MatchIdea> allMatches = _matchBox.values.toList();
    NotificationService.scheduleMatchReminders(allMatches);
  }

  /// Feeds the home screen's "הפעולות האחרונות שלך" strip. Recorded here
  /// rather than at the call sites so every path that really changes a
  /// proposal shows up, with no extra bookkeeping asked of the matchmaker.
  void _recordActivity(String matchId, HomeActivityAction action) {
    RecentActivityStore.instance.record(
      kind: HomeItemKind.idea,
      targetId: matchId,
      action: action,
    );
  }
}
