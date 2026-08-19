import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, not during it: this reaches three providers and
    // ends in a network call, and the opening frame should not wait behind any
    // of that.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
