import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/engagement_dialogs.dart';
import 'package:shadchan/dialogs/match_journal_sheet.dart';
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
import 'package:shadchan/widgets/device_contact_picker_sheet.dart';

/// Which row of the folded "פעולות" panel an action belongs to.
///
/// The split is not cosmetic. [MatchActionGroup.status] moves the proposal from
/// one state to another and is the thing a matchmaker does after a phone call;
/// [MatchActionGroup.tools] adds to the proposal without changing where it
/// stands. Mixing the two into one grid of six put "סגירת הצעה" next to
/// "הוספת תזכורת" as though they were the same size of decision.
enum MatchActionGroup { status, tools }

/// Everything a proposal can have done to it, from the card it sits on.
///
/// **This list is the reason there is no proposal screen any more.** A pair of
/// names, a status and four buttons is the whole of what the old page offered
/// above its journal, and getting to it cost a push and a pop for every single
/// update — which is exactly why statuses went stale. The page is gone and its
/// actions moved here, behind one folded bar, so that running down רעיונות
/// after a round of calls never leaves the list.
enum MatchQuickAction {
  waiting('העברה להמתנה', Icons.pause_rounded, MatchActionGroup.status),
  dating('מתחילים לצאת', Icons.celebration_outlined, MatchActionGroup.status),
  close('סגירת הצעה', Icons.close_rounded, MatchActionGroup.status),
  married('חתונה', Icons.favorite_rounded, MatchActionGroup.status),
  reopen('פתיחה מחדש', Icons.refresh_rounded, MatchActionGroup.status),
  reminder(
    'הוספת תזכורת',
    Icons.notifications_active_outlined,
    MatchActionGroup.tools,
  ),
  contact(
    'הוספת איש קשר',
    Icons.person_add_alt_1_outlined,
    MatchActionGroup.tools,
  ),
  journal('יומן ההצעה', Icons.forum_outlined, MatchActionGroup.tools);

  const MatchQuickAction(this.label, this.icon, this.group);

  final String label;
  final IconData icon;
  final MatchActionGroup group;

  /// The status moves available from [status], in reading order.
  ///
  /// The three the app has always offered — "העברה להמתנה", "מתחילים לצאת",
  /// "סגירת הצעה" — are unchanged for an open proposal. The other rows only
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

  /// The tools, which are the same whatever the proposal's status is. A closed
  /// proposal still has a journal worth reading and a contact worth keeping.
  static const List<MatchQuickAction> toolActions = <MatchQuickAction>[
    reminder,
    contact,
    journal,
  ];
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
        await _moveToWaiting(context, repository, match);
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
      case MatchQuickAction.journal:
        await MatchJournalSheet.show(context, match);
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
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final MatchShareResult result = await MatchWhatsAppSheet.open(
      context,
      female: female,
      male: male,
    );

    if (!result.opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('אין מספר טלפון תקין או כרטיס שמור')),
        );
      return;
    }
    final String? label = result.label;
    if (label != null) {
      await repository.recordCardShared(match.id, label);
    }
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
      title: 'מתי לחזור להצעה?',
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

  static Future<void> _moveToWaiting(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(title: Text('למה ההצעה בהמתנה?')),
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

    final ReminderChoice? when = await ReminderPickerSheet.show(
      context,
      title: 'מתי לחזור לבדוק?',
      allowSkip: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );
    await repository.setWaiting(
      match.id,
      reason: reason,
      checkAgainOn: when?.date,
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
          labelText: 'מה הקשר להצעה?',
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
