import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadchan/services/connectivity_status.dart';
import 'package:shadchan/utils/app_colors.dart';

/// A thin line across the top of every screen while the app is offline.
///
/// **Small, and part of the layout rather than floating over it.** A floating
/// pill covers whatever happens to be under it — an app bar's title, a
/// button — on some screen nobody thought of; a line that takes the status
/// bar's place and moves the page down by its own height covers nothing. The
/// page beneath is given a [MediaQuery] without the top padding the line has
/// already used, so every app bar sits directly under it.
///
/// When the connection comes back the line turns green for a moment and says
/// so, then folds away — the sync is already catching up underneath.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  static const String offlineText = 'מצב לא מקוון · מוצג המידע האחרון שנשמר';
  static const String backOnlineText = 'החיבור חזר · מתעדכן';

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _offline = ConnectivityStatus.isOffline;
  bool _backOnline = false;
  Timer? _backOnlineTimer;

  @override
  void initState() {
    super.initState();
    ConnectivityStatus.offline.addListener(_onChanged);
  }

  @override
  void dispose() {
    ConnectivityStatus.offline.removeListener(_onChanged);
    _backOnlineTimer?.cancel();
    super.dispose();
  }

  void _onChanged() {
    final bool offline = ConnectivityStatus.isOffline;
    if (offline == _offline) {
      return;
    }
    _backOnlineTimer?.cancel();
    setState(() {
      _backOnline = _offline && !offline;
      _offline = offline;
    });
    if (_backOnline) {
      _backOnlineTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) {
          setState(() => _backOnline = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showing = _offline || _backOnline;
    final MediaQueryData media = MediaQuery.of(context);
    return Column(
      children: <Widget>[
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: showing
              ? _Strip(offline: _offline, topInset: media.padding.top)
              : const SizedBox(width: double.infinity),
        ),
        // Always the same widget, only its padding changes: swapping the
        // subtree for a differently shaped one would rebuild the whole app
        // underneath, losing every screen's state, each time the line came or
        // went.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: showing,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.offline, required this.topInset});

  final bool offline;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color ground = offline
        ? (dark ? AppColors.surfaceDm : AppColors.primaryInk)
        : const Color(0xFF5E8C61);
    const Color ink = Colors.white;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: ground,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, topInset + 3, 12, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                offline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                size: 14,
                color: ink,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  offline
                      ? OfflineBanner.offlineText
                      : OfflineBanner.backOnlineText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
