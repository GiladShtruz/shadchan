import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/notification_service.dart';
import 'package:uuid/uuid.dart';

/// Which side (if any) ended a proposal, used to phrase the journal and both
/// candidates' history when a proposal is rejected or the couple stopped.
enum MatchOutcomeParty { him, her, mutual, unknown }

class MatchRepository extends ChangeNotifier {
  MatchRepository(this._matchBox, this._noteBox);

  final Box<MatchIdea> _matchBox;
  final Box<MatchNote> _noteBox;
  final Uuid _uuid = const Uuid();

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
    // free-notes chat.
    await _matchBox.put(match.id, match);
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
    match
      ..status = newStatus
      ..updatedAt = now;
    // A deliberate pause only lasts as long as the proposal is waiting.
    if (newStatus != MatchStatus.unavailable) {
      match.waitingReason = null;
    }
    await match.save();
    await _createNote(
      matchId: matchId,
      text: 'סטטוס שונה ל-${newStatus.displayName}',
      createdAt: now,
      isAutomatic: true,
    );

    // A couple that starts dating is no longer available to anyone else.
    if (newStatus == MatchStatus.dating) {
      await markPersonBusy?.call(match.personAId);
      await markPersonBusy?.call(match.personBId);
    }

    notifyListeners();
    _refreshNotifications();
  }

  /// Marks a person as "תפוס". Wired to [PersonRepository] in `main.dart`.
  Future<void> Function(String personId)? markPersonBusy;

  /// Writes a line into a person's personal history. Wired to
  /// [PersonRepository.addNote] in `main.dart` so proposal outcomes are recorded
  /// on both candidates without this repository depending on the person store.
  Future<void> Function(String personId, String text)? addPersonHistoryNote;

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

    match
      ..reminderDate = date
      ..reminderNote = date == null ? null : note
      ..updatedAt = DateTime.now();
    await match.save();
    notifyListeners();
    _refreshNotifications();
  }

  /// Moves a proposal to "בהמתנה" with the reason the matchmaker picked, and
  /// optionally when to look at it again.
  Future<void> setWaiting(
    String matchId, {
    required String reason,
    DateTime? checkAgainOn,
  }) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }

    final DateTime now = DateTime.now();
    match
      ..status = MatchStatus.unavailable
      ..waitingReason = reason
      ..reminderDate = checkAgainOn
      ..reminderNote = checkAgainOn == null ? null : reason
      ..updatedAt = now;
    await match.save();
    await _createNote(
      matchId: matchId,
      text: 'סטטוס שונה ל-${MatchStatus.unavailable.displayName} ($reason)',
      createdAt: now,
      isAutomatic: true,
    );
    notifyListeners();
    _refreshNotifications();
  }

  /// Records where the outreach stands ("איפה זה עומד?"). Saved immediately and
  /// journaled. Choosing [MatchProgress.bothInterested] promotes the proposal to
  /// [MatchStatus.dating] (which marks both sides busy) — no extra middle steps.
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

    final String label = progress == MatchProgress.other
        ? (other?.trim().isNotEmpty ?? false ? other!.trim() : progress.displayName)
        : progress.displayName;
    await _createNote(
      matchId: matchId,
      text: 'איפה זה עומד: $label',
      createdAt: now,
      isAutomatic: true,
    );

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
    final String journalText = dated
        ? 'יצאו ולא המשיכו (החליט: $who)'
        : 'ההצעה נדחתה (מי: $who)';
    await addNote(
      matchId,
      trimmedNote.isEmpty ? journalText : '$journalText — $trimmedNote',
      isAutomatic: true,
    );

    // Each candidate's own history, phrased from their perspective.
    final Future<void> Function(String, String)? history = addPersonHistoryNote;
    if (history != null) {
      if (male != null) {
        await history(
          male.id,
          _historyLine(
            selfIsMale: true,
            otherName: femaleName,
            party: party,
            dated: dated,
            note: trimmedNote,
          ),
        );
      }
      if (female != null) {
        await history(
          female.id,
          _historyLine(
            selfIsMale: false,
            otherName: maleName,
            party: party,
            dated: dated,
            note: trimmedNote,
          ),
        );
      }
    }
  }

  String _historyLine({
    required bool selfIsMale,
    required String otherName,
    required MatchOutcomeParty party,
    required bool dated,
    required String note,
  }) {
    final String base;
    if (dated) {
      base = selfIsMale
          ? 'יצא עם $otherName ולא המשיכו'
          : 'יצאה עם $otherName ולא המשיכו';
    } else {
      final bool selfEnded =
          (selfIsMale && party == MatchOutcomeParty.him) ||
          (!selfIsMale && party == MatchOutcomeParty.her);
      final bool otherEnded =
          (selfIsMale && party == MatchOutcomeParty.her) ||
          (!selfIsMale && party == MatchOutcomeParty.him);
      if (party == MatchOutcomeParty.mutual) {
        base = 'ההצעה עם $otherName לא התאימה (הדדי)';
      } else if (selfEnded) {
        base = selfIsMale
            ? 'דחה את ההצעה עם $otherName'
            : 'דחתה את ההצעה עם $otherName';
      } else if (otherEnded) {
        // The other side ended it; phrase by their gender (opposite of self).
        base = selfIsMale
            ? '$otherName דחתה את ההצעה'
            : '$otherName דחה את ההצעה';
      } else {
        base = 'ההצעה עם $otherName נדחתה';
      }
    }
    return note.isEmpty ? base : '$base — $note';
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

      match.status = target;
      match.updatedAt = now;
      await match.save();
      await _createNote(
        matchId: match.id,
        text: target == MatchStatus.unavailable
            ? 'סטטוס שונה ל-${MatchStatus.unavailable.displayName} (אחד הצדדים לא פנוי)'
            : 'סטטוס שונה ל-${MatchStatus.idea.displayName} (שני הצדדים פנויים)',
        createdAt: now,
        isAutomatic: true,
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

    await _matchBox.delete(matchId);
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
  }) async {
    final MatchNote note = MatchNote(
      id: _uuid.v4(),
      matchId: matchId,
      text: text,
      createdAt: createdAt,
      isAutomatic: isAutomatic,
    );
    await _noteBox.put(note.id, note);
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
}
