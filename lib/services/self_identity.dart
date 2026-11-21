import 'package:flutter/foundation.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/own_card_mirror.dart';
import 'package:shadchan/utils/phone_utils.dart';

/// Who the user is, as far as their own database is concerned — so they
/// never appear in it as one of their own friends.
///
/// A record is the user themselves when it is the old own-card mirror
/// ([OwnCardMirror.isMirror]), when it follows the user's own personal card
/// (its `cardOwnerUid` is the account's uid), or when its phone is the
/// user's own number ("המספר שלי"). Such a record is left out of every list
/// the database feeds — המאגר, search, matches, the home rows, the counts —
/// but stays readable by id, so an idea or a note that names it still opens.
/// Nothing is deleted.
abstract final class SelfIdentity {
  static String? _phone;
  static String? _uid;

  /// Bumped when what identifies the user changes; the people repository
  /// redraws its lists on it.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void update({String? phone, String? uid}) {
    final String? p = PhoneUtils.normalizeForComparison(phone);
    final String? u = (uid ?? '').trim().isEmpty ? null : uid!.trim();
    bool changed = false;
    if (phone != null || _phone != null) {
      if (p != _phone) {
        _phone = p;
        changed = true;
      }
    }
    if (u != null && u != _uid) {
      _uid = u;
      changed = true;
    }
    if (changed) revision.value++;
  }

  /// Forgets the account (sign-out).
  static void clear() {
    if (_phone == null && _uid == null) return;
    _phone = null;
    _uid = null;
    revision.value++;
  }

  static bool isSelf(Person person) {
    if (OwnCardMirror.isMirror(person.id)) return true;
    final String? uid = _uid;
    if (uid != null && person.cardOwnerUid == uid) return true;
    final String? phone = _phone;
    // A real number only: a stray "123" is nobody.
    if (phone != null &&
        phone.length >= 9 &&
        PhoneUtils.normalizeForComparison(person.phone) == phone) {
      return true;
    }
    return false;
  }

  /// Whether [phone] is the user's own number.
  static bool isOwnPhone(String? phone) {
    final String? mine = _phone;
    if (mine == null || mine.length < 9) return false;
    return PhoneUtils.normalizeForComparison(phone) == mine;
  }

  @visibleForTesting
  static void reset() {
    _phone = null;
    _uid = null;
  }
}
