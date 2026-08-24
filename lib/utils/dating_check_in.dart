import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/utils/enums.dart';

/// A couple who are out, and the rhythm of asking how it is going.
///
/// **A dating proposal stopped being a proposal.** Everything the card offers
/// while an idea is in flight — ask him, ask her, send the card — is finished
/// business the moment the two of them are meeting, and leaving that machinery
/// on the card is what made "מתחילים לצאת" feel like a status rather than an
/// event. What replaces it is the only question left: how long has it been, and
/// have you checked?
///
/// **The rhythm is a week, then a month.** The first week of a couple going out
/// is when a matchmaker's call is actually worth something and when nobody
/// remembers to make it; after that, monthly, because a couple three months in
/// is either a couple or a conversation the matchmaker has already had. Both
/// are only defaults — [MatchIdea.checkInEveryDays] overrides the second, and a
/// matchmaker who wants to be left alone can set the reminder to whatever they
/// like or clear it.
abstract final class DatingCheckIn {
  /// The first check-in after a couple starts going out.
  static const Duration first = Duration(days: 7);

  /// And every one after it, unless the proposal says otherwise.
  static const int defaultEveryDays = 30;

  /// The choices the frequency menu offers, in days.
  static const List<int> frequencyOptions = <int>[7, 14, 30, 60, 90];

  static String frequencyLabel(int days) {
    switch (days) {
      case 7:
        return 'פעם בשבוע';
      case 14:
        return 'פעם בשבועיים';
      case 30:
        return 'פעם בחודש';
      case 60:
        return 'פעם בחודשיים';
      case 90:
        return 'פעם בשלושה חודשים';
      default:
        return 'כל $days ימים';
    }
  }

  /// How long this couple have been going out, or null when nothing in the
  /// record says when they started.
  ///
  /// Read from the status ledger first — the last move *into* "יוצאים", which
  /// is the one that is still running — and only then from the proposal's own
  /// `updatedAt`, which is what a record written before the ledger existed has.
  static DateTime? startedAt(
    MatchIdea match, {
    List<MatchStatusEvent> events = const <MatchStatusEvent>[],
  }) {
    if (match.status != MatchStatus.dating) {
      return null;
    }
    DateTime? latest;
    for (final MatchStatusEvent event in events) {
      if (event.matchId != match.id || event.toStatus != MatchStatus.dating) {
        continue;
      }
      if (latest == null || event.createdAt.isAfter(latest)) {
        latest = event.createdAt;
      }
    }
    return latest ?? match.updatedAt;
  }

  /// Whole days, floored, and never negative — a clock that has gone backwards
  /// must not produce "הם יוצאים כבר ‎-2 ימים".
  static int daysOut(DateTime startedAt, {DateTime? now}) {
    final int days = (now ?? DateTime.now()).difference(startedAt).inDays;
    return days < 0 ? 0 : days;
  }

  /// "הם יוצאים כבר 7 ימים 😊 בדקת איך הולך?" — and its shorter and longer
  /// forms, because "כבר 0 ימים" and "כבר 96 ימים" are both things a person
  /// would not say.
  static String headline(int days) {
    if (days <= 0) {
      return 'הם יצאו היום לראשונה 😊 שווה לבדוק איך היה';
    }
    if (days == 1) {
      return 'הם יוצאים כבר יום 😊 בדקת איך הולך?';
    }
    if (days < 14) {
      return 'הם יוצאים כבר $days ימים 😊 בדקת איך הולך?';
    }
    if (days < 60) {
      final int weeks = days ~/ 7;
      return weeks == 2
          ? 'הם יוצאים כבר שבועיים 😊 בדקת איך הולך?'
          : 'הם יוצאים כבר $weeks שבועות 😊 בדקת איך הולך?';
    }
    final int months = days ~/ 30;
    return months == 2
        ? 'הם יוצאים כבר חודשיים 😊 בדקת איך הולך?'
        : 'הם יוצאים כבר $months חודשים 😊 בדקת איך הולך?';
  }

  /// When to ask next, given when they started and when the last check was.
  ///
  /// The first one is [first] after they started; every one after that is
  /// [MatchIdea.checkInEveryDays] (or [defaultEveryDays]) after the last check.
  /// "The last check" is the reminder that was already set and has now passed —
  /// which is exactly what makes this a cadence rather than a single alarm.
  static DateTime nextCheckAt(
    MatchIdea match, {
    required DateTime startedAt,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    final DateTime firstCheck = startedAt.add(first);
    if (at.isBefore(firstCheck)) {
      return firstCheck;
    }
    final int every = match.checkInEveryDays ?? defaultEveryDays;
    final DateTime from = match.reminderDate ?? firstCheck;
    DateTime next = from.add(Duration(days: every));
    // A proposal reopened after months away must not schedule a reminder in
    // the past — that is a notification that fires the instant it is set.
    while (!next.isAfter(at)) {
      next = next.add(Duration(days: every));
    }
    return next;
  }
}
