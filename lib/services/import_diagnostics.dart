import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';

/// A record of one import attempt, written as it happens, so a failure can be
/// described by the person it happened to.
///
/// The AI import is the only feature in the app whose failures are not
/// reproducible here: it depends on the device's memory, its free storage, its
/// Play Integrity verdict and on an export file nobody else has a copy of. A
/// user reporting "it doesn't work" therefore hands over nothing actionable,
/// and the same report arrives from four unrelated causes. This collects the
/// handful of facts that separate them.
///
/// **Nothing personal goes in.** Not the file's name (a WhatsApp export is
/// named after the group, which names the user's contacts), not a message, not
/// a person, not a photo. Sizes, counts, error types. The dialog shows the
/// whole text before anything is sent, because a promise about what is in it is
/// worth less than the text itself.
class ImportDiagnostics {
  ImportDiagnostics(this.source);

  /// Which import was running — "וואטסאפ" or "אקסל". Free text; it is only
  /// ever read by a person.
  final String source;

  final DateTime startedAt = DateTime.now();
  final List<String> _lines = <String>[];

  /// Paths get redacted out of error messages, so the directory holding them
  /// has to be known. Set once the file is chosen.
  String? _sourcePath;
  String? _mediaDirName;

  static PackageInfo? _packageInfo;

  /// Read once, early, so the report is never missing the version because the
  /// lookup had not finished at the moment something failed.
  static Future<void> warmUp() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
  }

  void note(String label, Object? value) {
    _lines.add('$label: $value');
  }

  void noteFile(String path, int bytes) {
    _sourcePath = path;
    _mediaDirName = 'whatsapp_import_media';
    // The extension and the size, never the name.
    final int dot = path.lastIndexOf('.');
    note('סוג', dot == -1 ? 'ללא סיומת' : path.substring(dot).toLowerCase());
    note('גודל', formatBytes(bytes));
  }

  /// The finished report, ready to be shown and sent.
  String build({required String problem}) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('דיווח תקלה — ייבוא $source')
      ..writeln('---')
      ..writeln('בעיה: $problem');
    for (final String line in _lines) {
      buffer.writeln(line);
    }
    buffer
      ..writeln('משך: ${DateTime.now().difference(startedAt).inSeconds} שניות')
      ..writeln('גרסה: ${_versionLine()}')
      ..writeln('מכשיר: ${_deviceLine()}')
      ..writeln('התקנה: ${_installerLine()}')
      ..writeln('חתימה: ${_signatureLine()}')
      ..writeln('firebase: ${FirebaseBootstrap.isReady ? 'תקין' : 'לא עלה'}')
      ..writeln('appCheck: ${_appCheckLine()}');
    final String? uid = FirebaseBootstrap.uid;
    if (uid != null) {
      buffer.writeln('uid: $uid');
    }
    buffer.write('זמן: ${startedAt.toIso8601String().substring(0, 19)}');
    return buffer.toString();
  }

  /// An error reduced to what is safe and useful: its type and its message with
  /// every device path taken out.
  ///
  /// A `FileSystemException` prints the path it failed on, and that path ends
  /// in the export's file name — which is the group's name. Redacting here
  /// rather than at the dialog means a path can never reach the report by some
  /// route nobody thought of.
  String describeError(Object error) =>
      '${error.runtimeType}: ${redact(error.toString())}';

  /// [describeError] without the type, for a cause that arrived already
  /// flattened to text — a `WhatsAppReadException` crossing back from the
  /// worker isolate has no live error object left to name.
  String redact(String raw) {
    String text = raw;
    final String? path = _sourcePath;
    if (path != null) {
      text = text.replaceAll(path, '<הקובץ>');
      final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
      if (slash != -1) {
        text = text.replaceAll(path.substring(slash + 1), '<הקובץ>');
      }
    }
    final String? mediaDir = _mediaDirName;
    if (mediaDir != null) {
      text = text.replaceAll(
        RegExp('[^\\s]*$mediaDir[^\\s]*'),
        '<תיקיית מדיה>',
      );
    }
    text = text.replaceAll(RegExp(r'/(?:data|storage|var)/\S+'), '<נתיב>');
    if (text.length > 300) {
      text = '${text.substring(0, 300)}…';
    }
    return text;
  }

  static String _versionLine() {
    final PackageInfo? info = _packageInfo;
    if (info == null) {
      return 'לא ידועה';
    }
    return '${info.version}+${info.buildNumber}${kDebugMode ? ' (debug)' : ''}';
  }

  /// Where the install came from, which decides whether Play Integrity can
  /// attest it at all: an APK passed around by hand is not a build Play knows,
  /// so its attestation fails on a working phone with a correct configuration.
  static String _installerLine() {
    final String? store = _packageInfo?.installerStore;
    if (store == null || store.isEmpty) {
      return 'לא מחנות (הותקן ידנית)';
    }
    return store == 'com.android.vending' ? 'Google Play' : store;
  }

  /// The SHA-256 of the certificate that actually signed *this* install.
  ///
  /// The one fact no console can tell us and every one of these failures turns
  /// on. A build downloaded from Play is signed by Play's own key, not by the
  /// upload key — so a project that only knows the upload key's fingerprint
  /// refuses exactly the installs that came from the store, which is every real
  /// user and none of the developers.
  static String _signatureLine() {
    final String signature = _packageInfo?.buildSignature ?? '';
    return signature.isEmpty ? 'לא ידועה' : signature;
  }

  /// Whether this device can attest, and what it said when it could not.
  String _appCheckLine() {
    final String? error = FirebaseBootstrap.appCheckError;
    return error == null ? 'תקין' : redact(error);
  }

  static String _deviceLine() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } on Object {
      return 'לא ידוע';
    }
  }

  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).round()} KB';
    }
    return '$bytes B';
  }
}
