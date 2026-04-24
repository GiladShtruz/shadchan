import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/services/excel_export_service.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  test('buildWorkbookBytes creates Hebrew RTL Excel workbook', () {
    final DateTime now = DateTime(2026, 4, 24, 10, 30);
    final Person personA = Person(
      id: 'person-a',
      firstName: 'דוד',
      lastName: 'כהן',
      gender: Gender.male,
      birthDate: DateTime(2000, 1, 2),
      religiousLevel: ReligiousLevel.datiLeumi,
      city: 'ירושלים',
      phone: '0501234567',
      source: 'חבר',
      description: 'כרטיסייה לשליחה',
      createdAt: now,
      updatedAt: now,
    );
    final Person personB = Person(
      id: 'person-b',
      firstName: 'שרה',
      lastName: 'לוי',
      gender: Gender.female,
      manualAge: 24,
      createdAt: now,
      updatedAt: now,
    );
    final MatchIdea match = MatchIdea(
      id: 'match-1',
      personAId: personA.id,
      personBId: personB.id,
      status: MatchStatus.checking,
      currentHandler: CurrentHandler.me,
      createdAt: now,
      updatedAt: now,
    );

    final List<int> bytes = ExcelExportService.buildWorkbookBytes(
      people: <Person>[personA, personB],
      personNotes: <PersonNote>[
        PersonNote(
          id: 'person-note-1',
          personId: personA.id,
          text: 'הערה',
          createdAt: now,
          isAutomatic: false,
        ),
      ],
      matches: <MatchIdea>[match],
      matchNotes: <MatchNote>[
        MatchNote(
          id: 'match-note-1',
          matchId: match.id,
          text: 'הצעה נפתחה',
          createdAt: now,
          isAutomatic: true,
        ),
      ],
    );

    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final String workbookXml = utf8.decode(
      (archive.findFile('xl/workbook.xml')!.content as List<int>),
    );
    expect(workbookXml, contains('name="סיכום"'));
    expect(workbookXml, contains('name="אנשים"'));
    expect(workbookXml, contains('name="יומן אנשי קשר"'));
    expect(workbookXml, contains('name="הצעות"'));
    expect(workbookXml, contains('name="יומן הצעות"'));

    final Iterable<ArchiveFile> worksheetFiles = archive.files.where(
      (ArchiveFile file) =>
          file.isFile &&
          file.name.startsWith('xl/worksheets/sheet') &&
          file.name.endsWith('.xml'),
    );
    expect(worksheetFiles, hasLength(5));
    for (final ArchiveFile file in worksheetFiles) {
      final String worksheetXml = utf8.decode(file.content as List<int>);
      expect(worksheetXml, contains('rightToLeft="1"'));
    }
  });
}
