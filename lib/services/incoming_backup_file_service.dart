import 'dart:async';

import 'package:flutter/services.dart';

abstract class IncomingBackupFilesSource {
  Future<List<String>> takePendingFilePaths();

  Stream<String> get incomingFiles;
}

class IncomingBackupFileService implements IncomingBackupFilesSource {
  IncomingBackupFileService._();

  static final IncomingBackupFileService instance =
      IncomingBackupFileService._();

  static const MethodChannel _methodChannel = MethodChannel(
    'shadchan/incoming_backup_files/methods',
  );
  static const EventChannel _eventChannel = EventChannel(
    'shadchan/incoming_backup_files/events',
  );

  Stream<String>? _incomingFilesStream;

  @override
  Future<List<String>> takePendingFilePaths() async {
    try {
      final List<dynamic>? rawPaths = await _methodChannel
          .invokeMethod<List<dynamic>>('takePendingFilePaths');
      if (rawPaths == null) {
        return const <String>[];
      }

      return rawPaths
          .whereType<String>()
          .where((String path) => path.isNotEmpty)
          .toList();
    } on MissingPluginException {
      return const <String>[];
    } on PlatformException {
      return const <String>[];
    }
  }

  @override
  Stream<String> get incomingFiles {
    return _incomingFilesStream ??= _eventChannel
        .receiveBroadcastStream()
        .handleError((Object error, StackTrace stackTrace) {})
        .where((dynamic event) => event is String && event.isNotEmpty)
        .map((dynamic event) => event as String)
        .asBroadcastStream();
  }
}
