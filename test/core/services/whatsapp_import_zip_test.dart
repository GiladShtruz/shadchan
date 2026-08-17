import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shadchan/services/whatsapp_import_service.dart';

/// Reading the `.zip` half of an export.
///
/// Every case here is one of the ways the feature "worked on some phones and
/// not others": what comes out of the archive, what is deliberately left in it,
/// and what happens when the file is not what it claimed to be. None of them
/// could be told apart before — a bad zip, a zip of the wrong thing and a zip
/// too big for the phone all produced the same sentence.
void main() {
  late Directory temp;
  late String mediaDir;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('wa_zip_test');
    mediaDir = p.join(temp.path, 'media');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  /// A few bytes standing in for a real file — nothing here reads content.
  Uint8List blob(int size) =>
      Uint8List.fromList(List<int>.generate(size, (int i) => i % 256));

  String writeZip(Map<String, List<int>> entries, {String name = 'chat.zip'}) {
    final Archive archive = Archive();
    entries.forEach((String entryName, List<int> bytes) {
      archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
    });
    final File file = File(p.join(temp.path, name))
      ..writeAsBytesSync(ZipEncoder().encode(archive)!);
    return file.path;
  }

  const String card =
      'היי, יש הצעה טובה: יוסי כהן, בן 27, מבני ברק, רווק, 178 ס״מ';

  group('what comes out of the archive', () {
    test('the transcript is read and the photo is written to disk', () {
      final String zip = writeZip(<String, List<int>>{
        'WhatsApp Chat with שידוכים.txt': utf8Bytes(
          '17.2.2024, 15:49 - רחל: $card\n'
          '17.2.2024, 15:50 - רחל: IMG-20240217-WA0001.jpg (קובץ מצורף)',
        ),
        'IMG-20240217-WA0001.jpg': blob(2048),
      });

      final WhatsAppChat chat = WhatsAppImportService.readExportSync(
        zip,
        mediaDir,
      );

      expect(chat.messages, hasLength(2));
      expect(chat.messages.last.attachmentName, 'IMG-20240217-WA0001.jpg');
      final String? path = chat.mediaPaths['IMG-20240217-WA0001.jpg'];
      expect(path, isNotNull);
      expect(File(path!).lengthSync(), 2048);
      expect(chat.stats.mediaExtracted, 1);
      expect(chat.stats.transcriptFound, isTrue);
    });

    test('video and voice notes are never written out', () {
      // The reason the feature could fill a phone: a group export is mostly
      // these, and nothing in the app can ever open one.
      final String zip = writeZip(<String, List<int>>{
        'chat.txt': utf8Bytes('17.2.2024, 15:49 - רחל: $card'),
        'IMG-0001.jpg': blob(512),
        'VID-0002.mp4': blob(4096),
        'PTT-0003.opus': blob(4096),
        'doc.pdf': blob(1024),
      });

      final WhatsAppChat chat = WhatsAppImportService.readExportSync(
        zip,
        mediaDir,
      );

      expect(chat.mediaPaths.keys, <String>['IMG-0001.jpg']);
      expect(chat.stats.mediaExtracted, 1);
      expect(chat.stats.mediaSkipped, 3);
      expect(Directory(mediaDir).listSync(), hasLength(1));
    });

    test('a message naming a skipped video is not given an attachment', () {
      final String zip = writeZip(<String, List<int>>{
        'chat.txt': utf8Bytes(
          '17.2.2024, 15:49 - רחל: $card\n'
          '17.2.2024, 15:50 - רחל: VID-0002.mp4 (קובץ מצורף)',
        ),
        'VID-0002.mp4': blob(4096),
      });

      final WhatsAppChat chat = WhatsAppImportService.readExportSync(
        zip,
        mediaDir,
      );

      // The video line held nothing but the marker, so it leaves no message
      // behind at all rather than an empty one claiming a file that is not
      // on the device.
      expect(chat.messages, hasLength(1));
      expect(chat.messages.single.hasAttachment, isFalse);
    });
  });

  group('a file that is not what it claimed to be', () {
    test('a zip with no chat file inside says so', () {
      final String zip = writeZip(<String, List<int>>{
        'IMG-0001.jpg': blob(512),
      });

      expect(
        () => WhatsAppImportService.readExportSync(zip, mediaDir),
        throwsA(
          isA<WhatsAppReadException>().having(
            (WhatsAppReadException e) => e.reason,
            'reason',
            WhatsAppReadFailure.noTranscript,
          ),
        ),
      );
    });

    test('something that is not an archive says so, not "unreadable"', () {
      final File notAZip = File(p.join(temp.path, 'broken.zip'))
        ..writeAsBytesSync(blob(3000));

      expect(
        () => WhatsAppImportService.readExportSync(notAZip.path, mediaDir),
        throwsA(
          isA<WhatsAppReadException>().having(
            (WhatsAppReadException e) => e.reason,
            'reason',
            WhatsAppReadFailure.notAnArchive,
          ),
        ),
      );
    });
  });

  test('a bare .txt export is read as text and reports its size', () {
    final File txt = File(p.join(temp.path, 'chat.txt'))
      ..writeAsStringSync('17.2.2024, 15:49 - רחל: $card');

    final WhatsAppChat chat = WhatsAppImportService.readExportSync(
      txt.path,
      mediaDir,
    );

    expect(chat.messages, hasLength(1));
    expect(chat.stats.sourceBytes, txt.lengthSync());
    expect(chat.stats.archiveEntries, 0);
  });
}

List<int> utf8Bytes(String value) => utf8.encode(value);
