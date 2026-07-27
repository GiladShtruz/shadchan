import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/enums.dart';
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
                if (value == 'delete') {
                  _deleteMatch(context, matchRepository, match.id);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
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
                onOpenProfile: (Person person) =>
                    context.push('/people/${person.id}'),
                onWhatsApp: _openPersonWhatsApp,
                onStatusPicked: (Person person, ProfileStatus status) =>
                    _applyPersonStatus(
                      context,
                      personRepository,
                      person,
                      status,
                    ),
              ),
              const SizedBox(height: 14),
              _SituationCard(
                situation: situation,
                reminderDate: situation.reminderDate,
                onReminderTap:
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
                onStillWaiting:
                    situation.isDue && situation.reminderOwner != null
                    ? () => _postponePersonReminder(
                        context,
                        personRepository,
                        situation.reminderOwner!,
                      )
                    : null,
                onAvailable: situation.isDue && situation.reminderOwner != null
                    ? () => personRepository.updateProfileStatus(
                        situation.reminderOwner!.id,
                        ProfileStatus.available,
                      )
                    : null,
                availableLabel: 'חזר/ה לפנוי',
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

  List<_ProposalAction> _proposalActions(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
    _MatchSituation situation,
  ) {
    switch (match.status) {
      case MatchStatus.idea:
      case MatchStatus.checking:
        return <_ProposalAction>[
          _ProposalAction(
            label: 'התחילו לצאת',
            icon: Icons.favorite_rounded,
            emphasized: true,
            onTap: () => repository.updateStatus(match.id, MatchStatus.dating),
          ),
          _ProposalAction(
            label: 'העברה להמתנה',
            icon: Icons.pause_rounded,
            onTap: () => _setManualWaiting(context, repository, match),
          ),
          _ProposalAction(
            label: 'סגירת הצעה',
            icon: Icons.close_rounded,
            onTap: () => _showCloseSheet(context, repository, match),
          ),
        ];
      case MatchStatus.unavailable:
        return <_ProposalAction>[
          if (situation.reminderOwner == null)
            _ProposalAction(
              label: 'חזרה לפתוחה',
              icon: Icons.play_arrow_rounded,
              emphasized: true,
              onTap: () => repository.updateStatus(match.id, MatchStatus.idea),
            ),
          _ProposalAction(
            label: 'סגירת הצעה',
            icon: Icons.close_rounded,
            onTap: () => _showCloseSheet(context, repository, match),
          ),
        ];
      case MatchStatus.dating:
        return <_ProposalAction>[
          _ProposalAction(
            label: 'חתונה',
            icon: Icons.celebration_outlined,
            emphasized: true,
            onTap: () => _markMarried(context, repository, match),
          ),
          _ProposalAction(
            label: 'הפסיקו לצאת',
            icon: Icons.heart_broken_outlined,
            onTap: () => _showOutcomeDialog(
              context,
              repository,
              match,
              MatchStatus.dated,
            ),
          ),
        ];
      case MatchStatus.rejected:
      case MatchStatus.dated:
      case MatchStatus.married:
        return <_ProposalAction>[
          _ProposalAction(
            label: 'פתיחה מחדש',
            icon: Icons.refresh_rounded,
            onTap: () => repository.updateStatus(match.id, MatchStatus.idea),
          ),
        ];
    }
  }

  _MatchSituation _deriveSituation(
    MatchIdea match, {
    required ({Person? male, Person? female}) sides,
    required PersonRepository personRepository,
  }) {
    if (match.status.isArchived) {
      return _MatchSituation(
        title: 'נסגרה',
        detail: match.status.displayName,
        color: AppColors.statusColor(match.status.name),
        icon: match.status == MatchStatus.married
            ? Icons.celebration_outlined
            : Icons.check_circle_outline_rounded,
      );
    }
    if (match.status == MatchStatus.dating) {
      return const _MatchSituation(
        title: 'יוצאים',
        detail: 'הזוג בתהליך יציאה',
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
      final String detail = due
          ? 'לבדוק אם $name ${_returnedToAvailability(owner)}'
          : reminder == null
          ? '$name $status'
          : '$name $status · לבדוק שוב ב־${AppDateUtils.formatDateShort(reminder)}';
      return _MatchSituation(
        title: due ? 'דורש טיפול' : 'בהמתנה',
        detail: detail,
        color: due ? AppColors.secondary : AppColors.statusUnavailable,
        icon: due
            ? Icons.notification_important_outlined
            : Icons.pause_circle_outline_rounded,
        reminderOwner: owner,
        reminderDate: reminder,
        isDue: due,
      );
    }

    if (match.status == MatchStatus.unavailable) {
      final bool due = _isDue(match.reminderDate);
      final String reason = (match.waitingReason ?? '').trim();
      final String base = reason.isEmpty ? 'ההצעה בהמתנה' : reason;
      return _MatchSituation(
        title: due ? 'דורש טיפול' : 'בהמתנה',
        detail: match.reminderDate == null || due
            ? base
            : '$base · לבדוק שוב ב־${AppDateUtils.formatDateShort(match.reminderDate!)}',
        color: due ? AppColors.secondary : AppColors.statusUnavailable,
        icon: due
            ? Icons.notification_important_outlined
            : Icons.pause_circle_outline_rounded,
        reminderDate: match.reminderDate,
        isDue: due,
      );
    }

    final bool due = _isDue(match.reminderDate);
    return _MatchSituation(
      title: due ? 'דורש טיפול' : 'פתוחה',
      detail: due
          ? 'הגיע זמן לבדוק איתם אם הם מעוניינים!'
          : match.reminderDate == null
          ? 'אפשר לקדם את ההצעה'
          : 'תזכורת ל־${AppDateUtils.formatDateShort(match.reminderDate!)}',
      color: due ? AppColors.secondary : AppColors.statusIdea,
      icon: due
          ? Icons.notification_important_outlined
          : Icons.lightbulb_outline_rounded,
      reminderDate: match.reminderDate,
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
    final ReminderChoice? choice = await ReminderPickerSheet.show(
      context,
      title: 'מתי להזכיר לך לבדוק שוב?',
      allowSkip: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );
    if (choice?.date != null) {
      await repository.setPersonReminder(person.id, choice!.date!);
    }
  }

  Future<void> _changePersonReminder(
    BuildContext context,
    PersonRepository repository,
    Person person,
  ) async {
    final ReminderChoice? choice = await ReminderPickerSheet.show(
      context,
      title: 'מתי לבדוק שוב את ${_firstName(person)}?',
      allowClear: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );
    if (choice == null) return;
    if (choice.date == null) {
      await repository.clearPersonReminder(person.id);
    } else {
      await repository.setPersonReminder(person.id, choice.date!);
    }
  }

  Future<void> _postponePersonReminder(
    BuildContext context,
    PersonRepository repository,
    Person person,
  ) async {
    final DateTime now = DateTime.now();
    final DateTime base = DateTime(now.year, now.month, now.day);
    final DateTime? date = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(title: Text('לדחות את הבדיקה')),
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
    if (date != null) {
      await repository.setPersonReminder(person.id, date);
    }
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
    await repository.setReminder(
      match.id,
      choice.date,
      note: match.reminderNote,
    );
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
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(title: Text('למה ההצעה בהמתנה?')),
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
    final String? resolved = reason == '__other__'
        ? await _promptText(context, title: 'סיבת ההמתנה')
        : reason;
    if (resolved == null || resolved.trim().isEmpty || !context.mounted) {
      return;
    }
    final ReminderChoice? reminder = await ReminderPickerSheet.show(
      context,
      title: 'מתי לחזור לבדוק?',
      allowSkip: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );
    await repository.setWaiting(
      match.id,
      reason: resolved.trim(),
      checkAgainOn: reminder?.date,
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
        await showDialog<({MatchOutcomeParty party, String note})>(
          context: context,
          builder: (BuildContext context) => _OutcomeDialog(status: status),
        );
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

class _PairCard extends StatelessWidget {
  const _PairCard({
    required this.female,
    required this.male,
    required this.onOpenProfile,
    required this.onWhatsApp,
    required this.onStatusPicked,
  });

  final Person? female;
  final Person? male;
  final ValueChanged<Person> onOpenProfile;
  final ValueChanged<Person> onWhatsApp;
  final void Function(Person person, ProfileStatus status) onStatusPicked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _CandidateSide(
              person: female,
              gender: Gender.female,
              onOpenProfile: onOpenProfile,
              onWhatsApp: onWhatsApp,
              onStatusPicked: onStatusPicked,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 48, 7, 0),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite_rounded,
                color: theme.colorScheme.secondary,
                size: 21,
              ),
            ),
          ),
          Expanded(
            child: _CandidateSide(
              person: male,
              gender: Gender.male,
              onOpenProfile: onOpenProfile,
              onWhatsApp: onWhatsApp,
              onStatusPicked: onStatusPicked,
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

class _CandidateSide extends StatelessWidget {
  const _CandidateSide({
    required this.person,
    required this.gender,
    required this.onOpenProfile,
    required this.onWhatsApp,
    required this.onStatusPicked,
  });

  final Person? person;
  final Gender gender;
  final ValueChanged<Person> onOpenProfile;
  final ValueChanged<Person> onWhatsApp;
  final void Function(Person person, ProfileStatus status) onStatusPicked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = AppColors.genderAccent(gender, dark: dark);
    final Person? current = person;
    final List<String> details = <String>[
      if (current?.age != null) 'גיל ${current!.age}',
      if (current?.religiousLevelLabel.isNotEmpty ?? false)
        current!.religiousLevelLabel,
      if ((current?.city ?? '').trim().isNotEmpty) current!.city!.trim(),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.genderSurface(gender, dark: dark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: <Widget>[
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              onTap: current == null ? null : () => onOpenProfile(current),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                child: Column(
                  children: <Widget>[
                    if (current != null)
                      PersonAvatar(person: current, radius: 37)
                    else
                      CircleAvatar(
                        radius: 37,
                        backgroundColor: theme.colorScheme.surface,
                        child: const Icon(Icons.person_off_outlined),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      current?.fullName.trim().isNotEmpty == true
                          ? current!.fullName.trim()
                          : 'אדם נמחק',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details.isEmpty
                          ? 'פרטים בסיסיים חסרים'
                          : details.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (current != null) ...<Widget>[
            PopupMenuButton<ProfileStatus>(
              tooltip: 'שינוי הסטטוס של ${current.firstName}',
              position: PopupMenuPosition.under,
              padding: EdgeInsets.zero,
              onSelected: (ProfileStatus status) =>
                  onStatusPicked(current, status),
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<ProfileStatus>>[
                    for (final ProfileStatus status
                        in selectableProfileStatuses)
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
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ProfileStatusTag(status: current.profileStatus),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more, size: 16, color: accent),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Tooltip(
                message: 'WhatsApp עם ${current.firstName}',
                child: Material(
                  color: const Color(0xFF25D366).withValues(alpha: 0.14),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onWhatsApp(current),
                    child: const Padding(
                      padding: EdgeInsets.all(9),
                      child: FaIcon(
                        FontAwesomeIcons.whatsapp,
                        size: 19,
                        color: Color(0xFF25D366),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MatchSituation {
  const _MatchSituation({
    required this.title,
    required this.detail,
    required this.color,
    required this.icon,
    this.reminderOwner,
    this.reminderDate,
    this.isDue = false,
  });

  final String title;
  final String detail;
  final Color color;
  final IconData icon;
  final Person? reminderOwner;
  final DateTime? reminderDate;
  final bool isDue;
}

class _ProposalAction {
  const _ProposalAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool emphasized;
}

class _SituationCard extends StatelessWidget {
  const _SituationCard({
    required this.situation,
    required this.reminderDate,
    required this.onReminderTap,
    required this.onStillWaiting,
    required this.onAvailable,
    required this.availableLabel,
    required this.actions,
  });

  final _MatchSituation situation;
  final DateTime? reminderDate;
  final VoidCallback? onReminderTap;
  final VoidCallback? onStillWaiting;
  final VoidCallback? onAvailable;
  final String availableLabel;
  final List<_ProposalAction> actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<_ProposalAction> primary = actions
        .where((_ProposalAction action) => action.emphasized)
        .toList();
    final List<_ProposalAction> secondary = actions
        .where((_ProposalAction action) => !action.emphasized)
        .toList();
    final bool showDueChoice = onStillWaiting != null && onAvailable != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: situation.color.withValues(alpha: 0.22)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: situation.color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(situation.icon, color: situation.color, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      situation.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: situation.color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      situation.detail,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onReminderTap != null) ...<Widget>[
            const SizedBox(height: 12),
            _ReminderTile(
              date: reminderDate,
              color: situation.color,
              onTap: onReminderTap!,
            ),
          ],
          if (showDueChoice) ...<Widget>[
            const SizedBox(height: 12),
            _DueChoiceBlock(
              onStillWaiting: onStillWaiting!,
              onAvailable: onAvailable!,
              availableLabel: availableLabel,
            ),
          ],
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 12),
            for (final _ProposalAction action in primary)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: action.onTap,
                    icon: Icon(action.icon, size: 18),
                    label: Text(action.label),
                  ),
                ),
              ),
            if (secondary.isNotEmpty)
              Row(
                children: <Widget>[
                  for (final _ProposalAction action in secondary)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: action.onTap,
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        icon: Icon(action.icon, size: 17),
                        label: Text(
                          action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// The reminder row inside the situation card: one tappable tile that shows
/// when we plan to come back to the proposal, instead of a bare text button.
class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.date,
    required this.color,
    required this.onTap,
  });

  final DateTime? date;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? current = date;
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  current == null
                      ? Icons.notification_add_outlined
                      : Icons.event_available_outlined,
                  size: 19,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      current == null ? 'הוספת תזכורת' : 'חזרה להצעה בתאריך',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      current == null
                          ? 'בלי תזכורת ההצעה עלולה להישכח'
                          : '${AppDateUtils.formatDate(current)} · ${_relativeLabel(current)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.edit_calendar_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeLabel(DateTime date) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int days = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(today).inDays;
    if (days == 0) return 'היום';
    if (days == 1) return 'מחר';
    if (days > 1) return 'בעוד $days ימים';
    if (days == -1) return 'התאריך היה אתמול';
    return 'עברו ${-days} ימים';
  }
}

/// The "time to check in" prompt shown once a reminder is due.
class _DueChoiceBlock extends StatelessWidget {
  const _DueChoiceBlock({
    required this.onStillWaiting,
    required this.onAvailable,
    required this.availableLabel,
  });

  final VoidCallback onStillWaiting;
  final VoidCallback onAvailable;
  final String availableLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'מה המצב עכשיו?',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: onStillWaiting,
                  child: const Text('עדיין בהמתנה'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onAvailable,
                  child: Text(availableLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Always-visible card for the people around the proposal (a mother, a friend,
/// another matchmaker). Keeping it a real card - even when empty - makes the
/// "add a contact" action obvious instead of hiding it in a faint text link.
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

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          if (first != null) ...<Widget>[
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
          ],
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(first == null ? 18 : 0),
              bottom: const Radius.circular(18),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          first == null
                              ? 'הוספת איש קשר שקשור להצעה'
                              : 'הוספת איש קשר נוסף',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if (first == null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            'למשל אמא, חברה או שדכן שמעורב בהצעה',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
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
            decoration: const InputDecoration(hintText: 'הוסיפו הערה ליומן...'),
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

class _OutcomeDialog extends StatefulWidget {
  const _OutcomeDialog({required this.status});

  final MatchStatus status;

  @override
  State<_OutcomeDialog> createState() => _OutcomeDialogState();
}

class _OutcomeDialogState extends State<_OutcomeDialog> {
  final TextEditingController _noteController = TextEditingController();
  MatchOutcomeParty _party = MatchOutcomeParty.unknown;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.status == MatchStatus.dated
            ? 'יצאו ולא המשיכו'
            : 'ההצעה לא התקדמה',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('מי סיים?'),
            _option(MatchOutcomeParty.him, 'הוא'),
            _option(MatchOutcomeParty.her, 'היא'),
            _option(MatchOutcomeParty.mutual, 'הדדי'),
            _option(MatchOutcomeParty.unknown, 'לא ידוע'),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'סיבה או הערה (אופציונלי)',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop((party: _party, note: _noteController.text.trim())),
          child: const Text('שמירה'),
        ),
      ],
    );
  }

  Widget _option(MatchOutcomeParty value, String label) {
    final bool selected = _party == value;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(label),
      onTap: () => setState(() => _party = value),
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
