import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/excel_import_service.dart';

/// Shorthand for a row, so the tables below read like the sheets they stand in
/// for rather than like generic type noise.
List<String> r(List<String> cells) => cells;

void main() {
  group('a column with nothing in it is not sent', () {
    test('a blank column between two filled ones is removed', () {
      // The expensive case: a spacer column costs a tab on every single row,
      // so on a real sheet it is thousands of tokens that say nothing.
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['שם', '', 'גיל']),
        r(<String>['יוסי', '', '27']),
        r(<String>['נועה', '', '24']),
      ]);

      expect(pruned, <List<String>>[
        <String>['שם', 'גיל'],
        <String>['יוסי', '27'],
        <String>['נועה', '24'],
      ]);
    });

    test('a blank leading column is removed', () {
      // Individually trimming trailing cells never caught this one: the empty
      // cell is at the front of every row, not the end.
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['', 'שם', 'גיל']),
        r(<String>['', 'יוסי', '27']),
      ]);

      expect(pruned, <List<String>>[
        <String>['שם', 'גיל'],
        <String>['יוסי', '27'],
      ]);
    });

    test('padding added to square the grid is not sent back out', () {
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['שם', 'גיל', 'עיר']),
        r(<String>['יוסי']),
      ]);

      expect(pruned, <List<String>>[
        <String>['שם', 'גיל', 'עיר'],
        <String>['יוסי'],
      ]);
    });
  });

  group('a column that only counts the rows is not sent', () {
    test('a serial column under a heading is removed', () {
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['מס', 'שם']),
        r(<String>['1', 'יוסי']),
        r(<String>['2', 'נועה']),
        r(<String>['3', 'דוד']),
        r(<String>['4', 'מירי']),
      ]);

      expect(pruned.first, <String>['שם']);
      expect(pruned.last, <String>['מירי']);
    });

    test('a serial column with no heading at all is removed', () {
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['1', 'יוסי']),
        r(<String>['2', 'נועה']),
        r(<String>['3', 'דוד']),
        r(<String>['4', 'מירי']),
      ]);

      expect(pruned.every((List<String> row) => row.length == 1), isTrue);
    });

    test('a column of ages is NOT mistaken for a serial column', () {
      // The failure this guards against is silent and total: ages are numbers
      // in a column, and dropping them returns everybody with no age and
      // nothing on screen to say why.
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['שם', 'גיל']),
        r(<String>['יוסי', '27']),
        r(<String>['נועה', '24']),
        r(<String>['דוד', '31']),
        r(<String>['מירי', '29']),
      ]);

      expect(pruned.first, <String>['שם', 'גיל']);
      expect(pruned[1], <String>['יוסי', '27']);
    });

    test('consecutive ages that happen to run 1,2,3 still need four of them '
        'before anything is dropped', () {
      // Three rows of 1,2,3 is not evidence. Two people whose ages happen to
      // be consecutive must never cost the column.
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['שם', 'ילדים']),
        r(<String>['יוסי', '1']),
        r(<String>['נועה', '2']),
      ]);

      expect(pruned.first, <String>['שם', 'ילדים']);
    });
  });

  group('only a genuinely empty row is dropped', () {
    test('a blank row left behind in the sheet is dropped', () {
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['שם', 'גיל']),
        r(<String>['', '']),
        r(<String>['יוסי', '27']),
      ]);

      expect(pruned, <List<String>>[
        <String>['שם', 'גיל'],
        <String>['יוסי', '27'],
      ]);
    });

    test('a totals row is KEPT — reading a row is not our job', () {
      // Dropping it was tried and taken back out. It costs one line, the model
      // ignores it, and any rule that decides a row means nothing is a rule
      // that will one day decide a person means nothing — with a result that
      // looks exactly like a successful import.
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['שם', 'גיל']),
        r(<String>['יוסי', '27']),
        r(<String>['סה״כ', '1']),
      ]);

      expect(pruned, hasLength(3));
      expect(pruned.last, <String>['סה״כ', '1']);
    });

    test('a hand-drawn separator row is kept', () {
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['שם']),
        r(<String>['-----']),
        r(<String>['יוסי']),
      ]);

      expect(pruned, hasLength(3));
    });

    test('a repeated row is kept — two people can share every field shown', () {
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['יוסי כהן', '27']),
        r(<String>['יוסי כהן', '27']),
      ]);

      expect(pruned, hasLength(2));
    });

    test('a row with a single value survives', () {
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['שם', 'גיל']),
        r(<String>['יוסי', '']),
      ]);

      expect(pruned, hasLength(2));
      expect(pruned.last, <String>['יוסי']);
    });
  });

  group('what is deliberately left alone', () {
    test('a column filled in for only one person is kept', () {
      // It looks like noise and it is not: it is the one thing somebody wrote
      // down about that candidate, and losing it is invisible because the
      // import still returns everybody.
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['שם', 'הערות']),
        r(<String>['יוסי', '']),
        r(<String>['נועה', 'מדברת אנגלית']),
        r(<String>['דוד', '']),
      ]);

      expect(pruned.first, <String>['שם', 'הערות']);
      expect(pruned[2], <String>['נועה', 'מדברת אנגלית']);
    });

    test('an empty cell inside a row keeps its column position', () {
      // Position is meaning: a bare number under a heading of years is an age
      // only because of the column it sits in.
      final List<List<String>> pruned = ExcelImportService.prune(<List<String>>[
        r(<String>['שם', 'גיל', 'עיר']),
        r(<String>['יוסי', '', 'בני ברק']),
      ]);

      expect(pruned[1], <String>['יוסי', '', 'בני ברק']);
    });

    test('an empty sheet prunes to nothing rather than throwing', () {
      expect(ExcelImportService.prune(<List<String>>[]), isEmpty);
      expect(
        ExcelImportService.prune(<List<String>>[
          r(<String>['', '']),
        ]),
        isEmpty,
      );
    });
  });
}
