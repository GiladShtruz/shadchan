import 'dart:async';
import 'dart:io';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/match_preferences.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/religious_level_picker.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/screens/person_extended_edit_screen.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/details_message_dialog.dart';
import 'package:shadchan/dialogs/person_card_viewer.dart';
import 'package:shadchan/dialogs/home_board_actions.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';
import 'package:shadchan/widgets/person_photo_carousel.dart';
import 'package:shadchan/widgets/section_header.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/gender_text.dart';

/// Opens the "התאמות" view for a person from anywhere in the app — the heart on
/// a row in המאגר שלי lands on exactly the same screen the profile's own
/// התאמות button opens, so there is only one matches experience to learn.
Future<void> openSuggestionsFor(BuildContext context, String personId) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => _SuggestionsPage(personId: personId),
    ),
  );
}

/// Opens the extended card editor ("עריכה מורחבת") for a person.
///
/// Reachable from the profile's own menu and from the add-friends flow, where
/// choosing "לעדכון פרטים מלאים" continues straight into the full card instead
/// of settling for the four quick fields.
Future<void> openExtendedPersonEditor(
  BuildContext context,
  String personId, {
  bool isNewFriend = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => PersonExtendedEditScreen(
        personId: personId,
        isNewFriend: isNewFriend,
      ),
    ),
  );
}

/// The same view, raised as a sheet over the list it was opened from.
///
/// From המאגר שלי the matchmaker is running down a list of people and dipping
/// into one person's matches; a full page push makes that a departure and a
/// return. As a sheet, closing it puts the list back exactly where it was.
Future<void> openSuggestionsSheet(BuildContext context, String personId) {
  final ThemeData theme = Theme.of(context);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: _profileCanvasColor(theme),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (BuildContext sheetContext) {
      return SizedBox(
        // Tall enough to work in, short enough that the list underneath is
        // still visible behind it.
        height: MediaQuery.of(sheetContext).size.height * 0.9,
        child: _SuggestionsPage(personId: personId, asSheet: true),
      );
    },
  );
}

class PersonDetailScreen extends StatefulWidget {
  const PersonDetailScreen({
    super.key,
    required this.personId,
    this.initiallyEditing = false,
  });

  final String personId;
  final bool initiallyEditing;

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  /// Whether the profile header was scrolled away, so the AppBar shows a
  /// compact bar with the person's name only.
  bool _showCollapsedTitle = false;
  bool _showFullCard = false;
  bool _editingDetails = false;
  bool _editingFullCard = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    if (widget.initiallyEditing) {
      _editingDetails = true;
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    final bool collapsed =
        _scrollController.hasClients && _scrollController.offset > 150;
    if (collapsed != _showCollapsedTitle) {
      setState(() => _showCollapsedTitle = collapsed);
    }
  }

  Future<void> _openCardEditPage(BuildContext context) {
    return openExtendedPersonEditor(context, widget.personId);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final Person? person = personRepository.getById(widget.personId);
    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('פרטי איש קשר'), centerTitle: true),

        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.person_off_outlined,
                  size: 72,
                  color: colorScheme.primaryContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  'האדם לא נמצא',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/people'),
                  child: const Text('חזרה לרשימה'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final List<MatchIdea> relatedMatches = matchRepository.getByPersonId(
      widget.personId,
    );
    final List<MatchIdea> openMatches = relatedMatches
        .where((MatchIdea match) => !match.status.isArchived)
        .toList();
    final List<PersonNote> personNotes = personRepository.getNotesForPerson(
      person.id,
    );
    final List<PersonEvent> personEvents = personRepository.getEventsForPerson(
      person.id,
    );

    return Scaffold(
      backgroundColor: _profileCanvasColor(theme),
      appBar: AppBar(
        backgroundColor: _profileCanvasColor(theme),
        foregroundColor: _profileTextColor(theme),
        titleTextStyle: _profileAppBarTitleStyle(theme),
        centerTitle: true,
        // Compact bar: once the big header scrolls away, only the profile
        // name stays pinned at the top.
        title: AnimatedOpacity(
          opacity: _showCollapsedTitle ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Text(
            person.fullName.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: <Widget>[
          IconButton(
            // Straight to the share sheet with the card text and every saved
            // photo in one go. The old path handed WhatsApp a `wa.me?text=`
            // link, which can carry no images at all and drops the matchmaker
            // into WhatsApp's own compose box to send the text by hand.
            onPressed: () => ShareUtils.sharePerson(person),
            icon: const Icon(Icons.share_outlined),
            tooltip: 'שיתוף כרטיס',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) async {
              switch (value) {
                case 'extendedEdit':
                  setState(() {
                    _editingDetails = false;
                    _editingFullCard = false;
                  });
                  await _openCardEditPage(context);
                case 'board':
                  HomeBoardActions.toggle(
                    context,
                    HomeItemKind.person,
                    person.id,
                  );
                case 'shareContact':
                  await _shareInquiryContact(context, person);
                case 'whatsappContact':
                  await _openInquiryContactWhatsApp(context, person);
                case 'delete':
                  final bool shouldDelete = await _confirmDelete(
                    context,
                    person,
                  );
                  if (!shouldDelete) {
                    return;
                  }

                  await personRepository.delete(person.id);
                  if (context.mounted) {
                    // Return to the view the user came from instead of
                    // jumping to the people list.
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  }
              }
            },
            itemBuilder: (BuildContext context) {
              final bool hasContact = ShareUtils.inquiryContactText(
                person,
              ).isNotEmpty;
              return <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'extendedEdit',
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.edit_note_outlined),
                      SizedBox(width: 10),
                      Text('עריכה מורחבת'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'board',
                  height: HomeBoardActions.menuItemHeight,
                  child: HomeBoardActions.menuItemChild(
                    context,
                    HomeItemKind.person,
                    person.id,
                  ),
                ),
                if (hasContact) ...<PopupMenuEntry<String>>[
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'shareContact',
                    child: Text('שיתוף פרטי איש הקשר'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'whatsappContact',
                    child: Text('וואטסאפ לאיש הקשר'),
                  ),
                ],
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('מחיקת כרטיס'),
                ),
              ];
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 20),
          children: <Widget>[
            _ProfileSummaryHeader(
              person: person,
              editing: _editingDetails,
              onAvatarTap: () => PersonCardViewer.open(context, person.id),
              onStatusChanged: (ProfileStatus status) =>
                  _changeProfileStatus(context, person, status),
              onEdit: () {
                setState(() {
                  _editingDetails = true;
                  _editingFullCard = false;
                });
              },
              onEditingDone: () => setState(() => _editingDetails = false),
            ),
            _ProfileInlineActions(
              whatsappLabel: _firstNameOr(person, 'WhatsApp'),
              onWhatsApp: () => _openWhatsAppMessage(context, person),
              onMatches: () => _openSuggestions(context, person),
              onAddProposal: () => _openAddProposal(context, person),
            ),
            _WhatsAppCardSection(
              person: person,
              editing: _editingFullCard,
              expanded: _showFullCard,
              onToggleFull: () {
                setState(() => _showFullCard = !_showFullCard);
              },
              onRequestDetails: () => _requestDetails(context, person),
              onEditMessage: () => _editDetailsMessage(context, person),
              onEditCard: () {
                setState(() {
                  _editingFullCard = true;
                  _editingDetails = false;
                });
              },
              onEditingDone: () => setState(() => _editingFullCard = false),
            ),
            _ProposalContactsCard(person: person),
            _PersonalNotesCard(
              person: person,
              notes: personNotes,
              onShowAll: () => _openPersonNotes(context, person),
            ),
            _OpenProposalsSection(
              person: person,
              openMatches: openMatches,
              personRepository: personRepository,
            ),
            _HistorySection(
              events: personEvents,
              onShowAll: () => _openPersonHistory(context, person),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPersonHistory(BuildContext context, Person person) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            _PersonHistoryPage(personId: person.id),
      ),
    );
  }

  Future<void> _openSuggestions(BuildContext context, Person person) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            _SuggestionsPage(personId: person.id),
      ),
    );
  }

  /// Changes the global profile status. Busy and break statuses immediately
  /// offer a compact "check again" reminder; returning to an active status
  /// clears the person's reminder in the repository.
  Future<void> _changeProfileStatus(
    BuildContext context,
    Person person,
    ProfileStatus status,
  ) async {
    final PersonRepository personRepository = context.read<PersonRepository>();
    await personRepository.updateProfileStatus(person.id, status);

    if (!status.pausesMatches) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    final ReminderChoice? choice = await ReminderPickerSheet.show(
      context,
      title: 'מתי להזכיר לך לבדוק שוב?',
      allowSkip: true,
      recommendedLabel: 'עוד חודש',
      intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
    );

    final DateTime? date = choice?.date;
    if (date != null) {
      await personRepository.setPersonReminder(person.id, date);
    }
  }

  /// Opens WhatsApp with the request-details message pre-filled, and records
  /// the outreach on the person's "last updated" stamp.
  Future<void> _requestDetails(BuildContext context, Person person) async {
    if (PhoneUtils.toWhatsAppNumber(person.phone) == null) {
      _showSnackBar(context, 'אין מספר טלפון תקין לאיש הקשר');
      return;
    }

    final PersonRepository personRepository = context.read<PersonRepository>();
    // Persist while the Flutter route is still fully active. Updating the
    // provider after returning from an external-app transition could rebuild
    // the root Navigator while its overlay was being deactivated.
    await personRepository.touch(person.id);
    if (!context.mounted) {
      return;
    }

    final bool launched = await WhatsAppUtils.openDetailsRequest(person);
    if (!launched && context.mounted) {
      _showSnackBar(context, 'לא הצלחנו לפתוח את WhatsApp');
    }
  }

  /// A small editor for the fixed request-details wording. Saving overrides the
  /// gendered default for everyone; clearing restores the default.
  Future<void> _editDetailsMessage(BuildContext context, Person person) async {
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => DetailsMessageDialog(
        initialMessage: WhatsAppUtils.currentDetailsRequestMessage(
          person.gender,
        ),
        showReset: WhatsAppUtils.hasCustomDetailsRequestMessage(),
      ),
    );

    if (result == null) {
      return;
    }
    if (result == '__reset__') {
      await WhatsAppUtils.resetDetailsRequestMessage();
      return;
    }
    if (result.isNotEmpty) {
      await WhatsAppUtils.saveDetailsRequestMessage(result);
    }
  }

  Future<void> _openPersonNotes(BuildContext context, Person person) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return _PersonNotesPage(personId: person.id);
        },
      ),
    );
  }

  /// Opens a new idea for this person, either against someone already in the
  /// database or against a name that is not.
  Future<void> _openAddProposal(BuildContext context, Person person) async {
    final String? pick = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('הוספת הצעה'),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text('הוספת הצעה עם מועמד מתוך המאגר שלי'),
                onTap: () => Navigator.of(dialogContext).pop('database'),
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1),
                title: const Text('הוספת הצעה עם מועמד מחוץ למאגר שלי'),
                onTap: () => Navigator.of(dialogContext).pop('outside'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
          ],
        );
      },
    );

    if (pick == null || !context.mounted) {
      return;
    }

    context.push('/matches/add?preSelectedPersonId=${person.id}&pick=$pick');
  }

  /// Shares the contact's name and phone on their own, separately from the
  /// candidate's card.
  Future<void> _shareInquiryContact(BuildContext context, Person person) async {
    try {
      final bool shared = await ShareUtils.shareInquiryContact(person);
      if (!shared && context.mounted) {
        _showSnackBar(context, 'אין איש קשר לשיתוף');
      }
    } catch (_) {
      if (context.mounted) {
        _showSnackBar(context, 'לא ניתן לשתף כרגע');
      }
    }
  }

  Future<void> _openInquiryContactWhatsApp(
    BuildContext context,
    Person person,
  ) async {
    final bool launched = await WhatsAppUtils.openChatWithPhone(
      person.inquiryContactPhone,
    );
    if (!launched && context.mounted) {
      _showSnackBar(context, 'אין מספר טלפון תקין לאיש הקשר');
    }
  }

  Future<void> _openWhatsAppMessage(BuildContext context, Person person) async {
    if (PhoneUtils.toWhatsAppNumber(person.phone) == null) {
      _showSnackBar(context, 'אין מספר טלפון תקין לאיש הקשר');
      return;
    }

    final PersonRepository personRepository = context.read<PersonRepository>();
    final bool launched = await WhatsAppUtils.openChat(person);
    if (launched) {
      await personRepository.touch(person.id);
    } else if (context.mounted) {
      _showSnackBar(context, 'לא הצלחנו לפתוח את וואטסאפ');
    }
  }

  Future<bool> _confirmDelete(BuildContext context, Person person) async {
    final MatchRepository matchRepository = context.read<MatchRepository>();
    final int activeMatches = matchRepository
        .getByPersonId(person.id)
        .where((MatchIdea match) => !match.status.isArchived)
        .length;
    final String warning = activeMatches > 0
        ? '\n\nלאדם זה יש $activeMatches הצעות פעילות. ההצעות לא יימחקו.'
        : '';

    return ConfirmDialog.show(
      context,
      title: 'למחוק את האיש קשר?',
      message: 'האם למחוק את ${person.fullName.trim()}?$warning',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

const Color _profileCanvasLight = AppColors.background;
const Color _profileSurfaceLight = AppColors.surface;
const Color _profileSurfaceWarmLight = AppColors.secondaryLight;
const Color _profileBlushLight = AppColors.softPink;
const Color _profileGoldLight = AppColors.primaryLight;
const Color _profileTextLight = AppColors.onSurface;
const Color _profileMutedLight = AppColors.onSurfaceVariant;
const Color _profileGoldTextLight = AppColors.primaryDark;

Color _profileCanvasColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.scaffoldBackgroundColor
      : _profileCanvasLight;
}

Color _profileSurfaceColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.surface
      : _profileSurfaceLight;
}

Color _profileWarmSurfaceColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainerHighest
      : _profileSurfaceWarmLight;
}

Color _profileTextColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.onSurface
      : _profileTextLight;
}

/// The title style for the profile's own app bars.
///
/// The app-wide [AppBarTheme] bakes the banner's cream text colour straight
/// into `titleTextStyle`, and that wins over an `AppBar.foregroundColor` — so a
/// bar sitting on the cream canvas has to state the dark title colour itself,
/// or the title reads cream on cream.
TextStyle? _profileAppBarTitleStyle(ThemeData theme) {
  final TextStyle? style =
      theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge;
  return style?.copyWith(color: _profileTextColor(theme));
}

Color _profileMutedColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.onSurfaceVariant
      : _profileMutedLight;
}

List<BoxShadow> _profileSoftShadow(ThemeData theme) {
  if (theme.brightness == Brightness.dark) {
    return const <BoxShadow>[];
  }

  return <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.07),
      blurRadius: 28,
      offset: const Offset(0, 14),
    ),
  ];
}

class _ProfileSummaryHeader extends StatefulWidget {
  const _ProfileSummaryHeader({
    required this.person,
    required this.editing,
    required this.onAvatarTap,
    required this.onStatusChanged,
    required this.onEdit,
    required this.onEditingDone,
  });

  final Person person;
  final bool editing;
  final VoidCallback onAvatarTap;
  final ValueChanged<ProfileStatus> onStatusChanged;
  final VoidCallback onEdit;
  final VoidCallback onEditingDone;

  @override
  State<_ProfileSummaryHeader> createState() => _ProfileSummaryHeaderState();
}

class _ProfileSummaryHeaderState extends State<_ProfileSummaryHeader> {
  late final TextEditingController _nameController = TextEditingController();
  late final TextEditingController _ageController = TextEditingController();
  ReligiousLevel? _religiousLevel;
  String? _religiousLevelOther;
  List<String> _photoPaths = <String>[];
  final Set<String> _newPhotoPaths = <String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _resetDraft();
  }

  @override
  void didUpdateWidget(covariant _ProfileSummaryHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.person.id != widget.person.id ||
        (!oldWidget.editing && widget.editing)) {
      _resetDraft();
    } else if (oldWidget.editing && !widget.editing) {
      _discardNewPhotos();
    }
  }

  @override
  void dispose() {
    _discardNewPhotos();
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _resetDraft() {
    _discardNewPhotos();
    _nameController.text = widget.person.fullName;
    _ageController.text = widget.person.age?.toString() ?? '';
    _religiousLevel = widget.person.religiousLevel;
    _religiousLevelOther = widget.person.religiousLevelOther;
    _photoPaths = List<String>.from(widget.person.photosPaths);
  }

  void _discardNewPhotos() {
    if (_newPhotoPaths.isEmpty) {
      return;
    }
    PhotoPickerService.deletePhotoFiles(_newPhotoPaths);
    _newPhotoPaths.clear();
  }

  Future<void> _pickPrimaryPhoto() async {
    final String? path = await PhotoPickerService.pickSinglePhoto(
      context,
      namePrefix: widget.person.id,
    );
    if (path == null || !mounted) {
      return;
    }
    _discardNewPhotos();
    setState(() {
      _newPhotoPaths.add(path);
      _photoPaths = <String>[
        path,
        if (_photoPaths.length > 1) ..._photoPaths.skip(1),
      ];
    });
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final String fullName = _nameController.text.trim();
    if (fullName.isEmpty) {
      _showValidationMessage('יש להזין שם');
      return;
    }
    final String ageText = _ageController.text.trim();
    final int? age = ageText.isEmpty ? null : int.tryParse(ageText);
    if (ageText.isNotEmpty && (age == null || age < 10 || age > 120)) {
      _showValidationMessage('יש להזין גיל בין 10 ל-120');
      return;
    }

    setState(() => _saving = true);
    final List<String> parts = fullName
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    widget.person
      ..firstName = parts.first
      ..lastName = parts.skip(1).join(' ')
      ..setManualAge(age)
      ..religiousLevel = _religiousLevel
      ..religiousLevelOther = _religiousLevelOther
      ..photosPaths = List<String>.from(_photoPaths);
    await context.read<PersonRepository>().update(widget.person);
    _newPhotoPaths.clear();
    if (mounted) {
      setState(() => _saving = false);
      widget.onEditingDone();
    }
  }

  void _showValidationMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _cancel() {
    _resetDraft();
    widget.onEditingDone();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String summary = _personSummary(widget.person);
    final ReligiousLevelsProvider levelsProvider = context
        .watch<ReligiousLevelsProvider>();
    final List<ReligiousLevelChoice> religiousChoices = <ReligiousLevelChoice>[
      for (final ReligiousLevel level in levelsProvider.enabledLevels)
        ReligiousLevelChoice(level),
      for (final String label in levelsProvider.customLabels)
        ReligiousLevelChoice(ReligiousLevel.other, label),
    ];
    if (_religiousLevel != null &&
        !religiousChoices.any(
          (ReligiousLevelChoice choice) =>
              choice.level == _religiousLevel &&
              choice.customLabel == _religiousLevelOther,
        )) {
      religiousChoices.insert(
        0,
        ReligiousLevelChoice(_religiousLevel, _religiousLevelOther),
      );
    }
    final Person shownPerson = widget.editing
        ? widget.person.copyWith(photosPaths: _photoPaths)
        : widget.person;
    final String religiousLabel = _religiousLevel == ReligiousLevel.other
        ? (_religiousLevelOther ?? ReligiousLevel.other.displayName)
        : _religiousLevel?.displayName ?? 'סגנון דתי';

    return Material(
      color: _profileCanvasColor(theme),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: _profileSurfaceColor(theme),
            borderRadius: BorderRadius.circular(28),
            boxShadow: _profileSoftShadow(theme),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: widget.editing
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            onPressed: _saving ? null : _cancel,
                            icon: const Icon(Icons.close, size: 20),
                            tooltip: 'ביטול עריכה מהירה',
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check, size: 20),
                            tooltip: 'שמירת עריכה מהירה',
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      )
                    : IconButton(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: 'עריכת פרטי המועמד',
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          foregroundColor: _profileMutedColor(theme),
                        ),
                      ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Stack(
                    alignment: Alignment.bottomCenter,
                    children: <Widget>[
                      GestureDetector(
                        onTap: widget.editing ? null : widget.onAvatarTap,
                        child: Hero(
                          tag: 'person-${widget.person.id}',
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: _profileWarmSurfaceColor(theme),
                              shape: BoxShape.circle,
                            ),
                            child: PersonAvatar(
                              person: shownPerson,
                              radius: 54,
                            ),
                          ),
                        ),
                      ),
                      if (widget.editing)
                        Positioned(
                          bottom: 5,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.38),
                            shape: const CircleBorder(),
                            child: IconButton(
                              onPressed: _saving ? null : _pickPrimaryPhoto,
                              icon: const Icon(Icons.add, color: Colors.white),
                              tooltip: 'החלפת תמונת הפרופיל',
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.editing)
                TextField(
                  key: ValueKey<String>('quick-name-${widget.person.id}'),
                  controller: _nameController,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.words,
                  minLines: 1,
                  maxLines: 2,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: _profileTextColor(theme),
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: UnderlineInputBorder(),
                    focusedBorder: UnderlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                )
              else
                Text(
                  widget.person.fullName.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: _profileTextColor(theme),
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              const SizedBox(height: 6),
              if (widget.editing)
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'גיל',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _profileMutedColor(theme),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 42,
                          child: TextField(
                            key: ValueKey<String>(
                              'quick-age-${widget.person.id}',
                            ),
                            controller: _ageController,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _profileMutedColor(theme),
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: UnderlineInputBorder(),
                              focusedBorder: UnderlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(vertical: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '·',
                      style: TextStyle(color: _profileMutedColor(theme)),
                    ),
                    PopupMenuButton<ReligiousLevelChoice>(
                      tooltip: 'בחירת סגנון דתי',
                      onSelected: (ReligiousLevelChoice choice) {
                        setState(() {
                          _religiousLevel = choice.level;
                          _religiousLevelOther = choice.customLabel;
                        });
                      },
                      itemBuilder: (BuildContext context) =>
                          religiousChoices.map((ReligiousLevelChoice choice) {
                            final String label =
                                choice.level == ReligiousLevel.other
                                ? (choice.customLabel ??
                                      ReligiousLevel.other.displayName)
                                : choice.level?.displayName ?? '';
                            return PopupMenuItem<ReligiousLevelChoice>(
                              value: choice,
                              child: Text(label),
                            );
                          }).toList(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              religiousLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: _profileMutedColor(theme),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.expand_more,
                              size: 18,
                              color: _profileMutedColor(theme),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if ((widget.person.city ?? '')
                        .trim()
                        .isNotEmpty) ...<Widget>[
                      Text(
                        '·',
                        style: TextStyle(color: _profileMutedColor(theme)),
                      ),
                      Text(
                        widget.person.city!.trim(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _profileMutedColor(theme),
                        ),
                      ),
                    ],
                  ],
                )
              else
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _profileMutedColor(theme),
                  ),
                ),
              const SizedBox(height: 12),
              _ProfileStatusSwitcher(
                status: widget.person.profileStatus,
                onStatusChanged: widget.onStatusChanged,
              ),
              const SizedBox(height: 10),
              Text(
                _relativeUpdatedLabel(widget.person.updatedAt),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _profileMutedColor(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The profile's three primary actions, placed in the scrolling content so the
/// app-level bottom navigation remains the only persistent bottom bar.
class _ProfileInlineActions extends StatelessWidget {
  const _ProfileInlineActions({
    required this.whatsappLabel,
    required this.onWhatsApp,
    required this.onMatches,
    required this.onAddProposal,
  });

  final String whatsappLabel;
  final VoidCallback onWhatsApp;
  final VoidCallback onMatches;
  final VoidCallback onAddProposal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ProfileActionButton(
              icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 21),
              label: whatsappLabel,
              onPressed: onWhatsApp,
              foregroundColor: _whatsappGreen,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ProfileActionButton(
              icon: const Icon(Icons.group_outlined, size: 22),
              label: 'התאמות',
              onPressed: onMatches,
              emphasized: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ProfileActionButton(
              icon: const Icon(Icons.favorite_border, size: 20),
              label: 'לפתיחת הצעה',
              onPressed: onAddProposal,
              subtle: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.foregroundColor,
    this.emphasized = false,
    this.subtle = false,
  });

  final Widget icon;
  final String label;
  final VoidCallback onPressed;
  final Color? foregroundColor;
  final bool emphasized;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = emphasized
        ? theme.colorScheme.onPrimaryContainer
        : foregroundColor ?? _profileTextColor(theme);

    return Material(
      color: emphasized
          ? theme.colorScheme.primaryContainer
          : subtle
          ? Colors.transparent
          : _profileSurfaceColor(theme),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 74),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: emphasized
                  ? theme.colorScheme.primary.withValues(alpha: 0.18)
                  : _profileMutedColor(
                      theme,
                    ).withValues(alpha: subtle ? 0.18 : 0.12),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconTheme(
                data: IconThemeData(color: color),
                child: icon,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: emphasized || foregroundColor == null
                      ? color
                      : _profileTextColor(theme),
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The prominent, inline "הערות אישיות" card on the profile page. Each note is
/// its own item; the matchmaker can add one inline, tap an item to edit or
/// delete it, and open the full journal with "הצג הכל". A short preview keeps
/// the section from taking over the page.
/// The people a proposal for this candidate can be passed through.
///
/// Drawn only when there is one. A matchmaker who is not in direct touch with a
/// candidate reaches them through a mutual friend, and the whole point of
/// recording that person is being able to write to them from here — so the
/// WhatsApp link sits on the row rather than two taps deep in a menu.
class _ProposalContactsCard extends StatelessWidget {
  const _ProposalContactsCard({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MatchContact> contacts = person.proposalContacts
        .where(
          (MatchContact contact) =>
              contact.name.trim().isNotEmpty || contact.phone.trim().isNotEmpty,
        )
        .toList();
    if (contacts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        decoration: BoxDecoration(
          color: _profileSurfaceColor(theme),
          borderRadius: BorderRadius.circular(20),
          boxShadow: _profileSoftShadow(theme),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'איש קשר להעברת הצעות',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: _profileTextColor(theme),
              ),
            ),
            const SizedBox(height: 4),
            for (final MatchContact contact in contacts)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      <String>[
                        contact.name.trim(),
                        contact.phone.trim(),
                      ].where((String part) => part.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _profileTextColor(theme),
                      ),
                    ),
                  ),
                  if (PhoneUtils.toWhatsAppNumber(contact.phone) != null)
                    IconButton(
                      tooltip: 'WhatsApp עם ${contact.name.trim()}',
                      onPressed: () =>
                          WhatsAppUtils.openChatWithPhone(contact.phone),
                      icon: const FaIcon(
                        FontAwesomeIcons.whatsapp,
                        size: 18,
                        color: Color(0xFF25D366),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PersonalNotesCard extends StatelessWidget {
  const _PersonalNotesCard({
    required this.person,
    required this.notes,
    required this.onShowAll,
  });

  final Person person;
  final List<PersonNote> notes;
  final VoidCallback onShowAll;

  static const int _previewCount = 5;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = _profileMutedColor(theme);
    final List<_PersonNoteEntry> entries = _entries();
    final List<_PersonNoteEntry> preview = entries.take(_previewCount).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: _profileSurfaceColor(theme),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: muted.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'הערות אישיות',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: _profileTextColor(theme),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (entries.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? theme.colorScheme.surfaceContainerHighest
                          : _profileBlushLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      entries.length.toString(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.brightness == Brightness.dark
                            ? theme.colorScheme.onSurfaceVariant
                            : AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'הוספת הערה',
                  visualDensity: VisualDensity.compact,
                  color: muted,
                  onPressed: () => _addNote(context),
                ),
              ],
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
                child: Text(
                  'רק לעיניך — עדיין אין הערות. {הוסף|הוסיפי} משהו {שתרצה|שתרצי} לזכור.'
                      .forGender(context.userGender),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              )
            else
              for (final _PersonNoteEntry entry in preview)
                _NotePreviewRow(
                  entry: entry,
                  onTap: () => _editNote(context, entry),
                ),
            if (entries.length > _previewCount)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onShowAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('הצגת הכל (${entries.length})'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_PersonNoteEntry> _entries() {
    final List<_PersonNoteEntry> entries = notes.map((PersonNote note) {
      return _PersonNoteEntry(
        noteId: note.id,
        text: note.text,
        createdAt: note.createdAt,
        isAutomatic: note.isAutomatic,
      );
    }).toList();

    final String legacyNotes = (person.notes ?? '').trim();
    if (legacyNotes.isNotEmpty) {
      entries.add(
        _PersonNoteEntry(
          noteId: null,
          text: legacyNotes,
          createdAt: person.createdAt,
          isAutomatic: false,
        ),
      );
    }

    // Newest first for the preview.
    entries.sort(
      (_PersonNoteEntry a, _PersonNoteEntry b) =>
          b.createdAt.compareTo(a.createdAt),
    );
    return entries;
  }

  Future<void> _addNote(BuildContext context) async {
    final PersonRepository repository = context.read<PersonRepository>();
    final String? text = await _promptNoteText(context, title: 'הוספת הערה');
    final String trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) {
      return;
    }
    await repository.addNote(person.id, trimmed);
  }

  Future<void> _editNote(BuildContext context, _PersonNoteEntry entry) async {
    if (entry.isAutomatic) {
      // Automatic notes are a log line, not something the user hand-edits.
      return;
    }
    final PersonRepository repository = context.read<PersonRepository>();
    final _NoteEditResult? result = await showDialog<_NoteEditResult>(
      context: context,
      builder: (BuildContext dialogContext) {
        final TextEditingController controller = TextEditingController(
          text: entry.text,
        );
        return AlertDialog(
          title: const Text('עריכת הערה'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(const _NoteEditResult.delete()),
              child: Text(
                'מחיקה',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_NoteEditResult.save(controller.text.trim())),
              child: const Text('שמירה'),
            ),
          ],
        );
      },
    );

    if (result == null) {
      return;
    }

    if (result.delete) {
      if (entry.noteId != null) {
        await repository.deleteNote(entry.noteId!);
      } else {
        person.notes = null;
        await repository.update(person);
      }
      return;
    }

    final String trimmed = result.text.trim();
    if (trimmed.isEmpty || trimmed == entry.text) {
      return;
    }
    if (entry.noteId != null) {
      await repository.updateNote(entry.noteId!, trimmed);
    } else {
      person.notes = trimmed;
      await repository.update(person);
    }
  }

  Future<String?> _promptNoteText(
    BuildContext context, {
    required String title,
  }) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        final TextEditingController controller = TextEditingController();
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'משהו שתרצה לזכור...'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('הוספה'),
            ),
          ],
        );
      },
    );
  }
}

/// Result of the inline note editor: either a saved text or a delete request.
class _NoteEditResult {
  const _NoteEditResult.save(this.text) : delete = false;
  const _NoteEditResult.delete() : text = '', delete = true;

  final String text;
  final bool delete;
}

/// A single compact note item in the inline preview.
class _NotePreviewRow extends StatelessWidget {
  const _NotePreviewRow({required this.entry, required this.onTap});

  final _PersonNoteEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = _profileMutedColor(theme);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Icon(
                entry.isAutomatic ? Icons.auto_awesome_outlined : Icons.circle,
                size: entry.isAutomatic ? 14 : 7,
                color: muted,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: entry.isAutomatic ? muted : _profileTextColor(theme),
                  fontStyle: entry.isAutomatic
                      ? FontStyle.italic
                      : FontStyle.normal,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStatusSwitcher extends StatefulWidget {
  const _ProfileStatusSwitcher({
    required this.status,
    required this.onStatusChanged,
  });

  final ProfileStatus status;
  final ValueChanged<ProfileStatus> onStatusChanged;

  @override
  State<_ProfileStatusSwitcher> createState() => _ProfileStatusSwitcherState();
}

class _ProfileStatusSwitcherState extends State<_ProfileStatusSwitcher> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ProfileStatusSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor = AppColors.profileStatusColor(widget.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ProfileStatusTag(status: widget.status),
                const SizedBox(width: 3),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 17,
                  color: statusColor,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: ProfileStatus.values
                  .where((ProfileStatus status) => status != widget.status)
                  .map((ProfileStatus status) {
                    return InkWell(
                      onTap: () => widget.onStatusChanged(status),
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: ProfileStatusTag(status: status),
                      ),
                    );
                  })
                  .toList(),
            ),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 160),
        ),
      ],
    );
  }
}

/// Inline preview of the person's send-card. Its quick edit mode keeps this
/// exact surface in place and swaps only the text for an editor.
class _WhatsAppCardSection extends StatefulWidget {
  const _WhatsAppCardSection({
    required this.person,
    required this.editing,
    required this.expanded,
    required this.onToggleFull,
    required this.onRequestDetails,
    required this.onEditMessage,
    required this.onEditCard,
    required this.onEditingDone,
  });

  final Person person;
  final bool editing;
  final bool expanded;
  final VoidCallback onToggleFull;
  final VoidCallback onRequestDetails;
  final VoidCallback onEditMessage;
  final VoidCallback onEditCard;
  final VoidCallback onEditingDone;

  @override
  State<_WhatsAppCardSection> createState() => _WhatsAppCardSectionState();
}

class _WhatsAppCardSectionState extends State<_WhatsAppCardSection> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.person.description ?? '',
  );
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _WhatsAppCardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.person.id != widget.person.id ||
        (!oldWidget.editing && widget.editing)) {
      _controller.text = widget.person.description ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final String value = _controller.text.trim();
    widget.person.description = value.isEmpty ? null : value;
    await context.read<PersonRepository>().update(widget.person);
    if (mounted) {
      setState(() => _saving = false);
      widget.onEditingDone();
    }
  }

  void _cancel() {
    _controller.text = widget.person.description ?? '';
    widget.onEditingDone();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String description = (widget.person.description ?? '').trim();
    final bool hasCard = description.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: _profileSurfaceColor(theme),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _profileMutedColor(theme).withValues(alpha: 0.14),
          ),
        ),
        child: Stack(
          children: <Widget>[
            // The body owns the top of the card. Only its end-side inset is
            // reserved for the overlaid edit control, so the control never
            // consumes a row or pushes the whole card down.
            Padding(
              key: ValueKey<String>(
                'candidate-full-card-body-${widget.person.id}',
              ),
              padding: EdgeInsetsDirectional.only(
                end: widget.editing ? 80 : 38,
              ),
              child: widget.editing
                  ? TextField(
                      key: ValueKey<String>('quick-card-${widget.person.id}'),
                      controller: _controller,
                      autofocus: true,
                      minLines: 5,
                      maxLines: 14,
                      textInputAction: TextInputAction.newline,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _profileTextColor(theme),
                        height: 1.55,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'טקסט הכרטיס המלא לשיתוף',
                        alignLabelWithHint: true,
                      ),
                    )
                  : hasCard
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AnimatedCrossFade(
                          key: ValueKey<String>(
                            'candidate-full-card-text-${widget.person.id}',
                          ),
                          firstChild: Text(
                            description,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _profileTextColor(theme),
                              height: 1.5,
                            ),
                          ),
                          secondChild: Text(
                            description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _profileTextColor(theme),
                              height: 1.55,
                            ),
                          ),
                          crossFadeState: widget.expanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 180),
                          sizeCurve: Curves.easeOut,
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: widget.onToggleFull,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              widget.expanded
                                  ? 'סגירת הכרטיס המלא'
                                  : 'הצגת הכרטיס המלא',
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'אין עדיין כרטיס מלא או תמונה — רק פרטים בסיסיים.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _profileMutedColor(theme),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: widget.onRequestDetails,
                            icon: const FaIcon(
                              FontAwesomeIcons.whatsapp,
                              size: 16,
                            ),
                            label: const Text(
                              'בקש פרטים ב-WhatsApp',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _profileTextColor(theme),
                              side: BorderSide(
                                color: _profileMutedColor(
                                  theme,
                                ).withValues(alpha: 0.2),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        // A pencil beside the button reads as "edit this
                        // person's message"; it is the app-wide wording that is
                        // being changed, so it is a quiet line of its own.
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: widget.onEditMessage,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: _profileMutedColor(theme),
                              textStyle: theme.textTheme.bodySmall,
                            ),
                            child: const Text('לעריכת ההודעה'),
                          ),
                        ),
                      ],
                    ),
            ),
            PositionedDirectional(
              top: -8,
              end: -8,
              child: widget.editing
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          onPressed: _saving ? null : _cancel,
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: 'ביטול עריכת הכרטיס',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check, size: 20),
                          tooltip: 'שמירת הכרטיס',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    )
                  : IconButton(
                      onPressed: widget.onEditCard,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'עריכת טקסט הכרטיס המלא',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        foregroundColor: _profileMutedColor(theme),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The inline "הצעות פתוחות" section on the profile page: every open proposal
/// for this person, newest first, tapping a row opens the proposal.
class _OpenProposalsSection extends StatelessWidget {
  const _OpenProposalsSection({
    required this.person,
    required this.openMatches,
    required this.personRepository,
  });

  final Person person;
  final List<MatchIdea> openMatches;
  final PersonRepository personRepository;

  @override
  Widget build(BuildContext context) {
    if (openMatches.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final List<MatchIdea> ordered = List<MatchIdea>.from(openMatches)
      ..sort((MatchIdea a, MatchIdea b) => b.updatedAt.compareTo(a.updatedAt));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Text(
              'הצעות פתוחות (${ordered.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                color: _profileTextColor(theme),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _profileSurfaceColor(theme),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _profileMutedColor(theme).withValues(alpha: 0.12),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (
                  int index = 0;
                  index < ordered.length;
                  index++
                ) ...<Widget>[
                  _OpenProposalRow(
                    match: ordered[index],
                    otherPerson: personRepository.getById(
                      ordered[index].personAId == person.id
                          ? ordered[index].personBId
                          : ordered[index].personAId,
                    ),
                  ),
                  if (index + 1 < ordered.length)
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: _profileMutedColor(theme).withValues(alpha: 0.12),
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

/// One compact proposal row: the other side, the proposal status, and a single
/// WhatsApp shortcut for that other side.
class _OpenProposalRow extends StatelessWidget {
  const _OpenProposalRow({required this.match, required this.otherPerson});

  final MatchIdea match;
  final Person? otherPerson;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String otherName = otherPerson?.fullName.trim().isNotEmpty == true
        ? otherPerson!.fullName.trim()
        : 'אדם נמחק';
    final bool hasWhatsApp =
        PhoneUtils.toWhatsAppNumber(otherPerson?.phone) != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/matches/${match.id}'),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  otherName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: _profileTextColor(theme),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: match.status),
              const SizedBox(width: 4),
              IconButton(
                onPressed: hasWhatsApp && otherPerson != null
                    ? () => _openWhatsApp(context, otherPerson!)
                    : null,
                icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 18),
                tooltip: 'WhatsApp עם $otherName',
                color: _whatsappGreen,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(BuildContext context, Person target) async {
    final bool launched = await WhatsAppUtils.openChat(target);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('אין מספר טלפון תקין לפתיחת וואטסאפ')),
        );
    }
  }
}

/// The large "match preview" overlay opened by tapping a candidate: the person
/// we are matching for on top, the candidate below, each with its own scrolling
/// card, and a single "פתח רעיון" action. It floats over the matches list, so
/// closing returns to exactly the same scroll position. Returns true when the
/// user chose to open an idea.
/// The two-cards-facing-each-other comparison.
///
/// One shared view wherever two people are being weighed against each other:
/// from התאמות, from the automatic pair suggestions and from an open proposal.
/// Each half holds its own photos, summary and full send-card text and scrolls
/// on its own inside its half of the screen, so neither card pushes the other
/// off. Returns true when the matchmaker asked to open a proposal from here.
///
/// [showOpenIdeaAction] is false when the proposal already exists — there the
/// view is only a comparison, and closing it returns to the proposal.
Future<bool?> openMatchComparison(
  BuildContext context, {
  required Person source,
  required Person candidate,
  bool showOpenIdeaAction = true,
}) {
  return _MatchPreviewSheet.show(
    context,
    source: source,
    candidate: candidate,
    showOpenIdeaAction: showOpenIdeaAction,
  );
}

abstract final class _MatchPreviewSheet {
  static Future<bool?> show(
    BuildContext context, {
    required Person source,
    required Person candidate,
    bool showOpenIdeaAction = true,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          clipBehavior: Clip.antiAlias,
          backgroundColor: _profileSurfaceColor(theme),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.86,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 0),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          showOpenIdeaAction ? 'רעיון להצעה' : 'השוואת כרטיסים',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: _profileTextColor(theme),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'סגירה',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _MatchPreviewHalf(person: source)),
                Divider(
                  height: 1,
                  color: _profileMutedColor(theme).withValues(alpha: 0.2),
                ),
                Expanded(child: _MatchPreviewHalf(person: candidate)),
                if (showOpenIdeaAction)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          icon: const Icon(Icons.favorite_border),
                          label: const Text('פתיחת רעיון'),
                        ),
                      ),
                    ),
                  )
                else
                  const SafeArea(top: false, child: SizedBox(height: 4)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One half of the match preview: a person's photos, name, summary and their
/// full send-card text, scrolling on its own.
class _MatchPreviewHalf extends StatelessWidget {
  const _MatchPreviewHalf({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String description = (person.description ?? '').trim();
    final List<String> photos = person.photosPaths
        .where((String path) => File(path).existsSync())
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              PersonAvatar(person: person, radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      person.fullName.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _profileTextColor(theme),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _personSummary(person),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _profileMutedColor(theme),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (photos.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            // Whole photo, never cropped or stretched — this is the view where
            // the two candidates are weighed against each other, so what the
            // photo actually shows matters more than a tidy rectangle. All of
            // the person's photos are swipeable here.
            PersonPhotoCarousel(
              photosPaths: photos,
              height: 220,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(16),
              backgroundColor: _profileWarmSurfaceColor(theme),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            description.isEmpty ? 'אין עדיין כרטיס לשליחה' : description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: description.isEmpty
                  ? _profileMutedColor(theme)
                  : _profileTextColor(theme),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The full-screen "התאמות" view, opened from the profile's floating action
/// bar. It owns the suggestion filtering, ordering and accept/reject flow that
/// used to live inside the person page's tab.
class _SuggestionsPage extends StatefulWidget {
  const _SuggestionsPage({required this.personId, this.asSheet = false});

  final String personId;

  /// Raised over a list instead of pushed as a page: the canvas is the sheet's
  /// own, and the bar closes rather than goes back.
  final bool asSheet;

  @override
  State<_SuggestionsPage> createState() => _SuggestionsPageState();
}

class _SuggestionsPageState extends State<_SuggestionsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final Person? person = personRepository.getById(widget.personId);

    if (person == null) {
      return Scaffold(
        backgroundColor: widget.asSheet ? Colors.transparent : null,
        appBar: AppBar(title: const Text('התאמות'), centerTitle: true),
        body: const Center(child: Text('האדם לא נמצא')),
      );
    }

    final MatchProposalFilters? savedSuggestionFilters =
        MatchProposalFilterSheet.savedFiltersFor(person.id);
    final List<Person> matchingCandidates = personRepository
        .getAll()
        .where(
          (Person candidate) => _matchesSuggestionFilters(
            source: person,
            candidate: candidate,
            filters: savedSuggestionFilters,
          ),
        )
        .toList();
    // Order the suggestions in tiers, preserving relative order within each:
    // candidates that already have an open/בהמתנה proposal with this person
    // come first, then the remaining active suggestions, then candidates the
    // user soft-dismissed (לא מתאים — pushed to the end of the list), and
    // finally candidates whose opened proposal was rejected.
    final Set<String> dismissedIds = SuggestionDismissals.dismissedFor(
      person.id,
    );
    final List<Person> prioritizedSuggestions = <Person>[];
    final List<Person> activeSuggestions = <Person>[];
    final List<Person> dismissedSuggestions = <Person>[];
    final List<Person> rejectedSuggestions = <Person>[];
    for (final Person candidate in matchingCandidates) {
      final MatchIdea? existingMatch = matchRepository.findExisting(
        person.id,
        candidate.id,
      );
      final MatchStatus? existingStatus = existingMatch?.status;
      if (existingStatus == MatchStatus.rejected) {
        rejectedSuggestions.add(candidate);
      } else if (existingStatus == MatchStatus.idea ||
          existingStatus == MatchStatus.checking ||
          existingStatus == MatchStatus.unavailable) {
        prioritizedSuggestions.add(candidate);
      } else if (dismissedIds.contains(candidate.id)) {
        dismissedSuggestions.add(candidate);
      } else {
        activeSuggestions.add(candidate);
      }
    }
    // Within each tier, candidates that pause matches (תפוס/בהפסקה) drop after
    // the available ones — and inside each of those two groups the ones whose
    // card changed most recently come first, so a candidate the matchmaker has
    // just updated in the app is the first one they are offered.
    List<Person> byRecency(Iterable<Person> people) =>
        people.toList()
          ..sort((Person a, Person b) => b.updatedAt.compareTo(a.updatedAt));
    List<Person> availableFirst(List<Person> people) => <Person>[
      ...byRecency(people.where((Person p) => !p.profileStatus.pausesMatches)),
      ...byRecency(people.where((Person p) => p.profileStatus.pausesMatches)),
    ];
    final List<Person> suggestedPeople = <Person>[
      ...availableFirst(prioritizedSuggestions),
      ...availableFirst(activeSuggestions),
      ...availableFirst(dismissedSuggestions),
      ...availableFirst(rejectedSuggestions),
    ];

    final String query = _query.trim().toLowerCase();
    final bool searching = query.isNotEmpty;
    // Manual search covers the whole database — including people the automatic
    // filter left out — restricted to the opposite gender so the pairing stays
    // valid.
    final Gender? targetGender = switch (person.gender) {
      Gender.male => Gender.female,
      Gender.female => Gender.male,
      Gender.unknown => null,
    };
    final List<Person> searchResults = searching
        ? (personRepository.getAll()..removeWhere(
            (Person p) =>
                p.id == person.id ||
                p.hidden ||
                (targetGender != null && p.gender != targetGender) ||
                !p.fullName.toLowerCase().contains(query),
          ))
        : const <Person>[];

    return Scaffold(
      // In a sheet the canvas is already painted by the sheet itself; painting
      // it again here would hide its rounded top corners.
      backgroundColor: widget.asSheet
          ? Colors.transparent
          : _profileCanvasColor(theme),
      appBar: AppBar(
        backgroundColor: widget.asSheet
            ? Colors.transparent
            : _profileCanvasColor(theme),
        foregroundColor: _profileTextColor(theme),
        titleTextStyle: _profileAppBarTitleStyle(theme),
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: !widget.asSheet,
        leading: widget.asSheet
            ? IconButton(
                tooltip: 'סגירה',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text('התאמות · ${person.fullName.trim()}'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _SuggestionSearchField(
              controller: _searchController,
              onChanged: (String value) => setState(() => _query = value),
            ),
            Expanded(
              child: searching
                  ? _SearchResultsList(
                      results: searchResults,
                      onOpenPreview: (Person candidate) =>
                          _openMatchPreview(context, person, candidate),
                    )
                  : _SuggestedMatchesTab(
                      sourcePerson: person,
                      suggestedPeople: suggestedPeople,
                      matchRepository: matchRepository,
                      hasCustomFilters: savedSuggestionFilters != null,
                      onFilterPressed: () =>
                          _openSuggestionFilters(context, person),
                      onOpenPreview: (Person candidate) =>
                          _openMatchPreview(context, person, candidate),
                      onAccept: (Person candidate) =>
                          _acceptSuggestion(context, person, candidate),
                      onReject: (Person candidate) =>
                          _rejectSuggestion(context, person, candidate),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the large preview overlay for a candidate; if the user taps
  /// "פתח רעיון" there, opens (or jumps to) the proposal. An existing proposal
  /// skips the preview and goes straight to it.
  Future<void> _openMatchPreview(
    BuildContext context,
    Person source,
    Person candidate,
  ) async {
    final MatchRepository matchRepository = context.read<MatchRepository>();
    final MatchIdea? existing = matchRepository.findExisting(
      source.id,
      candidate.id,
    );
    if (existing != null) {
      context.push('/matches/${existing.id}');
      return;
    }

    final bool? opened = await _MatchPreviewSheet.show(
      context,
      source: source,
      candidate: candidate,
    );
    if (opened == true && context.mounted) {
      await _openSuggestedCandidate(context, source, candidate);
    }
  }

  bool _matchesSuggestionFilters({
    required Person source,
    required Person candidate,
    required MatchProposalFilters? filters,
  }) {
    if (filters == null) {
      // The matches view opens on what this candidate is looking for, taken
      // from their own card — not on a rule applied to everybody.
      return MatchSuggestionUtils.matchesOwnPreferences(
        source: source,
        candidate: candidate,
      );
    }

    if (!MatchSuggestionUtils.isEligibleCandidate(
      source: source,
      candidate: candidate,
    )) {
      return false;
    }

    final int? candidateAge = candidate.age;
    if (filters.minAge != null &&
        (candidateAge == null || candidateAge < filters.minAge!)) {
      return false;
    }
    if (filters.maxAge != null &&
        (candidateAge == null || candidateAge > filters.maxAge!)) {
      return false;
    }

    final bool hasReligiousFilter =
        filters.religiousLevels.isNotEmpty ||
        filters.religiousLevelOtherLabels.isNotEmpty;
    if (hasReligiousFilter &&
        !filters.religiousLevels.contains(candidate.religiousLevel) &&
        !(candidate.religiousLevel == ReligiousLevel.other &&
            filters.religiousLevelOtherLabels.contains(
              candidate.religiousLevelOther?.trim(),
            ))) {
      return false;
    }

    if (filters.profileStatuses.isNotEmpty &&
        !filters.profileStatuses.contains(candidate.profileStatus)) {
      return false;
    }

    return true;
  }

  Future<void> _openSuggestionFilters(
    BuildContext context,
    Person sourcePerson,
  ) async {
    if (sourcePerson.gender == Gender.unknown) {
      _showSnackBar(context, 'יש לבחור מגדר לפני סינון התאמות');
      return;
    }

    final Gender targetGender = sourcePerson.gender == Gender.male
        ? Gender.female
        : Gender.male;

    final MatchProposalFilters? filters = await MatchProposalFilterSheet.show(
      context,
      targetGender: targetGender,
      sourcePersonId: sourcePerson.id,
      initialFilters: _defaultSuggestionFilters(sourcePerson),
    );

    if (filters != null && mounted) {
      setState(() {});
    }
  }

  /// What the filter sheet opens showing: this candidate's own saved criteria,
  /// so changing them there starts from what they already say rather than from
  /// a blank sheet.
  MatchProposalFilters _defaultSuggestionFilters(Person sourcePerson) {
    final MatchPreferences preferences = MatchPreferences.forPerson(
      sourcePerson,
    );
    final ({int minAge, int maxAge})? femaleAgeRange =
        sourcePerson.gender == Gender.male
        ? MatchSuggestionUtils.femaleAgeRangeForMale(sourcePerson.age)
        : null;

    return MatchProposalFilters(
      minAge: preferences.minAge ?? femaleAgeRange?.minAge,
      maxAge: preferences.maxAge ?? femaleAgeRange?.maxAge,
      religiousLevels: preferences.religiousLevels,
      religiousLevelOtherLabels: preferences.religiousLevelOtherLabels,
      profileStatuses: const <ProfileStatus>[],
    );
  }

  Future<void> _openSuggestedCandidate(
    BuildContext context,
    Person sourcePerson,
    Person selectedPerson,
  ) async {
    final Person male = sourcePerson.gender == Gender.male
        ? sourcePerson
        : selectedPerson;
    final Person female = sourcePerson.gender == Gender.female
        ? sourcePerson
        : selectedPerson;

    final MatchRepository matchRepository = context.read<MatchRepository>();
    final MatchIdea? existingMatch = matchRepository.findExisting(
      male.id,
      female.id,
    );

    if (existingMatch != null) {
      context.push('/matches/${existingMatch.id}');
      return;
    }

    final MatchIdea? newMatch = await matchRepository.create(
      male.id,
      female.id,
    );
    if (newMatch != null && context.mounted) {
      context.push('/matches/${newMatch.id}?justCreated=true');
    }
  }

  Future<void> _acceptSuggestion(
    BuildContext context,
    Person sourcePerson,
    Person candidate,
  ) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'פתיחת הצעה',
      message:
          'האם לפתוח הצעה בין ${sourcePerson.fullName.trim()} '
          'ל${candidate.fullName.trim()}?',
      confirmText: 'פתיחה',
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    await _openSuggestedCandidate(context, sourcePerson, candidate);
  }

  Future<void> _rejectSuggestion(
    BuildContext context,
    Person sourcePerson,
    Person candidate,
  ) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'לא מתאים?',
      message: 'ההתאמה תעבור לסוף הרשימה.',
      confirmText: 'לא מתאים',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    // Soft dismissal only: the candidate drops to the end of the suggestions
    // list. No rejected proposal is created, so the pair never shows up under
    // רעיונות שנשללו.
    await SuggestionDismissals.dismiss(sourcePerson.id, candidate.id);
    if (mounted) {
      setState(() {});
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The whole-database search box atop the התאמות view.
class _SuggestionSearchField extends StatelessWidget {
  const _SuggestionSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'חיפוש בכל המאגר…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'ניקוי',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: _profileSurfaceColor(theme),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Results of the whole-database manual search — people who may not pass the
/// automatic filter. Tapping one opens the match preview overlay.
class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({
    required this.results,
    required this.onOpenPreview,
  });

  final List<Person> results;
  final ValueChanged<Person> onOpenPreview;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const _TabEmptyState(
        icon: Icons.search_off,
        title: 'לא נמצאו תוצאות',
        subtitle: 'אפשר לנסות שם אחר',
      );
    }

    final ThemeData theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final Person candidate = results[index];
        return Material(
          color: _profileSurfaceColor(theme),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () => onOpenPreview(candidate),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  PersonAvatar(person: candidate, radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          candidate.fullName.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: _profileTextColor(theme),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _personSummary(candidate),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _profileMutedColor(theme),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: _profileMutedColor(theme)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SuggestedMatchesTab extends StatelessWidget {
  const _SuggestedMatchesTab({
    required this.sourcePerson,
    required this.suggestedPeople,
    required this.matchRepository,
    required this.hasCustomFilters,
    required this.onFilterPressed,
    required this.onOpenPreview,
    required this.onAccept,
    required this.onReject,
  });

  final Person sourcePerson;
  final List<Person> suggestedPeople;
  final MatchRepository matchRepository;
  final bool hasCustomFilters;
  final VoidCallback onFilterPressed;
  final ValueChanged<Person> onOpenPreview;
  final ValueChanged<Person> onAccept;
  final ValueChanged<Person> onReject;

  @override
  Widget build(BuildContext context) {
    if (sourcePerson.gender == Gender.unknown) {
      return _SuggestionTabScaffold(
        header: _SuggestionFilterHeader(
          count: 0,
          hasCustomFilters: hasCustomFilters,
          onFilterPressed: onFilterPressed,
        ),
        child: const _TabEmptyState(
          icon: Icons.wc_outlined,
          title: 'צריך לבחור מגדר',
          subtitle: 'אחרי עדכון מגדר יוצגו התאמות אוטומטיות',
        ),
      );
    }

    if (suggestedPeople.isEmpty) {
      return _SuggestionTabScaffold(
        header: _SuggestionFilterHeader(
          count: 0,
          hasCustomFilters: hasCustomFilters,
          onFilterPressed: onFilterPressed,
        ),
        child: _TabEmptyState(
          icon: Icons.favorite_border,
          title: 'לא נמצאו התאמות',
          subtitle: hasCustomFilters
              ? 'אפשר לשנות את הסינון ולנסות שוב'
              : 'אין כרגע אנשים שעומדים בסינון האוטומטי',
        ),
      );
    }

    return Column(
      children: <Widget>[
        _SuggestionFilterHeader(
          count: suggestedPeople.length,
          hasCustomFilters: hasCustomFilters,
          onFilterPressed: onFilterPressed,
        ),
        Expanded(
          child: _SuggestedMatchesList(
            sourcePerson: sourcePerson,
            suggestedPeople: suggestedPeople,
            matchRepository: matchRepository,
            onOpenPreview: onOpenPreview,
            onAccept: onAccept,
            onReject: onReject,
          ),
        ),
      ],
    );
  }
}

class _SuggestedMatchesList extends StatefulWidget {
  const _SuggestedMatchesList({
    required this.sourcePerson,
    required this.suggestedPeople,
    required this.matchRepository,
    required this.onOpenPreview,
    required this.onAccept,
    required this.onReject,
  });

  final Person sourcePerson;
  final List<Person> suggestedPeople;
  final MatchRepository matchRepository;
  final ValueChanged<Person> onOpenPreview;
  final ValueChanged<Person> onAccept;
  final ValueChanged<Person> onReject;

  @override
  State<_SuggestedMatchesList> createState() => _SuggestedMatchesListState();
}

class _SuggestedMatchesListState extends State<_SuggestedMatchesList> {
  /// Candidates whose quick-view card is currently expanded inline.
  final Set<String> _expandedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
      itemCount: widget.suggestedPeople.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final ThemeData theme = Theme.of(context);
        final Person candidate = widget.suggestedPeople[index];
        final MatchIdea? existingMatch = widget.matchRepository.findExisting(
          widget.sourcePerson.id,
          candidate.id,
        );
        final bool hasCard = (candidate.description ?? '').trim().isNotEmpty;
        final bool expanded = _expandedIds.contains(candidate.id);

        return Material(
          color: _profileSurfaceColor(theme),
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: <Widget>[
              InkWell(
                onTap: () => existingMatch != null
                    ? context.push('/matches/${existingMatch.id}')
                    : widget.onOpenPreview(candidate),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: <Widget>[
                      GestureDetector(
                        onTap: () => context.push('/people/${candidate.id}'),
                        child: PersonAvatar(person: candidate, radius: 25),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    candidate.fullName.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: _profileTextColor(theme),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                // The card expander sits up on the name line
                                // rather than as a third round button — the
                                // action row stays "לא מתאים" and "פתיחת הצעה"
                                // only.
                                if (hasCard)
                                  _CardExpanderButton(
                                    expanded: expanded,
                                    onPressed: () {
                                      setState(() {
                                        if (!_expandedIds.remove(
                                          candidate.id,
                                        )) {
                                          _expandedIds.add(candidate.id);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _personSummary(candidate),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _profileMutedColor(theme),
                              ),
                            ),
                            if (existingMatch != null) ...<Widget>[
                              const SizedBox(height: 6),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: _StatusChip(
                                  status: existingMatch.status,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      _SuggestionIconButton(
                        icon: Icons.close,
                        tooltip: 'לא מתאים',
                        backgroundColor: theme.colorScheme.error.withValues(
                          alpha: 0.12,
                        ),
                        foregroundColor: theme.colorScheme.error,
                        onPressed: () => widget.onReject(candidate),
                      ),
                      const SizedBox(width: 8),
                      _SuggestionIconButton(
                        icon: Icons.favorite_outline,
                        tooltip: 'פתיחת הצעה',
                        backgroundColor: _profileGoldLight,
                        foregroundColor: _profileGoldTextLight,
                        onPressed: () => widget.onAccept(candidate),
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _CandidateQuickCard(candidate: candidate),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The small chevron on a suggestion's name line that opens their card inline.
/// Deliberately not one of the round action buttons: three of those in a row
/// read as a crowd, and this one is a view, not a decision.
class _CardExpanderButton extends StatelessWidget {
  const _CardExpanderButton({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Tooltip(
      message: expanded ? 'סגירת כרטיס' : 'הצגת כרטיס',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 180),
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: _profileMutedColor(theme),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline quick view of a candidate's send-card: primary photo + card text,
/// shown under the suggestion row without leaving the profile.
class _CandidateQuickCard extends StatelessWidget {
  const _CandidateQuickCard({required this.candidate});

  final Person candidate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String description = (candidate.description ?? '').trim();
    final List<String> photoPaths = candidate.photosPaths
        .where((String path) => File(path).existsSync())
        .toList(growable: false);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _profileWarmSurfaceColor(theme),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (photoPaths.isNotEmpty)
            PersonPhotoCarousel(
              photosPaths: photoPaths,
              height: 220,
              borderRadius: BorderRadius.zero,
              fit: BoxFit.contain,
              backgroundColor: _profileWarmSurfaceColor(theme),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _profileTextColor(theme),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionIconButton extends StatelessWidget {
  const _SuggestionIconButton({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: foregroundColor, size: 22),
          ),
        ),
      ),
    );
  }
}

class _SuggestionTabScaffold extends StatelessWidget {
  const _SuggestionTabScaffold({required this.header, required this.child});

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        header,
        Expanded(child: child),
      ],
    );
  }
}

class _SuggestionFilterHeader extends StatelessWidget {
  const _SuggestionFilterHeader({
    required this.count,
    required this.hasCustomFilters,
    required this.onFilterPressed,
  });

  final int count;
  final bool hasCustomFilters;
  final VoidCallback onFilterPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _profileSurfaceColor(theme),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _profileMutedColor(theme).withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                hasCustomFilters ? 'סינון אישי פעיל' : 'סינון אוטומטי',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: _profileTextColor(theme),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (count > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Text(
                  '$count תוצאות',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _profileMutedColor(theme),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: onFilterPressed,
              icon: Icon(hasCustomFilters ? Icons.tune : Icons.tune_outlined),
              label: const Text('סינון'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _profileMutedColor(theme),
                side: BorderSide(
                  color: _profileMutedColor(theme).withValues(alpha: 0.18),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabEmptyState extends StatelessWidget {
  const _TabEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Stays centered when there is room, but scrolls instead of overflowing
    // when the tab viewport is short (it lives inside a NestedScrollView body,
    // which can hand it very little height at some scroll positions).
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _profileTextColor(theme),
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _profileMutedColor(theme),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "עודכן לאחרונה לפני X ימים" — a small relative-time line under the profile
/// status. Only meaningful actions (edit, note, status change, opening/updating
/// a proposal, a WhatsApp action) bump [Person.updatedAt]; merely viewing the
/// card does not.
String _relativeUpdatedLabel(DateTime updatedAt) {
  final DateTime now = DateTime.now();
  final DateTime updatedDay = DateTime(
    updatedAt.year,
    updatedAt.month,
    updatedAt.day,
  );
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int days = today.difference(updatedDay).inDays;
  if (days <= 0) {
    return 'עודכן היום';
  }
  if (days == 1) {
    return 'עודכן אתמול';
  }
  if (days < 7) {
    return 'עודכן לפני $days ימים';
  }
  if (days < 30) {
    final int weeks = days ~/ 7;
    return weeks == 1 ? 'עודכן לפני שבוע' : 'עודכן לפני $weeks שבועות';
  }
  if (days < 365) {
    final int months = days ~/ 30;
    return months == 1 ? 'עודכן לפני חודש' : 'עודכן לפני $months חודשים';
  }
  final int years = days ~/ 365;
  return years == 1 ? 'עודכן לפני שנה' : 'עודכן לפני $years שנים';
}

/// A muted green that reads as "WhatsApp" without breaking the cream palette.
const Color _whatsappGreen = AppColors.profileAvailable;

String _firstNameOr(Person? person, String fallback) {
  final String first = person?.firstName.trim() ?? '';
  if (first.isNotEmpty) {
    return first;
  }
  final String full = person?.fullName.trim() ?? '';
  return full.isEmpty ? fallback : full;
}

String _personSummary(Person person) {
  final List<String> parts = <String>[
    if (person.age != null) 'גיל ${person.age}',
    if (person.religiousLevelLabel.isNotEmpty) person.religiousLevelLabel,
    if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
  ];
  return parts.isEmpty ? 'פרטים חסרים' : parts.join(' · ');
}

class _PersonNotesPage extends StatelessWidget {
  const _PersonNotesPage({required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context) {
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final Person? person = personRepository.getById(personId);

    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('יומן הערות'), centerTitle: true),
        body: const Center(child: Text('איש הקשר לא נמצא')),
      );
    }

    final List<PersonNote> notes = personRepository.getNotesForPerson(
      person.id,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('יומן הערות'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _PersonalNotesNotice(),
            ),
            const SizedBox(height: 16),
            _PersonNotesSection(person: person, notes: notes),
          ],
        ),
      ),
    );
  }
}

class _PersonalNotesNotice extends StatelessWidget {
  const _PersonalNotesNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.lock_outline,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ההערות כאן הן לצפייה אישית שלך בלבד.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonNotesSection extends StatefulWidget {
  const _PersonNotesSection({required this.person, required this.notes});

  final Person person;
  final List<PersonNote> notes;

  @override
  State<_PersonNotesSection> createState() => _PersonNotesSectionState();
}

class _PersonNotesSectionState extends State<_PersonNotesSection> {
  final TextEditingController _controller = TextEditingController();
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<_PersonNoteEntry> entries = _buildEntries();

    return _Section(
      title: 'יומן הערות',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(entries.length.toString()),
      ),
      child: Column(
        children: <Widget>[
          _PersonNotesTimeline(
            entries: entries,
            dateFormat: _dateFormat,
            onEdit: _editNote,
            onDelete: _deleteNote,
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'הוספת הערה...'),
                  onSubmitted: (_) => _addNote(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _canSend ? _addNote : null,
                icon: Icon(
                  Icons.send,
                  color: _canSend
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_PersonNoteEntry> _buildEntries() {
    final List<_PersonNoteEntry> entries = widget.notes.map((PersonNote note) {
      return _PersonNoteEntry(
        noteId: note.id,
        text: note.text,
        createdAt: note.createdAt,
        isAutomatic: note.isAutomatic,
      );
    }).toList();

    final String legacyNotes = (widget.person.notes ?? '').trim();
    if (legacyNotes.isNotEmpty) {
      entries.add(
        _PersonNoteEntry(
          noteId: null,
          text: legacyNotes,
          createdAt: widget.person.createdAt,
          isAutomatic: false,
        ),
      );
    }

    entries.sort(
      (_PersonNoteEntry a, _PersonNoteEntry b) =>
          a.createdAt.compareTo(b.createdAt),
    );
    return entries;
  }

  Future<void> _addNote() async {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    await context.read<PersonRepository>().addNote(widget.person.id, text);
    _controller.clear();
  }

  Future<void> _editNote(_PersonNoteEntry entry) async {
    final TextEditingController editController = TextEditingController(
      text: entry.text,
    );
    final String? newText = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('עריכת הערה'),
          content: TextField(
            controller: editController,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(editController.text),
              child: const Text('שמירה'),
            ),
          ],
        );
      },
    );
    editController.dispose();

    final String trimmed = (newText ?? '').trim();
    if (trimmed.isEmpty || trimmed == entry.text || !mounted) {
      return;
    }

    final PersonRepository repository = context.read<PersonRepository>();
    if (entry.noteId != null) {
      await repository.updateNote(entry.noteId!, trimmed);
    } else {
      widget.person.notes = trimmed;
      await repository.update(widget.person);
    }
  }

  Future<void> _deleteNote(_PersonNoteEntry entry) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'מחיקת הערה',
      message: 'למחוק את ההערה?',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    final PersonRepository repository = context.read<PersonRepository>();
    if (entry.noteId != null) {
      await repository.deleteNote(entry.noteId!);
    } else {
      widget.person.notes = null;
      await repository.update(widget.person);
    }
  }

  bool get _canSend => _controller.text.trim().isNotEmpty;

  void _handleChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _PersonNoteEntry {
  const _PersonNoteEntry({
    required this.noteId,
    required this.text,
    required this.createdAt,
    required this.isAutomatic,
  });

  /// Null for the legacy note stored directly on the person.
  final String? noteId;
  final String text;
  final DateTime createdAt;
  final bool isAutomatic;
}

class _PersonNotesTimeline extends StatelessWidget {
  const _PersonNotesTimeline({
    required this.entries,
    required this.dateFormat,
    required this.onEdit,
    required this.onDelete,
  });

  final List<_PersonNoteEntry> entries;
  final DateFormat dateFormat;
  final ValueChanged<_PersonNoteEntry> onEdit;
  final ValueChanged<_PersonNoteEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
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
          children: entries.map((_PersonNoteEntry entry) {
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
                            if (entry.isAutomatic)
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
                                      entry.text,
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
                                entry.text,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    dateFormat.format(entry.createdAt),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                SizedBox(
                                  height: 24,
                                  width: 32,
                                  child: PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    tooltip: 'פעולות הערה',
                                    icon: Icon(
                                      Icons.more_horiz,
                                      size: 18,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    onSelected: (String value) {
                                      if (value == 'edit') {
                                        onEdit(entry);
                                      } else if (value == 'delete') {
                                        onDelete(entry);
                                      }
                                    },
                                    itemBuilder: (BuildContext context) {
                                      return <PopupMenuEntry<String>>[
                                        if (!entry.isAutomatic)
                                          const PopupMenuItem<String>(
                                            value: 'edit',
                                            child: Text('עריכת הערה'),
                                          ),
                                        const PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Text('מחיקת הערה'),
                                        ),
                                      ];
                                    },
                                  ),
                                ),
                              ],
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

String _eventDateShort(DateTime date) => '${date.day}.${date.month}';

/// A small colour per event type, so the timeline reads at a glance.
Color _eventColor(PersonEventType type) {
  switch (type) {
    case PersonEventType.proposalOpened:
      return AppColors.statusIdea;
    case PersonEventType.dated:
      return AppColors.statusDating;
    case PersonEventType.rejected:
      return AppColors.statusRejected;
    case PersonEventType.statusChanged:
      return AppColors.statusUnavailable;
    case PersonEventType.note:
      return AppColors.statusChecking;
    case PersonEventType.cardChanged:
      return AppColors.onSurfaceVariant;
    case PersonEventType.reminderSet:
      return AppColors.profileOnBreak;
  }
}

/// The inline "היסטוריה אחרונה" feed: the last handful of meaningful events in
/// dense rows, with a link to the full history screen.
class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.events, required this.onShowAll});

  final List<PersonEvent> events;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final List<PersonEvent> preview = events.take(6).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        decoration: BoxDecoration(
          color: _profileSurfaceColor(theme),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _profileMutedColor(theme).withValues(alpha: 0.14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'היסטוריה אחרונה',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: _profileTextColor(theme),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final PersonEvent event in preview) _HistoryRow(event: event),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onShowAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('לכל ההיסטוריה'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One dense line in the history timeline: small date, a type-coloured dot, and
/// the event text.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event});

  final PersonEvent event;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = _eventColor(event.type);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 34,
            child: Text(
              _eventDateShort(event.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: _profileMutedColor(theme),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              event.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _profileTextColor(theme),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The filters on the full history screen.
enum _HistoryFilter {
  all('הכל'),
  proposals('הצעות'),
  dated('יצאו'),
  rejected('שלילות'),
  notes('הערות');

  const _HistoryFilter(this.label);

  final String label;

  bool matches(PersonEvent event) {
    switch (this) {
      case _HistoryFilter.all:
        return true;
      case _HistoryFilter.proposals:
        return event.type == PersonEventType.proposalOpened;
      case _HistoryFilter.dated:
        return event.type == PersonEventType.dated;
      case _HistoryFilter.rejected:
        return event.type == PersonEventType.rejected;
      case _HistoryFilter.notes:
        return event.type == PersonEventType.note;
    }
  }
}

/// The full history screen for a person, with the filter row from the spec
/// (הכל / הצעות / יצאו / שלילות / הערות).
class _PersonHistoryPage extends StatefulWidget {
  const _PersonHistoryPage({required this.personId});

  final String personId;

  @override
  State<_PersonHistoryPage> createState() => _PersonHistoryPageState();
}

class _PersonHistoryPageState extends State<_PersonHistoryPage> {
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final Person? person = personRepository.getById(widget.personId);
    final List<PersonEvent> events = person == null
        ? const <PersonEvent>[]
        : personRepository.getEventsForPerson(person.id);
    final List<PersonEvent> filtered = events.where(_filter.matches).toList();

    return Scaffold(
      backgroundColor: _profileCanvasColor(theme),
      appBar: AppBar(
        backgroundColor: _profileCanvasColor(theme),
        foregroundColor: _profileTextColor(theme),
        titleTextStyle: _profileAppBarTitleStyle(theme),
        centerTitle: true,
        title: const Text('היסטוריה'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                children: <Widget>[
                  for (final _HistoryFilter filter in _HistoryFilter.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(filter.label),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const _TabEmptyState(
                      icon: Icons.history,
                      title: 'אין אירועים',
                      subtitle: 'כאן תופיע ההיסטוריה של המועמד',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (BuildContext context, int index) =>
                          _HistoryRow(event: filtered[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    final Color baseColor = AppColors.statusColor(status.name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.statusBackgroundColor(status.name),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.displayName,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: baseColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({this.title, required this.child, this.trailing});

  final String? title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        decoration: BoxDecoration(
          color: _profileSurfaceColor(theme),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _profileMutedColor(theme).withValues(alpha: 0.14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(title: title ?? '', trailing: trailing),
            child,
          ],
        ),
      ),
    );
  }
}
