import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/device_contact_picker_sheet.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_photo_carousel.dart';

class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({
    super.key,
    required this.matchId,
    this.autoPromptWhatsApp = false,
  });

  final String matchId;

  /// Whether to auto-open the "send WhatsApp?" prompt. Only true when the
  /// proposal was just created, so revisiting it from a list stays quiet.
  final bool autoPromptWhatsApp;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  // The statuses offered in the picker sheet, ordered as a proposal usually
  // progresses. "בבדיקה" is intentionally omitted so an open proposal is just
  // "רעיון".
  static const List<MatchStatus> _selectableStatuses = <MatchStatus>[
    MatchStatus.idea,
    MatchStatus.unavailable,
    MatchStatus.dating,
    MatchStatus.dated,
    MatchStatus.rejected,
    MatchStatus.married,
  ];

  final TextEditingController _noteController = TextEditingController();
  // The journal shows a small, gentle date — no time by default.
  final DateFormat _noteDateFormat = DateFormat('dd.MM');

  /// Which side's card is currently expanded inline (its person id), or null.
  String? _expandedPersonId;

  String? _promptedWhatsAppMatchId;
  bool _isWhatsAppPromptOpen = false;

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
        appBar: AppBar(title: const Text('פרטי הצעה'), centerTitle: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.heart_broken_outlined,
                  size: 72,
                  color: theme.colorScheme.primaryContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  'ההצעה לא נמצאה',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/matches'),
                  child: const Text('חזרה להצעות'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Person? personA = personRepository.getById(match.personAId);
    final Person? personB = personRepository.getById(match.personBId);
    final List<MatchNote> notes = matchRepository.getNotesForMatch(match.id);
    _scheduleWhatsAppPrompt(match, personA: personA, personB: personB);

    // Sides are laid out by gender, not stored order: the woman is always on
    // the right and the man on the left (RTL puts the first child on the right).
    final ({Person? male, Person? female}) sides = _matchPeopleByGender(
      personA,
      personB,
    );
    final String femaleId = identical(sides.female, personA)
        ? match.personAId
        : match.personBId;
    final String maleId = identical(sides.male, personA)
        ? match.personAId
        : match.personBId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('פרטי הצעה'),
        centerTitle: true,
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'עוד',
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
                      size: 20,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // --- The two candidates -------------------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _PersonCard(
                    person: sides.female,
                    gender: Gender.female,
                    expanded: _expandedPersonId == femaleId,
                    onToggle: () => _toggleExpanded(femaleId),
                    onMissingPhone: _showSnackBar,
                    missingPhoneMessage: 'אין מספר טלפון תקין לבחורה',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 44,
                  ),
                  child: Icon(
                    Icons.favorite,
                    color: theme.colorScheme.secondary,
                    size: 18,
                  ),
                ),
                Expanded(
                  child: _PersonCard(
                    person: sides.male,
                    gender: Gender.male,
                    expanded: _expandedPersonId == maleId,
                    onToggle: () => _toggleExpanded(maleId),
                    onMissingPhone: _showSnackBar,
                    missingPhoneMessage: 'אין מספר טלפון תקין לבחור',
                  ),
                ),
              ],
            ),
            // The expanded detail panel sits full-width beneath the pair so
            // photos and the full card have real room on a small screen.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _expandedPersonId == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _ExpandedPersonPanel(
                        person: _expandedPersonId == femaleId
                            ? sides.female
                            : sides.male,
                        personId: _expandedPersonId!,
                        gender: _expandedPersonId == femaleId
                            ? Gender.female
                            : Gender.male,
                        onShare: _sharePerson,
                        onClose: () => _toggleExpanded(_expandedPersonId!),
                      ),
                    ),
            ),
            const SizedBox(height: 16),

            // --- Status + reminder --------------------------------------
            _StatusReminderCard(
              status: match.status,
              reminderDate: match.reminderDate,
              onStatusTap: () =>
                  _showStatusSheet(context, matchRepository, match),
              onReminderTap: () =>
                  _showReminderDialog(context, matchRepository, match),
            ),

            // --- "איפה זה עומד?" (only while the proposal is still in outreach)
            if (_showsProgressRow(match.status)) ...<Widget>[
              const SizedBox(height: 12),
              _ProgressRow(
                progress: match.progress,
                progressOther: match.progressOther,
                onTap: () =>
                    _showProgressSheet(context, matchRepository, match),
              ),
            ],
            const SizedBox(height: 20),

            // --- Journal ------------------------------------------------
            _JournalHeader(onAdd: _focusNoteField),
            const SizedBox(height: 12),
            _MatchTimeline(
              notes: notes,
              dateFormat: _noteDateFormat,
              onEdit: (MatchNote note) =>
                  _editNote(context, matchRepository, note),
              onDelete: (MatchNote note) =>
                  _deleteNote(context, matchRepository, note),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    focusNode: _noteFocus,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'הוסיפו הערה ליומן...',
                    ),
                    onSubmitted: (_) => _addNote(matchRepository, match.id),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _canSendNote
                      ? () => _addNote(matchRepository, match.id)
                      : null,
                  icon: Icon(
                    Icons.send,
                    color: _canSendNote
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // --- Related contacts ---------------------------------------
            _RelatedContactsSection(
              contacts: match.relatedContacts,
              onAdd: () => _addRelatedContact(context, matchRepository, match),
              onRemove: (int index) =>
                  matchRepository.removeRelatedContact(match.id, index),
              onMissingPhone: _showSnackBar,
            ),
            const SizedBox(height: 18),
            Text(
              'נפתחה: ${AppDateUtils.formatDate(match.createdAt)}  ·  '
              'עודכן: ${AppDateUtils.timeAgo(match.updatedAt)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The outreach row only makes sense before the couple is dating or the
  /// proposal is closed.
  bool _showsProgressRow(MatchStatus status) {
    switch (status) {
      case MatchStatus.idea:
      case MatchStatus.checking:
      case MatchStatus.unavailable:
        return true;
      case MatchStatus.dating:
      case MatchStatus.dated:
      case MatchStatus.rejected:
      case MatchStatus.married:
        return false;
    }
  }

  final FocusNode _noteFocus = FocusNode();

  void _toggleExpanded(String personId) {
    setState(() {
      _expandedPersonId = _expandedPersonId == personId ? null : personId;
    });
  }

  void _focusNoteField() {
    FocusScope.of(context).requestFocus(_noteFocus);
  }

  Future<void> _sharePerson(Person person) async {
    await ShareUtils.sharePerson(person);
  }

  // --- Status picker --------------------------------------------------------

  Future<void> _showStatusSheet(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final MatchStatus? picked = await showModalBottomSheet<MatchStatus>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'סטטוס ההצעה',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ..._selectableStatuses.map((MatchStatus status) {
                final bool isSelected = match.status == status;
                final Color color = AppColors.statusColor(status.name);
                return ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.16),
                    child: Text(
                      status.icon,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  title: Text(
                    status.displayName,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_rounded, color: color)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(status),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (picked == null || picked == match.status || !context.mounted) {
      return;
    }

    switch (picked) {
      case MatchStatus.unavailable:
        await _showWaitingReasonDialog(context, repository, match);
      case MatchStatus.rejected:
      case MatchStatus.dated:
        await _showOutcomeDialog(context, repository, match, picked);
      case MatchStatus.idea:
      case MatchStatus.checking:
      case MatchStatus.dating:
      case MatchStatus.married:
        await _changeStatus(context, repository, match, picked);
    }
  }

  /// Moving to "בהמתנה" asks which side is unavailable; the reason is journaled
  /// via [MatchRepository.setWaiting].
  Future<void> _showWaitingReasonDialog(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    const List<String> presets = <String>[
      'הוא בהפסקה',
      'היא בהפסקה',
      'הוא תפוס',
      'היא תפוסה',
    ];
    final String? reason = await _pickReasonSheet(
      context,
      title: 'למה ההצעה בהמתנה?',
      presets: presets,
      otherLabel: 'אחר / כתיבה חופשית',
    );
    if (reason == null || reason.isEmpty) {
      return;
    }
    await repository.setWaiting(match.id, reason: reason);
  }

  /// Moving to "נדחה"/"יצאו" asks who ended it plus an optional note, then writes
  /// the proposal journal and both candidates' history.
  Future<void> _showOutcomeDialog(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
    MatchStatus status,
  ) async {
    final ({MatchOutcomeParty party, String note})? result =
        await showDialog<({MatchOutcomeParty party, String note})>(
          context: context,
          builder: (BuildContext dialogContext) {
            MatchOutcomeParty party = MatchOutcomeParty.unknown;
            final TextEditingController noteController =
                TextEditingController();
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                Widget option(MatchOutcomeParty value, String label) {
                  final bool selected = party == value;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(label),
                    onTap: () => setDialogState(() => party = value),
                  );
                }

                return AlertDialog(
                  title: Text(
                    status == MatchStatus.dated
                        ? 'הזוג יצא ולא המשיך'
                        : 'ההצעה נדחתה',
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('מי סיים?'),
                      option(MatchOutcomeParty.him, 'הוא'),
                      option(MatchOutcomeParty.her, 'היא'),
                      option(MatchOutcomeParty.mutual, 'הדדי'),
                      option(MatchOutcomeParty.unknown, 'לא ידוע'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: noteController,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'הערה (אופציונלי)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('ביטול'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop((
                        party: party,
                        note: noteController.text.trim(),
                      )),
                      child: const Text('שמור'),
                    ),
                  ],
                );
              },
            );
          },
        );

    if (result == null) {
      return;
    }
    await repository.recordOutcome(
      match.id,
      newStatus: status,
      party: result.party,
      note: result.note.isEmpty ? null : result.note,
    );
  }

  /// A shared sheet that offers preset reasons plus a free-text "other" option.
  Future<String?> _pickReasonSheet(
    BuildContext context, {
    required String title,
    required List<String> presets,
    required String otherLabel,
  }) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ...presets.map(
                (String preset) => ListTile(
                  title: Text(preset),
                  onTap: () => Navigator.of(sheetContext).pop(preset),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(otherLabel),
                onTap: () => Navigator.of(sheetContext).pop(' other'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (choice == null) {
      return null;
    }
    if (choice != ' other') {
      return choice;
    }
    if (!context.mounted) {
      return null;
    }
    return _promptFreeText(context, title: title);
  }

  Future<String?> _promptFreeText(
    BuildContext context, {
    required String title,
  }) async {
    final TextEditingController controller = TextEditingController();
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('שמור'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return (text == null || text.isEmpty) ? null : text;
  }

  // --- "איפה זה עומד?" -------------------------------------------------------

  Future<void> _showProgressSheet(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final MatchProgress? picked = await showModalBottomSheet<MatchProgress>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'איפה זה עומד?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ...MatchProgress.values.map((MatchProgress progress) {
                final bool isSelected = match.progress == progress;
                return ListTile(
                  title: Text(
                    progress.displayName,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(progress),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (picked == null || !context.mounted) {
      return;
    }

    String? other;
    if (picked == MatchProgress.other) {
      other = await _promptFreeText(context, title: 'איפה זה עומד?');
      if (other == null) {
        return;
      }
    }
    await repository.setProgress(match.id, picked, other: other);
  }

  // --- Related contacts -----------------------------------------------------

  Future<void> _addRelatedContact(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final DeviceContactChoice? choice = await DeviceContactPickerSheet.show(
      context,
    );
    if (choice == null) {
      return;
    }
    await repository.addRelatedContact(
      match.id,
      MatchContact(name: choice.name, phone: choice.phone),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
    MatchStatus newStatus,
  ) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'שינוי סטטוס',
      message: 'לשנות את סטטוס ההצעה ל"${newStatus.displayName}"?',
    );

    if (confirmed != true) {
      return;
    }

    await repository.updateStatus(match.id, newStatus);
  }

  // --- Journal actions ------------------------------------------------------

  Future<void> _editNote(
    BuildContext context,
    MatchRepository repository,
    MatchNote note,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: note.text,
    );
    final String? updated = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('עריכת הערה'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('שמור'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (updated != null && updated.isNotEmpty) {
      await repository.updateNote(note.id, updated);
    }
  }

  Future<void> _deleteNote(
    BuildContext context,
    MatchRepository repository,
    MatchNote note,
  ) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'מחיקת הערה',
      message: 'למחוק את ההערה מהיומן?',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (confirmed == true) {
      await repository.deleteNote(note.id);
    }
  }

  // --- WhatsApp auto-prompt (unchanged behaviour) ---------------------------

  void _scheduleWhatsAppPrompt(
    MatchIdea match, {
    required Person? personA,
    required Person? personB,
  }) {
    if (!widget.autoPromptWhatsApp) {
      return;
    }
    if (_promptedWhatsAppMatchId == match.id || _isWhatsAppPromptOpen) {
      return;
    }
    if (personA == null && personB == null) {
      return;
    }

    _promptedWhatsAppMatchId = match.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _isWhatsAppPromptOpen) {
        return;
      }

      final MatchIdea? currentMatch = context.read<MatchRepository>().getById(
        match.id,
      );
      if (currentMatch == null) {
        return;
      }

      final PersonRepository personRepository = context
          .read<PersonRepository>();
      final Person? currentPersonA = personRepository.getById(
        currentMatch.personAId,
      );
      final Person? currentPersonB = personRepository.getById(
        currentMatch.personBId,
      );

      await _showWhatsAppPrompt(
        personA: currentPersonA,
        personB: currentPersonB,
      );
    });
  }

  Future<void> _showWhatsAppPrompt({
    required Person? personA,
    required Person? personB,
  }) async {
    final ({Person? male, Person? female}) people = _matchPeopleByGender(
      personA,
      personB,
    );

    _isWhatsAppPromptOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            title: const Text('תרצה לשלוח ווטסאפ?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _MatchWhatsAppActionTile(
                  person: people.male,
                  fallbackLabel: 'הבחור',
                  onTap: () => _openWhatsAppFromPrompt(
                    dialogContext,
                    people.male,
                    'אין מספר טלפון תקין לבחור',
                  ),
                ),
                _MatchWhatsAppActionTile(
                  person: people.female,
                  fallbackLabel: 'הבחורה',
                  onTap: () => _openWhatsAppFromPrompt(
                    dialogContext,
                    people.female,
                    'אין מספר טלפון תקין לבחורה',
                  ),
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
        : personB;

    return (male: male, female: female);
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openWhatsAppFromPrompt(
    BuildContext dialogContext,
    Person? person,
    String errorMessage,
  ) async {
    if (person == null) {
      return;
    }

    Navigator.of(dialogContext).pop();
    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  Future<void> _showReminderDialog(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
  ) async {
    final TextEditingController noteController = TextEditingController(
      text: match.reminderNote,
    );
    DateTime? selectedDate = match.reminderDate;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('תזכורת להצעה'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('תאריך תזכורת'),
                    subtitle: Text(
                      selectedDate != null
                          ? AppDateUtils.formatDateShort(selectedDate!)
                          : 'לא נבחר תאריך',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final DateTime now = DateTime.now();
                      final DateTime today = DateTime(
                        now.year,
                        now.month,
                        now.day,
                      );
                      final DateTime initialDate =
                          selectedDate != null && !selectedDate!.isBefore(today)
                          ? selectedDate!
                          : today;
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: initialDate,
                        firstDate: today,
                        lastDate: today.add(const Duration(days: 365)),
                        locale: const Locale('he'),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'הערה (אופציונלי)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              actions: <Widget>[
                if (match.reminderDate != null)
                  TextButton(
                    onPressed: () async {
                      match
                        ..reminderDate = null
                        ..reminderNote = null;
                      await repository.update(match);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    child: Text(
                      'מחק תזכורת',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('ביטול'),
                ),
                FilledButton(
                  onPressed: selectedDate == null
                      ? null
                      : () async {
                          match
                            ..reminderDate = selectedDate
                            ..reminderNote = noteController.text.trim().isEmpty
                                ? null
                                : noteController.text.trim();
                          await repository.update(match);
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                  child: const Text('שמור'),
                ),
              ],
            );
          },
        );
      },
    );

    noteController.dispose();
  }

  Future<void> _addNote(MatchRepository repository, String matchId) async {
    final String text = _noteController.text.trim();
    if (text.isEmpty) {
      return;
    }

    await repository.addNote(matchId, text);
    _noteController.clear();
  }

  Future<void> _deleteMatch(
    BuildContext context,
    MatchRepository repository,
    String matchId,
  ) async {
    final bool shouldDelete = await ConfirmDialog.show(
      context,
      title: 'למחוק את ההצעה?',
      message: 'למחוק את ההצעה? כל ההערות יימחקו.',
      confirmText: 'מחיקה',
      isDestructive: true,
    );

    if (shouldDelete != true) {
      return;
    }

    await repository.deleteMatch(matchId);
    if (context.mounted) {
      context.go('/matches');
    }
  }

  bool get _canSendNote => _noteController.text.trim().isNotEmpty;

  void _handleNoteChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

/// A compact candidate card: avatar, name and `age · style`, with a WhatsApp
/// button and an expand toggle. The rich detail lives in the full-width panel
/// that opens below the pair, so this stays lightweight on a small screen.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.gender,
    required this.expanded,
    required this.onToggle,
    required this.onMissingPhone,
    required this.missingPhoneMessage,
  });

  final Person? person;
  final Gender gender;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onMissingPhone;
  final String missingPhoneMessage;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = AppColors.genderAccent(gender, dark: dark);

    final List<String> details = <String>[
      if (person?.age != null) '${person!.age}',
      if (person?.religiousLevelLabel.isNotEmpty ?? false)
        person!.religiousLevelLabel,
    ];

    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.genderSurface(gender, dark: dark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: accent.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: person == null ? null : onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _MiniWhatsAppButton(
                    person: person,
                    onMissingPhone: onMissingPhone,
                    missingPhoneMessage: missingPhoneMessage,
                  ),
                  const Spacer(),
                  if (person != null)
                    _RoundIconButton(
                      icon: expanded
                          ? Icons.expand_less_rounded
                          : Icons.chevron_left_rounded,
                      accent: accent,
                      onTap: onToggle,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              if (person != null)
                PersonAvatar(person: person!, radius: 34)
              else
                CircleAvatar(
                  radius: 34,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.person_off_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                person?.fullName.trim().isNotEmpty == true
                    ? person!.fullName.trim()
                    : 'אדם נמחק',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (details.isNotEmpty) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  details.join(' · '),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The full-width detail panel that opens beneath the pair for one candidate:
/// photo carousel, technical details, the full card to send, and a link to the
/// complete profile.
class _ExpandedPersonPanel extends StatelessWidget {
  const _ExpandedPersonPanel({
    required this.person,
    required this.personId,
    required this.gender,
    required this.onShare,
    required this.onClose,
  });

  final Person? person;
  final String personId;
  final Gender gender;
  final ValueChanged<Person> onShare;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = AppColors.genderAccent(gender, dark: dark);
    final Person? p = person;

    if (p == null) {
      return const SizedBox.shrink();
    }

    final List<(String, String)> techDetails = <(String, String)>[
      if (p.age != null) ('גיל', '${p.age}'),
      if (p.displayHeight.isNotEmpty) ('גובה', p.displayHeight),
      if (p.maritalStatus != null)
        ('מצב', p.maritalStatus!.displayNameFor(p.gender)),
      if ((p.city ?? '').trim().isNotEmpty) ('עיר', p.city!.trim()),
      if (p.religiousLevelLabel.isNotEmpty) ('סגנון', p.religiousLevelLabel),
      if ((p.source ?? '').trim().isNotEmpty) ('מקור', p.source!.trim()),
    ];

    final String description = (p.description ?? '').trim();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.genderSurface(gender, dark: dark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PersonPhotoCarousel(
            photosPaths: p.photosPaths,
            height: 240,
            placeholder: PersonAvatar(person: p, radius: 64),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        p.fullName.trim().isNotEmpty
                            ? p.fullName.trim()
                            : 'אדם נמחק',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'סגירה',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (techDetails.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: techDetails
                        .map(
                          ((String, String) d) => _DetailChip(
                            label: d.$1,
                            value: d.$2,
                            accent: accent,
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'הכרטיס לשליחה',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Text(
                    description.isEmpty
                        ? 'עדיין אין כרטיסייה לשליחה'
                        : description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: description.isEmpty
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => onShare(p),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('שלח כרטיס'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/people/$personId'),
                        icon: const Icon(Icons.person_outline_rounded, size: 18),
                        label: const Text('לפרופיל המלא'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: <TextSpan>[
            TextSpan(
              text: '$label ',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 20, color: accent),
        ),
      ),
    );
  }
}

/// Small circular WhatsApp button used in the collapsed candidate card.
class _MiniWhatsAppButton extends StatelessWidget {
  const _MiniWhatsAppButton({
    required this.person,
    required this.onMissingPhone,
    required this.missingPhoneMessage,
  });

  final Person? person;
  final ValueChanged<String> onMissingPhone;
  final String missingPhoneMessage;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Person? currentPerson = person;
    final bool canOpen =
        currentPerson != null &&
        WhatsAppUtils.buildChatUri(currentPerson) != null;

    return Material(
      color: canOpen
          ? const Color(0xFF25D366).withValues(alpha: 0.16)
          : theme.colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: !canOpen
            ? null
            : () async {
                final bool launched = await WhatsAppUtils.openChat(
                  currentPerson,
                );
                if (!launched) {
                  onMissingPhone(missingPhoneMessage);
                }
              },
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: FaIcon(
              FontAwesomeIcons.whatsapp,
              size: 16,
              color: canOpen
                  ? const Color(0xFF25D366)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact "status + reminder" card with two tappable columns.
class _StatusReminderCard extends StatelessWidget {
  const _StatusReminderCard({
    required this.status,
    required this.reminderDate,
    required this.onStatusTap,
    required this.onReminderTap,
  });

  final MatchStatus status;
  final DateTime? reminderDate;
  final VoidCallback onStatusTap;
  final VoidCallback onReminderTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            Expanded(
              child: _StatusReminderColumn(
                title: 'סטטוס הצעה',
                onTap: onStatusTap,
                child: _StatusPill(status: status),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            Expanded(
              child: _StatusReminderColumn(
                title: 'תזכורת',
                onTap: onReminderTap,
                child: _ReminderPill(date: reminderDate),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusReminderColumn extends StatelessWidget {
  const _StatusReminderColumn({
    required this.title,
    required this.onTap,
    required this.child,
  });

  final String title;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Column(
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.statusColor(status.name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(status.icon, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderPill extends StatelessWidget {
  const _ReminderPill({required this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasDate = date != null;
    final Color color = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: hasDate
            ? color.withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            hasDate
                ? Icons.notifications_active_rounded
                : Icons.notification_add_outlined,
            size: 16,
            color: hasDate ? color : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              hasDate ? AppDateUtils.formatDateShort(date!) : 'הוסף תזכורת',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: hasDate ? color : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalHeader extends StatelessWidget {
  const _JournalHeader({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'יומן ההצעה',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('הוסף הערה'),
        ),
      ],
    );
  }
}

/// A vertical timeline of the proposal's journal entries. The note text is the
/// focus; the date is small and quiet. Long-press opens edit / delete.
class _MatchTimeline extends StatelessWidget {
  const _MatchTimeline({
    required this.notes,
    required this.dateFormat,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MatchNote> notes;
  final DateFormat dateFormat;
  final ValueChanged<MatchNote> onEdit;
  final ValueChanged<MatchNote> onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (notes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          'אין עדיין רשומות ביומן — כאן יופיעו הערות ושינויי סטטוס לאורך התהליך.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Newest first reads best in a journal.
    final List<MatchNote> ordered = notes.reversed.toList();

    return Column(
      children: <Widget>[
        for (int i = 0; i < ordered.length; i++)
          _TimelineRow(
            note: ordered[i],
            isLast: i == ordered.length - 1,
            dateFormat: dateFormat,
            onEdit: () => onEdit(ordered[i]),
            onDelete: () => onDelete(ordered[i]),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.note,
    required this.isLast,
    required this.dateFormat,
    required this.onEdit,
    required this.onDelete,
  });

  final MatchNote note;
  final bool isLast;
  final DateFormat dateFormat;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData, Color) marker = _markerFor(note, theme);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The rail: coloured dot + connecting line.
          Column(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: marker.$2.withValues(alpha: 0.16),
                ),
                child: Icon(marker.$1, size: 18, color: marker.$2),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onLongPress: () => _showActions(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: note.isAutomatic
                        ? theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.4,
                          )
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        note.text,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: note.isAutomatic
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                          fontStyle: note.isAutomatic
                              ? FontStyle.italic
                              : FontStyle.normal,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFormat.format(note.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('עריכה'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onEdit();
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: const Text('מחיקה'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onDelete();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Picks an icon and colour for a journal entry. Manual notes get a neutral
  /// note glyph; automatic status notes are coloured by the status they mention.
  (IconData, Color) _markerFor(MatchNote note, ThemeData theme) {
    if (!note.isAutomatic) {
      return (Icons.chat_bubble_outline_rounded, theme.colorScheme.primary);
    }

    final String text = note.text;
    if (text.contains(MatchStatus.dating.displayName) ||
        text.contains('לצאת')) {
      return (Icons.favorite_rounded, AppColors.statusColor('dating'));
    }
    if (text.contains(MatchStatus.unavailable.displayName)) {
      return (Icons.pause_circle_outline_rounded, AppColors.statusColor('unavailable'));
    }
    if (text.contains(MatchStatus.rejected.displayName)) {
      return (Icons.cancel_outlined, AppColors.statusColor('rejected'));
    }
    if (text.contains(MatchStatus.married.displayName)) {
      return (Icons.celebration_outlined, AppColors.statusColor('married'));
    }
    if (text.contains(MatchStatus.dated.displayName)) {
      return (Icons.history_rounded, AppColors.statusColor('dated'));
    }
    return (Icons.tips_and_updates_outlined, AppColors.statusColor('idea'));
  }
}

class _MatchWhatsAppActionTile extends StatelessWidget {
  const _MatchWhatsAppActionTile({
    required this.person,
    required this.fallbackLabel,
    required this.onTap,
  });

  final Person? person;

  /// Shown instead of a first name when the contact is missing or unnamed.
  final String fallbackLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Person? currentPerson = person;
    final bool canOpen =
        currentPerson != null &&
        WhatsAppUtils.buildChatUri(currentPerson) != null;
    final String firstName = (currentPerson?.firstName ?? '').trim();
    final String label = firstName.isEmpty ? fallbackLabel : firstName;
    final String? subtitle = currentPerson == null
        ? 'איש הקשר חסר'
        : canOpen
        ? null
        : 'אין מספר טלפון תקין';

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      enabled: canOpen,
      leading: const Icon(Icons.chat_outlined),
      title: Text('ל$label'),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.open_in_new),
      onTap: canOpen ? onTap : null,
    );
  }
}

/// The subtle "איפה זה עומד?" row. Shows the current stage (or "טרם פניתי") and
/// opens the picker on tap.
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.progress,
    required this.progressOther,
    required this.onTap,
  });

  final MatchProgress? progress;
  final String? progressOther;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String value;
    if (progress == null) {
      value = MatchProgress.notStarted.displayName;
    } else if (progress == MatchProgress.other &&
        (progressOther?.trim().isNotEmpty ?? false)) {
      value = progressOther!.trim();
    } else {
      value = progress!.displayName;
    }

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.route_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                'איפה זה עומד?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_left_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contacts tied to the proposal. When empty it is just a quiet button; once a
/// contact exists it grows a titled list with WhatsApp and a remove menu.
class _RelatedContactsSection extends StatelessWidget {
  const _RelatedContactsSection({
    required this.contacts,
    required this.onAdd,
    required this.onRemove,
    required this.onMissingPhone,
  });

  final List<MatchContact> contacts;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<String> onMissingPhone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (contacts.isEmpty) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('הוסף איש קשר שקשור להצעה'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'אנשי קשר קשורים',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('הוסף'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (int i = 0; i < contacts.length; i++)
          _RelatedContactTile(
            contact: contacts[i],
            onRemove: () => onRemove(i),
            onMissingPhone: onMissingPhone,
          ),
      ],
    );
  }
}

class _RelatedContactTile extends StatelessWidget {
  const _RelatedContactTile({
    required this.contact,
    required this.onRemove,
    required this.onMissingPhone,
  });

  final MatchContact contact;
  final VoidCallback onRemove;
  final ValueChanged<String> onMissingPhone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = contact.name.trim().isEmpty
        ? 'איש קשר'
        : contact.name.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.only(start: 14, end: 4),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: contact.phone.trim().isEmpty ? null : Text(contact.phone),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'וואטסאפ',
              icon: const FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 20,
                color: Color(0xFF25D366),
              ),
              onPressed: () async {
                final bool launched = await WhatsAppUtils.openChatWithPhone(
                  contact.phone,
                );
                if (!launched) {
                  onMissingPhone('אין מספר טלפון תקין');
                }
              },
            ),
            IconButton(
              tooltip: 'הסרה',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
