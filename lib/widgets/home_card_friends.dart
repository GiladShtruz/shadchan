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
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/person_navigation.dart';

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

  /// The latest meaningful thing that happened to this card: the owner
  /// changed details or a photo, their status moved, or they gave (or
  /// widened) access. The carousel is ordered by it, newest first.
  final DateTime lastActivityAt;
}

/// "החברים שלך בשדכן" — on בית, under the two add buttons.
///
/// **Only friends this matchmaker can actually open:** access approved, a
/// card with text, and a photo. Drawn as a horizontal carousel of large
/// portrait photos, newest activity first — a card that changed today, or a
/// friend who has just said yes, comes to the front by itself.
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
    );
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

  static const double _width = 132;
  static const double _height = 176;

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1, 1.4);
    return SizedBox(
      // The name under the photo grows with the system font; the photo does
      // not.
      height: _height + 26 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: slides.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int index) => RepaintBoundary(
          child: _Slide(
            key: ValueKey<String>(slides[index].person.id),
            slide: slides[index],
            width: _width,
            height: _height,
          ),
        ),
      ),
    );
  }
}

/// One friend: a large rounded photo, a soft shade at its foot, the first
/// name over the shade and the full name under the photo.
class _Slide extends StatelessWidget {
  const _Slide({
    super.key,
    required this.slide,
    required this.width,
    required this.height,
  });

  final CardFriendSlide slide;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Person person = slide.person;
    final String path = person.photosPaths.firstWhere(
      (String p) => p.trim().isNotEmpty,
    );
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    final Color accent = AppColors.genderAccent(person.gender, dark: dark);
    final bool fresh =
        DateTime.now().difference(slide.lastActivityAt) <
        const Duration(days: 3);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openPersonProfile(context, person.id),
              child: SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image(
                      // Decoded at the size it is drawn — a full camera photo
                      // per slide is what makes a carousel stutter.
                      image: ResizeImage(
                        FileImage(File(path)),
                        width: (width * ratio).round(),
                        policy: ResizeImagePolicy.fit,
                      ),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: AppColors.genderSurface(
                          person.gender,
                          dark: dark,
                        ),
                        child: Icon(
                          Icons.person_outline_rounded,
                          size: 48,
                          color: accent,
                        ),
                      ),
                    ),
                    // A soft shade at the foot so the name reads on any photo.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: <double>[0.55, 1],
                          colors: <Color>[
                            Colors.transparent,
                            Color(0x99000000),
                          ],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      start: 10,
                      end: 10,
                      bottom: 9,
                      child: Text(
                        person.firstName.trim().isEmpty
                            ? person.fullName
                            : person.firstName.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          shadows: const <Shadow>[
                            Shadow(color: Color(0x66000000), blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                    // A thin line in the friend's own colour along the foot.
                    PositionedDirectional(
                      start: 0,
                      end: 0,
                      bottom: 0,
                      child: Container(height: 3, color: accent),
                    ),
                    if (fresh)
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
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
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            person.fullName.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
