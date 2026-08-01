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
      final List<List<String>> rows = _readRows(entry.value);
      if (rows.isNotEmpty) {
        tables.add(ExcelTable(sheetName: entry.key, rows: rows));
      }
    }
    return tables;
  }

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
