import 'dart:async';

import 'package:flutter/services.dart';

class IncomingSharedProfileDraft {
  const IncomingSharedProfileDraft({
    required this.id,
    required this.text,
    required this.filePaths,
  });

  final String id;
  final String? text;
  final List<String> filePaths;

  bool get hasText => text != null && text!.trim().isNotEmpty;
  bool get hasFiles => filePaths.isNotEmpty;
  bool get hasContent => hasText || hasFiles;

  factory IncomingSharedProfileDraft.fromMap(Map<dynamic, dynamic> map) {
    return IncomingSharedProfileDraft(
      id: (map['id'] as String?)?.trim().isNotEmpty == true
          ? map['id'] as String
          : DateTime.now().microsecondsSinceEpoch.toString(),
      text: _normalizedText(map['text']),
      filePaths: (map['filePaths'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .where((String path) => path.trim().isNotEmpty)
          .toList(),
    );
  }

  static String? _normalizedText(Object? value) {
    final String? text = value as String?;
    final String trimmed = text?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

abstract class IncomingSharedProfileSource {
  Future<List<IncomingSharedProfileDraft>> takePendingDrafts();

  Stream<IncomingSharedProfileDraft> get incomingDrafts;
}

class IncomingSharedProfileService implements IncomingSharedProfileSource {
  IncomingSharedProfileService._();

  static final IncomingSharedProfileService instance =
      IncomingSharedProfileService._();

  static const MethodChannel _methodChannel = MethodChannel(
    'shadchan/incoming_shared_profiles/methods',
  );
  static const EventChannel _eventChannel = EventChannel(
    'shadchan/incoming_shared_profiles/events',
  );

  Stream<IncomingSharedProfileDraft>? _incomingDraftsStream;

  @override
  Future<List<IncomingSharedProfileDraft>> takePendingDrafts() async {
    try {
      final List<dynamic>? rawDrafts = await _methodChannel
          .invokeMethod<List<dynamic>>('takePendingDrafts');
      if (rawDrafts == null) {
        return const <IncomingSharedProfileDraft>[];
      }

      return rawDrafts
          .whereType<Map<dynamic, dynamic>>()
          .map(IncomingSharedProfileDraft.fromMap)
          .where((IncomingSharedProfileDraft draft) => draft.hasContent)
          .toList();
    } on MissingPluginException {
      return const <IncomingSharedProfileDraft>[];
    } on PlatformException {
      return const <IncomingSharedProfileDraft>[];
    }
  }

  @override
  Stream<IncomingSharedProfileDraft> get incomingDrafts {
    return _incomingDraftsStream ??= _eventChannel
        .receiveBroadcastStream()
        .handleError((Object error, StackTrace stackTrace) {})
        .where((dynamic event) => event is Map<dynamic, dynamic>)
        .map(
          (dynamic event) => IncomingSharedProfileDraft.fromMap(
            event as Map<dynamic, dynamic>,
          ),
        )
        .where((IncomingSharedProfileDraft draft) => draft.hasContent)
        .asBroadcastStream();
  }
}
