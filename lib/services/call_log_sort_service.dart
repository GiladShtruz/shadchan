import 'package:flutter/services.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/utils/phone_utils.dart';

abstract final class CallLogSortService {
  static const MethodChannel _channel = MethodChannel('shadchan/call_log');

  static Future<List<ContactImportCandidate>> sortByRecentCalls(
    List<ContactImportCandidate> candidates,
  ) async {
    if (candidates.isEmpty) {
      return candidates;
    }

    final Map<String, int> recentCallOrder = await _loadRecentCallOrder();
    if (recentCallOrder.isEmpty) {
      return candidates;
    }

    final List<ContactImportCandidate> sorted =
        List<ContactImportCandidate>.from(candidates);
    sorted.sort((ContactImportCandidate a, ContactImportCandidate b) {
      final int? aIndex = recentCallOrder[a.normalizedPhone];
      final int? bIndex = recentCallOrder[b.normalizedPhone];

      if (aIndex != null && bIndex != null) {
        return aIndex.compareTo(bIndex);
      }
      if (aIndex != null) {
        return -1;
      }
      if (bIndex != null) {
        return 1;
      }

      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    return sorted;
  }

  static Future<Map<String, int>> _loadRecentCallOrder() async {
    try {
      final List<dynamic>? rawNumbers = await _channel.invokeListMethod(
        'getRecentCallNumbers',
      );
      if (rawNumbers == null || rawNumbers.isEmpty) {
        return const <String, int>{};
      }

      final Map<String, int> order = <String, int>{};
      for (final Object? rawNumber in rawNumbers) {
        final String? normalizedPhone = PhoneUtils.normalizeForComparison(
          rawNumber?.toString(),
        );
        if (normalizedPhone == null ||
            order.containsKey(normalizedPhone) ||
            !ContactsImportService.isSuggestedMobilePhone(normalizedPhone)) {
          continue;
        }

        order[normalizedPhone] = order.length;
      }

      return order;
    } on PlatformException {
      return const <String, int>{};
    } on MissingPluginException {
      return const <String, int>{};
    }
  }
}
