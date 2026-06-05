import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/section_header.dart';

class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({super.key, required this.matchId});

  final String matchId;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  // Status options shown to the user, ordered to match the proposals tabs.
  // "בבדיקה" is intentionally omitted so an open proposal is just "רעיון".
  static const List<MatchStatus> _selectableStatuses = <MatchStatus>[
    MatchStatus.idea,
    MatchStatus.unavailable,
    MatchStatus.dating,
    MatchStatus.dated,
    MatchStatus.rejected,
    MatchStatus.married,
  ];

  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _thirdPartyController = TextEditingController();
  final DateFormat _noteDateFormat = DateFormat('dd.MM.yyyy HH:mm');
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
    _thirdPartyController.dispose();
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

    if (match.currentHandler == CurrentHandler.thirdParty &&
        _thirdPartyController.text != (match.handlerName ?? '')) {
      _thirdPartyController.text = match.handlerName ?? '';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('פרטי הצעה'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'מחיקה',
            onPressed: () => _deleteMatch(context, matchRepository, match.id),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _PersonCard(
                    person: personA,
                    personId: match.personAId,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 32,
                  ),
                  child: Icon(
                    Icons.favorite,
                    color: theme.colorScheme.secondary,
                    size: 28,
                  ),
                ),
                Expanded(
                  child: _PersonCard(
                    person: personB,
                    personId: match.personBId,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'סטטוס'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _LargeStatusChip(status: match.status),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectableStatuses.map((MatchStatus status) {
                        final bool isSelected = match.status == status;
                        return ChoiceChip(
                          label: Text('${status.icon} ${status.displayName}'),
                          selected: isSelected,
                          selectedColor: AppColors.statusBackgroundColor(
                            status.name,
                          ),
                          labelStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: isSelected
                                ? AppColors.statusColor(status.name)
                                : theme.colorScheme.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          side: isSelected
                              ? BorderSide.none
                              : BorderSide(color: theme.colorScheme.outline),
                          onSelected: isSelected
                              ? null
                              : (_) => _changeStatus(
                                  context,
                                  matchRepository,
                                  match,
                                  status,
                                ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'תזכורת להצעה'),
            Card(
              child: ListTile(
                leading: Icon(
                  match.reminderDate != null
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  color: match.reminderDate != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  match.reminderDate != null
                      ? 'תזכורת פעילה'
                      : 'אין תזכורת להצעה',
                ),
                subtitle: Text(_reminderSubtitle(match)),
                trailing: TextButton.icon(
                  onPressed: () =>
                      _showReminderDialog(context, matchRepository, match),
                  icon: Icon(
                    match.reminderDate != null ? Icons.edit : Icons.add_alert,
                  ),
                  label: Text(match.reminderDate != null ? 'עריכה' : 'הוספה'),
                ),
                onTap: () =>
                    _showReminderDialog(context, matchRepository, match),
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'אחראי נוכחי'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: CurrentHandler.values.map((
                        CurrentHandler handler,
                      ) {
                        final bool isSelected = match.currentHandler == handler;
                        return ChoiceChip(
                          label: Text(
                            _handlerLabel(
                              handler: handler,
                              personA: personA,
                              personB: personB,
                              handlerName: match.handlerName,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: isSelected
                              ? null
                              : (_) => _changeHandler(
                                  context,
                                  matchRepository,
                                  match,
                                  handler,
                                ),
                        );
                      }).toList(),
                    ),
                    if (match.currentHandler ==
                        CurrentHandler.thirdParty) ...<Widget>[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _thirdPartyController,
                        decoration: const InputDecoration(
                          labelText: 'שם הגורם האחראי',
                        ),
                        onSubmitted: (String value) => _saveThirdPartyName(
                          context,
                          matchRepository,
                          match,
                          value,
                        ),
                        onTapOutside: (_) => _saveThirdPartyName(
                          context,
                          matchRepository,
                          match,
                          _thirdPartyController.text,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SectionHeader(
              title: 'יומן הערות',
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(notes.length.toString()),
              ),
            ),
            const SizedBox(height: 12),
            _NotesTimeline(notes: notes, dateFormat: _noteDateFormat),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'הוסיפו הערה...',
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
            const SizedBox(height: 24),
            Text(
              'נפתח: ${AppDateUtils.formatDate(match.createdAt)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
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

  String _handlerLabel({
    required CurrentHandler handler,
    required Person? personA,
    required Person? personB,
    required String? handlerName,
  }) {
    switch (handler) {
      case CurrentHandler.me:
        return CurrentHandler.me.displayName;
      case CurrentHandler.personA:
        return personA?.fullName.trim().isNotEmpty == true
            ? personA!.fullName.trim()
            : 'אדם נמחק';
      case CurrentHandler.personB:
        return personB?.fullName.trim().isNotEmpty == true
            ? personB!.fullName.trim()
            : 'אדם נמחק';
      case CurrentHandler.thirdParty:
        return (handlerName ?? '').trim().isNotEmpty
            ? handlerName!.trim()
            : CurrentHandler.thirdParty.displayName;
    }
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
      message: '''
לשנות סטטוס ל-${newStatus.displayName}?${newStatus.displayName == 'בהמתנה'
          ? '\n(אחד הצדדים תפוס או בהפסקה)'
          : ''}
''',
    );

    if (confirmed != true) {
      return;
    }

    await repository.updateStatus(match.id, newStatus);
  }

  void _scheduleWhatsAppPrompt(
    MatchIdea match, {
    required Person? personA,
    required Person? personB,
  }) {
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
            title: const Text('תרצה לשלוח להם ווטסאפ?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _MatchWhatsAppActionTile(
                  title: 'פתיחת שיחת ווטסאפ עם הבחור',
                  person: people.male,
                  onTap: () => _openWhatsAppFromPrompt(
                    dialogContext,
                    people.male,
                    'אין מספר טלפון תקין לבחור',
                  ),
                ),
                _MatchWhatsAppActionTile(
                  title: 'פתיחת שיחת ווטסאפ עם הבחורה',
                  person: people.female,
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

  Future<void> _changeHandler(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
    CurrentHandler handler,
  ) async {
    final String? handlerName = handler == CurrentHandler.thirdParty
        ? ((match.handlerName ?? '').trim().isEmpty
              ? null
              : match.handlerName!.trim())
        : null;

    await repository.updateHandler(match.id, handler, handlerName: handlerName);
  }

  Future<void> _saveThirdPartyName(
    BuildContext context,
    MatchRepository repository,
    MatchIdea match,
    String value,
  ) async {
    final String? normalized = value.trim().isEmpty ? null : value.trim();
    if ((match.handlerName ?? '') == (normalized ?? '')) {
      return;
    }

    await repository.updateHandler(
      match.id,
      CurrentHandler.thirdParty,
      handlerName: normalized,
    );
  }

  String _reminderSubtitle(MatchIdea match) {
    final DateTime? reminderDate = match.reminderDate;
    if (reminderDate == null) {
      return 'אפשר להוסיף תזכורת מתוך ההצעה עצמה';
    }

    final String dateText = AppDateUtils.formatDateShort(reminderDate);
    final String? note = match.reminderNote?.trim();
    if (note == null || note.isEmpty) {
      return dateText;
    }

    return '$dateText · $note';
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

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.personId});

  final Person? person;
  final String personId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> details = <String>[
      if (person?.age != null) 'גיל ${person!.age}',
      if (person?.religiousLevel != null) person!.religiousLevel!.displayName,
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            if (person != null)
              PersonAvatar(person: person!, radius: 28)
            else
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.person_off_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              person?.fullName.trim().isNotEmpty == true
                  ? person!.fullName.trim()
                  : 'אדם נמחק',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (details.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
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
            const SizedBox(height: 8),
            TextButton(
              onPressed: person == null
                  ? null
                  : () => context.push('/people/$personId'),
              child: const Text('צפה בכרטיס'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchWhatsAppActionTile extends StatelessWidget {
  const _MatchWhatsAppActionTile({
    required this.title,
    required this.person,
    required this.onTap,
  });

  final String title;
  final Person? person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Person? currentPerson = person;
    final bool canOpen =
        currentPerson != null &&
        WhatsAppUtils.buildChatUri(currentPerson) != null;
    final String subtitle = currentPerson == null
        ? 'איש הקשר חסר'
        : canOpen
        ? currentPerson.fullName.trim()
        : 'אין מספר טלפון תקין';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: canOpen,
      leading: const Icon(Icons.chat_outlined),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new),
      onTap: canOpen ? onTap : null,
    );
  }
}

class _LargeStatusChip extends StatelessWidget {
  const _LargeStatusChip({required this.status});

  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.statusBackgroundColor(status.name),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${status.icon} ${status.displayName}',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: AppColors.statusColor(status.name),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NotesTimeline extends StatelessWidget {
  const _NotesTimeline({required this.notes, required this.dateFormat});

  final List<MatchNote> notes;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'אין הערות עדיין',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Stack(
      children: <Widget>[
        PositionedDirectional(
          top: 0,
          bottom: 0,
          start: 5,
          child: Container(
            width: 2,
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
        ),
        Column(
          children: notes.map((MatchNote note) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (note.isAutomatic)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      note.text,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontStyle: FontStyle.italic,
                                          ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                note.text,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            const SizedBox(height: 8),
                            Text(
                              dateFormat.format(note.createdAt),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
