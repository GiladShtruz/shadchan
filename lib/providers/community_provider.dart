import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/community_counts.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/dating_history.dart';

/// The community layer as the screens see it.
///
/// It owns two things and deliberately no more: **this device's own counts**,
/// which are recomputed locally and cost nothing, and **when to publish them**,
/// which is twice a session. Everything shared — the community totals and the
/// leaderboard — is read straight from [CommunityService], which does its own
/// caching; there is no second copy of it here to go stale.
///
/// [myCounts] is available with no network at all. That is the point: the home
/// block and the personal side of the activity screen work on a plane, and only
/// the community column waits for anything.
class CommunityProvider extends ChangeNotifier {
  CommunityProvider();

  CommunityMemberCounts? _counts;
  bool _hidden = CommunityProfileStore.isHidden;
  bool _private = CommunityProfileStore.isPrivate;
  bool _publishing = false;
  bool _pulledHidden = false;
  String _name = '';

  /// This device's own figures, or null before the first refresh.
  CommunityMemberCounts? get myCounts => _counts;

  /// Whether the matchmaker has taken themselves off the leaderboard — or has
  /// simply not been asked yet, or has switched sharing off altogether, all of
  /// which come to the same thing here: no name of theirs on the board.
  bool get isHidden => _hidden || _private;

  /// Whether "שמור על הפרטיות שלי" is on — nothing about this matchmaker is
  /// published to the community at all. See [CommunityProfileStore.isPrivate].
  bool get isPrivate => _private;

  /// Turns sharing off, or back on.
  ///
  /// **Turning it on deletes what is already there.** A switch that only stops
  /// *future* writes would leave this week's counters and a name sitting in a
  /// collection every installed copy of the app can read, which is not what
  /// anybody who reaches for a privacy switch is asking for. Turning it back on
  /// republishes immediately from the counts already in hand, so the matchmaker
  /// does not have to close the app to rejoin.
  Future<void> setPrivate(bool private) async {
    if (_private == private) {
      return;
    }
    _private = private;
    CommunityProfileStore.setPrivate(private);
    CommunityService.invalidate();
    notifyListeners();

    if (private) {
      await CommunityService.deleteMyData();
      return;
    }
    final CommunityMemberCounts? counts = _counts;
    if (counts != null) {
      await CommunityService.publish(
        counts: counts,
        name: _name,
        hidden: _hidden,
      );
      CommunityService.invalidate();
      notifyListeners();
    }
  }

  /// Whether the one-time "may your name appear on the leaderboard?" question
  /// still needs asking.
  bool get needsLeaderboardConsent =>
      !CommunityProfileStore.hasAnsweredLeaderboardConsent;

  /// Records the answer and pushes it straight to the server, so a "no" takes
  /// effect without waiting for the next publish.
  Future<void> answerLeaderboardConsent({required bool hidden}) async {
    CommunityProfileStore.answerLeaderboardConsent(hidden: hidden);
    _hidden = hidden;
    CommunityService.invalidate();
    notifyListeners();
    await CommunityService.setHidden(hidden, name: _name);
  }

  /// Erases this account's row from the shared collection.
  ///
  /// Hidden first, then deleted: the next publish will recreate the row, and it
  /// must not recreate it with a name in it.
  Future<bool> deleteMyCommunityData() async {
    CommunityProfileStore.answerLeaderboardConsent(hidden: true);
    _hidden = true;
    notifyListeners();
    return CommunityService.deleteMyData();
  }

  /// Recomputes the local counts and, if Firebase is up, publishes them.
  ///
  /// Called from the two lifecycle moments the cloud backup already uses. It is
  /// safe to call repeatedly: every figure is derived from the ledgers rather
  /// than incremented, so a double call writes the same numbers again.
  Future<void> refresh({
    required PersonRepository people,
    required MatchRepository matches,
    required UserProfileProvider profile,
  }) async {
    _name = profile.name ?? '';
    final CommunityMemberCounts counts = CommunityCounts.build(
      people: people.getAll(),
      matches: matches.getAll(),
      matchStatusEvents: matches.getAllStatusEvents(),
      excludedFromDating: DatingCountExclusions.all(),
    );
    _counts = counts;
    // A personal number, kept whatever happens to the network. Nothing is
    // announced: `CommunityProfileStore.bestWeek` is read by the activity
    // screen, which is where somebody looking at their own figures will see it.
    CommunityProfileStore.recordWeek(counts.week.points);
    notifyListeners();

    // Nothing leaves the device for somebody who asked for nothing to. The
    // counts above were still computed, because every personal figure in the
    // app is drawn from them and none of that is anybody else's business.
    if (_private || _publishing || !FirebaseBootstrap.isReady) {
      return;
    }
    _publishing = true;
    try {
      // The opt-out is authoritative on the server, because it has to survive
      // a reinstall — but only the first time, and only if this device has not
      // been told otherwise since.
      if (!_pulledHidden) {
        _pulledHidden = true;
        final bool? stored = await CommunityService.fetchHidden();
        if (stored != null && stored != _hidden) {
          _hidden = stored;
          CommunityProfileStore.setHidden(stored);
          notifyListeners();
        }
      }

      await CommunityService.publish(
        counts: counts,
        name: _name,
        hidden: _hidden,
      );
      // This device's own numbers have just moved, so every cached community
      // figure is one publish out of date.
      CommunityService.invalidate();
    } finally {
      _publishing = false;
    }
  }

  /// Takes the matchmaker off the leaderboard, or puts them back.
  ///
  /// Written locally first so the screen answers immediately; the server write
  /// follows and is retried by the next publish if it fails.
  Future<void> setHidden(bool hidden) async {
    if (_hidden == hidden) {
      return;
    }
    _hidden = hidden;
    CommunityProfileStore.setHidden(hidden);
    CommunityService.invalidate();
    notifyListeners();
    unawaited(CommunityService.setHidden(hidden, name: _name));
  }

  /// This device's own breakdown for [period] — zeroes before the first
  /// refresh, which is what a brand-new install genuinely has.
  ActivityBreakdown myBreakdown(CommunityPeriod period) =>
      _counts?.forPeriod(period) ?? ActivityBreakdown.empty;

  /// This device's score for [period], or zero before the first refresh.
  int myPoints(CommunityPeriod period) => myBreakdown(period).points;
}
