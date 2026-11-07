import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/connectivity_status.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// Thrown by a repository asked to save something while the app is offline.
///
/// The flow that asked simply stops where it is — nothing after the save runs,
/// so no screen goes on to say "נשמר". [OfflineGuard] has already told the
/// user why by the time anybody sees this.
class OfflineWriteBlocked implements Exception {
  const OfflineWriteBlocked();

  @override
  String toString() => 'OfflineWriteBlocked';
}

/// No edits while offline.
///
/// **A product rule, not a technical one.** The database would happily take a
/// change offline and send it later. The decision is that a matchmaker with no
/// connection is looking at the last version the server agreed to, and that a
/// change made then must never *look* saved. So every action that changes
/// something is either stopped before it starts ([allow], at the button), or
/// refused at the repository ([ensureCanWrite]) if it slipped through — and
/// either way the same sentence explains it.
///
/// **What is not blocked:** reading, searching, filtering and moving between
/// screens, and everything the app writes by itself — the sync applying what
/// arrived, a card copied from a friend, migrations at launch. Those run
/// inside [exempt], or never pass through a guarded method at all.
abstract final class OfflineGuard {
  static const String messageTemplate =
      '{שים|שימי} לב, {אתה|את} במצב לא מקוון. עריכות לא יישמרו.';

  static const Symbol _exemptKey = #offlineGuardExempt;

  static DateTime? _lastShown;

  /// The app's root navigator, for a refusal that comes from a repository and
  /// so has no context of its own. Set once by `App`.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// True while user edits are refused.
  static bool get blocking =>
      ConnectivityStatus.isOffline && Zone.current[_exemptKey] != true;

  /// For a button that is about to start an edit: true when it may go ahead.
  /// Offline, it says why not and answers false.
  static bool allow(BuildContext context) {
    if (!blocking) {
      return true;
    }
    _notify(AppNotice.capture(context), _genderOf(context));
    return false;
  }

  /// For a screen whose only purpose is an edit (a form, an add-friends
  /// flow): opened while offline, it says why and closes itself after its
  /// first frame. The buttons that lead here already check with [allow]; this
  /// covers every other way in — a link, a notification, a route pushed from
  /// somewhere nobody remembered.
  static void leaveIfOffline(State<StatefulWidget> state) {
    if (!blocking) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!state.mounted || allow(state.context)) {
        return;
      }
      final NavigatorState navigator = Navigator.of(state.context);
      if (navigator.canPop()) {
        navigator.pop();
      }
    });
  }

  /// For a repository about to write: throws [OfflineWriteBlocked] (after
  /// saying why) when the write must not happen.
  static void ensureCanWrite() {
    if (!blocking) {
      return;
    }
    final BuildContext? context = navigatorKey?.currentContext;
    _notify(
      navigatorKey?.currentState?.overlay,
      context == null ? null : _genderOf(context),
    );
    throw const OfflineWriteBlocked();
  }

  /// Runs [body] with the guard off — for writes the app makes by itself.
  static Future<T> exempt<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: <Object?, Object?>{_exemptKey: true});

  static Gender? _genderOf(BuildContext context) {
    try {
      return Provider.of<UserProfileProvider>(context, listen: false).gender;
    } on Object {
      return null;
    }
  }

  /// One notice per moment: a screen that tries three writes in a row (an
  /// editor saving every field as focus leaves it) says it once.
  static void _notify(OverlayState? overlay, Gender? gender) {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastShown;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) {
      return;
    }
    _lastShown = now;
    AppNotice.showOn(overlay, messageTemplate.forGender(gender), isError: true);
  }

  @visibleForTesting
  static void debugReset() => _lastShown = null;
}
