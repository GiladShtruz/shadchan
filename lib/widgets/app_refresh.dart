import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/app_tokens.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/services/connectivity_status.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// What one pull to refresh asks for, beyond the account's own records.
enum RefreshScope {
  /// The database, the ideas and the synced cards — every page.
  records,

  /// …and the conversations.
  chats,

  /// …and the matchmakers (shares, community figures).
  matchmakers,
}

/// Pull to refresh, the same on every page that has it.
///
/// **Incremental, never a full reload.** The page keeps drawing what it
/// already has (the local copy) the whole time; the pull only asks each live
/// source to catch up now instead of on its next push — the account sync's
/// resume (changes since the last one), the cards a matchmaker follows, and
/// what the page itself shows. Nothing is emptied, so a scroll position, an
/// open filter or a search survives.
///
/// The indicator never spins for ever: every source is bounded
/// ([timeout]), and a pull that could not reach the server says so with
/// "נסה שוב" instead of pretending it worked.
abstract final class AppRefresh {
  static const Duration timeout = Duration(seconds: 12);
  static const String failedMessage = 'לא הצלחנו לרענן כרגע';
  static const String offlineMessage = 'אין חיבור לאינטרנט · מוצג המידע האחרון';
  static const String retryLabel = 'נסה שוב';

  /// Test seam: replaces the sources a pull reaches.
  @visibleForTesting
  static Future<void> Function(BuildContext context, RefreshScope scope)?
  debugSources;

  static Future<void> pull(BuildContext context, RefreshScope scope) async {
    final OverlayState? notices = AppNotice.capture(context);
    if (ConnectivityStatus.isOffline) {
      if (notices != null) {
        AppNotice.showOn(notices, offlineMessage);
      }
      return;
    }
    bool ok = true;
    try {
      await _sources(context, scope).timeout(timeout);
    } on Object {
      ok = false;
    }
    if (ok || notices == null || !context.mounted) return;
    AppNotice.showOn(
      notices,
      failedMessage,
      actionLabel: retryLabel,
      onAction: () {
        if (context.mounted) unawaited(pull(context, scope));
      },
    );
  }

  static Future<void> _sources(BuildContext context, RefreshScope scope) {
    final Future<void> Function(BuildContext, RefreshScope)? seam =
        debugSources;
    if (seam != null) return seam(context, scope);
    final SyncProvider? sync = _maybe<SyncProvider>(context);
    final CardAccessProvider? access = _maybe<CardAccessProvider>(context);
    return Future.wait<void>(<Future<void>>[
      if (sync != null) sync.resume(),
      if (access != null) access.resume(),
      if (scope == RefreshScope.chats) ChatService.refresh(),
      if (scope == RefreshScope.matchmakers) ...<Future<void>>[
        MatchmakerShares.refresh(force: true),
        Future<void>.sync(CommunityService.invalidate),
      ],
    ]);
  }

  static T? _maybe<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }
}

/// The standard pull-to-refresh indicator, in the app's action colour.
///
/// [child] must be a scrollable that can overscroll — give a short list
/// `AlwaysScrollableScrollPhysics` so it can be pulled when it does not fill
/// the screen.
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.child,
    this.scope = RefreshScope.records,
    this.onRefresh,
    this.edgeOffset = 0,
  });

  final Widget child;
  final RefreshScope scope;

  /// Something the page itself reloads, run beside the shared sources.
  final Future<void> Function()? onRefresh;

  /// Where the indicator starts, below a pinned header.
  final double edgeOffset;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return RefreshIndicator(
      color: dark ? AppColors.secondaryDarkDm : context.tokens.ctaAccent,
      edgeOffset: edgeOffset,
      onRefresh: () => Future.wait<void>(<Future<void>>[
        AppRefresh.pull(context, scope),
        if (onRefresh != null)
          onRefresh!().timeout(AppRefresh.timeout).catchError((Object _) {}),
      ]),
      child: child,
    );
  }
}
