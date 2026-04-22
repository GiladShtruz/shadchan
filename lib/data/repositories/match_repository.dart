import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/core/constants/enums.dart';
import 'package:shadchan/data/models/match_idea.dart';
import 'package:shadchan/data/models/match_note.dart';
import 'package:shadchan/data/models/person.dart';
import 'package:shadchan/data/repositories/person_repository.dart';
import 'package:uuid/uuid.dart';

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

    await _matchBox.put(match.id, match);
    await _createNote(
      matchId: match.id,
      text: 'הצעה נפתחה',
      createdAt: now,
      isAutomatic: true,
    );
    notifyListeners();
    return match;
  }

  Future<void> updateStatus(String matchId, MatchStatus newStatus) async {
    final MatchIdea? match = getById(matchId);
    if (match == null) {
      return;
    }

    final DateTime now = DateTime.now();
    match.status = newStatus;
    match.updatedAt = now;
    await match.save();
    await _createNote(
      matchId: matchId,
      text: 'סטטוס שונה ל-${newStatus.displayName}',
      createdAt: now,
      isAutomatic: true,
    );
    notifyListeners();
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
}
