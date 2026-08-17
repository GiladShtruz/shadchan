import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/import_diagnostics.dart';

/// The problem report a user sends to the developer.
///
/// The report exists because these failures cannot be reproduced here, and it
/// is only worth having if it is safe to send — so what it must *not* contain
/// is as much the point as what it must. A WhatsApp export is named after the
/// group, which names the user's contacts; the file's path leaks the same name
/// through any error message that prints it.
void main() {
  group('nothing personal reaches the report', () {
    test('the file is described by size and extension, never by name', () {
      final ImportDiagnostics log = ImportDiagnostics('וואטסאפ')
        ..noteFile(
          '/data/user/0/com.gilad.shadchan/cache/צאט עם שידוכי ירושלים.zip',
          4194304,
        );

      final String report = log.build(problem: 'לא הצלחנו לקרוא את הקובץ.');

      expect(report, isNot(contains('ירושלים')));
      expect(report, contains('.zip'));
      expect(report, contains('4.0 MB'));
    });

    test('an error carrying the path has the path taken out of it', () {
      const String path = '/storage/emulated/0/Download/צאט עם קבוצה סודית.zip';
      final ImportDiagnostics log = ImportDiagnostics('וואטסאפ')
        ..noteFile(path, 100);

      final String described = log.describeError(
        const FileSystemException('Cannot open file', path),
      );

      expect(described, isNot(contains('סודית')));
      expect(described, startsWith('FileSystemException'));
    });

    test('a long error is cut rather than sent whole', () {
      final ImportDiagnostics log = ImportDiagnostics('אקסל');

      final String described = log.describeError('x' * 5000);

      expect(described.length, lessThan(400));
      expect(described, endsWith('…'));
    });
  });

  test('the report says what went wrong and what was seen on the way', () {
    final ImportDiagnostics log = ImportDiagnostics('וואטסאפ')
      ..noteFile('/tmp/chat.zip', 1024)
      ..note('הודעות', 1200)
      ..note('תמונות', 43);

    final String report = log.build(problem: 'לא זוהו הודעות בקובץ.');

    expect(report, contains('דיווח תקלה — ייבוא וואטסאפ'));
    expect(report, contains('בעיה: לא זוהו הודעות בקובץ.'));
    expect(report, contains('הודעות: 1200'));
    expect(report, contains('תמונות: 43'));
    // Firebase never comes up under `flutter test`, and the report has to say
    // so rather than omit the line — "not there" is itself a diagnosis.
    expect(report, contains('firebase: לא עלה'));
    expect(report, contains('מכשיר: '));
  });

  /// The three lines that separate "this phone has a problem" from "this build
  /// was never registered", which every attestation report needs and none of
  /// them carried. Under `flutter test` there is no package info and no
  /// Firebase, so each falls back — but the line is always there, because a
  /// missing line reads as a missing answer.
  test('the report says where the install came from and what signed it', () {
    final ImportDiagnostics log = ImportDiagnostics('וואטסאפ');

    final String report = log.build(
      problem: 'המכשיר הזה לא מאושר לשימוש ב‑AI.',
    );

    expect(report, contains('התקנה: '));
    expect(report, contains('חתימה: '));
    expect(report, contains('appCheck: '));
  });
}
