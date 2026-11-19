import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/utils/personal_next_step.dart';

/// What one line of "מה חדש אצלי" is about.
enum PersonalWhatsNewKind {
  /// A matchmaker friend asked for access.
  request,

  /// A matchmaker among the owner's contacts has just joined שדכן.
  matchmakerJoined,

  /// A friend of the owner has just started keeping a card of their own.
  friendJoined,

  /// A news post from the שדכן team the owner has not opened yet.
  news,

  /// The card has not been looked at in a long while.
  review,
}

/// One line of "מה חדש אצלי".
class PersonalWhatsNewItem {
  const PersonalWhatsNewItem({
    required this.kind,
    required this.text,
    this.friend,
    this.newsId,
  });

  final PersonalWhatsNewKind kind;
  final String text;

  /// The matchmaker friend it is about, when it is about one.
  final MatchmakerFriend? friend;

  /// The news post it opens, for [PersonalWhatsNewKind.news].
  final String? newsId;
}

/// "מה חדש אצלי" on the personal home — **only real news**, and nothing at all
/// when there is none: a box that says "nothing new" is a box that teaches the
/// owner to stop looking.
///
/// What counts as new: a request waiting for an answer, a matchmaker from the
/// contacts or a friend who joined in the last [freshFor], a news post not
/// opened yet, and a card left alone long enough to be worth a look. A line
/// the next action already says ([nextStep]) is not said twice. Pure, so the
/// rules are tested.
abstract final class PersonalWhatsNew {
  /// How long "just joined" lasts.
  static const Duration freshFor = Duration(days: 7);

  /// The most lines the area ever shows.
  static const int maxLines = 3;

  static List<PersonalWhatsNewItem> build({
    required List<MatchmakerFriend> friends,
    required List<CardHelper> singleFriends,
    Set<String> hidden = const <String>{},
    bool reviewDue = false,
    PersonalNextStepKind? nextStep,
    String? latestNewsId,
    String? latestNewsTitle,
    Set<String> seenNews = const <String>{},
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    bool fresh(DateTime? when) =>
        when != null &&
        !when.isAfter(at.add(const Duration(minutes: 1))) &&
        at.difference(when) <= freshFor;
    final List<PersonalWhatsNewItem> out = <PersonalWhatsNewItem>[];

    // Requests come first — they are waiting on somebody — unless the next
    // action below is already "answer the request".
    final List<MatchmakerFriend> requests = <MatchmakerFriend>[
      for (final MatchmakerFriend f in friends)
        if (f.state == MatchmakerFriendState.requested) f,
    ];
    if (requests.isNotEmpty && nextStep != PersonalNextStepKind.request) {
      final MatchmakerFriend first = requests.first;
      final bool female = first.row?.matchmakerGender == 'female';
      out.add(
        PersonalWhatsNewItem(
          kind: PersonalWhatsNewKind.request,
          friend: requests.length == 1 ? first : null,
          text: requests.length == 1
              ? '${first.name} ${female ? 'ביקשה' : 'ביקש'} גישה לכרטיס שלך'
              : '${requests.length} שדכנים ביקשו גישה לכרטיס שלך',
        ),
      );
    }

    final List<MatchmakerFriend> joined =
        <MatchmakerFriend>[
          for (final MatchmakerFriend f in friends)
            if (f.state != MatchmakerFriendState.requested &&
                !hidden.contains(f.uid) &&
                fresh(f.joinedAt))
              f,
        ]..sort(
          (MatchmakerFriend a, MatchmakerFriend b) =>
              b.joinedAt!.compareTo(a.joinedAt!),
        );
    for (final MatchmakerFriend f in joined.take(2)) {
      out.add(
        PersonalWhatsNewItem(
          kind: PersonalWhatsNewKind.matchmakerJoined,
          friend: f,
          text: 'שדכן חדש מאנשי הקשר שלך: ${f.name}',
        ),
      );
    }

    final List<CardHelper> newFriends = <CardHelper>[
      for (final CardHelper f in singleFriends)
        if (fresh(f.joinedAt) && f.name.trim().isNotEmpty) f,
    ]..sort((CardHelper a, CardHelper b) => b.joinedAt!.compareTo(a.joinedAt!));
    if (newFriends.isNotEmpty) {
      out.add(
        PersonalWhatsNewItem(
          kind: PersonalWhatsNewKind.friendJoined,
          text: newFriends.length == 1
              ? 'גם ${newFriends.first.name.trim()} התחיל/ה להשתמש בשדכן'
              : '${newFriends.length} חברים שלך התחילו להשתמש בשדכן',
        ),
      );
    }

    final String? newsId = latestNewsId;
    if (newsId != null && !seenNews.contains(newsId)) {
      final String title = (latestNewsTitle ?? '').trim();
      out.add(
        PersonalWhatsNewItem(
          kind: PersonalWhatsNewKind.news,
          newsId: newsId,
          text: title.isEmpty ? 'עדכון חדש מצוות שדכן' : title,
        ),
      );
    }

    if (reviewDue &&
        nextStep != PersonalNextStepKind.review &&
        nextStep != PersonalNextStepKind.refresh) {
      out.add(
        const PersonalWhatsNewItem(
          kind: PersonalWhatsNewKind.review,
          text: 'עבר זמן מאז שעדכנת את הכרטיס',
        ),
      );
    }

    return out.take(maxLines).toList();
  }
}
