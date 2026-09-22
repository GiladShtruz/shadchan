import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/app_celebration.dart';

/// The confirmation after a batch of contacts was added — from the multi-add
/// list and on the way out of the swipe deck.
///
/// **It is a moment again, and this time without a button.** It began as a
/// full-screen dialog with a black wash, a bouncing 🎉 and an "אישור" to press;
/// that was cut back to a one-line toast at the bottom of the screen, which
/// fixed the chore and threw away the moment with it. Putting a first batch of
/// friends into an empty database is the hardest thing this app asks anybody to
/// do, and a grey strip above the tab bar is not an answer to it.
///
/// So it is large and centred again — see [AppCelebration] — and it still goes
/// away by itself after a few seconds, which is the part that was worth
/// keeping.
///
/// A *large* import does not come through here at all. It is recorded through
/// `CommunityProfileStore.noteBulkImport` and announced once, by
/// `AchievementWatcher`, which also silences the milestones it crossed — so an
/// import of three hundred is one sentence rather than four.
abstract final class ContactsAddedCelebration {
  static void show(BuildContext context, {required int count}) {
    AppCelebration.show(
      context,
      headline: 'מעולה!',
      message: count == 1 ? 'הוספת חבר אחד למאגר' : 'הוספת $count חברים למאגר',
    );
  }

  /// One friend who was added through the full card.
  ///
  /// Shown back on the screen the matchmaker started from, which is where the
  /// full editor now returns to instead of opening the friend's profile.
  static void showNewFriend(BuildContext context, Person person) {
    final String name = person.fullName.trim();
    final String joined = person.gender == Gender.female ? 'נוספה' : 'נוסף';
    AppCelebration.show(
      context,
      headline: 'הוספת חבר חדש למאגר!',
      message: name.isEmpty
          ? 'הכרטיס נשמר במאגר שלך'
          : '$name $joined למאגר שלך',
    );
  }
}
