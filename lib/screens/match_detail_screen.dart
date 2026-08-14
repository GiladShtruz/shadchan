import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/home_board_actions.dart';
import 'package:shadchan/dialogs/match_outcome_dialog.dart';
import 'package:shadchan/dialogs/reminder_note_dialog.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/reminder_alerts.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/device_contact_picker_sheet.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';

class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({
    super.key,
    required this.matchId,
    this.autoPromptWhatsApp = false,
  });

  final String matchId;
  final bool autoPromptWhatsApp;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocus = FocusNode();
  final DateFormat _noteDateFormat = DateFormat('dd.MM');

  String? _promptedWhatsAppMatchId;
  bool _isWhatsAppPromptOpen = false;

  /// Journal edit mode: the timeline turns into a multi-select list so several
  /// entries can be removed in one go instead of one dialog per note.
  bool _isJournalEditing = false;
  final Set<String> _selectedNoteIds = <String>{};

  @override
  void initState() {
    super.initState();
    _noteController.addListener(_handleNoteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Opening the card answers the home screen's alert badge. The reminder
      // itself stays until it is really handled.
      if (!mounted) {
        return;
      }
      final MatchIdea? match = context.read<MatchRepository>().getById(
        widget.matchId,
      );
      unawaited(ReminderAlerts.markSeen(widget.matchId, match?.reminderDate));
    });
  }

  @override
  void dispose() {
    _noteController
      ..removeListener(_handleNoteChanged)
      ..dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchIdea? match = matchRepository.getById(widget.matchId);

    if (match == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('פרטי הצעה')),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.heart_broken_outlined,
                  size: 68,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 14),
                const Text('ההצעה לא נמצאה'),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => context.go('/matches'),
                  child: const Text('חזרה לרעיונות'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Person? personA = personRepository.getById(match.personAId);
    final Person? personB = personRepository.getById(match.personBId);
    final ({Person? male, Person? female}) sides = _matchPeopleByGender(
      personA,
      personB,
    );
    final List<MatchNote> notes = matchRepository
        .getNotesForMatch(match.id)
        .where((MatchNote note) => !_isTechnicalJournalNote(note.text))
        .toList();
    final _MatchSituation situation = _deriveSituation(
      match,
      sides: sides,
      personRepository: personRepository,
    );

    _scheduleWhatsAppPrompt(match, personA: personA, personB: personB);

    // An emptied journal leaves nothing to select, so edit mode folds away on
    // its own; the selection is filtered too in case a note vanished under it.
    final Set<String> noteIds = notes.map((MatchNote note) => note.id).toSet();
    final bool journalEditing = _isJournalEditing && notes.isNotEmpty;
    final Set<String> selectedNoteIds = journalEditing
        ? _selectedNoteIds.intersection(noteIds)
        : const <String>{};

    return PopScope<Object?>(
      // Back is the natural way out of edit mode before it leaves the screen.
      canPop: !journalEditing,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _exitJournalEditing();
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('פרטי הצעה'),
          centerTitle: true,
          actions: <Widget>[
            PopupMenuButton<String>(
              tooltip: 'עוד',
              icon: const Icon(Icons.more_vert),
              onSelected: (String value) {
                switch (value) {
                  case 'board':
                    HomeBoardActions.toggle(
                      context,
                      HomeItemKind.idea,
                      match.id,
                    );
                  case 'delete':
                    _deleteMatch(context, matchRepository, match.id);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'board',
                  height: HomeBoardActions.menuItemHeight,
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.push_pin_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: HomeBoardActions.menuItemChild(
                          context,
                          HomeItemKind.idea,
                          match.id,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      const Text('מחיקת ההצעה'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            children: <Widget>[
              _PairCard(
                female: sides.female,
                male: sides.male,
                celebrating: match.status == MatchStatus.dating,
                statusLine: situation.line,
                statusColor: situation.color,
                statusIcon: situation.icon,
                onOpenProfile: (Person person) =>
                    context.push('/people/${person.id}'),
                onWhatsApp: _openWhatsAppMenu,
                onComparePair: sides.female == null || sides.male == null
                    ? null
                    : () => openMatchComparison(
                        context,
                        source: sides.female!,
                        candidate: sides.male!,
                        // The proposal is already open — this is only the
                        // side-by-side look, and closing it lands back here.
                        showOpenIdeaAction: false,
                      ),
                onStatusPicked: (Person person, ProfileStatus status) =>
                    _applyPersonStatus(
                      context,
                      personRepository,
                      person,
                      status,
                    ),
              ),
              const SizedBox(height: 12),
              _ReminderCard(
                date: situation.reminderDate,
                note: situation.reminderNote,
                isDue: situation.isDue,
                onTap:
                    match.status.isArchived ||
                        match.status == MatchStatus.dating
                    ? null
                    : situation.reminderOwner != null
                    ? () => _changePersonReminder(
                        context,
                        personRepository,
                        situation.reminderOwner!,
                      )
                    : () =>
                          _changeMatchReminder(context, matchRepository, match),
                onPostpone: situation.isDue
                    ? () => situation.reminderOwner != null
                          ? _postponePersonReminder(
                              context,
                              personRepository,
                              situation.reminderOwner!,
                            )
                          : _postponeMatchReminder(
                              context,
                              matchRepository,
                              match,
                            )
                    : null,
                onBackToAvailable:
                    situation.isDue && situation.reminderOwner != null
                    ? () => personRepository.updateProfileStatus(
                        situation.reminderOwner!.id,
                        ProfileStatus.available,
                      )
                    : null,
                backToAvailableLabel: situation.reminderOwner == null
                    ? null
                    : _returnedLabel(situation.reminderOwner!),
                onHandled:
                    situation.isDue &&
                        situation.reminderOwner == null &&
                        match.reminderDate != null
                    ? () => matchRepository.setReminder(match.id, null)
                    : null,
              ),
              const SizedBox(height: 12),
              _UpdateProposalCard(
                actions: _proposalActions(
                  context,
                  matchRepository,
                  match,
                  situation,
                ),
              ),
              const SizedBox(height: 12),
              _RelatedContactsCard(
                contacts: match.relatedContacts,
                onAdd: () =>
                    _addRelatedContact(context, matchRepository, match),
                onOpenList: () =>
                    _showContactsList(context, matchRepository, match),
                onWhatsApp: (MatchContact contact) =>
                    _openContactWhatsApp(contact),
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Text(
                    'יומן ההצעה',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  if (journalEditing)
                    IconButton(
                      tooltip: 'סיום עריכה',
                      onPressed: _exitJournalEditing,
                      icon: const Icon(Icons.close_rounded, size: 21),
                    )
                  else if (notes.isNotEmpty)
                    IconButton(
                      tooltip: 'עריכת היומן',
                      onPressed: _enterJournalEditing,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _MatchTimeline(
                notes: notes,
                dateFormat: _noteDateFormat,
                isEditing: journalEditing,
                selectedIds: selectedNoteIds,
                onOpen: (MatchNote note) => _openNote(matchRepository, note),
                onToggleSelected: _toggleNoteSelection,
                onStartEditing: _enterJournalEditing,
              ),
              const SizedBox(height: 12),
              if (!journalEditing)
                _JournalComposer(
                  controller: _noteController,
                  focusNode: _noteFocus,
                  canSend: _canSendNote,
                  onSend: () => _addNote(matchRepository, match.id),
                ),
            ],
          ),
        ),
        bottomNavigationBar: journalEditing
            ? _JournalEditBar(
                selectedCount: selectedNoteIds.length,
                onDelete: () => _deleteSelectedNotes(
                  matchRepository,
                  notes
                      .where(
                        (MatchNote note) => selectedNoteIds.contains(note.id),
                      )
                      .toList(),
                ),
                onCancel: _exitJournalEditing,
              )
            : null,
      ),
    );
  }

  void _enterJournalEditing() {
    _noteFocus.unfocus();
    setState(() {
      _isJournalEditing = true;
      _selectedNoteIds.clear();
    });
  }

  void _exitJournalEditing() {
    setState(() {
      _isJournalEditing = false;
      _selectedNoteIds.clear();
    });
  }

  void _toggleNoteSelection(MatchNote note) {
    setState(() {
      if (!_selectedNoteIds.remove(note.id)) {
        _selectedNoteIds.add(note.id);
      }
    });
  }

  /// Deletes every checked entry at once, with a single undo covering the whole
  /// batch so a mis-tap never costs the user the notes they had collected.
  Future<void> _deleteSelectedNotes(
    MatchRepository repository,
    List<MatchNote> selected,
  ) async {
    if (selected.isEmpty) return;
    _exitJournalEditing();

    for (final MatchNote note in selected) {
      await repository.deleteNote(note.id);
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            selected.length == 1
                ? 'ההערה נמחקה'
                : '${selected.length} הערות נמחקו',
          ),
          action: SnackBarAction(
            label: 'ביטול',
            onPressed: () async {
              for (final MatchNote note in selected) {
                await repository.restoreNote(note);
              }
            },
          ),
        ),
      );
  }

  /// The three ways a proposal moves on, in reading order: the two quiet ones
  /// on the sides and the one that matters — "יוצאים" — in the middle.
  List<_ProposalAction> _proposalActions(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
    _MatchSituation situation,
  ) {
    final _ProposalAction dating = _ProposalAction(
      label: 'יוצאים',
      icon: Icons.people_alt_outlined,
      tone: _ActionTone.go,
      emphasized: true,
      onTap: () => repository.updateStatus(match.id, MatchStatus.dating),
    );
    final _ProposalAction close = _ProposalAction(
      label: 'סגירת הצעה',
      icon: Icons.close_rounded,
      tone: _ActionTone.stop,
      onTap: () => _showCloseSheet(context, repository, match),
    );

    switch (match.status) {
      case MatchStatus.idea:
      case MatchStatus.checking:
        return <_ProposalAction>[
          _ProposalAction(
            label: 'העברה להמתנה',
            icon: Icons.pause_rounded,
            tone: _ActionTone.wait,
            onTap: () => _setManualWaiting(context, repository, match),
          ),
          dating,
          close,
        ];
      case MatchStatus.unavailable:
        return <_ProposalAction>[
          if (situation.reminderOwner == null)
            _ProposalAction(
              label: 'חזרה לפתוחה',
              icon: Icons.play_arrow_rounded,
              tone: _ActionTone.wait,
              onTap: () => repository.updateStatus(match.id, MatchStatus.idea),
            ),
          dating,
          close,
        ];
      case MatchStatus.dating:
        return <_ProposalAction>[
          _ProposalAction(
            label: 'הפסיקו לצאת',
            icon: Icons.heart_broken_outlined,
            tone: _ActionTone.stop,
            onTap: () => _showOutcomeDialog(
              context,
              repository,
              match,
              MatchStatus.dated,
            ),
          ),
          _ProposalAction(
            label: 'חתונה',
            icon: Icons.celebration_outlined,
            tone: _ActionTone.go,
            emphasized: true,
            onTap: () => _markMarried(context, repository, match),
          ),
        ];
      case MatchStatus.rejected:
      case MatchStatus.dated:
      case MatchStatus.married:
        return <_ProposalAction>[
          _ProposalAction(
            label: 'פתיחה מחדש',
            icon: Icons.refresh_rounded,
            tone: _ActionTone.go,
            emphasized: true,
            onTap: () => repository.updateStatus(match.id, MatchStatus.idea),
          ),
        ];
    }
  }

  /// The one line at the bottom of the pair card. It says what the proposal's
  /// state is and what is needed now — never a second sentence repeating what
  /// the chips above it already show.
  _MatchSituation _deriveSituation(
    MatchIdea match, {
    required ({Person? male, Person? female}) sides,
    required PersonRepository personRepository,
  }) {
    if (match.status.isArchived) {
      final bool married = match.status == MatchStatus.married;
      return _MatchSituation(
        line: married
            ? 'חתונה · מזל טוב!'
            : 'נסגרה · ${match.status.displayName}',
        color: AppColors.statusColor(match.status.name),
        icon: married
            ? Icons.celebration_outlined
            : Icons.check_circle_outline_rounded,
      );
    }
    if (match.status == MatchStatus.dating) {
      return const _MatchSituation(
        line: 'יוצאים',
        color: AppColors.statusDating,
        icon: Icons.favorite_rounded,
      );
    }

    final List<Person> paused = <Person>[
      if (sides.female?.profileStatus.pausesMatches ?? false) sides.female!,
      if (sides.male?.profileStatus.pausesMatches ?? false) sides.male!,
    ];
    if (paused.isNotEmpty) {
      paused.sort((Person a, Person b) {
        final DateTime? aDate = personRepository.personReminderFor(a.id);
        final DateTime? bDate = personRepository.personReminderFor(b.id);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });
      final Person owner = paused.first;
      final DateTime? reminder = personRepository.personReminderFor(owner.id);
      final bool due = _isDue(reminder);
      final String name = _firstName(owner);
      final String status = owner.profileStatus.displayName;
      return _MatchSituation(
        line: due
            ? 'תזכורת · לבדוק אם $name ${_returnedToAvailability(owner)}'
            : reminder == null
            ? 'בהמתנה · $name $status'
            : 'בהמתנה · $name $status · '
                  'לבדוק שוב ב־${AppDateUtils.formatDateShort(reminder)}',
        color: due ? AppColors.secondary : AppColors.statusUnavailable,
        icon: due
            ? Icons.notification_important_outlined
            : Icons.pause_circle_outline_rounded,
        reminderOwner: owner,
        reminderDate: reminder,
        reminderNote: personRepository.personReminderNoteFor(owner.id),
        isDue: due,
      );
    }

    if (match.status == MatchStatus.unavailable) {
      final bool due = _isDue(match.reminderDate);
      final String reason = (match.waitingReason ?? '').trim();
      final String withReason = reason.isEmpty ? '' : ' · $reason';
      return _MatchSituation(
        line: due
            ? reason.isEmpty
                  ? 'תזכורת · לבדוק מה קורה עם ההצעה'
                  : 'תזכורת · $reason'
            : match.reminderDate == null
            ? 'בהמתנה$withReason'
            : 'בהמתנה$withReason · '
                  'לבדוק שוב ב־${AppDateUtils.formatDateShort(match.reminderDate!)}',
        color: due ? AppColors.secondary : AppColors.statusUnavailable,
        icon: due
            ? Icons.notification_important_outlined
            : Icons.pause_circle_outline_rounded,
        reminderDate: match.reminderDate,
        reminderNote: match.reminderNote,
        isDue: due,
      );
    }

    final bool due = _isDue(match.reminderDate);
    return _MatchSituation(
      line: due ? 'תזכורת · הגיע הזמן לבדוק איתם' : 'פתוחה · יאללה לקדם',
      color: due ? AppColors.secondary : AppColors.statusIdea,
      icon: due
          ? Icons.notification_important_outlined
          : Icons.lightbulb_outline_rounded,
      reminderDate: match.reminderDate,
      reminderNote: match.reminderNote,
      isDue: due,
    );
  }

  bool _isDue(DateTime? date) {
    if (date == null) return false;
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return !DateTime(date.year, date.month, date.day).isAfter(today);
  }

  /// Applies a status picked from the dropdown on the pair card, and offers a
  /// follow-up reminder when the person is no longer available.
  Future<void> _applyPersonStatus(
    BuildContext context,
    PersonRepository repository,
    Person person,
    ProfileStatus picked,
  ) async {
    if (picked == person.profileStatus || !context.mounted) {
      return;
    }

    await repository.updateProfileStatus(person.id, picked);
    if (!picked.pausesMatches || !context.mounted) {
      return;
    }
    // The status change already moved every relevant proposal to "בהמתנה";
    // all that is left is when to look at this person again.
    await _pickPersonReminder(
      context,
      repository,
      person,
      title: 'מתי להזכיר לך לבדוק שוב?',
      allowSkip: true,
    );
  }

  Future<void> _changePersonReminder(
    BuildContext context,
    PersonRepository repository,
    Person person,
  ) async {
    await _pickPersonReminder(
      context,
      repository,
      person,
      title: 'מתי לבדוק שוב את ${_firstName(person)}?',
      allowClear: true,
    );
  }

  /// Picks a date for a person's own reminder and then offers to write a note
  /// on it. The reminder belongs to the person, so it shows on every proposal
  /// they are part of.
  Future<void> _pickPersonReminder(
    BuildContext context,
    PersonRepository repository,
    Person person, {
    required String title,
    bool allowSkip = false,
    bool allowClear = false,
  }) async {
    final ReminderChoice? choice = await ReminderPickerSheet.show(
      context,
      title: title,
      allowSkip: allowSkip,
      allowClear: allowClear,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );
    if (choice == null) return;
    if (choice.date == null) {
      await repository.clearPersonReminder(person.id);
      return;
    }

    String? note = repository.personReminderNoteFor(person.id);
    if (context.mounted) {
      final String? written = await ReminderNoteDialog.show(
        context,
        initialNote: note,
      );
      if (written != null) {
        note = written;
      }
    }
    await repository.setPersonReminder(person.id, choice.date!, note: note);
  }

  Future<void> _postponePersonReminder(
    BuildContext context,
    PersonRepository repository,
    Person person,
  ) async {
    final DateTime? date = await _pickPostponeDate(context);
    if (date != null) {
      await repository.setPersonReminder(
        person.id,
        date,
        note: repository.personReminderNoteFor(person.id),
      );
    }
  }

  /// The two-option sheet behind "עדיין בהמתנה": push the check a week or a
  /// month ahead without walking through the full picker.
  Future<DateTime?> _pickPostponeDate(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime base = DateTime(now.year, now.month, now.day);
    return showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(title: Text('מתי לבדוק שוב?')),
              ListTile(
                leading: const Icon(Icons.calendar_view_week_outlined),
                title: const Text('עוד שבוע'),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(base.add(const Duration(days: 7))),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('עוד חודש'),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(DateTime(base.year, base.month + 1, base.day)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _changeMatchReminder(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final ReminderChoice? choice = await ReminderPickerSheet.show(
      context,
      title: 'מתי לחזור להצעה?',
      allowClear: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );
    if (choice == null) return;
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

  /// "עדיין בהמתנה" for a reminder that belongs to the proposal itself.
  Future<void> _postponeMatchReminder(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final DateTime? date = await _pickPostponeDate(context);
    if (date != null) {
      await repository.setReminder(match.id, date, note: match.reminderNote);
    }
  }

  Future<void> _setManualWaiting(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    const List<String> reasons = <String>[
      'מחכים לתשובה ממנו',
      'מחכים לתשובה ממנה',
      'מחכים לתשובה משניהם',
      'צריך לברר עוד פרטים',
    ];
    // The reason is optional — the sheet leads with "בלי סיבה מיוחדת" so the
    // action never demands an explanation. The reminder that follows is the
    // part worth encouraging: it is what keeps the proposal from getting stuck
    // in "בהמתנה" with no date to come back to.
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(
                title: Text('למה ההצעה בהמתנה?'),
                subtitle: Text('לא חובה'),
              ),
              ListTile(
                leading: const Icon(Icons.pause_rounded),
                title: const Text('בלי סיבה מיוחדת'),
                onTap: () => Navigator.of(sheetContext).pop(''),
              ),
              const Divider(height: 1),
              for (final String reason in reasons)
                ListTile(
                  title: Text(reason),
                  onTap: () => Navigator.of(sheetContext).pop(reason),
                ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('סיבה אחרת'),
                onTap: () => Navigator.of(sheetContext).pop('__other__'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (reason == null || !context.mounted) return;

    String resolved = reason;
    if (reason == '__other__') {
      final String? written = await _promptText(context, title: 'סיבת ההמתנה');
      if (written == null || !context.mounted) return;
      resolved = written;
    }

    final ReminderChoice? reminder = await ReminderPickerSheet.show(
      context,
      title: 'מתי לחזור לבדוק?',
      allowSkip: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );

    String? note;
    if (reminder?.date != null && context.mounted) {
      note = await ReminderNoteDialog.show(context);
    }
    await repository.setWaiting(
      match.id,
      reason: resolved.trim(),
      checkAgainOn: reminder?.date,
      reminderNote: note,
    );
  }

  Future<void> _showCloseSheet(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final MatchStatus? status = await showModalBottomSheet<MatchStatus>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(title: Text('סגירת ההצעה')),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('ההצעה לא התקדמה'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(MatchStatus.rejected),
              ),
              ListTile(
                leading: const Icon(Icons.heart_broken_outlined),
                title: const Text('יצאו ולא המשיכו'),
                onTap: () => Navigator.of(sheetContext).pop(MatchStatus.dated),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (status != null && context.mounted) {
      await _showOutcomeDialog(context, repository, match, status);
    }
  }

  Future<void> _showOutcomeDialog(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
    MatchStatus status,
  ) async {
    final ({MatchOutcomeParty party, String note})? result =
        await MatchOutcomeDialog.show(context, status);
    if (result == null) return;
    await repository.recordOutcome(
      match.id,
      newStatus: status,
      party: result.party,
      note: result.note.isEmpty ? null : result.note,
    );
  }

  Future<void> _markMarried(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'מזל טוב!',
      message: 'לעדכן שהזוג התחתן?',
      confirmText: 'עדכון לחתונה',
    );
    if (confirmed == true) {
      await repository.updateStatus(match.id, MatchStatus.married);
    }
  }

  Future<void> _addRelatedContact(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final DeviceContactChoice? choice = await DeviceContactPickerSheet.show(
      context,
    );
    if (choice == null || !context.mounted) return;
    final String? description = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _ContactDescriptionDialog(contactName: choice.name),
    );
    if (description == null) return;
    await repository.addRelatedContact(
      match.id,
      MatchContact(
        name: choice.name,
        phone: choice.phone,
        description: description.trim().isEmpty ? null : description.trim(),
      ),
    );
  }

  Future<void> _showContactsList(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const ListTile(
                  title: Text(
                    'אנשי קשר שקשורים להצעה',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                for (
                  int index = 0;
                  index < match.relatedContacts.length;
                  index++
                )
                  _ContactListTile(
                    contact: match.relatedContacts[index],
                    onWhatsApp: () =>
                        _openContactWhatsApp(match.relatedContacts[index]),
                    onRemove: () async {
                      await repository.removeRelatedContact(match.id, index);
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_outlined),
                  title: const Text('הוספת איש קשר נוסף'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) {
                        _addRelatedContact(context, repository, match);
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPersonWhatsApp(Person person) async {
    final bool opened = await WhatsAppUtils.openChat(person);
    if (!opened) _showSnackBar('אין מספר טלפון תקין');
  }

  /// The small menu behind a candidate's WhatsApp button: talk to them, or send
  /// them the other side's card. Both options name the people, so there is
  /// never a doubt about who receives what.
  Future<void> _openWhatsAppMenu(Person person, Person? other) async {
    final String name = _firstName(person);
    final String? otherName = other == null ? null : _firstName(other);
    final bool hasCard = (other?.description ?? '').trim().isNotEmpty;

    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text(
                  'WhatsApp עם $name',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ListTile(
                leading: const FaIcon(
                  FontAwesomeIcons.whatsapp,
                  color: Color(0xFF25D366),
                ),
                title: Text('פתיחת שיחה עם $name'),
                onTap: () => Navigator.of(sheetContext).pop('chat'),
              ),
              if (otherName != null)
                ListTile(
                  enabled: hasCard,
                  leading: Icon(
                    Icons.contact_mail_outlined,
                    color: hasCard
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text('שליחת הכרטיס של $otherName אל $name'),
                  subtitle: hasCard
                      ? null
                      : Text('אין כרטיס שמור אצל $otherName'),
                  onTap: hasCard
                      ? () => Navigator.of(sheetContext).pop('card')
                      : null,
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (choice == 'chat') {
      await _openPersonWhatsApp(person);
    } else if (choice == 'card' && other != null) {
      final bool opened = await WhatsAppUtils.sendCardTo(person, other);
      if (!opened) _showSnackBar('אין מספר טלפון תקין או כרטיס שמור');
    }
  }

  Future<void> _openContactWhatsApp(MatchContact contact) async {
    final bool opened = await WhatsAppUtils.openChatWithPhone(contact.phone);
    if (!opened) _showSnackBar('אין מספר טלפון תקין');
  }

  Future<String?> _promptText(BuildContext context, {required String title}) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => _TextPromptDialog(title: title),
    );
  }

  Future<void> _addNote(MatchRepository repository, String matchId) async {
    final String text = _noteController.text.trim();
    if (text.isEmpty) return;
    await repository.addNote(matchId, text);
    _noteController.clear();
  }

  /// One dialog per note: edit the text, delete it, or back out - so a note is
  /// never two menus away from a small fix.
  Future<void> _openNote(MatchRepository repository, MatchNote note) async {
    final _NoteEditorResult? result = await showDialog<_NoteEditorResult>(
      context: context,
      builder: (BuildContext context) => _NoteEditorDialog(note: note),
    );
    if (result == null) return;

    if (result.delete) {
      await repository.deleteNote(note.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('ההערה נמחקה'),
            action: SnackBarAction(
              label: 'ביטול',
              onPressed: () => repository.restoreNote(note),
            ),
          ),
        );
      return;
    }

    final String text = result.text.trim();
    if (text.isNotEmpty && text != note.text.trim()) {
      await repository.updateNote(note.id, text);
    }
  }

  Future<void> _deleteMatch(
    BuildContext context,
    MatchRepository repository,
    String matchId,
  ) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'למחוק את ההצעה?',
      message: 'ההצעה וכל ההערות שלה יימחקו.',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (confirmed != true) return;
    await repository.deleteMatch(matchId);
    if (context.mounted) context.go('/matches');
  }

  void _scheduleWhatsAppPrompt(
    MatchIdea match, {
    required Person? personA,
    required Person? personB,
  }) {
    if (!widget.autoPromptWhatsApp ||
        _promptedWhatsAppMatchId == match.id ||
        _isWhatsAppPromptOpen ||
        (personA == null && personB == null)) {
      return;
    }
    _promptedWhatsAppMatchId = match.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _isWhatsAppPromptOpen) return;
      await _showWhatsAppPrompt(personA: personA, personB: personB);
    });
  }

  Future<void> _showWhatsAppPrompt({
    required Person? personA,
    required Person? personB,
  }) async {
    final ({Person? male, Person? female}) sides = _matchPeopleByGender(
      personA,
      personB,
    );
    _isWhatsAppPromptOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('לשלוח WhatsApp?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _WhatsAppPromptTile(
                  person: sides.female,
                  fallback: 'לבחורה',
                  onTap: () =>
                      _openWhatsAppFromPrompt(dialogContext, sides.female),
                ),
                _WhatsAppPromptTile(
                  person: sides.male,
                  fallback: 'לבחור',
                  onTap: () =>
                      _openWhatsAppFromPrompt(dialogContext, sides.male),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('בהמשך'),
              ),
            ],
          );
        },
      );
    } finally {
      _isWhatsAppPromptOpen = false;
    }
  }

  Future<void> _openWhatsAppFromPrompt(
    BuildContext dialogContext,
    Person? person,
  ) async {
    if (person == null) return;
    Navigator.of(dialogContext).pop();
    await _openPersonWhatsApp(person);
  }

  ({Person? male, Person? female}) _matchPeopleByGender(
    Person? personA,
    Person? personB,
  ) {
    final Person? male = personA?.gender == Gender.male
        ? personA
        : personB?.gender == Gender.male
        ? personB
        : personA ?? personB;
    final Person? female = personA?.gender == Gender.female
        ? personA
        : personB?.gender == Gender.female
        ? personB
        : identical(male, personA)
        ? personB
        : personA;
    return (male: male, female: female);
  }

  String _firstName(Person person) {
    final String name = person.firstName.trim();
    return name.isEmpty ? 'המועמד/ת' : name;
  }

  /// The button label for putting a paused person back to "פנוי".
  String _returnedLabel(Person person) {
    return person.gender == Gender.female ? 'חזרה לפנויה' : 'חזר לפנוי';
  }

  String _returnedToAvailability(Person person) {
    if (person.profileStatus == ProfileStatus.onBreak) {
      return person.gender == Gender.female ? 'חזרה מהפסקה' : 'חזר מהפסקה';
    }
    return person.gender == Gender.female ? 'פנויה שוב' : 'פנוי שוב';
  }

  bool _isTechnicalJournalNote(String text) {
    final String value = text.trim();
    return value.startsWith('סטטוס שונה ל') ||
        value.startsWith('איפה זה עומד:') ||
        value.startsWith('שונתה תזכורת') ||
        value.startsWith('נערך שדה');
  }

  bool get _canSendNote => _noteController.text.trim().isNotEmpty;

  void _handleNoteChanged() {
    if (mounted) setState(() {});
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The couple, as one shared card in exactly the language of the רעיונות
/// screen: a cream-white surface, a hairline border, a thin rose / blue stripe
/// at each outer edge — and no separate frame or background per side.
class _PairCard extends StatelessWidget {
  const _PairCard({
    required this.female,
    required this.male,
    required this.celebrating,
    required this.statusLine,
    required this.statusColor,
    required this.statusIcon,
    required this.onOpenProfile,
    required this.onWhatsApp,
    required this.onComparePair,
    required this.onStatusPicked,
  });

  final Person? female;
  final Person? male;
  final bool celebrating;

  /// The single derived line at the bottom: state plus what is needed now.
  final String statusLine;
  final Color statusColor;
  final IconData statusIcon;

  final ValueChanged<Person> onOpenProfile;
  final void Function(Person person, Person? other) onWhatsApp;

  /// Tapping the tile itself — anywhere that is not one of the per-person
  /// controls — opens the two cards facing each other.
  final VoidCallback? onComparePair;
  final void Function(Person person, ProfileStatus status) onStatusPicked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color celebrationAccent = dark
        ? AppColors.femaleAccentDm
        : AppColors.femaleAccent;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: celebrating ? null : theme.colorScheme.surface,
        gradient: celebrating
            ? LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[
                  Color.alphaBlend(
                    AppColors.softRose.withValues(alpha: dark ? 0.18 : 0.78),
                    theme.colorScheme.surface,
                  ),
                  Color.alphaBlend(
                    AppColors.softYellow.withValues(alpha: dark ? 0.10 : 0.46),
                    theme.colorScheme.surface,
                  ),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: celebrating
              ? celebrationAccent.withValues(alpha: 0.72)
              : theme.colorScheme.outlineVariant,
          width: celebrating ? 1.8 : 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: celebrating
                ? celebrationAccent.withValues(alpha: 0.24)
                : Colors.black.withValues(alpha: 0.035),
            blurRadius: celebrating ? 20 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          if (celebrating)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              color: celebrationAccent.withValues(alpha: dark ? 0.13 : 0.10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.auto_awesome, size: 16, color: celebrationAccent),
                  const SizedBox(width: 7),
                  Text(
                    'איזה כיף — הם יוצאים!',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: celebrationAccent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Icon(Icons.auto_awesome, size: 16, color: celebrationAccent),
                ],
              ),
            ),
          Stack(
            children: <Widget>[
              // Sits behind the two sides, so the per-person avatar, WhatsApp
              // and status controls keep their own taps and everything around
              // them opens the comparison.
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: onComparePair),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _EdgeStripe(
                    color: AppColors.genderAccent(Gender.female, dark: dark),
                    atStart: true,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 14, 6, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // In RTL the first child sits on the right.
                          Expanded(
                            child: _CandidateSide(
                              person: female,
                              other: male,
                              gender: Gender.female,
                              onOpenProfile: onOpenProfile,
                              onWhatsApp: onWhatsApp,
                              onStatusPicked: onStatusPicked,
                            ),
                          ),
                          _HeartLink(celebrating: celebrating),
                          Expanded(
                            child: _CandidateSide(
                              person: male,
                              other: female,
                              gender: Gender.male,
                              onOpenProfile: onOpenProfile,
                              onWhatsApp: onWhatsApp,
                              onStatusPicked: onStatusPicked,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _EdgeStripe(
                    color: AppColors.genderAccent(Gender.male, dark: dark),
                    atStart: false,
                  ),
                ],
              ),
            ],
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
            child: Row(
              children: <Widget>[
                Icon(statusIcon, size: 17, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusLine,
                    maxLines: 2,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The thin gender stripe on each outer edge of the pair card — the only place
/// the two sides are told apart.
class _EdgeStripe extends StatelessWidget {
  const _EdgeStripe({required this.color, required this.atStart});

  final Color color;
  final bool atStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 96,
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.75),
        borderRadius: BorderRadiusDirectional.horizontal(
          end: atStart ? const Radius.circular(12) : Radius.zero,
          start: atStart ? Radius.zero : const Radius.circular(12),
        ),
      ),
    );
  }
}

/// The heart between the two photos, with the dotted line the mockup uses.
class _HeartLink extends StatelessWidget {
  const _HeartLink({this.celebrating = false});

  final bool celebrating;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              Icon(
                Icons.favorite_rounded,
                size: celebrating ? 29 : 22,
                color: celebrating
                    ? AppColors.statusDating
                    : theme.colorScheme.secondary,
              ),
              if (celebrating)
                const Positioned(
                  top: -9,
                  right: -8,
                  child: Icon(
                    Icons.auto_awesome,
                    size: 12,
                    color: AppColors.secondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: 22,
            height: 2,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

/// The availability values a matchmaker can set by hand. `mazelTov` is left
/// out - it is set by the app when a proposal ends in a wedding.
const List<ProfileStatus> selectableProfileStatuses = <ProfileStatus>[
  ProfileStatus.available,
  ProfileStatus.busy,
  ProfileStatus.onBreak,
];

/// One candidate inside the shared card: photo in a gender ring, name, the
/// basic details, a small WhatsApp button and the global availability chip.
class _CandidateSide extends StatelessWidget {
  const _CandidateSide({
    required this.person,
    required this.other,
    required this.gender,
    required this.onOpenProfile,
    required this.onWhatsApp,
    required this.onStatusPicked,
  });

  final Person? person;

  /// The candidate on the other side — the card that can be sent to this one.
  final Person? other;

  final Gender gender;
  final ValueChanged<Person> onOpenProfile;
  final void Function(Person person, Person? other) onWhatsApp;
  final void Function(Person person, ProfileStatus status) onStatusPicked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ring = AppColors.genderAccent(gender, dark: dark);
    final Person? current = person;
    // Age and outlook only — the city says nothing about the proposal itself
    // and it is one line too many on a card this narrow.
    final List<String> details = <String>[
      if (current?.age != null) '${current!.age}',
      if (current?.religiousLevelLabel.isNotEmpty ?? false)
        current!.religiousLevelLabel,
    ];
    final bool hasPhone =
        current != null && PhoneUtils.toWhatsAppNumber(current.phone) != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Photo, name and details are one tap target: they all open the
        // profile.
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: current == null ? null : () => onOpenProfile(current),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ring, width: 2),
                  ),
                  child: current == null
                      ? CircleAvatar(
                          radius: 32,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.person_off_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : PersonAvatar(person: current, radius: 32),
                ),
                const SizedBox(height: 8),
                Text(
                  current?.fullName.trim().isNotEmpty == true
                      ? current!.fullName.trim()
                      : 'אדם נמחק',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  details.isEmpty ? 'פרטים בסיסיים חסרים' : details.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (current != null) ...<Widget>[
          const SizedBox(height: 6),
          Tooltip(
            message: 'WhatsApp עם ${current.firstName}',
            child: Material(
              color: const Color(0xFF25D366).withValues(alpha: 0.12),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: hasPhone ? () => onWhatsApp(current, other) : null,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: FaIcon(
                    FontAwesomeIcons.whatsapp,
                    size: 17,
                    color: hasPhone
                        ? const Color(0xFF25D366)
                        : theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          // The person's global availability — not a per-proposal state.
          PopupMenuButton<ProfileStatus>(
            tooltip: 'שינוי הסטטוס של ${current.firstName}',
            position: PopupMenuPosition.under,
            padding: EdgeInsets.zero,
            onSelected: (ProfileStatus status) =>
                onStatusPicked(current, status),
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<ProfileStatus>>[
                  for (final ProfileStatus status in selectableProfileStatuses)
                    PopupMenuItem<ProfileStatus>(
                      value: status,
                      height: 44,
                      child: Row(
                        children: <Widget>[
                          ProfileStatusTag(status: status),
                          const Spacer(),
                          if (status == current.profileStatus)
                            Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ProfileStatusTag(status: current.profileStatus),
                  const SizedBox(width: 1),
                  Icon(
                    Icons.expand_more,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The proposal's derived state — read from the two people's availability, the
/// proposal status and the reminders. Nothing here is stored separately.
class _MatchSituation {
  const _MatchSituation({
    required this.line,
    required this.color,
    required this.icon,
    this.reminderOwner,
    this.reminderDate,
    this.reminderNote,
    this.isDue = false,
  });

  /// The single line under the pair: "פתוחה · יאללה לקדם".
  final String line;
  final Color color;
  final IconData icon;

  /// Set when the reminder in play belongs to one of the people rather than to
  /// the proposal itself.
  final Person? reminderOwner;

  final DateTime? reminderDate;
  final String? reminderNote;
  final bool isDue;
}

/// The pastel traffic light of "עדכון הצעה" — go, wait, stop.
enum _ActionTone { go, wait, stop }

class _ProposalAction {
  const _ProposalAction({
    required this.label,
    required this.icon,
    required this.tone,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;

  final IconData icon;
  final _ActionTone tone;
  final VoidCallback onTap;

  /// The one action that leads — bigger, and the only one with a frame.
  final bool emphasized;

  Color get ink {
    switch (tone) {
      case _ActionTone.go:
        return AppColors.statusDating;
      case _ActionTone.wait:
        return AppColors.statusChecking;
      case _ActionTone.stop:
        return AppColors.statusRejected;
    }
  }
}

/// The reminder area, right under the pair: the one thing that keeps a proposal
/// from being forgotten, so it is clear and central — but never larger than the
/// work itself.
class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.date,
    required this.note,
    required this.isDue,
    required this.onTap,
    required this.onPostpone,
    required this.onBackToAvailable,
    required this.backToAvailableLabel,
    required this.onHandled,
  });

  final DateTime? date;
  final String? note;
  final bool isDue;

  /// Null while the proposal is dating or closed — there is nothing to plan.
  final VoidCallback? onTap;

  /// Offered only once the reminder has come due.
  final VoidCallback? onPostpone;
  final VoidCallback? onBackToAvailable;
  final String? backToAvailableLabel;
  final VoidCallback? onHandled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? current = date;
    final Color accent = isDue
        ? AppColors.secondary
        : theme.colorScheme.primary;
    final String? trimmedNote = note?.trim();
    final bool showDueRow =
        isDue &&
        (onPostpone != null || onBackToAvailable != null || onHandled != null);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDue
              ? accent.withValues(alpha: 0.45)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      current == null
                          ? Icons.notifications_none_rounded
                          : Icons.notifications_active_outlined,
                      size: 21,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          current == null
                              ? 'הוספת תזכורת'
                              : '${AppDateUtils.formatDate(current)} · '
                                    '${_relativeLabel(current)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitleFor(current, trimmedNote),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: isDue
                                ? accent
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: isDue
                                ? FontWeight.w700
                                : FontWeight.w400,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          if (showDueRow) ...<Widget>[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (onPostpone != null)
                    OutlinedButton.icon(
                      onPressed: onPostpone,
                      icon: const Icon(Icons.schedule, size: 17),
                      label: const Text('עדיין בהמתנה'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (onBackToAvailable != null)
                    FilledButton.icon(
                      onPressed: onBackToAvailable,
                      icon: const Icon(Icons.check_rounded, size: 17),
                      label: Text(backToAvailableLabel ?? 'חזר/ה לפנוי'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppColors.statusDating,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                    ),
                  if (onHandled != null)
                    TextButton.icon(
                      onPressed: onHandled,
                      icon: const Icon(Icons.check_circle_outline, size: 17),
                      label: const Text('טופל'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The line under the date. Once the reminder is due it says how long it has
  /// been waiting since the matchmaker asked to be reminded, with their own
  /// note after it when there is one.
  String _subtitleFor(DateTime? date, String? note) {
    if (date == null) {
      return 'נזכיר לך לחזור אליה בזמן הנכון';
    }
    final bool hasNote = note != null && note.isNotEmpty;
    if (!isDue) {
      return hasNote ? note : 'אפשר לשנות בלחיצה';
    }
    final String waited = AppDateUtils.remindedAgoLabel(date);
    return hasNote ? '$waited · $note' : waited;
  }

  static String _relativeLabel(DateTime date) {
    final int days = _daysFromToday(date);
    if (days == 0) return 'היום';
    if (days > 0) return AppDateUtils.futureReminderLabel(date);
    if (days == -1) return 'התאריך היה אתמול';
    return 'עברו ${-days} ימים';
  }

  static int _daysFromToday(DateTime date) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return DateTime(date.year, date.month, date.day).difference(today).inDays;
  }
}

/// "עדכון הצעה": one area, three ways on. The pastel traffic light is the only
/// colour here — the middle action leads, the two beside it stay quiet.
class _UpdateProposalCard extends StatelessWidget {
  const _UpdateProposalCard({required this.actions});

  final List<_ProposalAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              'עדכון הצעה',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < actions.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    flex: actions[i].emphasized ? 12 : 9,
                    child: _ActionTile(action: actions[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final _ProposalAction action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = action.ink;
    final bool lead = action.emphasized;

    return Material(
      color: ink.withValues(alpha: dark ? 0.20 : (lead ? 0.16 : 0.09)),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action.onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: lead
                ? Border.all(color: ink.withValues(alpha: 0.55), width: 1.4)
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 6,
              vertical: lead ? 14 : 11,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(action.icon, size: lead ? 24 : 20, color: ink),
                const SizedBox(height: 7),
                // The label is the whole tile now. A name that does not fit the
                // tile's width wraps onto a second line instead of being cut.
                Text(
                  action.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style:
                      (lead
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.labelMedium)
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ink,
                            height: 1.2,
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The people around the proposal (a mother, a friend, another matchmaker).
/// Until one is added this is only a quiet line — a full card here would
/// compete with the pair and the reminder for no reason. Once a contact exists
/// it becomes the card with all its details.
class _RelatedContactsCard extends StatelessWidget {
  const _RelatedContactsCard({
    required this.contacts,
    required this.onAdd,
    required this.onOpenList,
    required this.onWhatsApp,
  });

  final List<MatchContact> contacts;
  final VoidCallback onAdd;
  final VoidCallback onOpenList;
  final ValueChanged<MatchContact> onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchContact? first = contacts.isEmpty ? null : contacts.first;

    if (first == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('איש קשר שקשור להצעה'),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          ListTile(
            onTap: onOpenList,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: const Icon(Icons.person_outline_rounded),
            ),
            title: Text(
              first.name.trim().isEmpty ? 'איש קשר' : first.name.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: (first.description ?? '').trim().isEmpty
                ? null
                : Text(
                    first.description!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: 'WhatsApp',
                  onPressed: () => onWhatsApp(first),
                  icon: const FaIcon(
                    FontAwesomeIcons.whatsapp,
                    size: 19,
                    color: Color(0xFF25D366),
                  ),
                ),
                if (contacts.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '+${contacts.length - 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          InkWell(
            onTap: onAdd,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_add_alt_1_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'הוספת איש קשר נוסף',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactListTile extends StatelessWidget {
  const _ContactListTile({
    required this.contact,
    required this.onWhatsApp,
    required this.onRemove,
  });

  final MatchContact contact;
  final VoidCallback onWhatsApp;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final String description = (contact.description ?? '').trim();
    return ListTile(
      title: Text(
        contact.name.trim().isEmpty ? 'איש קשר' : contact.name.trim(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: description.isEmpty ? null : Text(description),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'WhatsApp',
            onPressed: onWhatsApp,
            icon: const FaIcon(
              FontAwesomeIcons.whatsapp,
              size: 19,
              color: Color(0xFF25D366),
            ),
          ),
          IconButton(
            tooltip: 'הסרה',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _MatchTimeline extends StatelessWidget {
  const _MatchTimeline({
    required this.notes,
    required this.dateFormat,
    required this.isEditing,
    required this.selectedIds,
    required this.onOpen,
    required this.onToggleSelected,
    required this.onStartEditing,
  });

  final List<MatchNote> notes;
  final DateFormat dateFormat;
  final bool isEditing;
  final Set<String> selectedIds;
  final ValueChanged<MatchNote> onOpen;
  final ValueChanged<MatchNote> onToggleSelected;
  final VoidCallback onStartEditing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (notes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          'כאן יופיעו שיחות, תשובות והערות שקשורות להצעה.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final List<MatchNote> ordered = notes.reversed.toList();
    return Column(
      children: ordered.map((MatchNote note) {
        final bool isSelected = isEditing && selectedIds.contains(note.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: isSelected
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              // Automatic entries open the same editor as hand-written ones -
              // an auto-generated line is still the matchmaker's journal, and
              // it is theirs to reword or remove.
              onTap: isEditing
                  ? () => onToggleSelected(note)
                  : () => onOpen(note),
              onLongPress: isEditing
                  ? null
                  : () {
                      onStartEditing();
                      onToggleSelected(note);
                    },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                // The checkbox centers against the whole card, so a long note
                // does not leave the box stranded at the top.
                child: Row(
                  children: <Widget>[
                    if (isEditing) ...<Widget>[
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: isSelected,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (_) => onToggleSelected(note),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(note.text),
                          const SizedBox(height: 3),
                          Text(
                            dateFormat.format(note.createdAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// The bar that replaces the composer while the journal is in edit mode:
/// delete the checked entries, or back out without touching anything.
/// The action bar shown while the journal is in edit mode. Edit mode can also
/// be left through the `X` next to the journal title, or with Back.
class _JournalEditBar extends StatelessWidget {
  const _JournalEditBar({
    required this.selectedCount,
    required this.onDelete,
    required this.onCancel,
  });

  final int selectedCount;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasSelection = selectedCount > 0;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: hasSelection ? onDelete : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 19),
                  label: Text(
                    !hasSelection
                        ? 'סמנו הערות למחיקה'
                        : selectedCount == 1
                        ? 'מחיקת הערה אחת'
                        : 'מחיקת $selectedCount הערות',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('ביטול'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the note dialog returned: either a delete, or the edited text.
class _NoteEditorResult {
  const _NoteEditorResult.save(this.text) : delete = false;
  const _NoteEditorResult.delete() : text = '', delete = true;

  final String text;
  final bool delete;
}

class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({required this.note});

  final MatchNote note;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.note.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('הערה ביומן'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(hintText: 'תוכן ההערה'),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actions: <Widget>[
        Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(const _NoteEditorResult.delete()),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline, size: 19),
              label: const Text('מחיקה'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(_NoteEditorResult.save(_controller.text)),
              child: const Text('שמירה'),
            ),
          ],
        ),
      ],
    );
  }
}

class _JournalComposer extends StatelessWidget {
  const _JournalComposer({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'הוספת הערה ליומן...'),
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'הוספת הערה',
          onPressed: canSend ? onSend : null,
          icon: const Icon(Icons.send_rounded, size: 19),
        ),
      ],
    );
  }
}

class _ContactDescriptionDialog extends StatefulWidget {
  const _ContactDescriptionDialog({required this.contactName});

  final String contactName;

  @override
  State<_ContactDescriptionDialog> createState() =>
      _ContactDescriptionDialogState();
}

class _ContactDescriptionDialogState extends State<_ContactDescriptionDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('הוספת ${widget.contactName}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'תיאור הקשר (אופציונלי)',
          hintText: 'למשל: אמא של כרמל',
        ),
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

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title});

  final String title;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('שמירה'),
        ),
      ],
    );
  }
}

class _WhatsAppPromptTile extends StatelessWidget {
  const _WhatsAppPromptTile({
    required this.person,
    required this.fallback,
    required this.onTap,
  });

  final Person? person;
  final String fallback;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const FaIcon(
        FontAwesomeIcons.whatsapp,
        color: Color(0xFF25D366),
      ),
      title: Text(
        person?.firstName.trim().isNotEmpty == true
            ? person!.firstName.trim()
            : fallback,
      ),
      enabled: person != null,
      onTap: person == null ? null : onTap,
    );
  }
}
