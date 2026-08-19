import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/activity_stats.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_achievements.dart';
import 'package:shadchan/utils/community_highlight.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/dating_history.dart';
import 'package:shadchan/utils/monthly_stats.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "הפעילות שלי" — everything the app counts, on one screen, in the order a
/// matchmaker cares about it.
///
/// **The hierarchy is the design.** ההישג → הנתונים → אבני הדרך → הקצב →
/// פעילות הקהילה → הדירוג. It opens by naming the best thing that has happened
/// in this database, in a sentence rather than a figure, and only then turns
/// the work into counts, ladders and a score. The community comes after all of
/// that, and the competitive part comes last. Reversed — leaderboard first —
/// the same figures read as a game with matchmaking as its scoring mechanism,
/// which is the one thing this screen must not feel like.
///
/// **Warm, and never loud.** The page is allowed to say תודה and to notice a
/// milestone, because a matchmaker who married two people off deserves better
/// than a number in a grey box. What it is not allowed to do is celebrate
/// *nothing*: every congratulation here is attached to something that actually
/// happened, an empty database is greeted with an invitation rather than
/// confetti, and the only gold on the page is still first place on the board.
///
/// The personal half needs no network at all. Only the community half waits —
/// and for a matchmaker who has not connected an account there is no community
/// half at all. Their own cards are unchanged, and where the totals and the
/// board would be there is one invitation. That is the whole of the gate: their
/// own history is theirs whether or not they ever sign in.
class CommunityActivityScreen extends StatefulWidget {
  const CommunityActivityScreen({super.key});

  /// How many Hebrew months the personal chart reaches back.
  static const int chartMonths = 6;

  @override
  State<CommunityActivityScreen> createState() =>
      _CommunityActivityScreenState();
}

class _CommunityActivityScreenState extends State<CommunityActivityScreen> {
  CommunityPeriod _minePeriod = CommunityPeriod.week;

  /// Bumped on every refresh, and handed to the two cards that read the
  /// network. Changing a child's key rebuilds it from `initState`, which is
  /// what makes "אני מרענן" mean a genuinely fresh read rather than the same
  /// cached figures drawn again.
  int _liveGeneration = 0;

  @override
  void initState() {
    super.initState();
    // Not during the opening frame: this recomputes the local ledgers, writes
    // this device's counters and then reads the community back.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  /// Recount, republish, re-read — in that order, which is the only order that
  /// can show the truth.
  ///
  /// **This is what fixed "פעילות הקהילה: 0".** The community figure is a sum
  /// over what every device has published, and this device publishes at app
  /// open and app pause — so a matchmaker who opened the app, added twenty
  /// friends and came straight here was reading a total that did not yet
  /// contain their own morning, out of a process cache that would not be asked
  /// again for minutes. Publishing first and forcing the read afterwards means
  /// the number on screen includes the work that was done a moment ago, and
  /// pulling down does it again.
  Future<void> _refresh() async {
    await context.read<CommunityProvider>().refresh(
      people: context.read<PersonRepository>(),
      matches: context.read<MatchRepository>(),
      profile: context.read<UserProfileProvider>(),
    );
    if (mounted) {
      setState(() => _liveGeneration++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CommunityProvider community = context.watch<CommunityProvider>();
    final bool signedIn = context.watch<AccountProvider>().isSignedIn;
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final UserProfileProvider profile = context.watch<UserProfileProvider>();

    final List<Person> people = personRepository.getAll();
    final List<MatchIdea> matches = matchRepository.getAll();
    final List<MatchStatusEvent> statusEvents = matchRepository
        .getAllStatusEvents();
    final Set<String> excluded = DatingCountExclusions.all();

    final ActivityBreakdown everything = ActivityStats.allTime(
      people: people,
      matches: matches,
      matchStatusEvents: statusEvents,
      excludedFromDating: excluded,
    );

    final List<ActivityBucket> bars = ActivityStats.monthlyBars(
      periods: MonthlyStats.buildPeriods(
        DateTime.now(),
        CommunityActivityScreen.chartMonths,
      ),
      people: people,
      matches: matches,
      matchStatusEvents: statusEvents,
      excludedFromDating: excluded,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('הפעילות שלי'), centerTitle: true),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: <Widget>[
              _CelebrationHeader(
                breakdown: everything,
                firstName: profile.firstName ?? profile.name ?? '',
              ),
              const SizedBox(height: 16),
              _MyNumbersCard(breakdown: everything),
              const SizedBox(height: 16),
              _MilestonesCard(breakdown: everything),
              const SizedBox(height: 16),
              _MyActivityCard(
                period: _minePeriod,
                onPeriod: (CommunityPeriod period) =>
                    setState(() => _minePeriod = period),
                points: community.myPoints(_minePeriod),
                bars: bars,
              ),
              const SizedBox(height: 16),
              if (signedIn) ...<Widget>[
                _CommunityActivityCard(
                  key: ValueKey<int>(_liveGeneration),
                  private: community.isPrivate,
                ),
                const SizedBox(height: 16),
                _LeaderboardCard(key: ValueKey<int>(-1 - _liveGeneration)),
              ] else
                const CommunityCard(
                  child: CommunitySignInCard.communityIsForMembers(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The palette the four kinds of work are drawn in.
///
/// Brand tones the app already wears — the stone blue, the amber, the olive and
/// the copper — one per kind of act, so a wedding is never the same colour as a
/// contact import. Lightened in the dark theme, where the saturated originals
/// are too dark to read as ink on their own wash.
Color _tone(Color base, ThemeData theme) =>
    theme.brightness == Brightness.dark
    ? Color.lerp(base, Colors.white, 0.45)!
    : base;

const Color _friendsTone = AppColors.primaryDark;
const Color _ideasTone = AppColors.statusChecking;
const Color _couplesTone = AppColors.statusDating;
const Color _weddingsTone = AppColors.secondary;

// --- 0. The one sentence worth opening on ------------------------------------

/// The header: who this is, and the best true thing that can be said about it.
///
/// **The headline is derived, never generic.** "כל הכבוד!" over an empty
/// database is the app congratulating somebody for installing it, which is
/// worth less than nothing; the line here names the highest real thing that has
/// happened — a wedding if there was one, otherwise a couple, otherwise an
/// idea, otherwise a friend — and when there is genuinely nothing yet it says
/// so warmly and points at the first step.
class _CelebrationHeader extends StatelessWidget {
  const _CelebrationHeader({required this.breakdown, required this.firstName});

  final ActivityBreakdown breakdown;
  final String firstName;

  ({IconData icon, Color tone, String headline, String body}) get _story {
    if (breakdown.engagements > 0) {
      return (
        icon: Icons.diamond_outlined,
        tone: _weddingsTone,
        headline: breakdown.engagements == 1
            ? 'בית אחד כבר קם בזכותך'
            : '${breakdown.engagements} בתים כבר קמו בזכותך',
        body:
            'מאחורי כל אחד מהם היו מחשבה, טלפונים והרבה סבלנות. '
            'אין הרבה דברים בעולם ששווים את זה.',
      );
    }
    if (breakdown.couples > 0) {
      return (
        icon: Icons.favorite_rounded,
        tone: _couplesTone,
        headline: breakdown.couples == 1
            ? 'זוג אחד כבר יצא לדרך בזכותך'
            : '${breakdown.couples} זוגות כבר יצאו לדרך בזכותך',
        body:
            'כל זוג כזה התחיל ממחשבה שלך על שני אנשים. '
            'שיהיה בשעה טובה.',
      );
    }
    if (breakdown.ideas > 0) {
      return (
        icon: Icons.lightbulb_outline_rounded,
        tone: _ideasTone,
        headline: breakdown.ideas == 1
            ? 'הרעיון הראשון שלך כבר בדרך'
            : '${breakdown.ideas} רעיונות כבר יצאו מהראש שלך אל המציאות',
        body:
            'לא כל רעיון מגיע לחופה, אבל בלי הרעיונות שום דבר לא קורה. '
            'ממשיכים.',
      );
    }
    if (breakdown.friends > 0) {
      return (
        icon: Icons.people_alt_outlined,
        tone: _friendsTone,
        headline: breakdown.friends == 1
            ? 'החבר הראשון שלך במאגר'
            : '${breakdown.friends} חברים כבר במאגר שלך',
        body:
            'כל שם כאן הוא אדם אמיתי שמחכה לרעיון הנכון. '
            'עכשיו מתחיל החלק המעניין.',
      );
    }
    return (
      icon: Icons.auto_awesome_outlined,
      tone: _friendsTone,
      headline: 'הכול מתחיל מחבר אחד',
      body:
          'מוסיפים חבר, פותחים רעיון — והמספרים בעמוד הזה מתחילים לספר סיפור.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final ({IconData icon, Color tone, String headline, String body}) story =
        _story;
    final Color tone = _tone(story.tone, theme);
    final String name = firstName.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[
            tone.withValues(alpha: dark ? 0.20 : 0.14),
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: dark ? 0.22 : 0.16),
                ),
                child: Icon(story.icon, size: 24, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name.isEmpty ? 'הפעילות שלך' : 'שלום, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            story.headline,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            story.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.55,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// --- 1. הנתונים שלך ---------------------------------------------------------

/// Four real counts, all-time, and no period switch.
///
/// **These are not points.** "3 חתונות" is a fact about three homes; turning it
/// into 150 anything is the second question, and it is asked in the card below
/// rather than here. There is no week/month switch either: a couple you married
/// last year is still a couple you married, and a matchmaker looking at their
/// own history should not have to choose a window to see it.
class _MyNumbersCard extends StatelessWidget {
  const _MyNumbersCard({required this.breakdown});

  final ActivityBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    return CommunityCard(
      title: 'הדרך שלך עד היום',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _NumberTile(
                  value: breakdown.friends,
                  label: 'חברים שהוספת',
                  icon: Icons.people_alt_outlined,
                  tone: _friendsTone,
                  metric: MonthlyStatMetric.people,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumberTile(
                  value: breakdown.ideas,
                  label: 'רעיונות שפתחת',
                  icon: Icons.lightbulb_outline_rounded,
                  tone: _ideasTone,
                  metric: MonthlyStatMetric.ideas,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _NumberTile(
                  value: breakdown.couples,
                  label: 'זוגות שהוצאת לדייט',
                  icon: Icons.favorite_outline_rounded,
                  tone: _couplesTone,
                  metric: MonthlyStatMetric.dating,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumberTile(
                  value: breakdown.engagements,
                  label: 'חתונות/אירוסין',
                  icon: Icons.diamond_outlined,
                  tone: _weddingsTone,
                  metric: MonthlyStatMetric.weddings,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One of the four, and the way into the records behind it.
///
/// A tile with its own tint rather than a figure in a row: four counts of four
/// different things, drawn identically, read as one table of numbers, and the
/// wedding count deserves not to look like the contact count.
class _NumberTile extends StatelessWidget {
  const _NumberTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.tone,
    required this.metric,
  });

  final int value;
  final String label;
  final IconData icon;
  final Color tone;

  /// Which list of records this number opens. The drill-downs already exist on
  /// the monthly stats screen and are the honest answer to "which ones?".
  final MonthlyStatMetric metric;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = _tone(tone, theme);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/stats/month/${metric.name}'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: ink.withValues(alpha: dark ? 0.14 : 0.10),
          border: Border.all(color: ink.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: ink),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                CommunityFigure.format(value),
                maxLines: 1,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  color: ink,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 2,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 2. אבני דרך -------------------------------------------------------------

/// The ladders, and where the matchmaker stands on each of them.
///
/// **The same ladders the app already congratulates people on**
/// ([CommunityAchievements]), drawn instead of announced. A milestone dialog is
/// a moment and then it is gone; this is the place somebody can come back to
/// and see that eleven more friends is a round number, which is a far better
/// use of the same four lists.
///
/// **Nothing here is a target set by the app.** The next rung is stated, not
/// demanded — no streaks, no "you are behind", no comparison with anybody —
/// because the only thing worse than an app that ignores good work is one that
/// nags about it.
class _MilestonesCard extends StatelessWidget {
  const _MilestonesCard({required this.breakdown});

  final ActivityBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    return CommunityCard(
      title: 'אבני דרך',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MilestoneRow(
            icon: Icons.people_alt_outlined,
            tone: _friendsTone,
            label: 'חברים במאגר',
            value: breakdown.friends,
            ladder: CommunityAchievements.friendMilestones,
            unit: 'חברים',
          ),
          _MilestoneRow(
            icon: Icons.lightbulb_outline_rounded,
            tone: _ideasTone,
            label: 'רעיונות שנפתחו',
            value: breakdown.ideas,
            ladder: CommunityAchievements.ideaMilestones,
            unit: 'רעיונות',
          ),
          _MilestoneRow(
            icon: Icons.favorite_outline_rounded,
            tone: _couplesTone,
            label: 'זוגות שיצאו לדרך',
            value: breakdown.couples,
            ladder: CommunityAchievements.coupleMilestones,
            unit: 'זוגות',
          ),
          _MilestoneRow(
            icon: Icons.local_fire_department_outlined,
            tone: _weddingsTone,
            label: 'נקודות פעילות',
            value: breakdown.points,
            ladder: CommunityAchievements.pointMilestones,
            unit: 'נקודות',
          ),
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    required this.ladder,
    required this.unit,
  });

  final IconData icon;
  final Color tone;
  final String label;
  final int value;
  final List<int> ladder;

  /// The word after the number in "עוד 7 חברים".
  final String unit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color ink = _tone(tone, theme);
    final int? reached = CommunityAchievements.reached(ladder, value);
    final int? next = CommunityAchievements.next(ladder, value);

    // From the rung just passed to the one ahead, so a bar that has just been
    // reset by a milestone starts empty rather than nearly full.
    final int floor = reached ?? 0;
    final double progress = next == null || next <= floor
        ? 1
        : ((value - floor) / (next - floor)).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (reached != null) ...<Widget>[
                Icon(
                  Icons.workspace_premium_outlined,
                  size: 14,
                  color: ink.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 3),
                Text(
                  CommunityFigure.format(reached),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                CommunityFigure.format(value),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: ink.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(
                ink.withValues(alpha: 0.85),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            next == null
                ? 'עברת את כל אבני הדרך כאן. מרשים.'
                : 'עוד ${CommunityFigure.format(next - value)} $unit '
                      'ל־${CommunityFigure.format(next)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// --- 3. הקצב שלך ------------------------------------------------------------

class _MyActivityCard extends StatelessWidget {
  const _MyActivityCard({
    required this.period,
    required this.onPeriod,
    required this.points,
    required this.bars,
  });

  final CommunityPeriod period;
  final ValueChanged<CommunityPeriod> onPeriod;
  final int points;
  final List<ActivityBucket> bars;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return CommunityCard(
      title: 'הקצב שלך',
      trailing: TextButton(
        onPressed: () => context.push('/stats/month'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('לפי חודשים'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CommunityPeriodTabs(
            selected: period,
            onChanged: onPeriod,
            periods: CommunityPeriodTabs.weekMonthAllTime,
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: CommunityFigure(
                  value: points,
                  label: 'נקודות פעילות ${period.label}',
                ),
              ),
              const SizedBox(width: 8),
              // One generous word for the window, from the same scale the
              // monthly screen uses. Never comparative and never negative —
              // see `ActivityStats.grade`.
              _GradeChip(points: points),
            ],
          ),
          const _WeeklyBestLine(),
          const SizedBox(height: 16),
          _ActivityChart(bars: bars),
          const SizedBox(height: 10),
          Text(
            ActivityPoints.shortExplanation,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// "קצב יפה" — the word beside the figure.
class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: lead.withValues(alpha: 0.14),
        border: Border.all(color: lead.withValues(alpha: 0.24)),
      ),
      child: Text(
        ActivityStats.grade(points),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: lead,
        ),
      ),
    );
  }
}

/// The personal weekly best, said in one line and never in a window.
///
/// It used to raise a "שיא שבועי חדש!!!" dialog on the launch *after* the week
/// it happened in — an interruption, about something the matchmaker had already
/// forgotten, arriving with no context. Here it costs a line, sits beside the
/// figure it is a record of, and is read by somebody who came to look at their
/// own numbers.
class _WeeklyBestLine extends StatelessWidget {
  const _WeeklyBestLine();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int best = CommunityProfileStore.bestWeek;
    if (best <= 0) {
      return const SizedBox.shrink();
    }

    final bool isThisWeek =
        CommunityProfileStore.bestWeekKey == CommunityPeriods.weekKey();
    final Color lead = communityLead(theme);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: lead.withValues(alpha: 0.09),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              isThisWeek
                  ? Icons.celebration_outlined
                  : Icons.trending_up_rounded,
              size: 16,
              color: lead,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isThisWeek
                    ? 'שיא חדש השבוע! $best נקודות'
                    : 'השיא השבועי שלך: $best נקודות',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: isThisWeek ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The personal activity chart: one bar per Hebrew month, oldest first.
///
/// **Only the reader is on it.** A second series for the community would turn
/// a picture of somebody's own year into a picture of how far behind they are,
/// and the community's own figures are two cards further down where they belong.
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.bars});

  final List<ActivityBucket> bars;

  static const double _height = 76;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);
    final int peak = bars.fold<int>(
      0,
      (int max, ActivityBucket bucket) =>
          bucket.points > max ? bucket.points : max,
    );

    if (bars.isEmpty || peak == 0) {
      return Text(
        'הגרף יתמלא ברגע שתהיה פעילות ראשונה.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (final ActivityBucket bucket in bars)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${bucket.points}',
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: bucket.points == 0
                          ? theme.colorScheme.onSurfaceVariant
                          : lead,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // A hairline for an empty month rather than nothing at all:
                  // a gap in a row of bars reads as missing data.
                  Container(
                    height: (_height * bucket.points / peak).clamp(
                      2.0,
                      _height,
                    ),
                    decoration: BoxDecoration(
                      color: lead.withValues(
                        alpha: bucket.points == 0 ? 0.2 : 0.75,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bucket.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// --- 4. פעילות הקהילה -------------------------------------------------------

class _CommunityActivityCard extends StatefulWidget {
  const _CommunityActivityCard({super.key, required this.private});

  /// Whether this matchmaker has switched sharing off. It changes nothing about
  /// what is *read* — the community's figures are theirs to look at either way
  /// — and adds one line saying their own work is not part of the sum.
  final bool private;

  @override
  State<_CommunityActivityCard> createState() => _CommunityActivityCardState();
}

class _CommunityActivityCardState extends State<_CommunityActivityCard> {
  CommunityPeriod _period = CommunityPeriod.week;
  final Map<CommunityPeriod, CommunityTotals> _totals =
      <CommunityPeriod, CommunityTotals>{};
  CommunityTotals? _week;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Straight past the process cache: this widget is rebuilt from scratch
    // whenever the screen refreshes, and a refresh that redraws the same
    // cached numbers is not a refresh.
    _load(_period, force: true);
  }

  Future<void> _load(CommunityPeriod period, {bool force = false}) async {
    // A window whose figures came back is not asked for again; one that never
    // resolved — no account yet, no network — always is. That distinction is
    // what stops an unlucky first read from freezing the card on zeroes for
    // the rest of the session. See [CommunityTotals.resolved].
    if (!force && (_totals[period]?.resolved ?? false)) {
      return;
    }
    setState(() => _loading = true);
    final CommunityTotals totals = await CommunityService.totals(
      period,
      forceRefresh: force,
    );
    // The human sentence is always about the week, whichever window is on
    // screen: "השבוע יצאו 6 זוגות" is news, and "מאז ומעולם יצאו 6 זוגות" is a
    // statistic.
    final CommunityTotals week = period == CommunityPeriod.week
        ? totals
        : _week ??
              await CommunityService.totals(
                CommunityPeriod.week,
                forceRefresh: force,
              );
    if (!mounted) {
      return;
    }
    setState(() {
      _totals[period] = totals;
      _week = week;
      _loading = false;
    });
  }

  void _select(CommunityPeriod period) {
    setState(() => _period = period);
    _load(period);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityTotals? totals = _totals[_period];
    final CommunityTotals? week = _week;
    final String? highlight = week == null || !week.resolved
        ? null
        : CommunityHighlight.forWeek(
            week,
            seed: CommunityHighlight.seedFor(DateTime.now()),
          );

    return CommunityCard(
      title: 'פעילות הקהילה',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (highlight != null) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.volunteer_activism_outlined,
                  size: 16,
                  color: communityLead(theme),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    highlight,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          CommunityPeriodTabs(
            selected: _period,
            onChanged: _select,
            periods: CommunityPeriodTabs.weekMonthAllTime,
          ),
          const SizedBox(height: 14),
          if (totals == null && _loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...<Widget>[
            CommunityFigure(
              value: totals?.points ?? 0,
              label: 'נקודות פעילות ${_period.label}',
            ),
            const SizedBox(height: 10),
            // One quiet list rather than six cards competing with each other.
            CommunityStatLine(
              icon: Icons.person_add_alt_1_outlined,
              label: 'חברים שנוספו',
              value: totals?.friends ?? 0,
            ),
            CommunityStatLine(
              icon: Icons.lightbulb_outline_rounded,
              label: 'רעיונות שנפתחו',
              value: totals?.ideas ?? 0,
            ),
            CommunityStatLine(
              icon: Icons.favorite_outline_rounded,
              label: 'זוגות שהתחילו לצאת',
              value: totals?.couples ?? 0,
            ),
            CommunityStatLine(
              icon: Icons.diamond_outlined,
              label: 'אירוסין/חתונות',
              value: totals?.engagements ?? 0,
            ),
            CommunityStatLine(
              icon: Icons.groups_outlined,
              label: 'שדכנים פעילים',
              value: totals?.activeMatchmakers ?? 0,
            ),
            // A read that never left the device says so, instead of passing
            // itself off as a community that did nothing.
            if (totals != null && !totals.resolved) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'לא הצלחנו לטעון את נתוני הקהילה כרגע. אפשר למשוך את המסך '
                'למטה כדי לנסות שוב.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
            if (widget.private) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.shield_moon_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '"שמור על הפרטיות שלי" פעיל, ולכן הפעילות שלך לא נכללת '
                      'במספרים האלה.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// --- 5. דירוג השדכנים -------------------------------------------------------

class _LeaderboardCard extends StatefulWidget {
  const _LeaderboardCard({super.key});

  @override
  State<_LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends State<_LeaderboardCard> {
  CommunityPeriod _period = CommunityPeriod.week;
  CommunityLeaderboard? _board;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);
    final CommunityProvider community = context.read<CommunityProvider>();
    final CommunityLeaderboard board = await CommunityService.leaderboard(
      _period,
      includeMe: !community.isHidden,
      myPoints: community.myPoints(_period),
      forceRefresh: force,
    );
    if (mounted) {
      setState(() {
        _board = board;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityProvider community = context.watch<CommunityProvider>();
    final CommunityLeaderboard? board = _board;

    return CommunityCard(
      title: 'דירוג השדכנים',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CommunityPeriodTabs(
            selected: _period,
            onChanged: (CommunityPeriod period) {
              setState(() => _period = period);
              _load();
            },
            // The only place "היום" appears. A daily board resets at midnight
            // Israel time and is worth checking; a daily *total* is noise.
            periods: CommunityPeriod.values,
          ),
          const SizedBox(height: 12),
          if (_loading && board == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (board == null || board.top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                board != null && !board.resolved
                    ? 'לא הצלחנו לטעון את הדירוג כרגע. אפשר למשוך את המסך '
                          'למטה כדי לנסות שוב.'
                    : 'עוד לא נרשמה פעילות בתקופה הזאת.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...<Widget>[
            for (int i = 0; i < board.top.length; i++)
              CommunityRankRow(place: i + 1, entry: board.top[i]),
            if (community.isPrivate) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                '"שמור על הפרטיות שלי" פעיל, ולכן אינך מופיע בדירוג.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ] else if (community.isHidden) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'הסתרת את עצמך מהדירוג, ולכן גם המיקום שלך לא מוצג.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ] else if (board.myRank != null &&
                board.myRank! > CommunityService.leaderboardSize) ...<Widget>[
              const Divider(height: 22),
              _MyPlaceLine(board: board),
            ],
          ],
        ],
      ),
    );
  }
}

/// Where the reader stands when they are not in the ten.
///
/// **A position and a score, and nothing else.** No "עוד 4 פעולות ואתה עוקף
/// את…": a board is competition enough, and a running commentary on the gap
/// turns other matchmakers into obstacles.
class _MyPlaceLine extends StatelessWidget {
  const _MyPlaceLine({required this.board});

  final CommunityLeaderboard board;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = board.activeMatchmakers < (board.myRank ?? 0)
        ? board.myRank!
        : board.activeMatchmakers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'המיקום שלך: ${board.myRank} מתוך $total שדכנים פעילים',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${CommunityFigure.format(board.myPoints)} נקודות פעילות',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
