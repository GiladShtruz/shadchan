import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/engagement_dialogs.dart';
import 'package:shadchan/dialogs/match_outcome_dialog.dart';
import 'package:shadchan/dialogs/match_status_sheet.dart';
import 'package:shadchan/dialogs/person_whatsapp_menu.dart';
import 'package:shadchan/dialogs/reminder_note_dialog.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_stage.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/device_contact_picker_sheet.dart';

/// What kind of thing an action is.
///
/// The split is not cosmetic. [MatchActionGroup.status] moves the proposal from
/// one state to another and is the thing a matchmaker does after a phone call;
/// [MatchActionGroup.tools] adds to the proposal without changing where it
/// stands. Only the status group is drawn as a row of tiles — the tools each
/// get a control shaped like what they do, because a grid of six identical
/// squares put "סגירת רעיון" next to "הוספת תזכורת" as though they were the same
/// size of decision.
enum MatchActionGroup { status, tools }

/// Everything a proposal can have done to it, from the card it sits on.
///
/// **This list is the reason there is no proposal screen any more.** A pair of
/// names, a status and four buttons is the whole of what the old page offered
/// above its journal, and getting to it cost a push and a pop for every single
/// update — which is exactly why statuses went stale. The page is gone and its
/// actions moved here, behind one folded bar, so that running down רעיונות
/// after a round of calls never leaves the list.
///
/// The journal is not in here, because it is not a button: opening the panel
/// shows it. See `MatchJournalView`.
enum MatchQuickAction {
  waiting('העברה להמתנה', Icons.pause_rounded, MatchActionGroup.status),
  dating('מתחילים לצאת', Icons.celebration_outlined, MatchActionGroup.status),
  close('סגירת רעיון', Icons.close_rounded, MatchActionGroup.status),
  married('חתונה', Icons.favorite_rounded, MatchActionGroup.status),
  reopen('פתיחה מחדש', Icons.refresh_rounded, MatchActionGroup.status),
  reminder(
    'הוספת תזכורת',
    Icons.notifications_active_outlined,
    MatchActionGroup.tools,
  ),
  contact(
    'הוספת איש קשר שקשור לרעיון',
    Icons.person_add_alt_1_outlined,
    MatchActionGroup.tools,
  );

  const MatchQuickAction(this.label, this.icon, this.group);

  final String label;
  final IconData icon;
  final MatchActionGroup group;

  /// The status moves available from [status], in reading order.
  ///
  /// The three the app has always offered — "העברה להמתנה", "מתחילים לצאת",
  /// "סגירת רעיון" — are unchanged for an open idea. The other rows only
  /// swap in what is actually possible: a proposal already waiting is offered
  /// its way back out, a couple already dating are offered the wedding rather
  /// than being told to start dating again, and a closed one is offered
  /// nothing but reopening.
  static List<MatchQuickAction> statusActionsFor(MatchStatus status) {
    switch (status) {
      case MatchStatus.idea:
      case MatchStatus.checking:
        return <MatchQuickAction>[waiting, dating, close];
      case MatchStatus.unavailable:
        return <MatchQuickAction>[reopen, dating, close];
      case MatchStatus.dating:
        return <MatchQuickAction>[married, close];
      case MatchStatus.rejected:
      case MatchStatus.dated:
      case MatchStatus.married:
        return <MatchQuickAction>[reopen];
    }
  }
}

/// Running a proposal from the list, without opening it.
///
/// Everything goes through the same repository calls the app has always used,
/// so a status set from a card is indistinguishable from one set anywhere
/// else — same journal entries, same history on both candidates.
abstract final class MatchQuickActions {
  static Future<void> run(
    BuildContext context,
    MatchQuickAction action,
    MatchIdea match, {
    Person? female,
    Person? male,
  }) async {
    final MatchRepository repository = context.read<MatchRepository>();
    switch (action) {
      case MatchQuickAction.waiting:
        await _moveToWaiting(
          context,
          repository,
          match,
          female: female,
          male: male,
        );
      case MatchQuickAction.dating:
        await repository.updateStatus(match.id, MatchStatus.dating);
      case MatchQuickAction.close:
        await _close(context, repository, match);
      case MatchQuickAction.married:
        await _markMarried(context, repository, match, female, male);
      case MatchQuickAction.reopen:
        await repository.updateStatus(match.id, MatchStatus.idea);
      case MatchQuickAction.reminder:
        await addReminder(context, repository, match);
      case MatchQuickAction.contact:
        await addRelatedContact(context, repository, match);
    }
  }

  /// "יאללה לקדם!" — the card going out to whoever should see it.
  ///
  /// What was sent comes back from the sheet as a sentence and is handed
  /// straight to [MatchRepository.recordCardShared], which files it in the
  /// journal and turns the row on the card from a prompt into a report. That
  /// round trip is the whole feature: the app cannot know whether a card was
  /// actually delivered, but it knows what the matchmaker chose to send and
  /// when, and that is the thing worth remembering.
  static Future<void> promote(
    BuildContext context,
    MatchIdea match, {
    required Person? female,
    required Person? male,
  }) async {
    final MatchRepository repository = context.read<MatchRepository>();
    final OverlayState? notices = AppNotice.capture(context);
    final MatchShareResult result = await MatchWhatsAppSheet.open(
      context,
      female: female,
      male: male,
    );

    if (!result.opened) {
      AppNotice.showOn(notices, 'אין מספר טלפון תקין או כרטיס שמור');
      return;
    }
    final String? label = result.label;
    if (label != null) {
      await repository.recordCardShared(match.id, label);
    }
    // The sheet is the other way to do what the card's own button does, so it
    // moves the stage the same way — otherwise a proposal whose card went out
    // through here would go on asking to be promoted to the side that already
    // has it.
    if (result.toGender case final Gender side) {
      await repository.markSideAsked(match.id, side);
    }
  }

  /// "יאללה לקדם" — the one step this proposal is actually waiting for.
  ///
  /// **Opening the chat *is* the action, so the stage moves with it.** The old
  /// row asked who to message and then remembered what was sent; it could not
  /// say whether the proposal had got any further, because "a card went out"
  /// and "he has been asked" are not the same fact and only the first was
  /// recorded. Now the button names the side whose turn it is, opens their
  /// chat with the other one's card, and — if that actually opened — writes
  /// down that they have been asked. The next time the card is drawn it offers
  /// the next step by itself.
  ///
  /// **Nothing moves when nothing opened.** A side with no phone number, or
  /// WhatsApp not installed, leaves the stage exactly where it was: a proposal
  /// that claims somebody was asked because a launch failed is worse than one
  /// that admits it is still waiting.
  static Future<void> advance(
    BuildContext context,
    MatchIdea match,
    MatchNextStep step, {
    required Person? female,
    required Person? male,
  }) async {
    final MatchRepository repository = context.read<MatchRepository>();
    final OverlayState? notices = AppNotice.capture(context);

    if (step == MatchNextStep.startDating) {
      await repository.updateStatus(match.id, MatchStatus.dating);
      return;
    }

    final bool askingMale = step == MatchNextStep.askMale;
    final Person? target = askingMale ? male : female;
    final Person? other = askingMale ? female : male;
    if (target == null) {
      AppNotice.showOn(notices, 'הצד הזה כבר לא קיים במאגר');
      return;
    }

    final MatchShareResult result = await MatchWhatsAppSheet.approach(
      target: target,
      other: other,
    );
    if (!result.opened) {
      AppNotice.showOn(
        notices,
        'אין מספר טלפון תקין, אז אי אפשר לפתוח וואטסאפ',
      );
      return;
    }
    final String? label = result.label;
    if (label != null) {
      await repository.recordCardShared(match.id, label);
    }
    await repository.markSideAsked(
      match.id,
      askingMale ? Gender.male : Gender.female,
    );
  }

  /// The status set by hand, from the menu beside the button.
  ///
  /// "מתחילים לצאת" is routed through [run] rather than written here: it is a
  /// status change with two candidates' availability, a memory of what to put
  /// back and a community figure hanging off it, and there must be exactly one
  /// path to it.
  ///
  /// **And the way back out of it goes through the same door.** Picking any
  /// other status on a couple who are out has to undo everything that starting
  /// to date did — both cards go back to what they were, the check-in reminder
  /// stops being the point of the card — and only [MatchRepository.updateStatus]
  /// knows how to do that. So the status leaves "יוצאים" first, and only then
  /// are the two asked-dates written.
  static Future<void> setStage(
    BuildContext context,
    MatchIdea match,
    MatchStage stage, {
    Person? female,
    Person? male,
  }) async {
    if (stage == MatchStage.dating) {
      await run(
        context,
        MatchQuickAction.dating,
        match,
        female: female,
        male: male,
      );
      return;
    }

    final MatchRepository repository = context.read<MatchRepository>();
    // Read before the move: `match` is the live Hive record, so `updateStatus`
    // mutates the very field this is testing.
    final bool wasDating = match.status == MatchStatus.dating;
    if (wasDating) {
      // "בבדיקה" and not "רעיון": the proposal is being put back to a side
      // having been asked, which is exactly what `checking` means, and every
      // status this menu offers is one of those.
      await repository.updateStatus(match.id, MatchStatus.checking);
    }

    final DateTime now = DateTime.now();
    await repository.setStage(
      match.id,
      // The dates that were already there are kept where the stage still
      // includes that side, so setting "שאלתי את שניהם" on a proposal he was
      // asked about last week does not pretend both happened this minute.
      askedMaleAt:
          stage == MatchStage.askedMale || stage == MatchStage.askedBoth
          ? (match.askedMaleAt ?? now)
          : null,
      askedFemaleAt:
          stage == MatchStage.askedFemale || stage == MatchStage.askedBoth
          ? (match.askedFemaleAt ?? now)
          : null,
      label: stage.label,
    );
    // A couple who have just been taken back out of "יוצאים" have both dates
    // already, so `setStage` finds nothing to write and files no line. The
    // status move above is the thing that happened; this is what says so.
    if (wasDating) {
      await repository.addNote(
        match.id,
        'הסטטוס עודכן — ${stage.label}',
        isAutomatic: true,
      );
    }
  }

  /// The couple who are out: a chat with one of them, and the next check-in
  /// booked because it happened.
  static Future<void> checkInOnCouple(
    BuildContext context,
    MatchIdea match, {
    required Person person,
    required DateTime startedAt,
  }) async {
    final MatchRepository repository = context.read<MatchRepository>();
    final OverlayState? notices = AppNotice.capture(context);
    final bool opened = await WhatsAppUtils.openChat(person);
    if (!opened) {
      AppNotice.showOn(notices, 'לא הצלחנו לפתוח את וואטסאפ');
      return;
    }
    await repository.recordDatingCheckIn(
      match.id,
      startedAt: startedAt,
      note: 'בדקתי איך הולך — שיחה עם ${person.firstName.trim()}',
    );
  }

  /// The availability values a matchmaker sets by hand, per side, from the
  /// chip under each name. `mazelTov` is left out — the app sets that itself
  /// when a proposal ends in a wedding.
  static Future<void> setPersonStatus(
    BuildContext context,
    Person person,
    ProfileStatus status,
  ) async {
    if (person.profileStatus == status) {
      return;
    }
    final PersonRepository repository = context.read<PersonRepository>();
    await repository.updateProfileStatus(person.id, status);
    if (!status.pausesMatches || !context.mounted) {
      return;
    }
    // Marking someone busy or on a break already moved their proposals to
    // "בהמתנה". The only open question left is when to look at them again.
    final ReminderChoice? when = await ReminderPickerSheet.show(
      context,
      title: 'מתי להזכיר לך לבדוק שוב?',
      allowSkip: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );
    final DateTime? date = when?.date;
    if (date != null) {
      await repository.setPersonReminder(person.id, date);
    }
  }

  /// A date to come back to the proposal, and optionally a word about why.
  /// Clearing is offered too — a reminder that is done with should be able to
  /// go away without waiting for its own date to arrive.
  static Future<void> addReminder(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final ReminderChoice? choice = await ReminderPickerSheet.show(
      context,
      title: 'מתי לחזור לרעיון?',
      allowClear: match.reminderDate != null,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );
    if (choice == null) {
      return;
    }
    if (choice.date == null) {
      await repository.setReminder(match.id, null);
      return;
    }

    String? note = match.reminderNote;
    if (context.mounted) {
      final String? written = await ReminderNoteDialog.show(
        context,
        initialNote: note,
      );
      if (written != null) {
        note = written;
      }
    }
    await repository.setReminder(match.id, choice.date, note: note);
  }

  /// Somebody around the proposal who is not one of the two candidates — a
  /// mother, a friend, another matchmaker.
  static Future<void> addRelatedContact(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final DeviceContactChoice? choice = await DeviceContactPickerSheet.show(
      context,
    );
    if (choice == null || !context.mounted) {
      return;
    }
    final String? description = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _ContactRoleDialog(contactName: choice.name),
    );
    if (description == null) {
      return;
    }
    await repository.addRelatedContact(
      match.id,
      MatchContact(
        name: choice.name,
        phone: choice.phone,
        description: description.trim().isEmpty ? null : description.trim(),
      ),
    );
  }

  /// Which side a waiting reason is actually about, and what it says about
  /// them.
  ///
  /// **A reason is a fact about a person, not only about a proposal.** "היא
  /// בהפסקה" is true of her in every idea she is in, and the app used to write
  /// it down on exactly one of them: her card still read "פנוי", her other
  /// four ideas stayed open, and the next time she came up in a suggestion
  /// nothing on screen knew. So the reason now sets her status as well, which
  /// is the one change that makes the rest of the app agree with the sentence
  /// the matchmaker just picked.
  ///
  /// "בלי סיבה מיוחדת" and a reason the app does not recognise say nothing
  /// about either candidate and leave both cards alone.
  static ({Gender side, ProfileStatus status})? _statusFromWaitingReason(
    String reason,
  ) {
    switch (reason.trim()) {
      case 'הוא בהפסקה':
        return (side: Gender.male, status: ProfileStatus.onBreak);
      case 'היא בהפסקה':
        return (side: Gender.female, status: ProfileStatus.onBreak);
      case 'הוא תפוס':
        return (side: Gender.male, status: ProfileStatus.busy);
      case 'היא תפוסה':
        return (side: Gender.female, status: ProfileStatus.busy);
      default:
        return null;
    }
  }

  static Future<void> _moveToWaiting(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match, {
    Person? female,
    Person? male,
  }) async {
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(title: Text('למה הרעיון בהמתנה?')),
              for (final String option in <String>[
                ...MatchWaitingReasons.options,
                MatchWaitingReasons.noReason,
              ])
                ListTile(
                  title: Text(option),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(option == MatchWaitingReasons.noReason ? '' : option),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (reason == null || !context.mounted) {
      return;
    }

    // **A month is the answer unless somebody says otherwise.** A proposal put
    // on hold with no date on it is a proposal nobody ever comes back to, and
    // the reason field above already told the app what it needs to know; being
    // made to pick a date as well is what makes "בהמתנה" feel like paperwork.
    // "דלג" is still there for the matchmaker who genuinely wants none.
    final DateTime today = DateTime.now();
    final ReminderChoice? when = await ReminderPickerSheet.show(
      context,
      title: 'מתי לחזור לבדוק?',
      allowSkip: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
      defaultChoice: ReminderChoice(
        DateTime(today.year, today.month + 1, today.day),
      ),
    );
    await repository.setWaiting(
      match.id,
      reason: reason,
      checkAgainOn: when?.date,
    );

    // The reason, applied to whoever it was about. Written *after* the
    // proposal, so the sync that follows a status change finds this idea
    // already waiting and leaves it alone.
    if (_statusFromWaitingReason(reason)
        case final ({Gender side, ProfileStatus status}) verdict) {
      final Person? subject = verdict.side == Gender.male ? male : female;
      if (subject != null && context.mounted) {
        final PersonRepository people = context.read<PersonRepository>();
        await people.updateProfileStatus(
          subject.id,
          verdict.status,
          causedByMatchId: match.id,
        );
        // The same date, on the person as well: "לבדוק שוב בעוד חודש" was
        // answered once and means the same thing on both records.
        if (when?.date case final DateTime date) {
          await people.setPersonReminder(subject.id, date);
        }
      }
    }

    if (!context.mounted) {
      return;
    }
    // **Where it went, and the way to it.** "בהמתנה" moves a card out of the
    // list it was being worked in, which without a word looks exactly like the
    // card disappearing. The notice names the shelf it landed on and carries
    // the one tap that opens it.
    // The router is taken now, while this context is certainly alive: the
    // notice outlives the sheet and the card that raised it, and reading
    // `GoRouter.of` inside the callback would be reading a dead element.
    final GoRouter router = GoRouter.of(context);
    AppNotice.show(
      context,
      'הרעיון עבר לרשימת הרעיונות בהמתנה',
      actionLabel: 'למעבר',
      onAction: () => router.go('/matches?statuses=unavailable'),
    );
  }

  /// Closing a proposal, asking who ended it and why first.
  ///
  /// **Which closing it is comes from where the proposal already stands.** A
  /// couple who went out and stopped is a different fact from an idea that
  /// never got off the ground — the archive keeps them in separate halves and
  /// both candidates' histories are worded differently — and the proposal's own
  /// status already knows which of the two this is. Asking would be a question
  /// with a known answer.
  static Future<void> _close(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final MatchStatus closing = match.status == MatchStatus.dating
        ? MatchStatus.dated
        : MatchStatus.rejected;
    final ({MatchOutcomeParty party, String note})? outcome =
        await MatchOutcomeDialog.show(context, closing);
    if (outcome == null) {
      return;
    }
    await repository.recordOutcome(
      match.id,
      newStatus: closing,
      party: outcome.party,
      note: outcome.note.isEmpty ? null : outcome.note,
    );
  }

  /// The wedding, and the community's only piece of outgoing good news.
  ///
  /// Announced strictly on the transition: re-confirming a status that was
  /// already a wedding is not a second couple, and must not tell the community
  /// about the same one twice.
  static Future<void> _markMarried(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
    Person? female,
    Person? male,
  ) async {
    final bool alreadyMarried = match.status == MatchStatus.married;
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'מזל טוב!',
      message: 'לעדכן שהזוג התחתן?',
      confirmText: 'עדכון לחתונה',
    );
    if (confirmed != true) {
      return;
    }
    await repository.updateStatus(match.id, MatchStatus.married);
    if (alreadyMarried || !context.mounted) {
      return;
    }

    // What leaves the device is visible right here, and it is one name: the
    // matchmaker's own, and only if they are not hidden from the community and
    // say yes when asked. Nothing about either member of the couple is sent.
    final CommunityProvider community = context.read<CommunityProvider>();
    await EngagementFlow.celebrate(
      context,
      matchId: match.id,
      matchmakerName: context.read<UserProfileProvider>().name ?? '',
      shareName: !community.isHidden,
      private: community.isPrivate,
    );
  }
}

/// "מי זה?" — one line describing what a related contact is to the proposal.
class _ContactRoleDialog extends StatefulWidget {
  const _ContactRoleDialog({required this.contactName});

  final String contactName;

  @override
  State<_ContactRoleDialog> createState() => _ContactRoleDialogState();
}

class _ContactRoleDialogState extends State<_ContactRoleDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.contactName),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'מה הקשר לרעיון?',
          hintText: 'אמא של שרה, חבר של דוד…',
        ),
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('הוספה'),
        ),
      ],
    );
  }
}
