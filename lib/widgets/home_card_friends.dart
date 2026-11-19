import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/screens/friends_with_cards_screen.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/person_navigation.dart';
import 'package:shadchan/widgets/person_avatar.dart';

T? _maybeWatch<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

/// "חברים שלך עם כרטיס אישי בשדכן" — under the action list on בית.
///
/// Three faces each visit: a friend whose card was made in the last week
/// leads (newest first), the rest of the places are drawn at random from
/// everybody else, so the same three do not stand there every morning. Under
/// them one row — "X חברים נוספים שלך מנהלים כרטיס אישי · בקש מהם גישה" —
/// opens the whole list ([FriendsWithCardsScreen]).
///
/// Nothing is drawn while there is nobody to show.
class HomeCardFriendsSection extends StatefulWidget {
  const HomeCardFriendsSection({super.key, this.seed});

  /// Fixes the draw, for tests.
  final int? seed;

  static const String title = 'חברים שלך עם כרטיס אישי בשדכן';

  /// How many faces the home screen shows.
  static const int shown = 3;

  /// The three to show: new cards first (newest first), then a random draw
  /// from the others — stable for one [random].
  static List<FriendWithCard> pick(
    List<FriendWithCard> all, {
    required DateTime now,
    required Random random,
  }) {
    final List<FriendWithCard> fresh =
        all.where((FriendWithCard f) => f.isNew(now)).toList()..sort(
          (FriendWithCard a, FriendWithCard b) =>
              b.cardCreatedAt!.compareTo(a.cardCreatedAt!),
        );
    final List<FriendWithCard> rest =
        all.where((FriendWithCard f) => !f.isNew(now)).toList()
          ..sort(
            (FriendWithCard a, FriendWithCard b) =>
                a.ownerUid.compareTo(b.ownerUid),
          )
          ..shuffle(random);
    return <FriendWithCard>[...fresh, ...rest].take(shown).toList();
  }

  @override
  State<HomeCardFriendsSection> createState() => _HomeCardFriendsSectionState();
}

class _HomeCardFriendsSectionState extends State<HomeCardFriendsSection> {
  late final int _seed = widget.seed ?? Random().nextInt(1 << 30);

  @override
  Widget build(BuildContext context) {
    final CardAccessProvider? access = _maybeWatch<CardAccessProvider>(context);
    final PersonRepository? people = _maybeWatch<PersonRepository>(context);
    if (access == null || people == null) {
      return const SizedBox.shrink();
    }
    final List<FriendWithCard> all = FriendsWithCards.build(
      access: access,
      people: people,
      inbox: _maybeWatch<InboxProvider>(context),
    );
    if (all.isEmpty) {
      return const SizedBox.shrink();
    }
    final List<FriendWithCard> faces = HomeCardFriendsSection.pick(
      all,
      now: DateTime.now(),
      random: Random(_seed),
    );
    final int more = all.length - faces.length;
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color link = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          HomeCardFriendsSection.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final FriendWithCard friend in faces)
              Expanded(child: _FriendFace(friend: friend)),
            for (int i = faces.length; i < HomeCardFriendsSection.shown; i++)
              const Expanded(child: SizedBox.shrink()),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.push(FriendsWithCardsScreen.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    (more > 0
                            ? (more == 1
                                  ? 'עוד חבר אחד שלך מנהל כרטיס אישי · {בקש|בקשי} ממנו גישה'
                                  : '$more חברים נוספים שלך מנהלים כרטיס אישי · {בקש|בקשי} מהם גישה')
                            : 'לכל החברים שמנהלים כרטיס אישי')
                        .forGender(context.userGender),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: link,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: link),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the three: a large photo and the friend's full name under it.
class _FriendFace extends StatelessWidget {
  const _FriendFace({required this.friend});

  /// Half as large again as the faces it replaced (30).
  static const double _radius = 45;

  final FriendWithCard friend;

  void _open(BuildContext context) {
    final Person? person = friend.person;
    if (friend.state == FriendCardState.sees && person != null) {
      openPersonProfile(context, person.id);
      return;
    }
    context.push(
      FriendsWithCardsScreen.requestRoute(
        friend.ownerUid,
        phoneHash: friend.phoneHash,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Person? person = friend.person;
    final String fullName = (person?.fullName.trim().isNotEmpty ?? false)
        ? person!.fullName.trim()
        : friend.name.trim();
    final bool isNew = friend.isNew(DateTime.now());
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                person != null
                    ? PersonAvatar(person: person, radius: _radius)
                    : CircleAvatar(
                        radius: _radius,
                        backgroundColor: dark
                            ? AppColors.primaryLightDarkDm
                            : AppColors.softBlue,
                        child: Text(
                          fullName.isEmpty ? '' : fullName.characters.first,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                if (isNew)
                  PositionedDirectional(
                    top: -4,
                    end: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: dark
                            ? AppColors.secondaryDarkDm
                            : AppColors.secondary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'חדש',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // The full name and nothing else: who it is is the whole point.
            Text(
              fullName,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
