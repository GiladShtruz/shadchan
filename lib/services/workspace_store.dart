import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// The route somebody chose on "ברוך הבא!" before signing in.
enum EntryRoute {
  matchmaker,
  cardOwner;

  static EntryRoute? byName(Object? name) {
    for (final EntryRoute route in EntryRoute.values) {
      if (route.name == name) {
        return route;
      }
    }
    return null;
  }
}

/// Which of the two work areas the app opens on.
enum WorkArea {
  /// The matchmaker's tabs: בית, המאגר שלי, הרעיונות שלי, פרופיל.
  matchmaker,

  /// The card owner's own page, with no matchmaker navigation.
  personal;

  static WorkArea? byName(Object? name) {
    for (final WorkArea area in WorkArea.values) {
      if (area.name == name) {
        return area;
      }
    }
    return null;
  }
}

/// One account, two areas: the matchmaker system that always existed and the
/// card owner's personal area. This remembers which of them this device has
/// switched on and which one it was last in.
///
/// **Local, like [SignInPromptStore], and for the same reason:** the router
/// reads it on the first frame. Every write goes through [persistHomeSetting]
/// so a write triggered from a widget test's fake-async zone cannot hang
/// `Hive.close()`; `_pending` covers the frame before the write lands.
abstract final class WorkspaceStore {
  static const String _entryKey = 'workspace.entry';
  static const String _matchmakerKey = 'workspace.matchmakerEnabled';
  static const String _lastAreaKey = 'workspace.lastArea';
  static const String _homeAreaKey = 'workspace.homeArea';

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  static final Map<String, Object?> _pending = <String, Object?>{};

  /// Bumped on every change, so the shell can redraw its bottom bar the moment
  /// the matchmaker area is switched on or off.
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

  /// The route picked before signing in, or null when nothing was picked —
  /// which is also every install from before the choice existed, and those
  /// are matchmakers.
  static EntryRoute? get entryRoute => EntryRoute.byName(_read(_entryKey));

  static void chooseEntry(EntryRoute route) => _write(_entryKey, route.name);

  /// Whether the matchmaker system is switched on for this account.
  ///
  /// True unless somebody signed up as a card owner only. Everybody who used
  /// the app before the personal area existed is a matchmaker, and the absence
  /// of the key has to say so.
  static bool get matchmakerEnabled {
    final Object? value = _read(_matchmakerKey);
    return !(value == false || value == 'false');
  }

  static void setMatchmakerEnabled(bool enabled) =>
      _write(_matchmakerKey, enabled);

  /// The area the app opens on next launch.
  ///
  /// Only an explicit move changes it — entering the personal area, or the
  /// "לעבור לאזור השדכן" button. Opening a setting, a notification or any
  /// inner screen does not, so a launch never lands on some sub-page.
  static WorkArea get lastArea {
    if (!matchmakerEnabled) {
      return WorkArea.personal;
    }
    return WorkArea.byName(_read(_lastAreaKey)) ?? WorkArea.matchmaker;
  }

  static void setLastArea(WorkArea area) {
    if (WorkArea.byName(_read(_lastAreaKey)) == area) {
      return;
    }
    _write(_lastAreaKey, area.name);
  }

  /// The page somebody with **both** areas chose as their home page, or null
  /// while they have not been asked (or have only one area).
  ///
  /// Asked once, the first time both areas exist ([HomeAreaPrompt]), and
  /// changed later from the settings. It decides where a launch opens; see
  /// [launchArea].
  static WorkArea? get homeArea => WorkArea.byName(_read(_homeAreaKey));

  static void setHomeArea(WorkArea area) => _write(_homeAreaKey, area.name);

  /// Where a launch opens: the chosen home page when there is one, else the
  /// area the user was last in. A card-only user always opens on their own.
  static WorkArea get launchArea {
    if (!matchmakerEnabled) {
      return WorkArea.personal;
    }
    return homeArea ?? lastArea;
  }

  /// Forgets everything, for a sign-out: the next person on the phone chooses
  /// their own route.
  static Future<void> reset() async {
    _pending.clear();
    await _box?.deleteAll(<String>[
      _entryKey,
      _matchmakerKey,
      _lastAreaKey,
      _homeAreaKey,
    ]);
    revision.value++;
  }
}
