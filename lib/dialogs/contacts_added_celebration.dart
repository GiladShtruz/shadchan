import 'package:flutter/material.dart';
import 'package:shadchan/widgets/app_toast.dart';

/// The confirmation after a batch of contacts was added — from the multi-add
/// list and on the way out of the swipe deck.
///
/// **It was a full-screen dialog with a black wash, a bouncing 🎉 and a button
/// to press.** For adding three contacts. The message was right and the
/// container was not: a confirmation of something the matchmaker just watched
/// happen does not need the screen, and it certainly does not need dismissing.
/// The words are unchanged; only the box is gone.
///
/// A *large* import does not come through here at all. It is recorded through
/// `CommunityProfileStore.noteBulkImport` and announced once, by
/// `AchievementWatcher`, which also silences the milestones it crossed — so an
/// import of three hundred is one sentence rather than four.
abstract final class ContactsAddedCelebration {
  static void show(BuildContext context, {required int count}) {
    AppToast.show(
      context,
      count == 1
          ? 'מעולה, הוספת חבר אחד למאגר'
          : 'מעולה, הוספת $count חברים למאגר',
      emoji: '🎉',
    );
  }
}
