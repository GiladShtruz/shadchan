import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One card this phone published for somebody else to read — a shared card
/// (`networkCards`) or a couple-space card (`partnerCards`) — as far as the
/// publisher needs to know: its photo paths, its readers (none for a
/// partner), and a print of its values.
///
/// **Why it exists (2026-11-22).** Both publishers used to read *every* card
/// they had published back from the server whenever anything they publish
/// changed — hundreds of documents for one edited friend, and for the couple
/// space the whole database on every app launch. They now keep this record
/// on the phone ([PublishedCards]) and ask the server itself once a day.
@immutable
class PublishedCard {
  const PublishedCard({
    required this.paths,
    this.readers = const <String>[],
    this.valuesPrint,
    this.data,
  });

  /// From the server's own document (values compared field by field).
  factory PublishedCard.fromServer(Map<String, dynamic> data) => PublishedCard(
    paths: <String>[
      for (final Object? p
          in (data['photoPaths'] as List?) ?? const <Object?>[])
        '$p',
    ],
    readers: <String>[
      for (final Object? r in (data['readers'] as List?) ?? const <Object?>[])
        '$r',
    ]..sort(),
    data: data,
  );

  final List<String> paths;
  final List<String> readers;

  /// The print of the values this phone wrote; null when unknown.
  final String? valuesPrint;

  /// The server's document, when this came from the server.
  final Map<String, dynamic>? data;

  /// Whether [values] (whose print is [print]) is what the server holds.
  bool sameValues(Map<String, Object?> values, String print) {
    final Map<String, dynamic>? server = data;
    if (server != null) {
      for (final MapEntry<String, Object?> e in values.entries) {
        if (jsonEncode(e.value) != jsonEncode(server[e.key])) return false;
      }
      return true;
    }
    return valuesPrint != null && valuesPrint == print;
  }

  /// The same card, its values no longer known (so it is written next time).
  PublishedCard unknownValues() =>
      PublishedCard(paths: paths, readers: readers);
}

/// [PublishedCard]s as they are kept on the phone (a device-only setting —
/// `network.held` / `partner.held` in `AccountSyncCodec`).
abstract final class PublishedCards {
  /// How often the record is checked against the server itself — which also
  /// catches a card the server changed or removed on its own.
  static const Duration verifyEvery = Duration(hours: 24);

  static Map<String, PublishedCard>? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return <String, PublishedCard>{
        for (final MapEntry<dynamic, dynamic> e in decoded.entries)
          if (e.value is Map)
            '${e.key}': PublishedCard(
              paths: <String>[
                for (final Object? p
                    in (e.value['p'] as List?) ?? const <Object?>[])
                  '$p',
              ],
              readers: <String>[
                for (final Object? r
                    in (e.value['r'] as List?) ?? const <Object?>[])
                  '$r',
              ],
              valuesPrint: e.value['f'] as String?,
            ),
      };
    } catch (_) {
      return null;
    }
  }

  static String encode(Map<String, PublishedCard> cards) =>
      jsonEncode(<String, Object?>{
        for (final MapEntry<String, PublishedCard> e in cards.entries)
          e.key: <String, Object?>{
            'p': e.value.paths,
            'r': e.value.readers,
            if (e.value.valuesPrint != null) 'f': e.value.valuesPrint,
          },
      });
}
