import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/app_tokens.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/screens/known_matchmakers_screen.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_navigation.dart';
import 'package:shadchan/utils/avatar_image.dart';
import 'package:shadchan/utils/known_matchmakers.dart';

/// The matchmakers hidden from the home carousel — hidden, never blocked:
/// still on "שדכנים שאני מכיר", still able to share and chat. Synced with
/// the account.
abstract final class PartnerCarouselHidden {
  static const String key = 'partners.hiddenFromHome';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Set<String>? _cache;

  static Set<String> get uids {
    final Set<String>? cached = _cache;
    if (cached != null) return cached;
    Set<String> out = <String>{};
    if (Hive.isBoxOpen('settings')) {
      final Object? raw = Hive.box<dynamic>('settings').get(key);
      if (raw is String && raw.isNotEmpty) {
        try {
          final Object? list = jsonDecode(raw);
          if (list is List)
            out = <String>{for (final Object? u in list) ?u as String?};
        } catch (_) {}
      }
    }
    return _cache = out;
  }

  static void hide(String uid) => _write(<String>{...uids, uid});
  static void show(String uid) => _write(<String>{...uids}..remove(uid));

  static void _write(Set<String> next) {
    _cache = next;
    persistHomeSetting(key, jsonEncode(next.toList()..sort()));
    revision.value++;
  }

  static void forgetCache() {
    _cache = null;
    revision.value++;
  }
}

/// "שדכנים שותפים" on בית, beside "החברים שלך": the matchmakers this one
/// knows from the phone book, as a horizontal row — a big photo, the full
/// name and one action ([KnownMatchmakerAction]): "למאגר" (with "X
/// כרטיסים") for one who shares with me, "צ'אט" when only I share, else
/// "שיתוף מאגר". New ones (joined this week) lead with a mark; then the
/// most recently active. A small arrow on each card offers "הסתרה מהבית".
/// "לכל השדכנים" under the row opens "שדכנים שאני מכיר".
///
/// **Reads nothing.** It draws the helpers the server already computed and
/// the share rows already on the phone; the rows are refreshed (one small
/// read) when the home page opens, never listened to from here.
class HomePartnerMatchmakers extends StatefulWidget {
  const HomePartnerMatchmakers({super.key});

  static const String title = 'שדכנים שותפים';

  /// The most cards in the row; the rest are on "לכל השדכנים".
  static const int maxCards = 20;

  @override
  State<HomePartnerMatchmakers> createState() => _HomePartnerMatchmakersState();
}

class _HomePartnerMatchmakersState extends State<HomePartnerMatchmakers> {
  List<KnownMatchmaker> _shown = const <KnownMatchmaker>[];
  Object? _key;

  @override
  void initState() {
    super.initState();
    unawaited(MatchmakerShares.refresh());
  }

  @override
  Widget build(BuildContext context) {
    if (!WorkspaceStore.matchmakerEnabled) return const SizedBox.shrink();
    CardAccessProvider? access;
    try {
      access = Provider.of<CardAccessProvider>(context, listen: false);
      context.select<CardAccessProvider, int>(
        (CardAccessProvider a) => a.helpersRevision,
      );
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        MatchmakerShares.rows,
        MatchmakerShares.busy,
        PartnerCarouselHidden.revision,
      ]),
      builder: (BuildContext context, _) {
        final Object key = Object.hash(
          access!.helpersRevision,
          identityHashCode(MatchmakerShares.rows.value),
          PartnerCarouselHidden.revision.value,
        );
        if (key != _key) {
          _key = key;
          _shown = KnownMatchmakers.carousel(
            knownMatchmakerGroups(access),
            hidden: PartnerCarouselHidden.uids,
          ).take(HomePartnerMatchmakers.maxCards).toList(growable: false);
        }
        if (_shown.isEmpty) return const SizedBox.shrink();
        final ThemeData theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              HomePartnerMatchmakers.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            _Row(list: _shown),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () =>
                    AppNavigation.open(context, KnownMatchmakersScreen.route),
                child: const Text('לכל השדכנים'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.list});
  final List<KnownMatchmaker> list;

  static const double _width = 132;

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1, 1.4);
    return SizedBox(
      height: 102 + 98 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) => RepaintBoundary(
          child: _Card(
            key: ValueKey<String>(list[i].uid),
            matchmaker: list[i],
            width: _width,
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.matchmaker, required this.width});

  final KnownMatchmaker matchmaker;
  final double width;

  static const double _photo = 86;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KnownMatchmaker m = matchmaker;
    final String name = m.name.trim().isEmpty ? 'שדכן/ית' : m.name.trim();
    final String? photo = m.photoUrl?.trim();
    final Color ring = m.sharesWithMe
        ? context.tokens.maleAccent
        : context.tokens.lightAccent;
    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 1,
        shadowColor: context.tokens.textPrimary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => AppNavigation.open(
            context,
            KnownMatchmakersScreen.profileRoute(m.uid),
          ),
          // The card's other choices — the profile, "הסתרה מהבית" — on a long
          // press. A small arrow used to hang off the card's corner for them,
          // and the card's own clip cut it into a stray "L" above the photo.
          onLongPress: () => _CardMenu.show(context, m),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
            child: Column(
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      width: _photo,
                      height: _photo,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ring, width: 2),
                      ),
                      // No photo: a plain, flat figure of a person — never
                      // a first letter.
                      child: CircleAvatar(
                        backgroundColor: context.tokens.maleWash,
                        foregroundImage: photo == null || photo.isEmpty
                            ? null
                            : avatarImage(context, photo, diameter: _photo),
                        child: const Icon(
                          Icons.person_rounded,
                          size: _photo * 0.62,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    if (m.isNew())
                      const PositionedDirectional(
                        top: -4,
                        end: -10,
                        child: NewMark(),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                KnownMatchmakerAction(matchmaker: m, expand: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A card's other choices, on a long press: the profile, "הסתרה מהבית".
abstract final class _CardMenu {
  static Future<void> show(BuildContext context, KnownMatchmaker m) async {
    final String? value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('לפרופיל'),
              onTap: () => Navigator.pop(context, 'profile'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('הסתרה מהבית'),
              onTap: () => Navigator.pop(context, 'hide'),
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('לכל השדכנים'),
              onTap: () => Navigator.pop(context, 'all'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || value == null) return;
    switch (value) {
      case 'profile':
        AppNavigation.open(context, KnownMatchmakersScreen.profileRoute(m.uid));
      case 'hide':
        PartnerCarouselHidden.hide(m.uid);
      case 'all':
        context.push(KnownMatchmakersScreen.route);
    }
  }
}
