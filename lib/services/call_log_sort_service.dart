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

    // Adding contacts is the one place we may prompt for the call-log
    // permission, since the recent-call order materially improves the import.
    return applyOrder(
      candidates,
      await loadRecentCallOrderRequestingPermission(),
    );
  }

  /// Sorts an already-loaded list by an already-loaded call-log [order].
  ///
  /// Split out from [sortByRecentCalls] so the add-contacts screen can put its
  /// cached list on the screen *first* and reorder it when the call log
  /// answers, instead of holding the first frame behind a method channel that
  /// reads the whole device call log and may raise a permission dialog. That
  /// wait was the several seconds of blank screen after "הוספה מאנשי קשר".
  ///
  /// An empty [order] means the call log was unavailable, unreadable or
  /// refused; the list keeps whatever order it arrived in, which is by name.
  static List<ContactImportCandidate> applyOrder(
    List<ContactImportCandidate> candidates,
    Map<String, int> order,
  ) {
    if (candidates.isEmpty || order.isEmpty) {
      return candidates;
    }

    final List<ContactImportCandidate> sorted =
        List<ContactImportCandidate>.from(candidates);
    sorted.sort((ContactImportCandidate a, ContactImportCandidate b) {
      final int? aIndex = order[a.normalizedPhone];
      final int? bIndex = order[b.normalizedPhone];

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

  /// Returns a map of normalized phone number -> recency index (0 = most
  /// recently called) **only when the `READ_CALL_LOG` permission is already
  /// granted** — it never prompts. Empty when the call log is unavailable, the
  /// permission is missing, or on iOS (where the call log can't be read). The
  /// permission is requested elsewhere, only while adding contacts.
  static Future<Map<String, int>> loadRecentCallOrder() =>
      _loadOrder('getRecentCallNumbersIfGranted');

  /// Like [loadRecentCallOrder] but may request the `READ_CALL_LOG` permission.
  /// Only call this from the add-contacts flow, where prompting is expected.
  static Future<Map<String, int>> loadRecentCallOrderRequestingPermission() =>
      _loadOrder('getRecentCallNumbers');

  static Future<Map<String, int>> _loadOrder(String method) async {
    try {
      final List<dynamic>? rawNumbers = await _channel.invokeListMethod(method);
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
