import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/excel_import_service.dart';

/// Turning a worksheet into the text the model sees.
///
/// This step runs entirely on the device and decides what actually leaves it,
/// so it is worth pinning down. The failures it guards are quiet ones: a `.0`
/// on every age that invites the model to read the column as something else,
/// and a row that arrives padded with empty cells because the grid remembers a
/// column somebody once touched.
void main() {
  group('cell text reads as a person would see it', () {
    test('a whole number loses the decimal point a spreadsheet gave it', () {
      expect(ExcelImportService.cellText(DoubleCellValue(27)), '27');
      expect(ExcelImportService.cellText(IntCellValue(27)), '27');
    });

    test('a real fraction keeps it — heights are written this way', () {
      expect(ExcelImportService.cellText(DoubleCellValue(1.78)), '1.78');
    });

    test('text is trimmed, and an empty cell is empty', () {
      expect(ExcelImportService.cellText(TextCellValue('  חיפה  ')), 'חיפה');
      expect(ExcelImportService.cellText(null), '');
    });

    test('a boolean reads in Hebrew, since the model reads Hebrew', () {
      expect(ExcelImportService.cellText(BoolCellValue(true)), 'כן');
      expect(ExcelImportService.cellText(BoolCellValue(false)), 'לא');
    });
  });

  group('prompt text keeps the sheet traceable', () {
    const ExcelTable table = ExcelTable(
      sheetName: 'גיליון1',
      rows: <List<String>>[
        <String>['שם', 'גיל'],
        <String>['יוסי כהן', '27'],
        <String>['נועה ברגר', '24'],
      ],
    );

    test('every line is numbered so a person can be traced to a row', () {
      expect(
        table.toPromptText(),
        '1\tשם\tגיל\n2\tיוסי כהן\t27\n3\tנועה ברגר\t24',
      );
    });

    test('a later batch carries the header row with it', () {
      // Without this, a sheet that states a value by column — a grid of names
      // under the headings 21, 22, 23 — loses it from the second batch on.
      // The rows come back looking fine, just with the ages missing.
      expect(
        table.toPromptText(startRow: 1, maxRows: 1),
        '1\tשם\tגיל\n2\tיוסי כהן\t27',
      );
    });

    test('the first batch does not repeat the header it already contains', () {
      expect(
        table.toPromptText(startRow: 0, maxRows: 2),
        '1\tשם\tגיל\n2\tיוסי כהן\t27',
      );
    });

    test('row numbers stay the sheet\'s own, never renumbered per batch', () {
      // A person has to be traceable to the line they came from, and the
      // repeated header must keep its real number 1 rather than becoming the
      // first line of this window.
      expect(
        table.toPromptText(startRow: 2, maxRows: 50),
        '1\tשם\tגיל\n3\tנועה ברגר\t24',
      );
    });

    test('an empty table renders as nothing at all', () {
      const ExcelTable empty = ExcelTable(
        sheetName: 'ריק',
        rows: <List<String>>[],
      );

      expect(empty.isEmpty, isTrue);
      expect(empty.toPromptText(), isEmpty);
    });
  });

  group('reading a workbook', () {
    test('drops padding columns and blank rows the grid invents', () {
      final Excel workbook = Excel.createExcel();
      final Sheet sheet = workbook[workbook.getDefaultSheet()!];
      sheet.appendRow(<CellValue?>[
        TextCellValue('יוסי'),
        IntCellValue(27),
        // The grid remembers these; the data does not contain them.
        TextCellValue(''),
        TextCellValue(''),
      ]);
      sheet.appendRow(<CellValue?>[TextCellValue(''), TextCellValue('')]);
      sheet.appendRow(<CellValue?>[TextCellValue('נועה'), IntCellValue(24)]);

      final List<List<String>> rows = ExcelImportService.readRowsFromBytes(
        workbook.encode()!,
      );

      expect(rows, <List<String>>[
        <String>['יוסי', '27'],
        <String>['נועה', '24'],
      ]);
    });
  });
}
