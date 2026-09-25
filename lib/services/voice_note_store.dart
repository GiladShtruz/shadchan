import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Where voice notes live: `voice_notes/` in the app's own documents.
///
/// A note stores only the file's *name* (see `PersonNote.audioFile`), and this
/// is the one place that turns a name into a file. iOS moves the app's
/// container on every update, so an absolute path written today is a path to
/// nothing after the next release; a name resolved against the current
/// documents directory is not.
///
/// **The recordings never leave the phone.** They are not in the cloud backup
/// or the JSON export — only the note that points at them is.
abstract final class VoiceNoteStore {
  static const String _folder = 'voice_notes';
  static const Uuid _uuid = Uuid();

  /// The audio kinds a shared file is accepted as. WhatsApp's voice notes are
  /// `.opus`; everything else is what a phone's recorder or another app hands
  /// over.
  static const Set<String> audioExtensions = <String>{
    '.opus',
    '.ogg',
    '.oga',
    '.m4a',
    '.aac',
    '.mp3',
    '.wav',
    '.amr',
    '.3gp',
  };

  static bool isAudioPath(String path) =>
      audioExtensions.contains(p.extension(path).toLowerCase());

  static Future<Directory> directory() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory folder = Directory(p.join(documents.path, _folder));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  static Future<File> fileFor(String name) async {
    final Directory folder = await directory();
    return File(p.join(folder.path, p.basename(name)));
  }

  /// A fresh path for the in-app recorder to write to, and the name to store.
  static Future<({String name, String path})> newRecording() async {
    final String name = 'rec_${_uuid.v4()}.m4a';
    final File file = await fileFor(name);
    return (name: name, path: file.path);
  }

  /// Copies a shared audio file in and returns the name to store, or null
  /// when it cannot be read.
  static Future<String?> importFile(String sourcePath) async {
    final File source = File(sourcePath);
    if (!await source.exists()) {
      return null;
    }
    final String extension = p.extension(sourcePath).toLowerCase();
    final String name =
        'shared_${_uuid.v4()}${extension.isEmpty ? '.opus' : extension}';
    final File target = await fileFor(name);
    await source.copy(target.path);
    return name;
  }

  static Future<void> delete(String? name) async {
    if (name == null || name.isEmpty) {
      return;
    }
    try {
      final File file = await fileFor(name);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // A recording that is already gone is the outcome that was wanted.
    }
  }
}
