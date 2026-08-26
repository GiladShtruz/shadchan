import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shadchan/models/community_profile.dart';
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
  /// [connect] exists only so a widget test can build the app without it.
  ///
  /// `Firebase.initializeApp` never completes inside `testWidgets`' fake-async
  /// zone — the platform channel has no other side to reply from — so
  /// `ensureReady`'s 30-second deadline is left pending and fails the test with
  /// a pending timer. Passing `() async {}` skips the attempt; `isReady` is
  /// false either way, which is the state under test. The same seam is on
  /// `AccountProvider` and `SyncProvider`, for the same reason.
  CommunityProvider({Future<void> Function()? connect})
    : _connect = connect ?? FirebaseBootstrap.ensureReady;

  final Future<void> Function() _connect;

  CommunityMemberCounts? _counts;
  bool _hidden = CommunityProfileStore.isHidden;
  bool _private = CommunityProfileStore.isPrivate;
  bool _publishing = false;
  bool _pulledHidden = false;
  int _publishRevision = 0;
  String _name = '';
  String? _photoPath;
  String _about = '';
  List<MatchmakerShare> _shares = const <MatchmakerShare>[];
  String _benefit = '';
  String _contactPhone = '';

  /// This device's own figures, or null before the first refresh.
  CommunityMemberCounts? get myCounts => _counts;

  /// Bumped once per successful publish.
  ///
  /// Anything drawing community figures watches this and re-reads when it
  /// moves: the shared numbers are known to have changed at exactly that
  /// moment, and — more importantly — the read that filled the screen may have
  /// happened before there was an account at all and come back with nothing.
  int get publishRevision => _publishRevision;

  /// Whether the matchmaker has taken themselves off the leaderboard, or has
  /// switched sharing off altogether — both come to the same thing here: no
  /// name of theirs on the board. Neither is the default; a matchmaker appears
  /// under their name until they ask not to.
  bool get isHidden => _hidden || _private;

  /// Whether "שמור על הפרטיות שלי" is on — nothing about this matchmaker is
  /// published to the community at all. See [CommunityProfileStore.isPrivate].
  bool get isPrivate => _private;

  /// Drops everything held about the matchmaker who was signed in.
  ///
  /// Called from `AccountSwitch.signOutAndClear`, after the local store has
  /// been reset. Nothing here reaches the network: the outgoing account's row
  /// in the shared collection is theirs and stays exactly as it was — this only
  /// stops the *next* account inheriting a name, a face and a set of counts
  /// that were never theirs.
  void reset() {
    _counts = null;
    _hidden = false;
    _private = false;
    _publishing = false;
    _pulledHidden = false;
    _name = '';
    _photoPath = null;
    _about = '';
    _shares = const <MatchmakerShare>[];
    _benefit = '';
    _contactPhone = '';
    CommunityService.invalidate();
    notifyListeners();
  }

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
        photoUrl: CommunityProfileStore.uploadedAvatarUrl,
        about: _about,
        shares: _shares,
        benefit: _benefit,
        contactPhone: _contactPhone,
      );
      _notePublished();
    }
  }

  /// Erases this account's row from the shared collection.
  ///
  /// Hidden first, then deleted: the next publish will recreate the row, and it
  /// must not recreate it with a name in it.
  Future<bool> deleteMyCommunityData() async {
    CommunityProfileStore.setHidden(true);
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
    // First name *and* surname. The board is a list of people, and one word
    // is not enough to tell two of them apart once the community is bigger
    // than a handful — see [UserProfileProvider.fullName].
    _name = profile.fullName ?? '';
    _photoPath = profile.photoPath;
    // The public page — everything the matchmaker chose to let other
    // matchmakers see. See [CommunityProfile].
    _about = profile.about ?? '';
    _shares = profile.communityShares;
    _benefit = profile.communityBenefit ?? '';
    _contactPhone = profile.communityPhone ?? '';
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
    if (_private || _publishing) {
      return;
    }
    _publishing = true;
    try {
      // **This used to give up when Firebase was not up yet, and never come
      // back.** `CloudSyncScheduler` starts Firebase and calls this in the same
      // breath, so on app open `isReady` is nearly always false here — the
      // first publish of a session was therefore skipped entirely and had to
      // wait for the app to be paused. On a device that is opened, used and
      // closed by the task switcher, that is a publish that never happens, and
      // the matchmaker's work never reaches the community figures at all.
      //
      // Awaiting the same future the bootstrap already has in hand costs
      // nothing and cannot start a second initialisation.
      if (!FirebaseBootstrap.isReady) {
        await _connect();
      }
      if (!FirebaseBootstrap.isReady) {
        return;
      }

      // **The counters go first, before anything that can be slow.** They used
      // to be third in the queue, behind a Firestore read for the stored
      // opt-out and an upload of the matchmaker's photograph — two network
      // round trips standing in front of the one write this method exists to
      // make. At app pause, which is one of the two moments this runs, the
      // process can be frozen at any point; anything waiting behind a round
      // trip there is a publish that simply does not happen, and a device that
      // does not publish is a matchmaker the community total has never heard
      // of. The other two are reconciled straight afterwards, and the second
      // publish is free when they changed nothing — see
      // [CommunityService.publish], which compares the row it is about to
      // write against the last one that landed.
      //
      // It carries the picture URL this device *last uploaded* rather than an
      // empty one, which is the URL already on the document: without it the
      // first write would blank the photograph and the second would put it
      // back, which is two writes, a flicker on somebody else's leaderboard,
      // and a row that no longer matches its own fingerprint every launch.
      if (await CommunityService.publish(
        counts: counts,
        name: _name,
        hidden: _hidden,
        photoUrl: CommunityProfileStore.uploadedAvatarUrl,
        about: _about,
        shares: _shares,
        benefit: _benefit,
        contactPhone: _contactPhone,
      )) {
        _notePublished();
      }

      // The opt-out is authoritative on the server, because it has to survive
      // a reinstall — but only the first time, and only if this device has not
      // been told otherwise since.
      if (!_pulledHidden) {
        _pulledHidden = true;
        final bool? stored = await CommunityService.fetchHidden();
        if (stored != null && stored != _hidden) {
          _hidden = stored;
          CommunityProfileStore.setHidden(stored);
        }
      }

      // The picture, if there is one and it is allowed. Cheap when nothing
      // changed — see `CommunityService.uploadAvatar`.
      final String photoUrl = await CommunityService.uploadAvatar(
        localPath: _photoPath,
        hidden: _hidden,
      );
      // Free whenever the two reconciliations above changed nothing: the row is
      // then byte for byte the one just written, and [CommunityService.publish]
      // recognises its own fingerprint and returns without touching the
      // network.
      if (await CommunityService.publish(
        counts: counts,
        name: _name,
        hidden: _hidden,
        photoUrl: photoUrl,
        about: _about,
        shares: _shares,
        benefit: _benefit,
        contactPhone: _contactPhone,
      )) {
        _notePublished();
      }
    } finally {
      _publishing = false;
    }
  }

  /// Announces that this device's row has just been written.
  ///
  /// Every cached community figure is now one publish out of date, and whatever
  /// is on screen is reading the stale ones: the home banner and the activity
  /// screen both take their community figures from a read they fired before
  /// this landed — usually before there was even an account — so without this
  /// the landing page keeps yesterday's answer, or no answer at all, for the
  /// rest of the session.
  void _notePublished() {
    CommunityService.invalidate();
    _publishRevision++;
    notifyListeners();
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
