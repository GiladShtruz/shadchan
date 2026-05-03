import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/hebrew_date_utils.dart';

class ExcelExportService {
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('dd.MM.yyyy HH:mm');

  static Future<File> exportData(
    PersonRepository personRepo,
    MatchRepository matchRepo,
  ) async {
    final List<int> bytes = buildWorkbookBytes(
      people: personRepo.getAll(),
      personNotes: personRepo.getAllNotes(),
      matches: matchRepo.getAll(),
      matchNotes: matchRepo.getAllNotes(),
    );

    final Directory tempDirectory = await getTemporaryDirectory();
    final String formattedDate = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.now());
    final File excelFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}shadchan_excel_$formattedDate.xlsx',
    );

    await excelFile.writeAsBytes(bytes);
    return excelFile;
  }

  static Future<void> shareExport(File excelFile) async {
    await Share.shareXFiles(<XFile>[
      XFile(excelFile.path),
    ], subject: 'ייצוא אקסל שדכן');
  }

  @visibleForTesting
  static List<int> buildWorkbookBytes({
    required List<Person> people,
    required List<PersonNote> personNotes,
    required List<MatchIdea> matches,
    required List<MatchNote> matchNotes,
  }) {
    final Excel excel = Excel.createExcel();
    final Map<String, String> sheetRenames = <String, String>{};
    final Map<String, Person> peopleById = <String, Person>{
      for (final Person person in people) person.id: person,
    };
    int sheetIndex = 1;

    Sheet nextSheet(String displayName) {
      final String originalName = sheetIndex == 1
          ? 'Sheet1'
          : 'Sheet$sheetIndex';
      sheetIndex++;
      final Sheet sheet = excel[originalName];
      sheetRenames[originalName] = _sanitizeSheetName(displayName);
      return sheet;
    }

    _writeTableSheet(
      sheet: nextSheet('סיכום'),
      title: 'סיכום ייצוא',
      headers: const <String>['נתון', 'ערך'],
      rows: <List<String>>[
        <String>['תאריך ייצוא', _dateTimeFormat.format(DateTime.now())],
        <String>['אנשים', people.length.toString()],
        <String>['הערות אנשי קשר', personNotes.length.toString()],
        <String>['הצעות', matches.length.toString()],
        <String>['הערות הצעות', matchNotes.length.toString()],
      ],
      columnWidths: const <double>[24, 24],
    );

    _writeTableSheet(
      sheet: nextSheet('אנשים'),
      title: 'אנשים',
      headers: const <String>[
        'מזהה',
        'שם פרטי',
        'שם משפחה',
        'שם מלא',
        'מגדר',
        'גיל',
        'תאריך לידה לועזי',
        'תאריך לידה עברי',
        'גיל ידני',
        'סגנון דתי',
        'עיר',
        'טלפון',
        'איש קשר לבירורים',
        'טלפון לבירורים',
        'מקור היכרות',
        'סטטוס',
        'מועדף',
        'כרטיסייה לשליחה',
        'הערות ישנות',
        'תמונות',
        'נוצר',
        'עודכן',
      ],
      rows: people.map(_personRow).toList(),
      columnWidths: const <double>[
        34,
        16,
        16,
        22,
        12,
        10,
        18,
        22,
        12,
        18,
        16,
        18,
        22,
        18,
        20,
        16,
        12,
        42,
        34,
        42,
        18,
        18,
      ],
    );

    _writeTableSheet(
      sheet: nextSheet('יומן אנשי קשר'),
      title: 'יומן הערות אנשי קשר',
      headers: const <String>[
        'מזהה הערה',
        'מזהה איש קשר',
        'איש קשר',
        'סוג הערה',
        'הערה',
        'נוצר',
      ],
      rows: personNotes.map((PersonNote note) {
        final Person? person = peopleById[note.personId];
        return <String>[
          note.id,
          note.personId,
          person?.fullName ?? '',
          note.isAutomatic ? 'אוטומטית' : 'ידנית',
          note.text,
          _formatDateTime(note.createdAt),
        ];
      }).toList(),
      columnWidths: const <double>[34, 34, 22, 14, 48, 18],
    );

    _writeTableSheet(
      sheet: nextSheet('הצעות'),
      title: 'הצעות',
      headers: const <String>[
        'מזהה',
        'מזהה צד א',
        'צד א',
        'מזהה צד ב',
        'צד ב',
        'סטטוס',
        'בארכיון',
        'בטיפול',
        'שם מטפל',
        'נוצר',
        'עודכן',
      ],
      rows: matches.map((MatchIdea match) {
        final Person? personA = peopleById[match.personAId];
        final Person? personB = peopleById[match.personBId];
        return <String>[
          match.id,
          match.personAId,
          personA?.fullName ?? '',
          match.personBId,
          personB?.fullName ?? '',
          match.status.displayName,
          _yesNo(match.status.isArchived),
          match.currentHandler.displayName,
          match.handlerName ?? '',
          _formatDateTime(match.createdAt),
          _formatDateTime(match.updatedAt),
        ];
      }).toList(),
      columnWidths: const <double>[34, 34, 22, 34, 22, 16, 12, 18, 20, 18, 18],
    );

    _writeTableSheet(
      sheet: nextSheet('יומן הצעות'),
      title: 'יומן הערות הצעות',
      headers: const <String>[
        'מזהה הערה',
        'מזהה הצעה',
        'צד א',
        'צד ב',
        'סוג הערה',
        'הערה',
        'נוצר',
      ],
      rows: matchNotes.map((MatchNote note) {
        final MatchIdea? match = _findMatch(matches, note.matchId);
        return <String>[
          note.id,
          note.matchId,
          _personName(peopleById, match?.personAId),
          _personName(peopleById, match?.personBId),
          note.isAutomatic ? 'אוטומטית' : 'ידנית',
          note.text,
          _formatDateTime(note.createdAt),
        ];
      }).toList(),
      columnWidths: const <double>[34, 34, 22, 22, 14, 48, 18],
    );

    final List<int>? fileBytes = excel.save();
    if (fileBytes == null) {
      throw Exception('Failed to generate Excel bytes');
    }

    return _fixWorkbookBytes(
      originalBytes: fileBytes,
      sheetRenames: sheetRenames,
    );
  }

  static void _writeTableSheet({
    required Sheet sheet,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> columnWidths,
  }) {
    final int colCount = headers.length;
    final CellStyle titleStyle = _titleStyle();
    final CellStyle headerStyle = _headerStyle();
    final CellStyle evenRowStyle = _dataStyle(
      backgroundHex: _ExcelColorHex.evenRowBackground,
    );
    final CellStyle oddRowStyle = _dataStyle(
      backgroundHex: _ExcelColorHex.textOnFilledSurface,
    );

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: colCount - 1, rowIndex: 0),
    );
    final Data titleCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    );
    titleCell.value = TextCellValue(title);
    titleCell.cellStyle = titleStyle;
    sheet.setRowHeight(0, 40);

    for (int c = 0; c < colCount; c++) {
      final Data cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }
    sheet.setRowHeight(1, 28);

    for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final List<String> row = rows[rowIndex];
      final CellStyle style = rowIndex.isEven ? evenRowStyle : oddRowStyle;
      final int excelRowIndex = rowIndex + 2;

      for (int columnIndex = 0; columnIndex < colCount; columnIndex++) {
        final Data cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: columnIndex,
            rowIndex: excelRowIndex,
          ),
        );
        cell.value = TextCellValue(
          columnIndex < row.length ? row[columnIndex] : '',
        );
        cell.cellStyle = style;
      }
    }

    for (int c = 0; c < colCount; c++) {
      sheet.setColumnWidth(c, c < columnWidths.length ? columnWidths[c] : 18);
    }
  }

  static List<String> _personRow(Person person) {
    return <String>[
      person.id,
      person.firstName,
      person.lastName,
      person.fullName,
      person.gender.displayName,
      person.age?.toString() ?? '',
      _formatNullableDate(person.birthDate),
      _hebrewBirthDate(person),
      person.manualAge?.toString() ?? '',
      person.religiousLevel?.displayName ?? '',
      person.city ?? '',
      person.phone ?? '',
      person.inquiryContactName ?? '',
      person.inquiryContactPhone ?? '',
      person.source ?? '',
      person.profileStatus.displayName,
      _yesNo(person.isFavorite),
      person.description ?? '',
      person.notes ?? '',
      person.photosPaths.join('\n'),
      _formatDateTime(person.createdAt),
      _formatDateTime(person.updatedAt),
    ];
  }

  static String _hebrewBirthDate(Person person) {
    if (person.hebrewBirthYear != null &&
        person.hebrewBirthMonth != null &&
        person.hebrewBirthDay != null) {
      return HebrewDateUtils.format(
        year: person.hebrewBirthYear!,
        month: person.hebrewBirthMonth!,
        day: person.hebrewBirthDay!,
      );
    }

    final DateTime? birthDate = person.birthDate;
    if (birthDate == null) {
      return '';
    }

    final ({int year, int month, int day})? hebrew =
        HebrewDateUtils.fromGregorian(birthDate);
    if (hebrew == null) {
      return '';
    }

    return HebrewDateUtils.format(
      year: hebrew.year,
      month: hebrew.month,
      day: hebrew.day,
    );
  }

  static MatchIdea? _findMatch(List<MatchIdea> matches, String matchId) {
    for (final MatchIdea match in matches) {
      if (match.id == matchId) {
        return match;
      }
    }
    return null;
  }

  static String _personName(Map<String, Person> peopleById, String? personId) {
    if (personId == null) {
      return '';
    }
    return peopleById[personId]?.fullName ?? '';
  }

  static String _formatNullableDate(DateTime? date) {
    if (date == null) {
      return '';
    }
    return _dateFormat.format(date);
  }

  static String _formatDateTime(DateTime date) {
    return _dateTimeFormat.format(date);
  }

  static String _yesNo(bool value) {
    return value ? 'כן' : 'לא';
  }

  static CellStyle _titleStyle() {
    return CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: ExcelColor.fromHexString(
        _ExcelColorHex.textOnFilledSurface,
      ),
      backgroundColorHex: ExcelColor.fromHexString(
        _ExcelColorHex.titleBackground,
      ),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );
  }

  static CellStyle _headerStyle() {
    return CellStyle(
      bold: true,
      fontSize: 12,
      fontColorHex: ExcelColor.fromHexString(
        _ExcelColorHex.textOnFilledSurface,
      ),
      backgroundColorHex: ExcelColor.fromHexString(
        _ExcelColorHex.headerBackground,
      ),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      leftBorder: _headerBorder(),
      rightBorder: _headerBorder(),
      bottomBorder: _headerBorder(),
      topBorder: _headerBorder(),
      textWrapping: TextWrapping.WrapText,
    );
  }

  static CellStyle _dataStyle({required String backgroundHex}) {
    return CellStyle(
      fontSize: 11,
      fontColorHex: ExcelColor.fromHexString(_ExcelColorHex.dataText),
      backgroundColorHex: ExcelColor.fromHexString(backgroundHex),
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
      leftBorder: _dataBorder(),
      rightBorder: _dataBorder(),
      bottomBorder: _dataBorder(),
      topBorder: _dataBorder(),
      textWrapping: TextWrapping.WrapText,
    );
  }

  static Border _headerBorder() {
    return Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.fromHexString(
        _ExcelColorHex.textOnFilledSurface,
      ),
    );
  }

  static Border _dataBorder() {
    return Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.fromHexString(_ExcelColorHex.gridBorder),
    );
  }

  static List<int> _fixWorkbookBytes({
    required List<int> originalBytes,
    required Map<String, String> sheetRenames,
  }) {
    final Archive archive = ZipDecoder().decodeBytes(originalBytes);
    final Archive newArchive = Archive();

    for (final ArchiveFile archiveFile in archive.files) {
      if (!archiveFile.isFile) {
        continue;
      }

      List<int> content = archiveFile.content as List<int>;

      if (archiveFile.name.startsWith('xl/worksheets/sheet') &&
          archiveFile.name.endsWith('.xml')) {
        String xml = utf8.decode(content);
        if (!xml.contains('rightToLeft="1"')) {
          xml = xml.replaceFirst('<sheetView ', '<sheetView rightToLeft="1" ');
        }
        content = utf8.encode(xml);
      }

      if (archiveFile.name == 'xl/workbook.xml') {
        String xml = utf8.decode(content);
        for (final MapEntry<String, String> entry in sheetRenames.entries) {
          xml = xml.replaceFirst(
            'name="${_escapeXmlAttribute(entry.key)}"',
            'name="${_escapeXmlAttribute(entry.value)}"',
          );
        }
        content = utf8.encode(xml);
      }

      newArchive.addFile(
        ArchiveFile(archiveFile.name, content.length, content),
      );
    }

    return ZipEncoder().encode(newArchive)!;
  }

  static String _sanitizeSheetName(String value) {
    final String sanitized = value
        .replaceAll(RegExp(r'[\[\]\*:/\\?]'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (sanitized.isEmpty) {
      return 'גיליון';
    }

    return sanitized.length > 31 ? sanitized.substring(0, 31) : sanitized;
  }

  static String _escapeXmlAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll("'", '&apos;');
  }
}

abstract final class _ExcelColorHex {
  static const String textOnFilledSurface = '#FFFFFF';
  static const String titleBackground = '#4A148C';
  static const String headerBackground = '#7B1FA2';
  static const String evenRowBackground = '#F3E5F5';
  static const String gridBorder = '#CE93D8';
  static const String dataText = '#1C1B1F';
}
