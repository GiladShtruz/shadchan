import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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

/// An export, ready to be read.
@immutable
class WhatsAppChat {
  const WhatsAppChat({required this.messages, required this.mediaPaths});

  final List<WhatsAppMessage> messages;

  /// File name inside the export → where it was written on this device.
  final Map<String, String> mediaPaths;

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

/// Reads a WhatsApp export — a `.txt` or the `.zip` that carries it alongside
/// its media — into messages, on the device.
///
/// Everything here is local. The model later receives text only: the media
/// files never leave the phone, and a photo is attached to a person by matching
/// the file *name* the model saw in the transcript back to the file that was
/// extracted here.
abstract final class WhatsAppImportService {
  /// Ignored past this. A group chat can run to hundreds of thousands of lines,
  /// and reading all of it into memory to find sixty people is a way to kill
  /// the app on the phone of the person who needs the feature most.
  static const int maxMessages = 20000;

  static Future<WhatsAppChat> readFile(File file) async {
    final String extension = p.extension(file.path).toLowerCase();
    if (extension == '.zip') {
      return readZip(await file.readAsBytes());
    }
    return parseText(_decode(await file.readAsBytes()));
  }

  static Future<WhatsAppChat> readZip(List<int> zipBytes) async {
    final Archive archive = ZipDecoder().decodeBytes(zipBytes);
    final Directory mediaDir = await _mediaDirectory();

    final Map<String, String> mediaPaths = <String, String>{};
    List<int>? transcript;

    for (final ArchiveFile entry in archive) {
      if (!entry.isFile) {
        continue;
      }
      final String name = p.basename(entry.name);
      // WhatsApp names the transcript after the chat, so the only reliable
      // marker is the extension. The first .txt wins; exports carry one.
      if (transcript == null && name.toLowerCase().endsWith('.txt')) {
        transcript = entry.content as List<int>;
        continue;
      }
      final File target = File(p.join(mediaDir.path, name));
      await target.create(recursive: true);
      await target.writeAsBytes(entry.content as List<int>);
      mediaPaths[name] = target.path;
    }

    if (transcript == null) {
      return WhatsAppChat(
        messages: const <WhatsAppMessage>[],
        mediaPaths: mediaPaths,
      );
    }
    return parseText(_decode(transcript), mediaPaths: mediaPaths);
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
      }
    }

    for (final String rawLine in text.split(RegExp(r'\r?\n'))) {
      if (messages.length >= maxMessages) {
        break;
      }
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

    return WhatsAppChat(messages: messages, mediaPaths: mediaPaths);
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

  /// The media file named in a message, when the export carries it.
  ///
  /// Matched by looking for a name that was actually extracted, rather than by
  /// guessing at the wording around it — WhatsApp writes "(file attached)",
  /// "(קובץ מצורף)" and a bare name depending on version and language.
  static String? _attachmentIn(String text, Map<String, String> mediaPaths) {
    for (final String name in mediaPaths.keys) {
      if (text.contains(name)) {
        return name;
      }
    }
    return null;
  }

  static final RegExp _attachmentMarker = RegExp(
    r'^\s*\S+\.(jpg|jpeg|png|webp|pdf|opus|mp4|m4a|ogg)\s*'
    r'(\((file attached|קובץ מצורף)\))?\s*$',
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
