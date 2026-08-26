import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/support_inbox_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/mazel_tov_inbox.dart';

/// Runs the cloud backup when the app opens and when it goes away.
///
/// Those two moments rather than a watcher on every write: a matchmaker
/// editing a card touches the database dozens of times in a minute, and
/// debouncing that into a sensible number of uploads is a whole scheduling
/// problem to get wrong. Open and close are the boundaries of a session, they
/// are cheap because the sync only sends what changed, and they cover the case
/// that actually matters — closing the app is the last thing that happens
/// before a phone is lost.
///
/// The gap this leaves is honest and worth stating: a change made and then
/// lost to a *crash* never reaches the cloud, because `detached` is not
/// delivered reliably on either platform. The local database is unaffected —
/// Hive already wrote it — so the loss is only of the cloud copy, until the
/// next launch.
class CloudSyncScheduler extends StatefulWidget {
  const CloudSyncScheduler({super.key, required this.child});

  final Widget child;

  @override
  State<CloudSyncScheduler> createState() => _CloudSyncSchedulerState();
}

class _CloudSyncSchedulerState extends State<CloudSyncScheduler>
    with WidgetsBindingObserver {
  AccountProvider? _account;

  /// The two ledgers whose changes are worth telling the community about, and
  /// the timer that stops a burst of them becoming a burst of writes.
  PersonRepository? _people;
  MatchRepository? _matches;
  Timer? _activityTimer;

  /// How long the app waits after the last change before republishing.
  ///
  /// **Long enough to swallow an import, short enough to be a live figure.**
  /// Adding four hundred friends fires four hundred notifications inside a few
  /// seconds; every one of them restarts this timer, so the whole import ends
  /// in exactly one publish. A single friend added by hand reaches the
  /// community twenty seconds later, which is what "the number moves when
  /// somebody does something" has to mean if two matchmakers are ever to see
  /// each other's work in the same sitting.
  static const Duration _activityDelay = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, not during it: this reaches three providers and
    // ends in a network call, and the opening frame should not wait behind any
    // of that.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sync();
      // "Is this an administrator?" is a Firestore read, so on the frame the
      // first sync runs the answer is still no. When it arrives the support
      // inbox has to be asked again — otherwise an administrator's console is
      // one app launch behind for the whole of the first session.
      if (mounted) {
        _account = context.read<AccountProvider>()
          ..addListener(_refreshSupportInbox);
        // **And the community figures follow the work, not only the session.**
        // Publishing at open and pause alone means a matchmaker who adds
        // twenty friends and stays in the app has told the community nothing —
        // and the other matchmakers looking at "פעילות הקהילה" in the same hour
        // are reading a total that does not contain any of it. These are the
        // two ledgers every published counter is derived from, so a change to
        // either is exactly the moment the row is stale.
        _people = context.read<PersonRepository>()..addListener(_noteActivity);
        _matches = context.read<MatchRepository>()..addListener(_noteActivity);
      }
    });
  }

  @override
  void dispose() {
    _account?.removeListener(_refreshSupportInbox);
    _people?.removeListener(_noteActivity);
    _matches?.removeListener(_noteActivity);
    _activityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A friend or an idea changed: republish, once the changes have stopped.
  ///
  /// Only the community counters are republished, not the whole cloud backup —
  /// that is a far larger write and it keeps the two moments it always had.
  void _noteActivity() {
    _activityTimer?.cancel();
    _activityTimer = Timer(_activityDelay, () {
      if (!mounted) {
        return;
      }
      // Cheap when nothing that is published actually moved: the counts are
      // recomputed locally, and `CommunityService.publish` recognises a row
      // identical to the last one it wrote and never reaches the network. So an
      // edit to somebody's phone number costs one local recount and no write.
      unawaited(
        context.read<CommunityProvider>().refresh(
          people: context.read<PersonRepository>(),
          matches: context.read<MatchRepository>(),
          profile: context.read<UserProfileProvider>(),
        ),
      );
    });
  }

  void _refreshSupportInbox() {
    if (!mounted) {
      return;
    }
    unawaited(
      context.read<SupportInboxProvider>().refresh(
        isAdmin: context.read<AccountProvider>().isSupportAdmin,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `paused` is the reliable "the user left" signal on both platforms;
    // `detached` arrives too late, and often not at all, to start a network
    // call from. `resumed` covers coming back after long enough away that the
    // session is effectively a new one.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.resumed) {
      _sync();
    }
  }

  void _sync() {
    if (!mounted) {
      return;
    }
    unawaited(
      context.read<SyncProvider>().sync(
        personRepo: context.read<PersonRepository>(),
        matchRepo: context.read<MatchRepository>(),
        profile: context.read<UserProfileProvider>(),
      ),
    );
    // The community tips ride the same two moments. This is the only place the
    // app pulls them on its own, which is what keeps Firebase off the cold
    // start: `TipsProvider`'s constructor reads a local cache and nothing else,
    // and the refresh happens here, a frame later, where a network call already
    // belongs. A tip approved this morning shows up on the next app open, which
    // is soon enough for a tip.
    unawaited(context.read<TipsProvider>().refreshApproved());

    // And so do this matchmaker's own community counters. Open and pause is
    // twice a session — the alternative, writing on every action, would be a
    // Firestore write per friend added during an import of four hundred.
    unawaited(
      context.read<CommunityProvider>().refresh(
        people: context.read<PersonRepository>(),
        matches: context.read<MatchRepository>(),
        profile: context.read<UserProfileProvider>(),
      ),
    );

    // And the postbox: congratulations other matchmakers sent about a wedding,
    // filed into the journal of the couple they are about. Same two moments,
    // for the same reason — it is warm news, not urgent news, and it costs one
    // query against an inbox that is empty for almost everybody.
    unawaited(MazelTovInbox.drain(context.read<MatchRepository>()));

    // And the support inbox: a report that arrived for an administrator, or an
    // answer that came back for whoever sent one. Same two moments again —
    // there is no push channel in this app, so "when the app is opened" is
    // when news can reach anybody, and that is exactly what the notifications
    // page and its bell are for.
    _refreshSupportInbox();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
