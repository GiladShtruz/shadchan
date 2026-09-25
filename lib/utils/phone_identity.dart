import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shadchan/utils/phone_utils.dart';

/// How a phone number is recognised across accounts without being stored in
/// the clear: one canonical form, then a hash of it.
///
/// `050-1234567`, `+972 50 123 4567` and `0501234567` are one person, so all
/// of them reduce to the same local ten-digit form before hashing — that is
/// what lets a matchmaker's copy of a friend recognise the friend's own card,
/// and a card owner's address book recognise a matchmaker.
///
/// **The hash hides a number from a casual reader, not from a determined
/// one.** Israeli mobile numbers are a small space and anybody with the app
/// could hash all of them. It keeps numbers out of plain sight in the
/// database; it is not a secret, and nothing in the rules treats it as one.
abstract final class PhoneIdentity {
  /// Bumping this invalidates every published hash at once, which is the only
  /// way the scheme can ever change.
  static const String _salt = 'shadchan-phone-v1:';

  /// The number in the one form everything else uses, or null when it is not
  /// a number that can identify anybody (too short, empty).
  static String? canonical(String? raw) {
    final String? local = PhoneUtils.normalizeForComparison(raw);
    if (local == null || local.length < 9) {
      return null;
    }
    return local;
  }

  /// The published identity of a number. Truncated to 24 hex characters — 96
  /// bits is far past any collision a phone book can produce, and a card
  /// owner's whole address book has to fit in one document.
  static String? hash(String? raw) {
    final String? number = canonical(raw);
    if (number == null) {
      return null;
    }
    final Digest digest = sha256.convert(utf8.encode('$_salt$number'));
    return digest.toString().substring(0, 24);
  }
}
