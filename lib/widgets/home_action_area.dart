import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/friends_with_cards_screen.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/reminder_log.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_navigation.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/home_config.dart';
import 'package:shadchan/utils/home_next_step.dart';
import 'package:shadchan/utils/home_open_ideas.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/utils/new_idea_suggestions.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/widgets/home_add_hub.dart';
import 'package:shadchan/widgets/notification_center.dart';

T? _maybeWatch<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

/// "מה עושים עכשיו?" — the area right under the greeting: the title, the one
/// recommendation the app thinks matters most right now, and the main add
/// button between "הוסף חברים" and "הוסף רעיון".
///
/// **The choice is made once per visit.** A recommendation that changed under
/// the reader's thumb while they were deciding would be worse than none, so
/// the key picked on arrival is held until the matchmaker comes back to the
/// app (or taps the wordmark, [visit]); only if what it described has gone —
/// the reminder was read, the request answered — is another one chosen on the
/// spot. See [HomeNextSteps] for the order and the rotation.
class HomeActionArea extends StatefulWidget {
  const HomeActionArea({
    super.key,
    required this.openIdeas,
    required this.visit,
    this.inputsOverride,
  });

  /// Every open proposal, as the board reads them.
  final List<HomeOpenIdea> openIdeas;

  /// Changes on every new visit to the home screen (arrival, resume, a tap
  /// on the wordmark). A new value lets the rotation take its next turn.
  final int visit;

  /// Test seam: the inputs, instead of reading them from the providers.
  final NextStepInputs? inputsOverride;

  @override
  State<HomeActionArea> createState() => _HomeActionAreaState();
}

class _HomeActionAreaState extends State<HomeActionArea> {
  /// The key shown on this visit, held until the next one.
  String? _heldKey;
  int _heldVisit = -1;

  String? _pairsKey;
  int _pairs = 0;

  int _suggestionCount(List<Person> everyone, List<MatchIdea> matches) {
    DateTime latest = DateTime(2000);
    for (final Person p in everyone) {
      if (p.updatedAt.isAfter(latest)) latest = p.updatedAt;
    }
    for (final MatchIdea m in matches) {
      if (m.updatedAt.isAfter(latest)) latest = m.updatedAt;
    }
    final String key =
        '${everyone.length}|${matches.length}|${latest.millisecondsSinceEpoch}';
    if (key != _pairsKey) {
      _pairsKey = key;
      _pairs = NewIdeaSuggestions.build(
        people: everyone,
        matches: matches,
        dismissedFor: SuggestionDismissals.dismissedFor,
      ).length;
    }
    return _pairs;
  }

  NextStepInputs _gather(BuildContext context) {
    final PersonRepository people = context.watch<PersonRepository>();
    final MatchRepository matches = context.watch<MatchRepository>();
    final Gender? gender = _maybeWatch<UserProfileProvider>(context)?.gender;
    final CardAccessProvider? access = _maybeWatch<CardAccessProvider>(context);
    final DateTime now = DateTime.now();
    final ReminderLog log = ReminderLog.instance;

    final List<DueFriend> dueFriends = <DueFriend>[];
    PersonReminders.all().forEach((String id, DateTime at) {
      final Person? person = people.getById(id);
      if (person != null &&
          !at.isAfter(now) &&
          !log.isRead(HomeItemKind.person, id, at)) {
        dueFriends.add(
          DueFriend(id: id, firstName: person.firstName, gender: person.gender),
        );
      }
    });

    NamedIdea? named(MatchIdea match) {
      final Person? a = people.getById(match.personAId);
      final Person? b = people.getById(match.personBId);
      if (a == null || b == null) return null;
      final bool aFirst = a.gender != Gender.female;
      return NamedIdea(
        id: match.id,
        maleName: (aFirst ? a : b).firstName,
        femaleName: (aFirst ? b : a).firstName,
      );
    }

    final List<MatchIdea> all = matches.getAll();
    final List<NamedIdea> dueIdeas = <NamedIdea>[];
    for (final MatchIdea match in all) {
      final DateTime? at = match.reminderDate;
      if (at != null &&
          !at.isAfter(now) &&
          !match.status.isArchived &&
          !log.isRead(HomeItemKind.idea, match.id, at)) {
        final NamedIdea? idea = named(match);
        if (idea != null) dueIdeas.add(idea);
      }
    }
    final Set<String> dueIdeaIds = <String>{
      for (final NamedIdea i in dueIdeas) i.id,
    };
    final List<MatchIdea> stale = <MatchIdea>[
      for (final HomeOpenIdea open in widget.openIdeas)
        if (!dueIdeaIds.contains(open.match.id) &&
            MatchStaleness.isStale(open.match, now: now))
          open.match,
    ]..sort((MatchIdea a, MatchIdea b) => a.updatedAt.compareTo(b.updatedAt));

    DateTime? lastIdea;
    for (final MatchIdea m in all) {
      if (lastIdea == null || m.createdAt.isAfter(lastIdea)) {
        lastIdea = m.createdAt;
      }
    }
    DateTime? lastFriend;
    final List<Person> everyone = people.getAll();
    for (final Person p in everyone) {
      if (!p.hidden &&
          (lastFriend == null || p.createdAt.isAfter(lastFriend))) {
        lastFriend = p.createdAt;
      }
    }

    final int friends = people.databaseCount;
    return NextStepInputs(
      friends: friends,
      now: now,
      gender: gender,
      pendingAccessRequests: access?.pendingRequests.length ?? 0,
      unreadNotices: NotificationCenter.unreadCount(context),
      dueFriends: dueFriends,
      dueIdeas: dueIdeas,
      staleIdeas: <NamedIdea>[for (final MatchIdea m in stale) ?named(m)],
      requestableCardFriends: access == null
          ? 0
          : FriendsWithCards.build(
              access: access,
              people: people,
              inbox: _maybeWatch<InboxProvider>(context),
            ).where((f) => f.state == FriendCardState.requestable).length,
      databaseSuggestions: friends > HomeConfig.databaseIdeasMinFriends
          ? _suggestionCount(everyone, all)
          : 0,
      lastIdeaAt: lastIdea,
      lastFriendAt: lastFriend,
      weekStart: CommunityPeriods.startOf(CommunityPeriod.week),
    );
  }

  NextStep? _choose(List<NextStep> candidates) {
    final DateTime now = DateTime.now();
    NextStep? held;
    for (final NextStep step in candidates) {
      if (step.key == _heldKey) held = step;
    }
    final NextStep? first = candidates.isEmpty ? null : candidates.first;
    // Still on the same visit, and what was chosen is still true: keep it —
    // unless something genuinely waiting has appeared above it since.
    if (held != null &&
        _heldVisit == widget.visit &&
        !(first != null && first.urgent && !held.urgent)) {
      return held;
    }
    final NextStep? picked = HomeNextSteps.pick(
      candidates,
      NextStepStore.memory,
      now,
    );
    if (picked != null && picked.key != _heldKey) {
      // A new choice is a new showing; holding the old one is not.
      NextStepStore.save(NextStepStore.memory.shown(picked.key, now));
    } else if (picked != null && _heldVisit != widget.visit) {
      NextStepStore.save(NextStepStore.memory.shown(picked.key, now));
    }
    _heldKey = picked?.key;
    _heldVisit = widget.visit;
    return picked;
  }

  void _act(NextStep step) {
    NextStepStore.save(NextStepStore.memory.acted(step.key, DateTime.now()));
    switch (step.action) {
      case NextStepAction.addFriends:
        AddPeopleDialog.show(context);
      case NextStepAction.addIdea:
        context.push('/matches/add');
      case NextStepAction.route:
        final String? route = step.route;
        if (route != null) {
          if (route.startsWith('/me')) {
            context.go(route);
          } else {
            AppNavigation.open(context, route);
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final NextStepInputs inputs = widget.inputsOverride ?? _gather(context);
    final NextStep? step = _choose(HomeNextSteps.candidates(inputs));

    return HomeAddHub(
      gender: inputs.gender,
      onAddPeople: () => AddPeopleDialog.show(context),
      onAddIdea: () => context.push('/matches/add'),
      header: _Header(
        step: step,
        onTap: step == null ? null : () => _act(step),
      ),
    );
  }
}

/// The title and the one recommendation under it.
class _Header extends StatelessWidget {
  const _Header({required this.step, required this.onTap});

  static const String title = 'מה עושים עכשיו?';

  final NextStep? step;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final NextStep? step = this.step;
    final Color accent = step != null && step.urgent
        ? (dark ? AppColors.secondaryDarkDm : AppColors.secondary)
        : (dark ? AppColors.primaryDarkDm : AppColors.primaryDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        if (step != null) ...<Widget>[
          const SizedBox(height: 10),
          Material(
            color: accent.withValues(alpha: dark ? 0.16 : 0.09),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: ValueKey<String>('nextStep:${step.key}'),
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
                child: Row(
                  children: <Widget>[
                    Icon(
                      step.urgent
                          ? Icons.notifications_active_outlined
                          : Icons.auto_awesome_outlined,
                      size: 20,
                      color: accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 0,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                step.actionLabel,
                                maxLines: 1,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: accent,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "השבוע 3/5 פעולות" — one quiet bar under the action area.
///
/// **A pace, not a task.** Five things a week is what a matchmaker who keeps
/// their database alive tends to do; the bar says how the week is going and
/// nothing happens when it is not full. Counted as *actions* — a friend added,
/// an idea opened, a couple out, a wedding — by the same [ActivityStats] the
/// activity screen counts with, from Sunday (Israel). Points are not what
/// this says; a wedding is one thing done, not fifty.
class HomeWeeklyProgress extends StatelessWidget {
  const HomeWeeklyProgress({super.key, this.target = defaultTarget});

  static const int defaultTarget = 5;

  final int target;

  /// The week's actions.
  static int actionsThisWeek({
    required PersonRepository people,
    required MatchRepository matches,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    final DateTime start =
        CommunityPeriods.startOf(CommunityPeriod.week) ??
        at.subtract(const Duration(days: 7));
    final ActivityBreakdown week = ActivityStats.breakdownBetween(
      start: start,
      end: ActivityStats.endOfToday(at),
      people: people.getAll(),
      matches: matches.getAll(),
      matchStatusEvents: matches.getAllStatusEvents(),
      excludedFromDating: DatingCountExclusions.all(),
      now: at,
    );
    return week.friends + week.ideas + week.couples + week.engagements;
  }

  @override
  Widget build(BuildContext context) {
    final int done = actionsThisWeek(
      people: context.watch<PersonRepository>(),
      matches: context.watch<MatchRepository>(),
    );
    return WeeklyProgressBar(done: done, target: target);
  }
}

/// The drawing of [HomeWeeklyProgress], given the figures.
class WeeklyProgressBar extends StatelessWidget {
  const WeeklyProgressBar({
    super.key,
    required this.done,
    required this.target,
  });

  final int done;
  final int target;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool reached = done >= target;
    final Color fill = reached
        ? (dark ? AppColors.statusDatingDm : AppColors.statusDating)
        : (dark ? AppColors.secondaryDarkDm : AppColors.secondary);
    final String label = reached
        ? 'השבוע $done פעולות – כל הכבוד!'
        : 'השבוע $done/$target פעולות';

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: <Widget>[
            Flexible(
              flex: 0,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 0,
                    end: target <= 0 ? 1 : (done / target).clamp(0, 1),
                  ),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (BuildContext context, double value, _) =>
                      LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        backgroundColor: dark
                            ? AppColors.dividerDm
                            : AppColors.divider,
                        valueColor: AlwaysStoppedAnimation<Color>(fill),
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
