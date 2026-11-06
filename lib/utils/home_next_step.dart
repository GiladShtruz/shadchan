import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/home_stage.dart';

/// What one recommendation leads to when it is tapped.
enum NextStepAction {
  /// A route to push.
  route,

  /// The add-friends choice ([AddPeopleDialog]).
  addFriends,

  /// Opening a new idea (`/matches/add`).
  addIdea,
}

/// The six tiers the home screen's one recommendation is chosen from, in the
/// order they are worth the matchmaker's attention.
enum NextStepTier {
  /// Something is waiting to be handled: an access request to the
  /// matchmaker's own card, a reminder that came due, unread notices.
  waiting,

  /// An open idea that has not moved for a week.
  openIdea,

  /// Friends who wrote a personal card the matchmaker can ask to see.
  cardFriends,

  /// Pairs the database itself suggests.
  suggestions,

  /// Opening a new idea.
  newIdea,

  /// Growing the database.
  addFriends,
}

/// One possible recommendation.
class NextStep {
  const NextStep({
    required this.key,
    required this.tier,
    required this.text,
    required this.actionLabel,
    required this.action,
    this.route,
  });

  /// Stable across visits for the same subject — what the rotation remembers.
  final String key;
  final NextStepTier tier;
  final String text;

  /// The short verb on the recommendation's button.
  final String actionLabel;
  final NextStepAction action;
  final String? route;

  /// Something that genuinely waits on the matchmaker; never rotated away.
  bool get urgent => tier == NextStepTier.waiting;
}

/// A friend whose own reminder came due.
class DueFriend {
  const DueFriend({required this.id, required this.firstName, this.gender});
  final String id;
  final String firstName;
  final Gender? gender;
}

/// An open idea, named by its two first names.
class NamedIdea {
  const NamedIdea({
    required this.id,
    required this.maleName,
    required this.femaleName,
  });
  final String id;
  final String maleName;
  final String femaleName;
}

/// Everything the choice looks at, gathered by the home screen.
class NextStepInputs {
  const NextStepInputs({
    required this.friends,
    required this.now,
    this.gender,
    this.pendingAccessRequests = 0,
    this.unreadNotices = 0,
    this.dueFriends = const <DueFriend>[],
    this.dueIdeas = const <NamedIdea>[],
    this.staleIdeas = const <NamedIdea>[],
    this.requestableCardFriends = 0,
    this.databaseSuggestions = 0,
    this.lastIdeaAt,
    this.lastFriendAt,
    this.weekStart,
  });

  /// Friends in the database.
  final int friends;
  final DateTime now;

  /// The matchmaker's own gender, for the verbs.
  final Gender? gender;

  /// Matchmakers asking to see the matchmaker's own personal card.
  final int pendingAccessRequests;

  /// The bell's count: due reminders plus unread notices.
  final int unreadNotices;

  /// Friends whose reminder came due and is still unread.
  final List<DueFriend> dueFriends;

  /// Ideas whose reminder came due and is still unread.
  final List<NamedIdea> dueIdeas;

  /// Open ideas with nothing new for a week, stalest first.
  final List<NamedIdea> staleIdeas;

  /// Friends with a personal card the matchmaker has not asked for yet.
  final int requestableCardFriends;

  /// Pairs the database suggests (0 when the database is too small to ask).
  final int databaseSuggestions;

  /// When the newest idea was opened, and when the newest friend was added.
  final DateTime? lastIdeaAt;
  final DateTime? lastFriendAt;

  /// The start of this week (Sunday, Israel). Defaults to seven days ago.
  final DateTime? weekStart;
}

/// What the rotation remembers between visits.
class NextStepMemory {
  const NextStepMemory({
    this.key,
    this.shownAt,
    this.streak = 0,
    this.actedKey,
    this.actedAt,
  });

  static const NextStepMemory empty = NextStepMemory();

  /// The last recommendation shown, when, and on how many visits in a row.
  final String? key;
  final DateTime? shownAt;
  final int streak;

  /// The last recommendation the matchmaker tapped, and when.
  final String? actedKey;
  final DateTime? actedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'shownAt': shownAt?.millisecondsSinceEpoch,
    'streak': streak,
    'actedKey': actedKey,
    'actedAt': actedAt?.millisecondsSinceEpoch,
  };

  static NextStepMemory fromJson(Object? raw) {
    if (raw is! Map) {
      return empty;
    }
    DateTime? at(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return NextStepMemory(
      key: raw['key'] as String?,
      shownAt: at(raw['shownAt']),
      streak: raw['streak'] is int ? raw['streak'] as int : 0,
      actedKey: raw['actedKey'] as String?,
      actedAt: at(raw['actedAt']),
    );
  }

  NextStepMemory shown(String key, DateTime now) => NextStepMemory(
    key: key,
    shownAt: now,
    streak: key == this.key ? streak + 1 : 1,
    actedKey: actedKey,
    actedAt: actedAt,
  );

  NextStepMemory acted(String key, DateTime now) => NextStepMemory(
    key: this.key,
    shownAt: shownAt,
    streak: streak,
    actedKey: key,
    actedAt: now,
  );
}

/// "מה עושים עכשיו?" — the one recommendation on the home screen.
///
/// **One sentence, never a list.** Everything below is about choosing which
/// single thing to say. The tiers come in a fixed order of usefulness —
/// something waiting, an idea that stalled, friends with a card, the
/// database's own pairs, a new idea, more friends — and the stage of the
/// database reorders the middle of it: a matchmaker with fewer than ten
/// friends is told about building the database and the friends who already
/// have a card before anything else, because there is nothing yet to manage.
///
/// **It does not nag.** A recommendation that is not urgent is shown on at
/// most [maxStreak] visits in a row before the next one gets a turn, and one
/// the matchmaker just acted on rests for [restAfterAction]. What is waiting
/// on them is never rotated away — it goes when it is handled.
///
/// Nothing here blocks anything: the two add buttons beside it always work.
abstract final class HomeNextSteps {
  static const int maxStreak = 2;
  static const Duration restAfterAction = Duration(hours: 12);

  /// The same recommendation is a new one after this long away.
  static const Duration streakForgottenAfter = Duration(days: 3);

  static const int _weekDays = 7;

  /// Every recommendation worth making now, best first.
  static List<NextStep> candidates(NextStepInputs inputs) {
    final Gender? g = inputs.gender;
    final DateTime weekStart =
        inputs.weekStart ??
        inputs.now.subtract(const Duration(days: _weekDays));

    final List<NextStep> waiting = <NextStep>[];
    if (inputs.pendingAccessRequests > 0) {
      final int n = inputs.pendingAccessRequests;
      waiting.add(
        NextStep(
          key: 'access',
          tier: NextStepTier.waiting,
          text: n == 1
              ? 'שדכן אחד ביקש גישה לכרטיס האישי שלך'
              : '$n שדכנים ביקשו גישה לכרטיס האישי שלך',
          actionLabel: 'לבקשות',
          action: NextStepAction.route,
          route: '/me?section=requests',
        ),
      );
    }
    final int dueCount = inputs.dueFriends.length + inputs.dueIdeas.length;
    final int otherWaiting = inputs.unreadNotices > dueCount
        ? inputs.unreadNotices - dueCount
        : 0;
    if (dueCount == 1 && otherWaiting == 0) {
      if (inputs.dueFriends.isNotEmpty) {
        final DueFriend f = inputs.dueFriends.first;
        waiting.add(
          NextStep(
            key: 'due:person:${f.id}',
            tier: NextStepTier.waiting,
            text: 'הגיע הזמן לחזור ל${_name(f.firstName)}',
            actionLabel: 'לכרטיס',
            action: NextStepAction.route,
            route: '/people/${f.id}',
          ),
        );
      } else {
        final NamedIdea i = inputs.dueIdeas.first;
        waiting.add(
          NextStep(
            key: 'due:idea:${i.id}',
            tier: NextStepTier.waiting,
            text: 'הגיע הזמן לחזור לרעיון של ${_pair(i)}',
            actionLabel: 'לרעיון',
            action: NextStepAction.route,
            route: '/matches/${i.id}',
          ),
        );
      }
    } else if (inputs.unreadNotices > 0 || dueCount > 0) {
      final int n = inputs.unreadNotices > dueCount
          ? inputs.unreadNotices
          : dueCount;
      waiting.add(
        NextStep(
          key: 'notices',
          tier: NextStepTier.waiting,
          text: n == 1
              ? 'יש עדכון אחד שמחכה לך'
              : 'יש לך $n בקשות ועדכונים שמחכים לך',
          actionLabel: 'להתראות',
          action: NextStepAction.route,
          route: '/reminders',
        ),
      );
    }

    final List<NextStep> openIdea = <NextStep>[
      if (inputs.staleIdeas.isNotEmpty)
        NextStep(
          key: 'stale:${inputs.staleIdeas.first.id}',
          tier: NextStepTier.openIdea,
          text: inputs.staleIdeas.length == 1
              ? 'יש רעיון שמחכה לעדכון: ${_pair(inputs.staleIdeas.first)}'
              : '${inputs.staleIdeas.length} רעיונות מחכים לשלב הבא – '
                    'אולי מתחילים מ${_pair(inputs.staleIdeas.first)}?',
          actionLabel: 'לרעיון',
          action: NextStepAction.route,
          route: '/matches/${inputs.staleIdeas.first.id}',
        ),
    ];

    final List<NextStep> cardFriends = <NextStep>[
      if (inputs.requestableCardFriends > 0)
        NextStep(
          key: 'cardFriends',
          tier: NextStepTier.cardFriends,
          text: inputs.requestableCardFriends == 1
              ? 'אחד החברים שלך הוסיף כרטיס אישי – אולי מתחילים ממנו?'
              : '${inputs.requestableCardFriends} חברים שלך הוסיפו כרטיס '
                    'אישי – אולי מתחילים מהם?',
          actionLabel: 'לבקש גישה',
          action: NextStepAction.route,
          route: '/card-friends',
        ),
    ];

    final List<NextStep> suggestions = <NextStep>[
      if (inputs.databaseSuggestions > 0)
        NextStep(
          key: 'suggestions',
          tier: NextStepTier.suggestions,
          text: inputs.databaseSuggestions == 1
              ? 'המאגר שלך מציע רעיון חדש – אולי הם מתאימים?'
              : 'המאגר שלך מציע ${inputs.databaseSuggestions} רעיונות חדשים '
                    '– מי מתאים למי?',
          actionLabel: 'לרעיונות',
          action: NextStepAction.route,
          route: '/ideas/new',
        ),
    ];

    final bool ideaThisWeek =
        inputs.lastIdeaAt != null && !inputs.lastIdeaAt!.isBefore(weekStart);
    final List<NextStep> newIdea = <NextStep>[
      if (inputs.friends >= 2)
        NextStep(
          key: 'newIdea',
          tier: NextStepTier.newIdea,
          text: ideaThisWeek
              ? 'מי עוד יכול להתאים למי? אולי רעיון נוסף השבוע'
              : 'עוד לא פתחת רעיון השבוע – מי יכול להתאים '
                    'למי?',
          actionLabel: 'לפתיחת רעיון',
          action: NextStepAction.addIdea,
        ),
    ];

    final bool friendThisWeek =
        inputs.lastFriendAt != null &&
        !inputs.lastFriendAt!.isBefore(weekStart);
    final String growText;
    if (inputs.friends == 0) {
      growText = 'מתחילים מכאן: החברים הראשונים במאגר שלך';
    } else if (inputs.friends < 10) {
      growText = 'כל חבר שמצטרף למאגר הוא עוד סיכוי להתאמה';
    } else if (!friendThisWeek) {
      growText = 'השבוע עוד לא נוסף חבר למאגר – מי עוד חסר בו?';
    } else {
      growText = 'מי עוד מהחברים שלך מחכה להצעה? אפשר להרחיב את המאגר';
    }
    final List<NextStep> grow = <NextStep>[
      NextStep(
        key: 'addFriends',
        tier: NextStepTier.addFriends,
        text: growText,
        actionLabel: 'להוספת חברים',
        action: NextStepAction.addFriends,
      ),
    ];

    final bool starting =
        HomeStage.forCount(inputs.friends) == HomeStage.starting;
    final List<NextStep> ordered = starting
        // A database still being built: grow it, and start from the friends
        // who already wrote a card, before anything is worth managing.
        ? <NextStep>[
            ...waiting,
            ...cardFriends,
            ...grow,
            ...openIdea,
            ...newIdea,
          ]
        : <NextStep>[
            ...waiting,
            ...openIdea,
            ...cardFriends,
            ...suggestions,
            ...newIdea,
            ...grow,
          ];
    return <NextStep>[
      for (final NextStep step in ordered)
        NextStep(
          key: step.key,
          tier: step.tier,
          text: step.text.forGender(g),
          actionLabel: step.actionLabel.forGender(g),
          action: step.action,
          route: step.route,
        ),
    ];
  }

  /// The one to show now, given what was shown and tapped on earlier visits.
  static NextStep? pick(
    List<NextStep> candidates,
    NextStepMemory memory,
    DateTime now,
  ) {
    if (candidates.isEmpty) {
      return null;
    }
    bool resting(NextStep step) {
      if (step.urgent) {
        return false;
      }
      final DateTime? acted = memory.actedAt;
      if (memory.actedKey == step.key &&
          acted != null &&
          now.difference(acted) < restAfterAction) {
        return true;
      }
      final DateTime? shown = memory.shownAt;
      return memory.key == step.key &&
          memory.streak >= maxStreak &&
          shown != null &&
          now.difference(shown) < streakForgottenAfter;
    }

    for (final NextStep step in candidates) {
      if (!resting(step)) {
        return step;
      }
    }
    // Everything has had its turn: the best one again.
    return candidates.first;
  }

  static String _name(String first) => first.trim().isEmpty ? 'חבר' : first;

  static String _pair(NamedIdea idea) =>
      '${_name(idea.maleName)} ו${_name(idea.femaleName)}';
}

/// Where [NextStepMemory] lives between launches: the settings box, written
/// through [persistHomeSetting] like every store the home screen reads.
/// Device-only (see `AccountSyncCodec`): it is written on every visit, and
/// which recommendation one phone showed says nothing to another.
abstract final class NextStepStore {
  static const String key = 'home.nextStep';

  static NextStepMemory? _cache;

  static NextStepMemory get memory {
    final NextStepMemory? cached = _cache;
    if (cached != null) {
      return cached;
    }
    NextStepMemory read = NextStepMemory.empty;
    if (Hive.isBoxOpen('settings')) {
      final Object? raw = Hive.box<dynamic>('settings').get(key);
      if (raw is String && raw.isNotEmpty) {
        try {
          read = NextStepMemory.fromJson(jsonDecode(raw));
        } catch (_) {}
      }
    }
    return _cache = read;
  }

  static void save(NextStepMemory memory) {
    _cache = memory;
    persistHomeSetting(key, jsonEncode(memory.toJson()));
  }

  /// For tests.
  static void reset() => _cache = null;

  /// A sign-out: the next account starts from nothing.
  static void forget() {
    _cache = NextStepMemory.empty;
    persistHomeSetting(key, '');
  }
}
