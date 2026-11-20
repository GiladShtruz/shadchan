import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/friends_with_cards_screen.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
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

/// One friend in the carousel, and when their card last moved.
class CardFriendSlide {
  const CardFriendSlide({
    required this.friend,
    required this.person,
    required this.lastActivityAt,
  });

  final FriendWithCard friend;
  final Person person;

  /// The photo drawn on the card: the first one actually on this device. A
  /// friend whose photos have not arrived yet is not shown at all — a card
  /// with an empty circle is exactly what this row must never draw.
  String? get photoPath => PersonAvatar.firstExistingPhoto(person);

  /// The latest meaningful thing that happened to this card: the owner
  /// changed details or a photo, their status moved, or they gave (or
  /// widened) access. The carousel is ordered by it, newest first.
  final DateTime lastActivityAt;
}

/// "החברים שלך בשדכן" — on בית, under the two add buttons.
///
/// **Only friends this matchmaker can actually open:** access approved, a
/// card with text, and a photo that is really on this device. Drawn the way
/// Instagram draws "הצעות בשבילך": a continuous horizontal row of small cards,
/// each a round photo, the full name and one "התאמות" button — newest
/// activity first, so a card that changed today or a friend who has just
/// said yes comes to the front by itself.
///
/// Under the carousel, one line to everybody else who keeps a card:
/// "עוד X חברים מנהלים כרטיס אישי".
///
/// Nothing is drawn while there is nobody to show and nobody to ask.
class HomeCardFriendsSection extends StatelessWidget {
  const HomeCardFriendsSection({super.key});

  static const String title = 'החברים שלך בשדכן';

  /// How many slides the carousel holds at most.
  static const int maxSlides = 15;

  /// The event kinds that count as a card moving.
  static const Set<PersonEventType> _activity = <PersonEventType>{
    PersonEventType.cardSynced,
    PersonEventType.cardSyncedMinor,
    PersonEventType.statusChanged,
  };

  /// Whether [person]'s card is full enough to be shown: text and a photo.
  static bool isFullCard(Person person) =>
      (person.description?.trim().isNotEmpty ?? false) &&
      person.photosPaths.any((String p) => p.trim().isNotEmpty);

  /// The slides, newest activity first. Pure, for tests.
  static List<CardFriendSlide> slidesFor(
    List<FriendWithCard> friends, {
    required Map<String, DateTime> latestEventByPerson,
    required CardAccess? Function(String ownerUid) rowOf,
  }) {
    final List<CardFriendSlide> slides = <CardFriendSlide>[];
    for (final FriendWithCard friend in friends) {
      final Person? person = friend.person;
      if (friend.state != FriendCardState.sees ||
          person == null ||
          person.hidden ||
          !isFullCard(person)) {
        continue;
      }
      DateTime last = person.createdAt;
      for (final DateTime? at in <DateTime?>[
        latestEventByPerson[person.id],
        rowOf(friend.ownerUid)?.updatedAt,
        friend.cardCreatedAt,
      ]) {
        if (at != null && at.isAfter(last)) last = at;
      }
      slides.add(
        CardFriendSlide(friend: friend, person: person, lastActivityAt: last),
      );
    }
    slides.sort(
      (CardFriendSlide a, CardFriendSlide b) =>
          b.lastActivityAt.compareTo(a.lastActivityAt),
    );
    return slides;
  }

  static Map<String, DateTime> _latestEvents(PersonRepository people) {
    final Map<String, DateTime> latest = <String, DateTime>{};
    for (final PersonEvent e in people.getAllEvents()) {
      if (!_activity.contains(e.type)) continue;
      final DateTime? known = latest[e.personId];
      if (known == null || e.createdAt.isAfter(known)) {
        latest[e.personId] = e.createdAt;
      }
    }
    return latest;
  }

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
    final List<CardFriendSlide> slides = slidesFor(
      all,
      latestEventByPerson: _latestEvents(people),
      rowOf: access.accessTo,
    ).where((CardFriendSlide s) => s.photoPath != null).toList();
    final List<CardFriendSlide> shown = slides.take(maxSlides).toList();
    final int more = all.length - shown.length;
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        if (shown.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _Carousel(slides: shown),
        ],
        if (more > 0 || shown.isEmpty) _MoreLink(more: more),
      ],
    );
  }
}

class _Carousel extends StatelessWidget {
  const _Carousel({required this.slides});

  final List<CardFriendSlide> slides;

  static const double _width = 128;

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1, 1.4);
    return SizedBox(
      // The photo is fixed; the name and the button grow with the font.
      height: 92 + 84 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        // Built as it scrolls, each card on its own layer: a long row of
        // photos must not cost a frame.
        itemCount: slides.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) => RepaintBoundary(
          child: _Slide(
            key: ValueKey<String>(slides[index].person.id),
            slide: slides[index],
            width: _width,
          ),
        ),
      ),
    );
  }
}

/// One friend, as a small card: a round photo, the full name under it, and
/// "התאמות" at the foot. The card opens the friend's profile; the button
/// opens their matches.
class _Slide extends StatelessWidget {
  const _Slide({super.key, required this.slide, required this.width});

  final CardFriendSlide slide;
  final double width;

  static const double _photo = 76;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Person person = slide.person;
    final String path = slide.photoPath!;
    final int cache = (_photo * MediaQuery.devicePixelRatioOf(context)).round();
    final Color accent = AppColors.genderAccent(person.gender, dark: dark);
    final bool fresh =
        DateTime.now().difference(slide.lastActivityAt) <
        const Duration(days: 3);

    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openPersonProfile(context, person.id),
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
                        border: Border.all(color: accent, width: 2),
                      ),
                      child: ClipOval(
                        child: Image(
                          // Decoded at the size it is drawn — a full camera
                          // photo per card is what makes a row stutter.
                          image: ResizeImage(
                            FileImage(File(path)),
                            width: cache,
                            height: cache,
                            policy: ResizeImagePolicy.fit,
                          ),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: AppColors.genderSurface(
                              person.gender,
                              dark: dark,
                            ),
                            child: Icon(
                              Icons.person_outline_rounded,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (fresh)
                      PositionedDirectional(
                        top: -4,
                        end: -10,
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
                            'עודכן',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: Text(
                      person.fullName.trim(),
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
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: FilledButton(
                    onPressed: () => openSuggestionsFor(context, person.id),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      backgroundColor: dark
                          ? AppColors.primaryDarkDm
                          : AppColors.primaryDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const FittedBox(child: Text('התאמות')),
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

class _MoreLink extends StatelessWidget {
  const _MoreLink({required this.more});

  final int more;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color link = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;
    final String text = more <= 0
        ? 'לכל החברים שמנהלים כרטיס אישי'
        : more == 1
        ? 'עוד חבר אחד מנהל כרטיס אישי'
        : 'עוד $more חברים מנהלים כרטיס אישי';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push(FriendsWithCardsScreen.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                text,
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
    );
  }
}
