import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';

/// What the one action on the personal home is about.
enum PersonalNextStepKind {
  /// A friend asked for access and is waiting.
  request,

  /// The card exists but is still a draft nobody can see.
  finishCard,

  /// Friends who matchmake here and cannot see the card yet.
  grant,

  /// No number of their own — friends cannot find the card without it.
  addPhone,

  /// Nothing on the card moved for three months.
  review,

  /// A single photo, or nothing touched for a while — worth a fresh one.
  refresh,

  /// Everything is in order: bring more friends in.
  invite,
}

/// The one thing worth doing now on the personal home, with the sentence
/// that says it and the short label of its button.
class PersonalNextStep {
  const PersonalNextStep({
    required this.kind,
    required this.text,
    required this.action,
    this.friend,
  });

  final PersonalNextStepKind kind;
  final String text;
  final String action;

  /// The friend the step is about, when it is one friend.
  final MatchmakerFriend? friend;

  /// After this long without an edit a card with photos is offered a
  /// refresh — well before the three-month review.
  static const Duration refreshAfter = Duration(days: 45);

  /// Picks exactly one step, in a fixed order of what matters most:
  /// a waiting request → a card nobody can see yet → friends who matchmake
  /// and have no access → a missing own number → a card untouched for three
  /// months → a fresh photo or detail → more friends.
  ///
  /// Pure, so the order is a fact the tests hold.
  static PersonalNextStep pick({
    required Person card,
    required bool live,
    required List<MatchmakerFriend> friends,
    required Set<String> hidden,
    required bool hasPhone,
    required bool friendsLoaded,
    required DateTime lastTouched,
    required bool reviewDue,
    Gender? gender,
    String? draftHint,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();

    final MatchmakerFriend? asking = friends
        .where(
          (MatchmakerFriend f) => f.state == MatchmakerFriendState.requested,
        )
        .firstOrNull;
    if (asking != null) {
      final String asked = asking.row?.matchmakerGender == 'female'
          ? 'ביקשה'
          : 'ביקש';
      return PersonalNextStep(
        kind: PersonalNextStepKind.request,
        text: asking.asksForCard
            ? '${asking.name} $asked גישה לכרטיס שלך'
            : '${asking.name} $asked גישה ל״מה אני מחפש/ת״',
        action: 'לאישור',
        friend: asking,
      );
    }

    if (!live) {
      return PersonalNextStep(
        kind: PersonalNextStepKind.finishCard,
        text: draftHint?.trim().isNotEmpty ?? false
            ? draftHint!.trim()
            : 'הכרטיס עוד לא גלוי לחברים — חסרים בו כמה פרטים',
        action: 'להשלמת הכרטיס',
      );
    }

    if (friendsLoaded) {
      final List<MatchmakerFriend> waiting = MatchmakerFriends.grantable(
        friends,
        hidden: hidden,
      );
      if (waiting.length == 1) {
        final MatchmakerFriend f = waiting.single;
        final bool female = f.row?.matchmakerGender == 'female';
        return PersonalNextStep(
          kind: PersonalNextStepKind.grant,
          text: female
              ? '${f.name} משדכת בשדכן ועדיין לא קיבלה גישה לכרטיס שלך'
              : '${f.name} משדך בשדכן ועדיין לא קיבל גישה לכרטיס שלך',
          action: 'לתת גישה',
          friend: f,
        );
      }
      if (waiting.length > 1) {
        return PersonalNextStep(
          kind: PersonalNextStepKind.grant,
          text:
              '${waiting.length} חברים שלך משדכים בשדכן ועדיין לא קיבלו גישה לכרטיס שלך',
          action: 'לתת גישה',
        );
      }
    }

    if (!hasPhone) {
      return const PersonalNextStep(
        kind: PersonalNextStepKind.addPhone,
        text: 'בלי המספר שלך חברים שמשדכים לא ימצאו את הכרטיס',
        action: 'הוספת המספר שלי',
      );
    }

    if (reviewDue) {
      return const PersonalNextStep(
        kind: PersonalNextStepKind.review,
        text: 'הכרטיס לא עודכן כבר כמה חודשים — הכול עדיין רלוונטי?',
        action: 'לעדכון הכרטיס',
      );
    }

    if (card.photosPaths.length < 2) {
      return PersonalNextStep(
        kind: PersonalNextStepKind.refresh,
        text: 'עוד תמונה תעזור לחברים להציג אותך טוב יותר',
        action: 'הוספת תמונה',
      );
    }
    if (at.difference(lastTouched) >= refreshAfter) {
      return const PersonalNextStep(
        kind: PersonalNextStepKind.refresh,
        text: 'עבר זמן מאז העדכון האחרון — אולי תמונה חדשה או פרט שהשתנה?',
        action: 'לרענון הכרטיס',
      );
    }

    return PersonalNextStep(
      kind: PersonalNextStepKind.invite,
      text: 'עוד חבר שמכיר אותך טוב יכול לחשוב {עליך|עלייך}'.forGender(gender),
      action: 'להזמנת חבר',
    );
  }
}
