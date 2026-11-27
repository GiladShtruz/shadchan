/// "מה חדש אצלי" — a small, living feed of what happened around the user
/// lately: their own work and what the people in their contacts did that
/// matters to them.
///
/// **One feed for every kind of user, filtered by side.** Each event belongs
/// to the matchmaker's work ([WhatsNewSide.matchmaker]), to the user's own
/// card ([WhatsNewSide.personal]) or to both. A matchmaker who is not single
/// sees only matchmaking; a single who does not matchmake sees only their own
/// side; somebody who is both gets one mixed feed — never "כרווק" beside
/// "כשדכן".
///
/// **Not a second notifications page.** The bell keeps everything; the feed
/// shows only what gives a sense of things moving — recent ([freshFor]),
/// meaningful, one line each, newest first — and nothing technical (a sync,
/// an app open, an update). Pure, so the rules are tested.
library;

/// Whose life an event is part of.
enum WhatsNewSide { matchmaker, personal, both }

/// What an event is about — decides its mark and where a tap goes.
enum WhatsNewKind {
  /// A matchmaker from the contacts joined שדכן.
  matchmakerJoined,

  /// A single friend started keeping a personal card.
  friendAddedCard,

  /// A friend approved access to their card.
  accessApproved,

  /// A matchmaker started sharing their database.
  shareOpened,

  /// A couple of mine started going out.
  coupleDating,

  /// A couple of mine got engaged / married.
  coupleEngaged,

  /// Ideas I opened today / this week (one aggregate line).
  ideasOpened,

  /// A friend updated their personal card.
  cardUpdated,

  /// A meaningful message: an idea or a card sent to me in a chat.
  message,

  /// Somebody asked for something that waits on me (access to my card).
  request,

  /// A friend of mine (a single) joined.
  friendJoined,

  /// A post from the שדכן team.
  news,

  /// An idea a matchmaker offered me / an idea between matchmakers approved.
  idea,

  /// My card has not been looked at in a while.
  review,
}

/// One line of the feed.
class WhatsNewEvent {
  const WhatsNewEvent({
    required this.key,
    required this.kind,
    required this.side,
    required this.text,
    required this.at,
    this.route,
    this.personId,
    this.uid,
    this.secondPersonId,
    this.payload,
  });

  /// Stable identity: two sources telling the same thing keep one line.
  final String key;
  final WhatsNewKind kind;
  final WhatsNewSide side;
  final String text;
  final DateTime at;

  /// Where a tap goes, when it is a plain route.
  final String? route;

  /// The friend in the database it is about (their face).
  final String? personId;

  /// The second side of a couple.
  final String? secondPersonId;

  /// The account it is about (a matchmaker, a chat partner).
  final String? uid;

  /// Anything else the screen needs to open it (an inbox item, a news id).
  final Object? payload;

  bool visibleTo({required bool single, required bool matchmaker}) =>
      switch (side) {
        WhatsNewSide.both => true,
        WhatsNewSide.matchmaker => matchmaker,
        WhatsNewSide.personal => single,
      };
}

abstract final class WhatsNewFeed {
  /// How far back the feed looks.
  static const Duration freshFor = Duration(days: 14);

  /// Lines shown before "עוד".
  static const int shown = 5;

  /// The most the feed ever holds.
  static const int maxLines = 15;

  /// The server's notices the feed takes, by side. Everything else stays on
  /// the bell only (reminders, status reports, technical notices, alerts).
  static const Map<String, WhatsNewSide> inboxKinds = <String, WhatsNewSide>{
    'matchmakerJoined': WhatsNewSide.matchmaker,
    'cardCreated': WhatsNewSide.matchmaker,
    'accessApproved': WhatsNewSide.matchmaker,
    'shareOpened': WhatsNewSide.matchmaker,
    'ideaProposalApproved': WhatsNewSide.matchmaker,
    'mazelTov': WhatsNewSide.matchmaker,
    'accessRequest': WhatsNewSide.personal,
    'shareOnwardRequest': WhatsNewSide.personal,
    'friendJoined': WhatsNewSide.personal,
    'personalNews': WhatsNewSide.personal,
  };

  static WhatsNewKind kindOfInbox(String kind) => switch (kind) {
    'matchmakerJoined' => WhatsNewKind.matchmakerJoined,
    'cardCreated' => WhatsNewKind.friendAddedCard,
    'accessApproved' => WhatsNewKind.accessApproved,
    'shareOpened' => WhatsNewKind.shareOpened,
    'ideaProposalApproved' => WhatsNewKind.idea,
    'mazelTov' => WhatsNewKind.coupleEngaged,
    'accessRequest' || 'shareOnwardRequest' => WhatsNewKind.request,
    'friendJoined' => WhatsNewKind.friendJoined,
    'personalNews' => WhatsNewKind.news,
    _ => WhatsNewKind.news,
  };

  /// "פתחת היום 3 רעיונות" / "פתחת השבוע 8 רעיונות" — one line for the
  /// ideas opened lately, null when there were none. [opened] are the
  /// creation times of the ideas the user opened.
  static WhatsNewEvent? ideasOpened(
    Iterable<DateTime> opened, {
    required DateTime now,
    String? femaleSuffix,
  }) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime weekAgo = today.subtract(const Duration(days: 6));
    int todayCount = 0;
    int weekCount = 0;
    DateTime? latest;
    for (final DateTime at in opened) {
      if (at.isAfter(now.add(const Duration(minutes: 1)))) continue;
      if (!at.isBefore(weekAgo)) {
        weekCount++;
        if (latest == null || at.isAfter(latest)) latest = at;
      }
      if (!at.isBefore(today)) todayCount++;
    }
    if (latest == null) return null;
    final String verb = 'פתחת${femaleSuffix ?? ''}';
    final String text = todayCount > 0 && todayCount == weekCount
        ? (todayCount == 1
              ? '$verb היום רעיון חדש'
              : '$verb היום $todayCount רעיונות')
        : todayCount > 0
        ? '$verb היום ${todayCount == 1 ? 'רעיון אחד' : '$todayCount רעיונות'}'
              ' · $weekCount השבוע'
        : weekCount == 1
        ? '$verb השבוע רעיון חדש'
        : '$verb השבוע $weekCount רעיונות';
    return WhatsNewEvent(
      key: 'ideasOpened',
      kind: WhatsNewKind.ideasOpened,
      side: WhatsNewSide.matchmaker,
      text: text,
      at: latest,
      route: '/matches',
    );
  }

  /// The feed: only what this user is (single, matchmaker or both) is
  /// about, only what is fresh, one line per [WhatsNewEvent.key], newest
  /// first, at most [maxLines].
  static List<WhatsNewEvent> build(
    Iterable<WhatsNewEvent> events, {
    required bool single,
    required bool matchmaker,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    final Map<String, WhatsNewEvent> byKey = <String, WhatsNewEvent>{};
    for (final WhatsNewEvent e in events) {
      if (!e.visibleTo(single: single, matchmaker: matchmaker)) continue;
      if (e.text.trim().isEmpty) continue;
      // A clock in the future is not news yet; an old event is not news.
      if (e.at.isAfter(at.add(const Duration(minutes: 5)))) continue;
      if (at.difference(e.at) > freshFor) continue;
      final WhatsNewEvent? known = byKey[e.key];
      if (known == null || e.at.isAfter(known.at)) byKey[e.key] = e;
    }
    final List<WhatsNewEvent> list = byKey.values.toList()
      ..sort((WhatsNewEvent a, WhatsNewEvent b) {
        final int byTime = b.at.compareTo(a.at);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });
    return list.take(maxLines).toList();
  }
}
