import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// The answer to "איך תרצה להשתמש בשדכן?", chosen before signing in.
///
/// It only decides how sign-up goes; afterwards the two capabilities live on
/// their own ([WorkspaceStore.matchmakerEnabled] and the profile's
/// `isSingle`) and can each be changed from the profile.
enum EntryRoute {
  /// "שדכן/ית" — the matchmaker's database, ideas and community.
  matchmaker,

  /// "רווק/ה" — a personal card and the matchmakers who see it.
  cardOwner,

  /// "רווק/ה וגם שדכן/ית" — both, in one account and one app.
  both;

  bool get wantsCard => this != EntryRoute.matchmaker;
  bool get wantsMatchmaking => this != EntryRoute.cardOwner;

  static EntryRoute? byName(Object? name) {
    for (final EntryRoute route in EntryRoute.values) {
      if (route.name == name) {
        return route;
      }
    }
    return null;
  }
}

/// **One user, one account, one app.** There are no "areas" any more — no
/// personal area beside a matchmaker's area and no button between them. What
/// differs between users is only which capabilities are switched on:
///
/// * the matchmaker's tools ([matchmakerEnabled]) — the database, the ideas,
///   partner matchmakers;
/// * a personal card (the profile's `isSingle`) — the card, its status and
///   the matchmakers who see it.
///
/// Either or both; never neither (the profile refuses to switch off the last
/// one). Both live in the `settings` box and travel with the account, so a
/// second phone opens with the same app.
///
/// **Local, like [SignInPromptStore], and for the same reason:** the router
/// reads it on the first frame. Every write goes through [persistHomeSetting]
/// so a write triggered from a widget test's fake-async zone cannot hang
/// `Hive.close()`; `_pending` covers the frame before the write lands.
abstract final class WorkspaceStore {
  static const String _entryKey = 'workspace.entry';
  static const String _matchmakerKey = 'workspace.matchmakerEnabled';

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  static final Map<String, Object?> _pending = <String, Object?>{};

  /// Drops values read ahead of the box, after another phone changed it.
  static void forgetCache() => _pending.clear();

  /// Bumped on every change, so the shell can redraw its bottom bar the moment
  /// the matchmaker's tools are switched on or off.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Object? _read(String key) =>
      _pending.containsKey(key) ? _pending[key] : _box?.get(key);

  static void _write(String key, Object value) {
    _pending[key] = value;
    persistHomeSetting(key, value.toString());
    revision.value++;
  }

  @visibleForTesting
  static void resetForTest() {
    _pending.clear();
    revision.value++;
  }

  /// The answer picked before signing in, or null when nothing was picked —
  /// which is also every install from before the choice existed, and those
  /// are matchmakers.
  static EntryRoute? get entryRoute => EntryRoute.byName(_read(_entryKey));

  static void chooseEntry(EntryRoute route) => _write(_entryKey, route.name);

  /// Whether the matchmaker's tools are switched on for this account.
  ///
  /// True unless somebody signed up as a single only. Everybody who used the
  /// app before the personal card existed is a matchmaker, and the absence of
  /// the key has to say so.
  static bool get matchmakerEnabled {
    final Object? value = _read(_matchmakerKey);
    return !(value == false || value == 'false');
  }

  static void setMatchmakerEnabled(bool enabled) =>
      _write(_matchmakerKey, enabled);

  /// Forgets everything, for a sign-out: the next person on the phone chooses
  /// their own way in.
  static Future<void> reset() async {
    _pending.clear();
    await _box?.deleteAll(<String>[
      _entryKey,
      _matchmakerKey,
      // Keys of the retired two-area model, cleared with the rest.
      'workspace.lastArea',
      'workspace.homeArea',
    ]);
    revision.value++;
  }
}
