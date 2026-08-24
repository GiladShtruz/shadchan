import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

/// A worksheet reduced to the text a model can read.
@immutable
class ExcelTable {
  const ExcelTable({required this.sheetName, required this.rows});

  final String sheetName;

  /// Non-empty rows, each already trimmed to its last filled cell.
  final List<List<String>> rows;

  bool get isEmpty => rows.isEmpty;

  /// Renders the rows as tab-separated lines, the shape a spreadsheet already
  /// has and the cheapest one to send. Row numbers are kept so a person can be
  /// traced back to the line they came from when something looks wrong.
  /// Renders a window of rows, always led by the first row.
  ///
  /// The header travels with every batch on purpose. Real sheets encode
  /// meaning in the column a value sits in — a grid of names under the
  /// headings 21, 22, 23 says each name's age by position alone — and a batch
  /// that starts at row 26 without those headings is a list of names with the
  /// ages silently stripped out. Empty cells are kept for the same reason:
  /// they are what holds a name in its column.
  String toPromptText({int startRow = 0, int? maxRows}) {
    final int end = maxRows == null
        ? rows.length
        : (startRow + maxRows).clamp(0, rows.length);
    final StringBuffer buffer = StringBuffer();

    void writeRow(int index) {
      buffer
        ..write(index + 1)
        ..write('\t')
        ..writeln(rows[index].join('\t'));
    }

    if (startRow > 0 && rows.isNotEmpty) {
      writeRow(0);
    }
    for (int i = startRow; i < end; i++) {
      writeRow(i);
    }
    return buffer.toString().trimRight();
  }
}

/// Reads a picked workbook into plain rows, on the device.
///
/// The file itself is never uploaded. A spreadsheet is already structured, so
/// decoding it locally and sending only the text costs less, keeps the binary
/// (with whatever else the workbook happens to contain — other sheets, hidden
/// columns, macros) off the network, and leaves one obvious place to look when
/// asking what exactly was sent.
abstract final class ExcelImportService {
  /// Rows past this are ignored. A shidduch database that needs more than this
  /// in one file is not the case this feature is for, and an unbounded read is
  /// a way to hang the app on a file nobody meant to pick.
  static const int maxRows = 2000;

  /// Reads every sheet that has content. Most files have one; a workbook with
  /// a "גברים" and a "נשים" sheet is common enough to be worth handling.
  static Future<List<ExcelTable>> read(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    final Excel workbook = Excel.decodeBytes(bytes);

    final List<ExcelTable> tables = <ExcelTable>[];
    for (final MapEntry<String, Sheet> entry in workbook.tables.entries) {
      final List<List<String>> rows = prune(_readRows(entry.value));
      if (rows.isNotEmpty) {
        tables.add(ExcelTable(sheetName: entry.key, rows: rows));
      }
    }
    return tables;
  }

  /// Takes out the empty scaffolding a spreadsheet carries, and nothing else.
  ///
  /// **A column is the expensive kind of waste.** A blank row costs one line;
  /// a blank column in the middle of the grid costs a tab on *every* row, and
  /// real exports are full of them — a spacer between two groups of headings,
  /// a column somebody cleared instead of deleting, the serial number down
  /// column A. On a 2,000-row sheet each of those is two thousand tokens
  /// bought to tell the model nothing.
  ///
  /// **No row is ever judged on what it says.** A row is dropped only when
  /// every cell in it is empty, which is a fact about the grid rather than a
  /// reading of the data. Rules that looked sensible — drop the "סה״כ" line,
  /// drop the hand-drawn divider, drop an exact repeat — are each a guess about
  /// what a row *means*, and all of them fail the same silent way: the import
  /// still returns a list of people, just with somebody missing from it, and
  /// nothing on screen says a row was skipped. A totals row costs one line and
  /// the model ignores it. A person costs a person.
  ///
  /// Columns are held to that same standard: a column with no content at all,
  /// and a column that only counts the rows. Both are reconstructible from the
  /// sheet itself, which is what makes them safe. A sparse column stays — a
  /// "הערות" filled in for one candidate out of three hundred looks exactly
  /// like noise, and is the one thing anybody wrote down about that person.
  @visibleForTesting
  static List<List<String>> prune(List<List<String>> rows) {
    final List<List<String>> kept = <List<String>>[
      for (final List<String> row in rows)
        if (row.any((String cell) => cell.isNotEmpty)) <String>[...row],
    ];
    if (kept.isEmpty) {
      return kept;
    }

    final int width = kept.fold<int>(
      0,
      (int max, List<String> row) => row.length > max ? row.length : max,
    );
    for (final List<String> row in kept) {
      while (row.length < width) {
        row.add('');
      }
    }

    final List<int> columns = <int>[
      for (int col = 0; col < width; col++)
        if (!_isEmptyColumn(kept, col) && !_isSerialColumn(kept, col)) col,
    ];

    // Always rebuilt through `_trimTrailing`, including when no column was
    // dropped: the padding above squares the grid off so columns can be judged,
    // and leaving that padding in would spend a tab per row to say nothing —
    // the very thing this method exists to stop.
    return <List<String>>[
      for (final List<String> row in kept)
        _trimTrailing(<String>[
          for (final int col in columns) row[col],
        ]),
    ];
  }

  /// Drops the empty cells off the end of a row.
  ///
  /// Safe in a way that dropping an empty cell in the *middle* would not be:
  /// the columns before it keep their positions, which is what tells the model
  /// that a bare number under a heading of years is an age.
  static List<String> _trimTrailing(List<String> row) {
    while (row.isNotEmpty && row.last.isEmpty) {
      row.removeLast();
    }
    return row;
  }

  static bool _isEmptyColumn(List<List<String>> rows, int col) =>
      rows.every((List<String> row) => row[col].isEmpty);

  /// A column that only counts the rows: 1, 2, 3… down the sheet.
  ///
  /// Recognised by the run of numbers rather than by its heading, because the
  /// heading is as often blank as it is "מס'". Either start is accepted — a
  /// sheet with a header row numbers its people from 1 on the second line, one
  /// without numbers them from 1 on the first.
  static bool _isSerialColumn(List<List<String>> rows, int col) {
    final List<int> numbers = <int>[];
    for (final List<String> row in rows) {
      final String cell = row[col];
      if (cell.isEmpty) {
        continue;
      }
      final int? value = int.tryParse(cell);
      if (value == null) {
        // A heading over the numbers is allowed, and nothing else is.
        if (numbers.isEmpty && _serialHeadings.contains(cell)) {
          continue;
        }
        return false;
      }
      numbers.add(value);
    }
    // Two numbers in a row prove nothing; a column of ages would qualify.
    if (numbers.length < 4) {
      return false;
    }
    for (int i = 1; i < numbers.length; i++) {
      if (numbers[i] != numbers[i - 1] + 1) {
        return false;
      }
    }
    return numbers.first == 0 || numbers.first == 1;
  }

  static const Set<String> _serialHeadings = <String>{
    'מס',
    'מס.',
    "מס'",
    'מספר',
    'מספר סידורי',
    '#',
    'no',
    'No',
    'index',
  };

  @visibleForTesting
  static List<List<String>> readRowsFromBytes(List<int> bytes) {
    final Excel workbook = Excel.decodeBytes(bytes);
    final Sheet? first = workbook.tables.values.isEmpty
        ? null
        : workbook.tables.values.first;
    return first == null ? <List<String>>[] : _readRows(first);
  }

  static List<List<String>> _readRows(Sheet sheet) {
    final List<List<String>> rows = <List<String>>[];
    for (final List<Data?> row in sheet.rows) {
      if (rows.length >= maxRows) {
        break;
      }
      final List<String> cells = row.map(_cellText).toList();
      // Trailing blanks are an artefact of the grid, not of the data: a sheet
      // reports every column it has ever touched, so a three-column table can
      // arrive with twenty empty cells on each row.
      while (cells.isNotEmpty && cells.last.isEmpty) {
        cells.removeLast();
      }
      if (cells.isNotEmpty) {
        rows.add(cells);
      }
    }
    return rows;
  }

  /// Cell text as a person would see it in the spreadsheet.
  ///
  /// Whole numbers lose their `.0` — an age stored as a double should reach the
  /// model as "27", not "27.0", because the second invites it to treat the
  /// column as something other than an age.
  @visibleForTesting
  static String cellText(CellValue? value) => switch (value) {
    null => '',
    TextCellValue() => value.value.toString().trim(),
    IntCellValue() => value.value.toString(),
    DoubleCellValue() =>
      value.value == value.value.roundToDouble()
          ? value.value.toInt().toString()
          : value.value.toString(),
    BoolCellValue() => value.value ? 'כן' : 'לא',
    _ => value.toString().trim(),
  };

  static String _cellText(Data? cell) => cellText(cell?.value);
}
