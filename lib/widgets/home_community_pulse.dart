import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/dialogs/mazel_tov_sheet.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/community_engagements_service.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/services/mazel_tov_service.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/utils/community_challenge.dart';
import 'package:shadchan/utils/community_highlight.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "מה קורה בקהילה עכשיו" — the one live thing on the home screen.
///
/// **Small, and alive.** Everything else on this page describes the reader's
/// own database, which by definition only changes when they change it. This is
/// the single area that moves on its own: one short true sentence at a time —
/// "18 רעיונות נפתחו היום", "6 זוגות התחילו לצאת השבוע", "מזל טוב! זוג נוסף
/// התארס" — turning over every few seconds under a heading and a slow green
/// pulse. A matchmaker works alone; this is the app saying, in the least
/// intrusive way it can, that they are not the only one working.
///
/// **Under it, the week's shared challenge.** One bar, one target, belonging to
/// everybody — see [CommunityChallenge] for why it is deliberately not a
/// personal goal and how the target is picked from last week's record.
///
/// **It draws nothing rather than drawing nothing interesting.** No account, no
/// answer from the server yet, or a genuinely quiet community all lead to an
/// empty box on the landing page, and an empty box teaches that the feature is
/// broken. The block simply is not there until it has something to say.
///
/// The two reads it needs (today and this week) go through [CommunityService]'s
/// process cache, which the activity screen and the numbers block already
/// share — so it costs one pair of aggregate queries every few minutes, not one
/// per rebuild.
class HomeCommunityPulse extends StatefulWidget {
  const HomeCommunityPulse({super.key, required this.onOpen});

  /// Where the whole block goes: the activity screen, which is the long form of
  /// everything summarised here.
  final VoidCallback onOpen;

  @override
  State<HomeCommunityPulse> createState() => _HomeCommunityPulseState();
}

class _HomeCommunityPulseState extends State<HomeCommunityPulse> {
  /// Long enough to read a short sentence without hurrying, short enough that a
  /// glance at the page catches it moving.
  static const Duration _dwell = Duration(seconds: 5);

  Timer? _timer;
  int _index = 0;
  CommunityTotals? _day;
  CommunityTotals? _week;

  /// The weddings whose matchmaker put their own name to them this week,
  /// newest first. Empty in most weeks, and empty until the read comes back.
  List<CommunityEngagement> _namedEngagements = const <CommunityEngagement>[];

  /// The engagement ids a bracha has already been sent for from this device, so
  /// the line stops offering an action it has already been given.
  final Set<String> _congratulated = <String>{};

  /// Whether the last look at [AccountProvider] said there was an account.
  ///
  /// The block is built before Firebase has finished restoring the session, so
  /// the first read happens with no account and comes back unresolved. Watching
  /// this is how the banner fills itself in a moment later instead of staying
  /// away for the rest of the session.
  bool _wasSignedIn = false;

  /// The publish this block last read after. See
  /// [CommunityProvider.publishRevision]: the read fired from `initState`
  /// usually happens before this device has told the server anything, so the
  /// figures it comes back with are missing the reader's own work and, on a
  /// cold start, often missing everybody's.
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Cheap and harmless without an account — `CommunityService` refuses an
    // anonymous uid and answers with an unresolved zero rather than reaching
    // the network.
    final CommunityTotals day = await CommunityService.totals(
      CommunityPeriod.day,
    );
    final CommunityTotals week = await CommunityService.totals(
      CommunityPeriod.week,
    );
    // The one line here that names somebody. Fetched beside the totals rather
    // than derived from them, because the aggregate knows how many weddings
    // there were and not whose they were — and only a record its own author
    // signed carries a name at all.
    final List<CommunityEngagement> named = week.engagements > 0
        ? await CommunityEngagementsService.namedThisWeek()
        : const <CommunityEngagement>[];
    if (week.resolved) {
      // The only place this is written. Next week it is what "בשבוע שעבר הגענו
      // ל־X" reads — see [CommunityProfileStore.recordCommunityWeek].
      CommunityProfileStore.recordCommunityWeek(
        weekKey: CommunityPeriods.weekKey(),
        friends: week.friends,
        ideas: week.ideas,
        couples: week.couples,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _day = day;
      _week = week;
      _namedEngagements = named;
      _index = 0;
    });
  }

  /// Starts (or restarts) the rotation, and stops it for a single line.
  ///
  /// A banner with one true thing to say says it and holds still; turning one
  /// sentence over into itself every five seconds is animation for its own
  /// sake.
  void _syncTimer(int lineCount) {
    if (lineCount < 2) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) {
      return;
    }
    _timer = Timer.periodic(_dwell, (_) {
      if (!mounted) {
        return;
      }
      setState(() => _index++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool signedIn = context.watch<AccountProvider>().isSignedIn;
    final int revision = context.watch<CommunityProvider>().publishRevision;

    // Firebase resolves the session a moment after launch, so the read fired
    // from `initState` usually happened with no account at all. This is the
    // rebuild that follows.
    if (signedIn && !_wasSignedIn) {
      _wasSignedIn = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    // And this is the rebuild that follows the first publish of the session,
    // which is the moment the cached community figures are known to be stale.
    if (revision != _revision) {
      _revision = revision;
      if (revision > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _load());
      }
    }

    final CommunityTotals? day = _day;
    final CommunityTotals? week = _week;
    if (!signedIn || day == null || week == null || !week.resolved) {
      _syncTimer(0);
      return const SizedBox.shrink();
    }

    final List<CommunityPulseLine> lines = CommunityHighlight.pulseLines(
      day: day,
      week: week,
      namedEngagements: _namedEngagements,
    );
    final CommunityChallenge challenge = CommunityChallenge.build(
      weekKey: CommunityPeriods.weekKey(),
      week: week,
      previousWeek: CommunityProfileStore.previousCommunityWeek,
    );

    // **The weekly challenge is drawn even in a quiet week.** It used to be
    // suppressed along with the news whenever the bar stood at zero, on the
    // reasoning that an empty box teaches a feature is broken — but a target at
    // 0 is not an empty box, it is a target, and Sunday morning is exactly when
    // the community most needs to see one. What is still never drawn is a
    // *read that did not resolve*: that is handled above, and it is the real
    // "we do not know" this block must stay silent about.
    _syncTimer(lines.length);

    final CommunityPulseLine? current = lines.isEmpty
        ? null
        : lines[_index % lines.length];

    return CommunityPulseCard(
      line: current,
      challenge: challenge,
      onOpen: widget.onOpen,
      // A line that can be acted on is acted on where it is read. Everything
      // else goes on opening the activity screen, which is the long form of
      // what the banner summarises.
      onLine: current != null && current.isActionable
          ? () => _congratulate(current.engagement!)
          : null,
      beat: _index,
      sent:
          current?.engagement != null &&
          _congratulated.contains(current!.engagement!.id),
    );
  }

  /// "שלחו מזל טוב" — the one action any line on this banner carries.
  ///
  /// The same flow the engagement card runs: four ready-made brachot and a
  /// field, delivered into the other matchmaker's journal for that couple. It
  /// is deliberately not a message thread — there is no inbox in this app and
  /// there is not going to be one.
  Future<void> _congratulate(CommunityEngagement engagement) async {
    final OverlayState? notices = AppNotice.capture(context);
    final String myName = context.read<UserProfileProvider>().name ?? '';
    final String? text = await MazelTovSheet.show(context);
    if (text == null || !mounted) {
      return;
    }
    // The rotation must not carry the line out from under a sheet somebody is
    // still reading the result of.
    _timer?.cancel();
    _timer = null;

    final bool ok = await MazelTovService.send(
      toUid: engagement.authorUid,
      matchId: engagement.matchId,
      text: text,
      // The same rule the leaderboard follows: a matchmaker who has not agreed
      // to publish their name sends the bracha without one, and the recipient
      // reads it as coming from "שדכן מהקהילה".
      fromName: CommunityProfileStore.isHidden ? '' : myName,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      if (ok) {
        _congratulated.add(engagement.id);
      }
    });
    AppNotice.showOn(
      notices,
      ok
          ? 'הברכה נשלחה. תודה!'
          : 'לא הצלחנו לשלוח כרגע. כדאי לנסות שוב כשיש חיבור לאינטרנט.',
    );
  }
}

/// The banner itself, given what to say.
///
/// Split from the widget above so the drawing can be looked at — and tested at
/// 320px and 1.5x text — without an account, a network or a clock. Everything
/// that decides *whether* to draw and *what is true* lives in
/// [HomeCommunityPulse]; this only knows how to lay out one line and one bar.
class CommunityPulseCard extends StatelessWidget {
  const CommunityPulseCard({
    super.key,
    required this.line,
    required this.challenge,
    required this.onOpen,
    this.onLine,
    this.sent = false,
    this.beat = 0,
  });

  static const String title = 'מה קורה בקהילה עכשיו';

  /// Changes whenever the line does; the dot pulses once on each new value.
  final int beat;

  /// The sentence showing right now, or null when the community has been quiet
  /// and only the challenge is worth drawing.
  final CommunityPulseLine? line;

  final CommunityChallenge challenge;
  final VoidCallback onOpen;

  /// What this particular line does when it is tapped, where it does anything.
  /// Null on every line that is only news — which is nearly all of them — and
  /// the line then falls through to [onOpen] like the rest of the card.
  final VoidCallback? onLine;

  /// Whether the action this line offers has already been taken.
  final bool sent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CommunityPulseLine? current = line;
    final int beat = this.beat;

    return CommunityCard(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                _LivePulse(beat: beat),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            if (current != null) ...<Widget>[
              const SizedBox(height: 10),
              _RotatingLine(line: current, onTap: onLine, sent: sent),
            ],
            const SizedBox(height: 14),
            _ChallengeBar(challenge: challenge),
          ],
        ),
      ),
    );
  }
}

/// The one sentence, changing.
///
/// Fades and rises a few pixels rather than sliding a whole line width: this is
/// a small area on a calm page, and a sentence that flies in from the side
/// turns a quiet banner into a ticker tape.
class _RotatingLine extends StatelessWidget {
  const _RotatingLine({required this.line, this.onTap, this.sent = false});

  final CommunityPulseLine line;

  /// Present only on a line that can be acted on — today that is one thing, a
  /// bracha to a matchmaker whose couple got engaged.
  final VoidCallback? onTap;

  /// Whether that bracha has already gone. The line stays in the rotation and
  /// stops offering the action, which is the honest thing for it to say.
  final bool sent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);
    final bool actionable = onTap != null && !sent;

    final Widget row = Row(
      key: ValueKey<String>('${line.text}|$sent'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: lead),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            sent ? '${line.text} — הברכה נשלחה 💛' : line.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.35,
              // Only a line that does something wears the colour that says so.
              color: actionable ? lead : null,
              decoration: actionable ? TextDecoration.underline : null,
              decorationColor: actionable ? lead.withValues(alpha: 0.5) : null,
            ),
          ),
        ),
        if (actionable) ...<Widget>[
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.favorite_rounded, size: 15, color: lead),
          ),
        ],
      ],
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      // The line's own tap has to beat the card's, and an `InkWell` inside the
      // card's `InkWell` is exactly how: the innermost hit wins, so the news
      // that can be answered is answered and everything else still opens the
      // activity screen.
      child: actionable
          ? InkWell(
              key: ValueKey<String>('action:${line.text}'),
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: row,
              ),
            )
          : row,
    );
  }
}

/// The week's shared target, as one bar.
class _ChallengeBar extends StatelessWidget {
  const _ChallengeBar({required this.challenge});

  final CommunityChallenge challenge;

  /// The one colour in the app that means "the community did it": the same
  /// green the dating band wears, because reaching a shared target is the same
  /// kind of good news.
  static const Color _done = Color(0xFF6F7A55);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = communityLead(theme);
    final bool won = challenge.reachedTarget || challenge.beatsRecord;
    final Color fill = won ? (dark ? const Color(0xFF9DB07A) : _done) : lead;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              won ? Icons.emoji_events_outlined : Icons.flag_outlined,
              size: 15,
              color: fill,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                challenge.headline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: challenge.progress),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double value, _) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 9,
                backgroundColor: theme.colorScheme.surface,
                valueColor: AlwaysStoppedAnimation<Color>(fill),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        // Both halves give way. At 1.5x system text "43 מתוך 150 רעיונות" is
        // wider than a third of a 320px card, and a figure that cannot shrink
        // put an overflow stripe across the bottom of the block.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Flexible(
              flex: 5,
              child: Text(
                challenge.subline,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              flex: 4,
              child: Text(
                challenge.progressLabel,
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                  color: fill,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The green dot that says the figures beside it are current.
///
/// **It beats once when the line changes, and is otherwise still.** The obvious
/// version — `repeat(reverse: true)` — is a permanently running animation on
/// the landing screen: the page would repaint sixty times a second for as long
/// as it is open, for a 14-pixel decoration. Tying the single pulse to the
/// moment the sentence beside it turns over costs nothing between beats, and
/// says the same thing better: the dot moves *because* something happened.
class _LivePulse extends StatefulWidget {
  const _LivePulse({required this.beat});

  /// Changes each time the banner turns over. Any new value fires one pulse.
  final int beat;

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void didUpdateWidget(covariant _LivePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.beat != oldWidget.beat) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color live = Color(0xFF4CAF50);

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        final double t = _controller.value;
        return SizedBox(
          width: 16,
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // The ring rides out and fades, once.
              Container(
                width: 8 + 8 * t,
                height: 8 + 8 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: live.withValues(alpha: 0.28 * (1 - t)),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: live,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
