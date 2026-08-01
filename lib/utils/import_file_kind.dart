import 'package:path/path.dart' as p;

/// What an incoming file is meant to be read as.
enum ImportFileKind {
  excel,

  /// A WhatsApp chat export — the `.zip` with its media, or the bare `.txt`.
  whatsapp,

  /// A plain list or a block of text holding several people.
  peopleText,
}

/// Decides whether a shared file is something the AI import can read, and what
/// to suggest it is.
///
/// The suggestion is only ever a default for the question put to the user. An
/// extension says how a file is encoded, not what is inside it: a `.txt` is as
/// likely to be a chat export as a typed list, and a `.zip` that is not a chat
/// export would otherwise be fed to the wrong parser and come back empty with
/// no explanation.
abstract final class ImportFileKinds {
  static const Set<String> supportedExtensions = <String>{
    '.xlsx',
    '.xlsm',
    '.zip',
    '.txt',
  };

  static bool isSupported(String path) =>
      supportedExtensions.contains(p.extension(path).toLowerCase());

  static String? firstSupported(Iterable<String> paths) {
    for (final String path in paths) {
      if (isSupported(path)) {
        return path;
      }
    }
    return null;
  }

  /// The kind to preselect for [path].
  static ImportFileKind suggestFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.xlsx':
      case '.xlsm':
        return ImportFileKind.excel;
      case '.zip':
        return ImportFileKind.whatsapp;
      default:
        return ImportFileKind.whatsapp;
    }
  }

  /// The kinds worth offering for [path]. A spreadsheet is only ever a
  /// spreadsheet; a `.txt` or `.zip` genuinely could be either.
  static List<ImportFileKind> optionsFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.xlsx':
      case '.xlsm':
        return const <ImportFileKind>[ImportFileKind.excel];
      case '.zip':
        return const <ImportFileKind>[ImportFileKind.whatsapp];
      default:
        return const <ImportFileKind>[
          ImportFileKind.whatsapp,
          ImportFileKind.peopleText,
        ];
    }
  }

  static String titleOf(ImportFileKind kind) => switch (kind) {
    ImportFileKind.excel => 'טבלת אנשים',
    ImportFileKind.whatsapp => 'ייצוא צ׳אט מוואטסאפ',
    ImportFileKind.peopleText => 'רשימת אנשים בטקסט',
  };

  static String subtitleOf(ImportFileKind kind) => switch (kind) {
    ImportFileKind.excel => 'גיליון עם שורה לכל אדם',
    ImportFileKind.whatsapp => 'שיחה שיוצאה מוואטסאפ, עם או בלי תמונות',
    ImportFileKind.peopleText => 'כרטיסיות או רשימה שנכתבו כטקסט חופשי',
  };
}
