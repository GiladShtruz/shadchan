import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One message out of an exported chat.
@immutable
class WhatsAppMessage {
  const WhatsAppMessage({
    required this.sender,
    required this.text,
    this.sentAt,
    this.attachmentName,
  });

  final String sender;
  final String text;
  final DateTime? sentAt;

  /// The media file this message carried, by its name inside the export.
  /// Resolved to a real path through [WhatsAppChat.mediaPaths].
  final String? attachmentName;

  bool get hasAttachment => attachmentName != null;
}

/// What reading an export actually cost and actually found.
///
/// Kept because the failures this feature has in the field are all
/// *device-dependent* — the same export works on one phone and not on the next
/// — and none of them can be reproduced here. Without a record of how big the
/// file was, how many entries came out of it and where the read stopped, a
/// report from a user is "it didn't work" and there is nothing to act on. This
/// is what [ImportDiagnostics] turns into the text they send.
@immutable
class WhatsAppReadStats {
  const WhatsAppReadStats({
    this.sourceBytes = 0,
    this.archiveEntries = 0,
    this.mediaExtracted = 0,
    this.mediaSkipped = 0,
    this.mediaBytes = 0,
    this.transcriptFound = true,
    this.truncatedMessages = false,
    this.cappedMedia = false,
  });

  final int sourceBytes;
  final int archiveEntries;
  final int mediaExtracted;

  /// Entries deliberately not written out: video, voice notes, documents, and
  /// anything past the caps. A group export is mostly these.
  final int mediaSkipped;
  final int mediaBytes;

  /// False when a `.zip` carried no `.txt` at all — a real and common case,
  /// because a share sheet will happily hand over the wrong zip.
  final bool transcriptFound;

  /// The chat was longer than [WhatsAppImportService.maxMessages] and only its
  /// most recent messages were kept.
  final bool truncatedMessages;

  /// Extraction stopped at a cap rather than at the end of the archive.
  final bool cappedMedia;
}

/// An export, ready to be read.
@immutable
class WhatsAppChat {
  const WhatsAppChat({
    required this.messages,
    required this.mediaPaths,
    this.stats = const WhatsAppReadStats(),
  });

  final List<WhatsAppMessage> messages;

  /// File name inside the export → where it was written on this device.
  final Map<String, String> mediaPaths;

  final WhatsAppReadStats stats;

  bool get isEmpty => messages.isEmpty;

  /// The messages worth paying to read.
  ///
  /// A matchmaker's group runs to thousands of lines of "תודה" and "אשאל
  /// ואחזור אליך", and sending all of it is expensive for no return. The
  /// filter is deliberately timid: it drops only what certainly holds no
  /// person, because a card missed here is a person who never reaches the
  /// database and nobody ever notices.
  ///
  /// Messages carrying a photo are always kept, however short. They are
  /// usually empty of text, and they are exactly what the model needs in order
  /// to tell whose photo it is.
  /// Each kept message with its position in the full chat, so the transcript
  /// can be numbered without searching the list for every line.
  List<({int index, WhatsAppMessage message})> get candidateMessages {
    final List<({int index, WhatsAppMessage message})> kept =
        <({int index, WhatsAppMessage message})>[];
    for (int i = 0; i < messages.length; i++) {
      final WhatsAppMessage message = messages[i];
      if (message.hasAttachment || _looksSubstantive(message.text)) {
        kept.add((index: i, message: message));
      }
    }
    return kept;
  }

  static bool _looksSubstantive(String text) {
    if (text.trim().length < 20) {
      return false;
    }
    return !_noise.hasMatch(text);
  }

  /// Chatter WhatsApp writes itself, plus the tombstone of a deleted message.
  static final RegExp _noise = RegExp(
    r'הודעה זו נמחקה|מחקת הודעה זו|This message was deleted|You deleted'
    r'|ההודעות והשיחות מוצפנות|Messages and calls are end-to-end encrypted'
    r'|הצטרף/ה באמצעות|הצטרפת באמצעות|joined using this group'
    r'|עזב/ה את הקבוצה|left$|הוסיף/ה את|added|הסיר/ה את|removed'
    r'|שינה/תה את נושא הקבוצה|changed the subject|changed this group'
    r'|created group|יצר/ה את הקבוצה',
    caseSensitive: false,
  );

  /// Renders messages for the model, numbered and with any attached file named
  /// in place.
  ///
  /// The number and the ordering are the whole mechanism for photos: the model
  /// never sees an image, only that `IMG-…jpg` arrived between these two
  /// messages, and decides from the conversation whether it belongs to the card
  /// above it or the one below.
  static String toTranscript(
    List<({int index, WhatsAppMessage message})> window,
  ) {
    final StringBuffer buffer = StringBuffer();
    for (final ({int index, WhatsAppMessage message}) entry in window) {
      buffer.write('#${entry.index} ${entry.message.sender}: ');
      if (entry.message.text.isNotEmpty) {
        buffer.write(entry.message.text.replaceAll('\n', ' ⏎ '));
      }
      if (entry.message.hasAttachment) {
        buffer.write(' [קובץ מצורף: ${entry.message.attachmentName}]');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }
}

/// Why reading an export stopped, in the terms the screen has to explain it in.
///
/// "לא הצלחנו לקרוא את הקובץ" was the answer to all of these, which is why the
/// same message came back from a zip that was not an export, a phone that ran
/// out of memory and a phone that ran out of disk — three problems with three
/// different fixes, none of which the user could be told.
enum WhatsAppReadFailure {
  /// Not a zip at all, or a damaged one.
  notAnArchive,

  /// A valid zip with no chat transcript inside it.
  noTranscript,

  /// The device could not hold the file. The characteristic failure of a big
  /// group export on a phone with a small heap.
  outOfMemory,

  /// Extracting the media filled the device.
  outOfSpace,

  unreadable,
}

/// Thrown out of the worker isolate, which is why [cause] is already a string.
///
/// An exception that crosses an isolate has to be copyable, and the causes here
/// are whatever the platform threw — a `FileSystemException`, an
/// `ArchiveException`, an `OutOfMemoryError`. Flattening them at the throw site
/// means the reason for a failure can never itself become a second, stranger
/// failure on the way back.
class WhatsAppReadException implements Exception {
  const WhatsAppReadException(this.reason, [this.cause]);

  WhatsAppReadException.of(this.reason, Object error)
    : cause = '${error.runtimeType}: $error';

  final WhatsAppReadFailure reason;
  final String? cause;

  @override
  String toString() => 'WhatsAppReadException($reason, $cause)';
}

/// Reads a WhatsApp export — a `.txt` or the `.zip` that carries it alongside
/// its media — into messages, on the device.
///
/// Everything here is local. The model later receives text only: the media
/// files never leave the phone, and a photo is attached to a person by matching
/// the file *name* the model saw in the transcript back to the file that was
/// extracted here.
///
/// **Nothing in this file may hold the whole export in memory.** A group
/// export with media is routinely 100–500 MB, and an Android heap is commonly
/// 128–256 MB, so the earlier `readAsBytes()` → `decodeBytes()` pair could not
/// work on a large export no matter how good the phone was — it needed two full
/// copies before it decompressed anything. That is the shape of the bug the
/// feature had: it worked on whoever's export was small, and failed on
/// everyone else's, which reads as "works on some phones". The zip is read
/// through [InputFileStream] and written through [OutputFileStream], one entry
/// at a time.
abstract final class WhatsAppImportService {
  /// Ignored past this, keeping the **most recent** messages.
  ///
  /// A group chat can run to hundreds of thousands of lines, and reading all of
  /// it into memory to find sixty people is a way to kill the app on the phone
  /// of the person who needs the feature most. Which end is kept matters: an
  /// export is written oldest-first, so keeping the first 20,000 — as this did
  /// — threw away exactly the recent candidates the import was opened for, and
  /// did it without saying so.
  static const int maxMessages = 20000;

  /// Only photos are written out of the archive.
  ///
  /// The model never sees an image; the only thing media is used for is to hand
  /// a person the picture that arrived with their card. Videos and voice notes
  /// cannot do that and are the bulk of a group export's size, so extracting
  /// them spent the user's storage and the phone's time on files nothing would
  /// ever open.
  static const Set<String> photoExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  };

  /// Ceilings on what one import may write to the device. Reached rather than
  /// crashed into: the chat still imports, it just arrives with fewer photos,
  /// and [WhatsAppReadStats.cappedMedia] says so.
  static const int maxMediaFiles = 3000;
  static const int maxMediaBytes = 300 * 1024 * 1024;
  static const int maxSingleMediaBytes = 32 * 1024 * 1024;

  /// A bare `.txt` past this is read as text but never held twice. Exports
  /// without media are small; one this large is not a chat export.
  static const int maxTranscriptBytes = 64 * 1024 * 1024;

  /// Reads [file] off the UI isolate.
  ///
  /// The work is seconds of decompression and thousands of file writes, all of
  /// it synchronous CPU and blocking I/O. On the main isolate that is a frozen
  /// app — long enough on a slow phone for Android to offer to close it, which
  /// is one of the ways this feature "did not work" without ever reporting an
  /// error. `path_provider` needs the platform channel, so the directory is
  /// resolved here and only its path crosses over.
  static Future<WhatsAppChat> readFile(File file) async {
    final String mediaDir = (await _mediaDirectory()).path;
    return compute(_readExport, (
      path: file.path,
      mediaDir: mediaDir,
    ), debugLabel: 'whatsapp-import');
  }

  /// The body of [readFile], on whichever isolate it is called from.
  @visibleForTesting
  static WhatsAppChat readExportSync(String path, String mediaDirPath) {
    final File file = File(path);
    final int sourceBytes = file.existsSync() ? file.lengthSync() : 0;
    if (p.extension(path).toLowerCase() == '.zip') {
      return _readZip(file, sourceBytes, mediaDirPath);
    }
    return _readTranscriptFile(file, sourceBytes);
  }

  static WhatsAppChat _readTranscriptFile(File file, int sourceBytes) {
    if (sourceBytes > maxTranscriptBytes) {
      throw const WhatsAppReadException(WhatsAppReadFailure.outOfMemory);
    }
    final String text;
    try {
      text = _decode(file.readAsBytesSync());
    } on OutOfMemoryError catch (error) {
      throw WhatsAppReadException.of(WhatsAppReadFailure.outOfMemory, error);
    } catch (error) {
      throw WhatsAppReadException.of(WhatsAppReadFailure.unreadable, error);
    }
    final WhatsAppChat chat = parseText(text);
    return WhatsAppChat(
      messages: chat.messages,
      mediaPaths: chat.mediaPaths,
      stats: WhatsAppReadStats(
        sourceBytes: sourceBytes,
        truncatedMessages: chat.stats.truncatedMessages,
      ),
    );
  }

  /// Walks the archive once, writing out only what the import can use.
  ///
  /// The transcript is taken first and kept as bytes — it is the one entry that
  /// has to be in memory — and every photo goes straight from the archive to
  /// disk through a stream, so peak memory is one photo rather than one export.
  static WhatsAppChat _readZip(
    File file,
    int sourceBytes,
    String mediaDirPath,
  ) {
    final Directory mediaDir = Directory(mediaDirPath);
    if (!mediaDir.existsSync()) {
      mediaDir.createSync(recursive: true);
    }

    InputFileStream? input;
    final Map<String, String> mediaPaths = <String, String>{};
    List<int>? transcript;
    int entries = 0;
    int extracted = 0;
    int skipped = 0;
    int mediaBytes = 0;
    bool capped = false;

    try {
      input = InputFileStream(file.path);
      final Archive archive = ZipDecoder().decodeBuffer(input);

      for (final ArchiveFile entry in archive) {
        if (!entry.isFile) {
          continue;
        }
        entries++;
        final String name = p.basename(entry.name);
        // WhatsApp names the transcript after the chat, so the only reliable
        // marker is the extension. The first .txt wins; exports carry one.
        if (transcript == null && name.toLowerCase().endsWith('.txt')) {
          if (entry.size > maxTranscriptBytes) {
            throw const WhatsAppReadException(WhatsAppReadFailure.outOfMemory);
          }
          transcript = entry.content as List<int>;
          entry.clear();
          continue;
        }

        if (!photoExtensions.contains(p.extension(name).toLowerCase()) ||
            entry.size <= 0 ||
            entry.size > maxSingleMediaBytes) {
          skipped++;
          continue;
        }
        if (extracted >= maxMediaFiles ||
            mediaBytes + entry.size > maxMediaBytes) {
          skipped++;
          capped = true;
          continue;
        }

        final File target = File(p.join(mediaDir.path, name));
        final OutputFileStream output = OutputFileStream(target.path);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
        entry.clear();
        mediaPaths[name] = target.path;
        extracted++;
        mediaBytes += entry.size;
      }
    } on WhatsAppReadException {
      rethrow;
    } on OutOfMemoryError catch (error) {
      throw WhatsAppReadException.of(WhatsAppReadFailure.outOfMemory, error);
    } on ArchiveException catch (error) {
      throw WhatsAppReadException.of(WhatsAppReadFailure.notAnArchive, error);
    } on FileSystemException catch (error) {
      // 28 is ENOSPC on both Android and iOS. The device filling up mid-import
      // is a real outcome for a group export and the only one whose fix is
      // "free some space", so it must not read as a corrupt file.
      throw WhatsAppReadException.of(
        error.osError?.errorCode == 28
            ? WhatsAppReadFailure.outOfSpace
            : WhatsAppReadFailure.unreadable,
        error,
      );
    } catch (error) {
      throw WhatsAppReadException.of(WhatsAppReadFailure.unreadable, error);
    } finally {
      input?.closeSync();
    }

    final WhatsAppReadStats stats = WhatsAppReadStats(
      sourceBytes: sourceBytes,
      archiveEntries: entries,
      mediaExtracted: extracted,
      mediaSkipped: skipped,
      mediaBytes: mediaBytes,
      transcriptFound: transcript != null,
      cappedMedia: capped,
    );

    if (transcript == null) {
      throw WhatsAppReadException(
        WhatsAppReadFailure.noTranscript,
        '${stats.archiveEntries} entries, no .txt',
      );
    }

    final WhatsAppChat chat = parseText(
      _decode(transcript),
      mediaPaths: mediaPaths,
    );
    return WhatsAppChat(
      messages: chat.messages,
      mediaPaths: mediaPaths,
      stats: WhatsAppReadStats(
        sourceBytes: stats.sourceBytes,
        archiveEntries: stats.archiveEntries,
        mediaExtracted: stats.mediaExtracted,
        mediaSkipped: stats.mediaSkipped,
        mediaBytes: stats.mediaBytes,
        cappedMedia: stats.cappedMedia,
        truncatedMessages: chat.stats.truncatedMessages,
      ),
    );
  }

  /// Decodes as UTF-8, which is what WhatsApp writes.
  ///
  /// Reading the bytes as code units instead — the obvious shortcut — turns
  /// every Hebrew letter into mojibake, and the damage is silent: the file
  /// opens, the lines parse, and only the names are ruined.
  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  @visibleForTesting
  static WhatsAppChat parseText(
    String content, {
    Map<String, String> mediaPaths = const <String, String>{},
  }) {
    String text = content;
    if (text.startsWith('﻿')) {
      text = text.substring(1);
    }

    final List<WhatsAppMessage> messages = <WhatsAppMessage>[];
    bool truncated = false;
    String? sender;
    DateTime? sentAt;
    final StringBuffer body = StringBuffer();

    void flush() {
      final String? current = sender;
      if (current == null) {
        return;
      }
      final String raw = body.toString().trim();
      final String? attachment = _attachmentIn(raw, mediaPaths);
      final String cleaned = _stripAttachmentMarkers(raw);
      if (cleaned.isNotEmpty || attachment != null) {
        messages.add(
          WhatsAppMessage(
            sender: current,
            text: cleaned,
            sentAt: sentAt,
            attachmentName: attachment,
          ),
        );
        // Dropped in blocks rather than one at a time, so a very long chat
        // costs one list shift per 20,000 messages instead of one per message.
        if (messages.length >= maxMessages * 2) {
          messages.removeRange(0, messages.length - maxMessages);
          truncated = true;
        }
      }
    }

    for (final String rawLine in text.split(RegExp(r'\r?\n'))) {
      final String line = _stripDirectionMarks(rawLine);
      final _Header? header = _readHeader(line);
      if (header == null) {
        // A continuation of the message above. Chat cards are written across
        // many lines, so this is the common case, not the exception.
        if (sender != null) {
          body
            ..write('\n')
            ..write(line);
        }
        continue;
      }

      flush();
      sender = header.sender;
      sentAt = header.sentAt;
      body
        ..clear()
        ..write(header.text);
    }
    flush();

    if (messages.length > maxMessages) {
      messages.removeRange(0, messages.length - maxMessages);
      truncated = true;
    }

    return WhatsAppChat(
      messages: messages,
      mediaPaths: mediaPaths,
      stats: WhatsAppReadStats(truncatedMessages: truncated),
    );
  }

  /// Matches both export shapes.
  ///
  /// Android writes `17.2.2024, 15:49 - שם: הודעה`; iOS writes
  /// `[17.2.2024, 15:49:30] שם: הודעה`. Supporting only one silently produces
  /// an export where every line looks like a continuation and no message is
  /// ever found.
  /// The date separator and the comma after it both vary by locale — `.`, `/`
  /// and `-` all occur, and some builds write no comma at all. Being strict
  /// here is indistinguishable from a corrupt file: every line reads as a
  /// continuation and the import reports "no messages found".
  static final RegExp _androidHeader = RegExp(
    r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4}),?\s+(\d{1,2}):(\d{2})(?::\d{2})?'
    r'(?:\s*[APap]\.?[Mm]\.?)?\s+-\s+([^:]{1,80}):\s?(.*)$',
  );
  static final RegExp _iosHeader = RegExp(
    r'^\[(\d{1,2})[./-](\d{1,2})[./-](\d{2,4}),?\s+(\d{1,2}):(\d{2})(?::\d{2})?'
    r'(?:\s*[APap]\.?[Mm]\.?)?\]\s*([^:]{1,80}):\s?(.*)$',
  );

  static _Header? _readHeader(String line) {
    final RegExpMatch? match =
        _androidHeader.firstMatch(line) ?? _iosHeader.firstMatch(line);
    if (match == null) {
      return null;
    }

    final String sender = match.group(6)!.trim();
    if (sender.isEmpty) {
      return null;
    }

    int year = int.parse(match.group(3)!);
    if (year < 100) {
      year += 2000;
    }
    DateTime? sentAt;
    try {
      sentAt = DateTime(
        year,
        int.parse(match.group(2)!),
        int.parse(match.group(1)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
      );
    } catch (_) {
      sentAt = null;
    }

    return _Header(sender: sender, sentAt: sentAt, text: match.group(7)!);
  }

  /// A file name that looks like an attachment, wherever it sits in the line.
  ///
  /// WhatsApp writes it as a bare name, as `IMG-… (file attached)`, as
  /// `‏<attached: IMG-…>` and as `<קובץ מצורף: IMG-…>` depending on version and
  /// language, so the name is found by its own shape rather than by the wording
  /// around it.
  static final RegExp _fileNameToken = RegExp(
    r'[^\s\\/:*?"<>|]+\.(?:jpe?g|png|webp|heic|heif|gif|pdf|opus|mp[34]|m4a|'
    r'ogg|aac|3gp|wav|vcf|docx?|xlsx?|zip)',
    caseSensitive: false,
  );

  /// The media file named in a message, when the export carries it.
  ///
  /// Looked up rather than scanned for. The obvious version — walk every
  /// extracted name and ask whether the text contains it — is O(messages ×
  /// files), and a group export is 20,000 messages against 3,000 files: sixty
  /// million substring searches, each over the whole message, on whatever
  /// thread happened to call it. That alone could hold a phone for minutes with
  /// no progress and nothing on screen.
  static String? _attachmentIn(String text, Map<String, String> mediaPaths) {
    if (mediaPaths.isEmpty) {
      return null;
    }
    for (final RegExpMatch match in _fileNameToken.allMatches(text)) {
      final String name = match.group(0)!;
      if (mediaPaths.containsKey(name)) {
        return name;
      }
      final String base = p.basename(name);
      if (base != name && mediaPaths.containsKey(base)) {
        return base;
      }
    }
    return null;
  }

  /// A line that is nothing but an attachment marker, so it can be removed.
  ///
  /// The extension list is deliberately the same one [_fileNameToken] knows: a
  /// kind of file the app can *name* but not *strip* leaves the raw file name
  /// sitting in the message text, and that text is what a person's card is kept
  /// from word for word.
  static final RegExp _attachmentMarker = RegExp(
    r'^\s*\S+\.(?:jpe?g|png|webp|heic|heif|gif|pdf|opus|mp[34]|m4a|ogg|aac|'
    r'3gp|wav|vcf|docx?|xlsx?)\s*'
    r'(?:\((?:file attached|קובץ מצורף)\))?\s*$',
    caseSensitive: false,
    multiLine: true,
  );

  static final RegExp _mediaOmitted = RegExp(
    r'<\s*(Media omitted|המדיה לא נכללה|מדיה הושמטה)\s*>',
    caseSensitive: false,
  );

  static String _stripAttachmentMarkers(String text) {
    return text
        .replaceAll(_attachmentMarker, '')
        .replaceAll(_mediaOmitted, '')
        .trim();
  }

  /// Hebrew exports are full of invisible direction marks, which break every
  /// anchored pattern they land in front of.
  ///
  /// Written as escapes on purpose: as literal characters they are invisible in
  /// the editor, so the one line whose job is to remove them would be the one
  /// line nobody could see was wrong.
  static final RegExp _directionMarks = RegExp(
    '[\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  );

  static String _stripDirectionMarks(String value) =>
      value.replaceAll(_directionMarks, '');

  static Future<Directory> _mediaDirectory() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(
      p.join(documents.path, 'whatsapp_import_media'),
    );
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

/// Top-level so it can cross to a worker isolate.
WhatsAppChat _readExport(({String path, String mediaDir}) request) =>
    WhatsAppImportService.readExportSync(request.path, request.mediaDir);

@immutable
class _Header {
  const _Header({
    required this.sender,
    required this.sentAt,
    required this.text,
  });

  final String sender;
  final DateTime? sentAt;
  final String text;
}
