import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/friends_with_cards_screen.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/person_navigation.dart';
import 'package:shadchan/utils/enums.dart';
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
  const CardFriendSlide({required this.person, required this.lastActivityAt});

  final Person person;

  /// The photo drawn on the card: the first one actually on this device. A
  /// friend whose photos have not arrived yet is not shown at all — a card
  /// with an empty circle is exactly what this row must never draw.
  String? get photoPath => PersonAvatar.firstExistingPhoto(person);

  /// The latest meaningful thing that happened to this friend: their record
  /// was edited, their card synced, their status moved, or they gave (or
  /// widened) access. The carousel is ordered by it, newest first.
  final DateTime lastActivityAt;
}

/// "החברים שלך" — on בית, under the two add buttons.
///
/// **Every friend in the database with a full card** — card text and a
/// photo really on this device — whether the matchmaker wrote the card or the
/// friend keeps their own. Drawn the way Instagram draws "הצעות בשבילך": a
/// continuous horizontal row of compact cards, each a large round photo, the
/// full name and one "התאמות" button.
///
/// **Newest first, and a little different each visit.** The friends updated
/// most recently lead ([fixedLead]); the rest of the row turns over on every
/// app open and return, so the database keeps coming back to mind instead of
/// the same ten faces. Only [maxSlides] are ever built, and the row builds
/// lazily as it scrolls.
///
/// Under it, always: "חברים שלי שמנהלים כרטיס אישי".
class HomeCardFriendsSection extends StatefulWidget {
  const HomeCardFriendsSection({super.key});

  static const String title = 'החברים שלך';
  static const String cardOwnersLink = 'חברים שלי שמנהלים כרטיס אישי';

  /// How many slides the carousel holds at most.
  static const int maxSlides = 20;

  /// How many of the most recently updated always lead the row.
  static const int fixedLead = 6;

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

  /// The friends who can be in the row, newest activity first. Pure, for
  /// tests: [hasPhoto] says whether a photo is really on the device.
  static List<CardFriendSlide> slidesFor(
    Iterable<Person> people, {
    required Map<String, DateTime> latestEventByPerson,
    required CardAccess? Function(String ownerUid) rowOf,
  }) {
    final List<CardFriendSlide> slides = <CardFriendSlide>[];
    for (final Person person in people) {
      if (person.hidden ||
          person.needsReview ||
          person.profileStatus == ProfileStatus.mazelTov ||
          !isFullCard(person)) {
        continue;
      }
      DateTime last = person.updatedAt.isAfter(person.createdAt)
          ? person.updatedAt
          : person.createdAt;
      final String? owner = person.cardOwnerUid;
      for (final DateTime? at in <DateTime?>[
        latestEventByPerson[person.id],
        owner == null || owner.isEmpty ? null : rowOf(owner)?.updatedAt,
      ]) {
        if (at != null && at.isAfter(last)) last = at;
      }
      slides.add(CardFriendSlide(person: person, lastActivityAt: last));
    }
    slides.sort(
      (CardFriendSlide a, CardFriendSlide b) =>
          b.lastActivityAt.compareTo(a.lastActivityAt),
    );
    return slides;
  }

  /// The row for one visit: the [fixedLead] newest, then the rest turned by
  /// [seed] — each at most once, only those with a photo on the device
  /// ([hasPhoto]), [maxSlides] in all.
  static List<CardFriendSlide> pick(
    List<CardFriendSlide> ranked, {
    required int seed,
    bool Function(CardFriendSlide slide)? hasPhoto,
  }) {
    final bool Function(CardFriendSlide) ok =
        hasPhoto ?? (CardFriendSlide s) => s.photoPath != null;
    final List<CardFriendSlide> out = <CardFriendSlide>[];
    int i = 0;
    for (; i < ranked.length && out.length < fixedLead; i++) {
      if (ok(ranked[i])) out.add(ranked[i]);
    }
    final List<CardFriendSlide> rest = ranked.sublist(i);
    if (rest.isEmpty) return out;
    final int start = (seed * 7).abs() % rest.length;
    for (int k = 0; k < rest.length && out.length < maxSlides; k++) {
      final CardFriendSlide s = rest[(start + k) % rest.length];
      if (ok(s)) out.add(s);
    }
    return out;
  }

  static Map<String, DateTime>? _latestMemo;
  static int _latestRevision = -1;

  /// Walked once per change of the database, not on every rebuild of the
  /// home page.
  static Map<String, DateTime> _latestEvents(PersonRepository people) {
    final Map<String, DateTime>? memo = _latestMemo;
    if (memo != null && _latestRevision == people.revision) return memo;
    final Map<String, DateTime> latest = <String, DateTime>{};
    for (final PersonEvent e in people.getAllEvents()) {
      if (!_activity.contains(e.type)) continue;
      final DateTime? known = latest[e.personId];
      if (known == null || e.createdAt.isAfter(known)) {
        latest[e.personId] = e.createdAt;
      }
    }
    _latestRevision = people.revision;
    return _latestMemo = latest;
  }

  @override
  State<HomeCardFriendsSection> createState() => _HomeCardFriendsSectionState();
}

class _HomeCardFriendsSectionState extends State<HomeCardFriendsSection>
    with WidgetsBindingObserver {
  static int _visits = 0;
  late int _seed = _visits++;

  Object? _key;
  List<CardFriendSlide> _shown = const <CardFriendSlide>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is a new visit: the row turns over.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _seed = _visits++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PersonRepository? people = _maybeWatch<PersonRepository>(context);
    if (people == null) {
      return const SizedBox.shrink();
    }
    // Only the access rows' revision — not every notification — and only
    // to date a friend's last activity.
    final CardAccessProvider? access = _maybeRead<CardAccessProvider>(context);
    final int accessRev = access == null
        ? 0
        : context.select<CardAccessProvider, int>(
            (CardAccessProvider a) => a.revision,
          );
    final Object key = Object.hash(people.revision, accessRev, _seed);
    if (key != _key) {
      _key = key;
      _shown = HomeCardFriendsSection.pick(
        HomeCardFriendsSection.slidesFor(
          people.getAll(),
          latestEventByPerson: HomeCardFriendsSection._latestEvents(people),
          rowOf: access?.accessTo ?? (_) => null,
        ),
        seed: _seed,
      );
    }
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_shown.isNotEmpty) ...<Widget>[
          Text(
            HomeCardFriendsSection.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          _Carousel(slides: _shown),
          const SizedBox(height: 6),
        ],
        const _CardOwnersButton(),
      ],
    );
  }
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

class _Carousel extends StatelessWidget {
  const _Carousel({required this.slides});

  final List<CardFriendSlide> slides;

  static const double _width = 132;

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1, 1.4);
    return SizedBox(
      // The photo is fixed; the name and the button grow with the font.
      height: 102 + 84 * scale,
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

  static const double _photo = 86;

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

/// "חברים שלי שמנהלים כרטיס אישי" — always under the row, to the page of
/// the friends who keep their own card.
class _CardOwnersButton extends StatelessWidget {
  const _CardOwnersButton();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color link = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        onPressed: () => context.push(FriendsWithCardsScreen.route),
        style: OutlinedButton.styleFrom(
          foregroundColor: link,
          side: BorderSide(color: link.withValues(alpha: 0.45)),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        icon: const Icon(Icons.badge_outlined, size: 18),
        label: const Text(HomeCardFriendsSection.cardOwnersLink),
      ),
    );
  }
}
