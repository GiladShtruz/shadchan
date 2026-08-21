import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// The proposal journal, which is now the proposal's whole record.
///
/// A proposal used to have a screen of its own, and the journal on it was a
/// place for the matchmaker's own free notes — a status change, a reminder, a
/// contact added, all happened without leaving a dated line anywhere a person
/// could read. The screen is gone and the journal took its job: **every action
/// on a proposal writes itself down**, so "where does this stand and what have
/// I already done?" is answered by reading, not by remembering.
///
/// These tests are the guard on that. A new action added without a journal line
/// shows up here as a missing entry rather than as a gap somebody notices six
/// months later, when the answer is no longer reconstructible.
void main() {
  late Directory directory;
  late Box<Person> people;
  late Box<MatchIdea> matches;
  late Box<MatchNote> notes;
  late Box<PersonEvent> personEvents;
  late Box<MatchStatusEvent> statusEvents;
  late PersonRepository personRepository;
  late MatchRepository matchRepository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('match_journal_');
    Hive.init(directory.path);
    Hive.registerAdapter(PersonAdapter());
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(RegionAdapter());
    }
    Hive.registerAdapter(MatchIdeaAdapter());
    Hive.registerAdapter(MatchNoteAdapter());
    Hive.registerAdapter(MatchContactAdapter());
    Hive.registerAdapter(MatchStatusEventAdapter());
    Hive.registerAdapter(PersonEventAdapter());
    Hive.registerAdapter(PersonEventTypeAdapter());
    Hive.registerAdapter(GenderAdapter());
    Hive.registerAdapter(ReligiousLevelAdapter());
    Hive.registerAdapter(MatchStatusAdapter());
    Hive.registerAdapter(MatchProgressAdapter());
    Hive.registerAdapter(CurrentHandlerAdapter());
    Hive.registerAdapter(ProfileStatusAdapter());
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    people = await Hive.openBox<Person>('people');
    matches = await Hive.openBox<MatchIdea>('matches');
    notes = await Hive.openBox<MatchNote>('match_notes');
    personEvents = await Hive.openBox<PersonEvent>('person_events');
    statusEvents = await Hive.openBox<MatchStatusEvent>('match_status_events');
    await people.clear();
    await matches.clear();
    await notes.clear();
    await personEvents.clear();
    await statusEvents.clear();
    await Hive.box<dynamic>('settings').clear();

    personRepository = PersonRepository(people, null, personEvents);
    matchRepository = MatchRepository(matches, notes, statusEvents)
      ..resolvePerson = personRepository.getById
      ..markPersonBusy = ((String personId, String matchId) =>
          personRepository.updateProfileStatus(
            personId,
            ProfileStatus.busy,
            causedByMatchId: matchId,
          ));
  });

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<MatchIdea> openProposal() async {
    final DateTime now = DateTime.now();
    Person person(String id, Gender gender) => Person(
      id: id,
      firstName: 'שם$id',
      lastName: 'לוי',
      gender: gender,
      manualAge: 26,
      createdAt: now,
      updatedAt: now,
    );
    await personRepository.add(person('male', Gender.male));
    await personRepository.add(person('female', Gender.female));
    final MatchIdea? match = await matchRepository.create('male', 'female');
    return match!;
  }

  List<String> journalOf(String matchId) => matchRepository
      .getNotesForMatch(matchId)
      .map((MatchNote note) => note.text)
      .toList();

  test('the journal opens with the proposal', () async {
    final MatchIdea match = await openProposal();
    // It used to start empty on purpose, back when it was only a place for
    // free notes. A record whose first line is missing reads as though the
    // proposal appeared from nowhere.
    expect(journalOf(match.id), <String>['הרעיון נפתח']);
  });

  test('every status move writes one line, and only one', () async {
    final MatchIdea match = await openProposal();

    await matchRepository.updateStatus(match.id, MatchStatus.dating);
    expect(journalOf(match.id), <String>['הרעיון נפתח', 'התחילו לצאת']);

    // A move that had no warmer sentence of its own used to write nothing at
    // all — the status changed and the journal did not notice.
    await matchRepository.updateStatus(match.id, MatchStatus.unavailable);
    expect(journalOf(match.id).last, 'ההצעה עברה להמתנה');

    // Re-setting the status a proposal already has is not a move and must not
    // read as one.
    final int before = journalOf(match.id).length;
    await matchRepository.updateStatus(match.id, MatchStatus.unavailable);
    expect(journalOf(match.id).length, before);
  });

  test(
    'a closing is written once, by the line that knows who ended it',
    () async {
      final MatchIdea match = await openProposal();
      await matchRepository.recordOutcome(
        match.id,
        newStatus: MatchStatus.rejected,
        party: MatchOutcomeParty.her,
        note: 'הוא רחוק מדי',
      );

      // "ההצעה נסגרה" directly above "ההצעה נדחתה (מי: שםfemale)" would say the
      // same thing twice and date it twice, so `updateStatus` suppresses its
      // generic line for this caller.
      final List<String> journal = journalOf(match.id);
      expect(journal, hasLength(2));
      expect(journal.last, contains('נדחתה'));
      expect(journal.last, contains('הוא רחוק מדי'));
      expect(journal, isNot(contains('ההצעה נסגרה')));
    },
  );

  test('reminders, contacts and their removal all file themselves', () async {
    final MatchIdea match = await openProposal();

    await matchRepository.setReminder(
      match.id,
      DateTime(2026, 9, 3),
      note: 'לבדוק עם אמא שלה',
    );
    expect(
      journalOf(match.id).last,
      'נקבעה תזכורת ל־03.09.2026 — לבדוק עם אמא שלה',
    );

    // Clearing is the same decision in reverse. Without a line, "handled it"
    // and "gave up on it" look identical afterwards.
    await matchRepository.setReminder(match.id, null);
    expect(journalOf(match.id).last, 'התזכורת בוטלה');

    await matchRepository.addRelatedContact(
      match.id,
      const MatchContact(
        name: 'רבקה כהן',
        phone: '0501234567',
        description: 'אמא של שרה',
      ),
    );
    expect(
      journalOf(match.id).last,
      'נוסף איש קשר להצעה: רבקה כהן (אמא של שרה)',
    );

    await matchRepository.removeRelatedContact(match.id, 0);
    expect(journalOf(match.id).last, 'הוסר איש קשר מההצעה: רבקה כהן');
  });

  test('a card going out moves the proposal to "בבדיקה" and says so', () async {
    final MatchIdea match = await openProposal();
    await matchRepository.recordCardShared(match.id, 'הכרטיס של שרה נשלח לדוד');

    final MatchIdea? saved = matchRepository.getById(match.id);
    // This is what turns the card's "יאללה לקדם!" row from a prompt into a
    // report.
    expect(saved?.lastShareLabel, 'הכרטיס של שרה נשלח לדוד');
    expect(saved?.lastShareAt, isNotNull);
    expect(saved?.status, MatchStatus.checking);
    expect(journalOf(match.id).last, 'הכרטיס של שרה נשלח לדוד');
  });

  test('a proposal that is not simply open is not put back into play', () async {
    final MatchIdea match = await openProposal();
    await matchRepository.updateStatus(match.id, MatchStatus.dating);
    await matchRepository.recordCardShared(match.id, 'נפתחה שיחה עם דוד');

    // Forwarding a card out of a proposal is not a reason to un-date a couple,
    // reopen a closed proposal, or take a waiting one off its pause.
    expect(matchRepository.getById(match.id)?.status, MatchStatus.dating);
    expect(journalOf(match.id).last, 'נפתחה שיחה עם דוד');
  });

  test('an undone delete keeps a congratulation as a congratulation', () async {
    final MatchIdea match = await openProposal();
    await matchRepository.addMazelTov(
      matchId: match.id,
      text: 'מזל טוב!!',
      fromName: 'שדכנית מהצפון',
    );
    final MatchNote note = matchRepository
        .getNotesForMatch(match.id)
        .firstWhere((MatchNote n) => n.mazelTovFrom != null);

    await matchRepository.deleteNote(note.id);
    await matchRepository.restoreNote(note);

    // Restored *as it was*: dropping the sender turned an undone delete into an
    // ordinary journal line with nobody behind it.
    final MatchNote restored = matchRepository
        .getNotesForMatch(match.id)
        .firstWhere((MatchNote n) => n.id == note.id);
    expect(restored.mazelTovFrom, 'שדכנית מהצפון');
  });
}
