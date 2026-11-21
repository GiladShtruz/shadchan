import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/screens/chats_screen.dart';
import 'package:shadchan/services/personal_helpers_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/utils/personal_nav.dart';
import 'package:shadchan/widgets/personal_home_sections.dart';

/// "השדכנים שלי" on בית, after "שדכנים שותפים" — for a user who keeps a
/// personal card. The matchmakers among the user's friends, as a horizontal
/// row of cards in the same shape as the partners' row: photo, name, last
/// activity, and a chat button. A tap on a card opens that matchmaker's
/// sheet (access, permissions, chat); "לכל השדכנים שלי" under the row opens
/// the full page.
///
/// It replaces the large "השדכנים שלי" shortcut button: the people
/// themselves are a better way in than a button about them.
///
/// **Reads nothing.** Everything it draws is already in
/// [CardAccessProvider]; it rebuilds only when the helpers or the rows
/// change.
class HomeMyMatchmakers extends StatefulWidget {
  const HomeMyMatchmakers({super.key});

  static const String title = 'השדכנים שלי';
  static const String seeAllLabel = 'לכל השדכנים שלי';
  static const int maxCards = 20;

  /// Requests first, then the most recently active, then who sees the card,
  /// then the rest by name — what is worth a look, first.
  static List<MatchmakerFriend> order(
    Iterable<MatchmakerFriend> friends, {
    Set<String> hidden = const <String>{},
  }) {
    final List<MatchmakerFriend> list = friends
        .where(
          (MatchmakerFriend f) =>
              f.canReadCard ||
              f.state == MatchmakerFriendState.requested ||
              !MatchmakerFriends.isHidden(f, hidden),
        )
        .toList();
    int rank(MatchmakerFriend f) =>
        f.state == MatchmakerFriendState.requested ? 0 : 1;
    list.sort((MatchmakerFriend a, MatchmakerFriend b) {
      final int byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final DateTime? al = a.lastActiveAt, bl = b.lastActiveAt;
      if (al != null || bl != null) {
        if (al == null) return 1;
        if (bl == null) return -1;
        final int byActive = bl.compareTo(al);
        if (byActive != 0) return byActive;
      }
      if (a.canReadCard != b.canReadCard) return a.canReadCard ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  @override
  State<HomeMyMatchmakers> createState() => _HomeMyMatchmakersState();
}

class _HomeMyMatchmakersState extends State<HomeMyMatchmakers> {
  List<MatchmakerFriend> _shown = const <MatchmakerFriend>[];
  Object? _key;

  @override
  Widget build(BuildContext context) {
    CardAccessProvider access;
    try {
      access = Provider.of<CardAccessProvider>(context, listen: false);
      context.select<CardAccessProvider, Object>(
        (CardAccessProvider a) => Object.hash(a.helpersRevision, a.revision),
      );
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<int>(
      valueListenable: PersonalHelpersStore.revision,
      builder: (BuildContext context, int hiddenRevision, _) {
        final Object key = Object.hash(
          access.helpersRevision,
          access.revision,
          hiddenRevision,
        );
        if (key != _key) {
          _key = key;
          _shown = HomeMyMatchmakers.order(
            matchmakerFriendsOf(access),
            hidden: PersonalHelpersStore.hidden,
          ).take(HomeMyMatchmakers.maxCards).toList(growable: false);
        }
        if (_shown.isEmpty) return const SizedBox.shrink();
        final ThemeData theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              HomeMyMatchmakers.title,
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
                onPressed: () => PersonalNav.openMatchmakers(context),
                child: const Text(HomeMyMatchmakers.seeAllLabel),
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
  final List<MatchmakerFriend> list;

  static const double _width = 132;

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1, 1.4);
    return SizedBox(
      height: 112 + 92 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) => RepaintBoundary(
          child: _Card(
            key: ValueKey<String>(list[i].uid),
            friend: list[i],
            width: _width,
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.friend, required this.width});

  final MatchmakerFriend friend;
  final double width;

  static const double _photo = 86;

  /// The uid a chat with this friend is opened with — never a couple's
  /// shared database, which is not a person to write to.
  String? get _chatUid {
    final CardAccess? row = friend.row;
    if (row != null) {
      if (row.status == CardAccessStatus.blocked) return null;
      if (row.granteeUids.length > 1) return null;
      return row.matchmakerUid;
    }
    return friend.helper?.uid;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = friend.name.trim().isEmpty
        ? 'שדכן/ית'
        : friend.name.trim();
    final bool requested = friend.state == MatchmakerFriendState.requested;
    final String? line = requested
        ? MatchmakerFriends.stateLabel(friend)
        : friend.lastActiveAt == null
        ? null
        : MatchmakerFriends.recentActivityLabel(
            friend.lastActiveAt!,
            female: friend.row?.matchmakerGender == 'female',
          );
    final String? chatUid = _chatUid;
    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 1,
        shadowColor: AppColors.darkBlue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => MatchmakerFriendSheet.show(context, friend),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
            child: Column(
              children: <Widget>[
                Container(
                  width: _photo,
                  height: _photo,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: friend.canReadCard
                          ? AppColors.primary
                          : AppColors.teal,
                      width: 2,
                    ),
                  ),
                  child: MatchmakerFace(friend: friend, radius: _photo / 2),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Text(
                    line ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: requested ? AppColors.copper : AppColors.mutedInk,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: chatUid == null
                      ? FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size.fromHeight(36),
                          ),
                          onPressed: () =>
                              MatchmakerFriendSheet.show(context, friend),
                          child: const Text('לפרופיל'),
                        )
                      : FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size.fromHeight(36),
                          ),
                          onPressed: () => ChatLauncher.open(
                            context,
                            otherUid: chatUid,
                            otherName: name,
                          ),
                          child: const Text('צ\'אט'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
