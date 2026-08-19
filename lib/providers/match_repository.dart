import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/dating_history.dart';
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

      return _matchesPersonQuery(personA, normalizedQuery) ||
          _matchesPersonQuery(personB, normalizedQuery);
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

    // No automatic "opened" journal note — the journal stays a personal
    // free-notes chat. The opening is still recorded on each candidate's
    // history timeline.
    await _matchBox.put(match.id, match);

    final Person? Function(String)? resolve = resolvePerson;
    // The fallback only stands in for a record that vanished between the
    // proposal being made and this line being written, so it is deliberately
    // the one word that fits either side.
    final String nameA = _shortName(resolve?.call(personAId), 'הצד השני');
    final String nameB = _shortName(resolve?.call(personBId), 'הצד השני');
    await logPersonEvent?.call(
      personAId,
      PersonEventType.proposalOpened,
      'נפתחה הצעה עם $nameB',
      relatedPersonId: personBId,
      relatedMatchId: match.id,
    );
    await logPersonEvent?.call(
      personBId,
      PersonEventType.proposalOpened,
      'נפתחה הצעה עם $nameA',
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

  Future<void> updateStatus(String matchId, MatchStatus newStatus) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }

    final DateTime now = DateTime.now();
    final MatchStatus previous = match.status;
    match
      ..status = newStatus
      ..updatedAt = now;
    // A deliberate pause only lasts as long as the proposal is waiting.
    if (newStatus != MatchStatus.unavailable) {
      match.waitingReason = null;
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

    _recordActivity(matchId, HomeActivityAction.changedStatus);
    notifyListeners();
    _refreshNotifications();
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

  /// Sets (or clears, with a null [date]) the reminder on a proposal. Clearing
  /// is also how a due reminder is marked as handled, which takes the proposal
  /// off the "ביקשת שנזכיר לך" list.
  Future<void> setReminder(
    String matchId,
    DateTime? date, {
    String? note,
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
    match
      ..reminderDate = date
      ..reminderNote = date == null || trimmedNote.isEmpty ? null : trimmedNote
      ..updatedAt = DateTime.now();
    await match.save();
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
      text: trimmedReason.isEmpty
          ? 'ההצעה עברה להמתנה'
          : 'ההצעה בהמתנה — $trimmedReason',
      createdAt: now,
      isAutomatic: true,
    );
    notifyListeners();
    _refreshNotifications();
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

    // Move the status first (writes its own "סטטוס שונה" journal line).
    await updateStatus(matchId, newStatus);

    // A human-readable summary line for the proposal journal.
    final String who = switch (party) {
      MatchOutcomeParty.him => maleName,
      MatchOutcomeParty.her => femaleName,
      MatchOutcomeParty.mutual => 'שני הצדדים',
      MatchOutcomeParty.unknown => 'לא ידוע',
    };
    // "שני הצדדים" on a proposal that never got off the ground is not two
    // people who each said no — it is the one answer the dialog offers for
    // "מהבירור עלה שזה פחות מתאים", and six months from now that is the fact
    // worth reading back. So it is written as the sentence rather than as a
    // name slotted into the generic rejection line.
    final bool fromInquiry = !dated && party == MatchOutcomeParty.mutual;
    final String journalText = dated
        ? 'יצאו ולא המשיכו (החליט: $who)'
        : fromInquiry
        ? _inquiryOutcomeLine
        : 'ההצעה נדחתה (מי: $who)';
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
      otherName: femaleName,
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
      otherName: maleName,
      selfIsMale: false,
      eventType: eventType,
      party: party,
      dated: dated,
      note: trimmedNote,
      matchId: match.id,
    );
  }

  /// Writes one candidate's side of a closing as **two** history entries: the
  /// closing itself ("נסגרה הצעה עם שושנה") and, on its own line, why
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
      'נסגרה הצעה עם $otherName',
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
  /// stand on its own, so it keeps "את ההצעה". The other side is the opposite
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
      return note.isEmpty ? '$verb את ההצעה' : '$verb$because';
    }
    if (otherEnded) {
      final String verb = selfIsMale ? 'דחתה' : 'דחה';
      return note.isEmpty
          ? '$otherName $verb את ההצעה'
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

  /// Attaches a contact (from the device address book) to a proposal.
  Future<void> addRelatedContact(String matchId, MatchContact contact) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }
    match
      ..relatedContacts = <MatchContact>[...match.relatedContacts, contact]
      ..updatedAt = DateTime.now();
    await match.save();
    notifyListeners();
  }

  Future<void> removeRelatedContact(String matchId, int index) async {
    final MatchIdea? match = getById(matchId);
    if (match == null || index < 0 || index >= match.relatedContacts.length) {
      return;
    }
    final List<MatchContact> updated = <MatchContact>[...match.relatedContacts]
      ..removeAt(index);
    match
      ..relatedContacts = updated
      ..updatedAt = DateTime.now();
    await match.save();
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

  Future<void> deleteMatch(String matchId) async {
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

  Future<void> finishImport() async {
    notifyListeners();
  }

  bool _matchesPersonQuery(Person? person, String query) {
    if (person == null) {
      return false;
    }

    return person.firstName.toLowerCase().contains(query) ||
        person.lastName.toLowerCase().contains(query) ||
        person.fullName.toLowerCase().contains(query);
  }

  Future<void> _createNote({
    required String matchId,
    required String text,
    required DateTime createdAt,
    required bool isAutomatic,
    String? mazelTovFrom,
  }) async {
    final MatchNote note = MatchNote(
      id: _uuid.v4(),
      matchId: matchId,
      text: text,
      createdAt: createdAt,
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
