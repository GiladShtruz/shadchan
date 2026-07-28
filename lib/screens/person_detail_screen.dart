import 'dart:async';
import 'dart:io';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/person_photo_editor.dart';
import 'package:shadchan/widgets/religious_level_picker.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/details_message_dialog.dart';
import 'package:shadchan/dialogs/home_board_actions.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/recent_activity_store.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/widgets/device_contact_picker_sheet.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';
import 'package:shadchan/widgets/person_photo_carousel.dart';
import 'package:shadchan/widgets/section_header.dart';

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
  final GlobalKey _cardSectionKey = GlobalKey();

  /// Whether the profile header was scrolled away, so the AppBar shows a
  /// compact bar with the person's name only.
  bool _showCollapsedTitle = false;
  bool _showFullCard = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    // Feeds the home screen's "חזרה מהירה" strip. Deferred past this frame:
    // the home screen is still alive behind this route, and notifying it from
    // inside initState would rebuild it mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RecentActivityStore.instance.record(
        kind: HomeItemKind.person,
        targetId: widget.personId,
        action: HomeActivityAction.openedPerson,
      );
    });
    if (widget.initiallyEditing) {
      // The old edit route now lands on the dedicated card-edit page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openCardEditPage(context);
        }
      });
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

  Future<void> _openCardEditPage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return _PersonCardEditPage(personId: widget.personId);
        },
      ),
    );
  }

  void _showCardInline() {
    if (!_showFullCard) {
      setState(() => _showFullCard = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? cardContext = _cardSectionKey.currentContext;
      if (!mounted || cardContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        cardContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0.08,
      );
    });
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) async {
              switch (value) {
                case 'board':
                  HomeBoardActions.toggle(
                    context,
                    HomeItemKind.person,
                    person.id,
                  );
                case 'edit':
                  await _openCardEditPage(context);
                case 'share':
                  await _sharePerson(context, person);
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
                PopupMenuItem<String>(
                  value: 'board',
                  child: Text(
                    HomeBoardActions.menuLabel(HomeItemKind.person, person.id),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Text('עריכת כרטיס'),
                ),
                const PopupMenuItem<String>(
                  value: 'share',
                  child: Text('שיתוף כרטיס'),
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
              onAvatarTap: _showCardInline,
              onStatusChanged: (ProfileStatus status) =>
                  _changeProfileStatus(context, person, status),
            ),
            _ProfileInlineActions(
              whatsappLabel: _firstNameOr(person, 'WhatsApp'),
              onWhatsApp: () => _openWhatsAppMessage(context, person),
              onMatches: () => _openSuggestions(context, person),
              onAddProposal: () => _openAddProposal(context, person),
            ),
            _WhatsAppCardSection(
              key: _cardSectionKey,
              person: person,
              expanded: _showFullCard,
              onToggleFull: () {
                setState(() => _showFullCard = !_showFullCard);
              },
              onShare: () => _showCardShareSheet(context, person),
              onRequestDetails: () => _requestDetails(context, person),
              onEditMessage: () => _editDetailsMessage(context, person),
            ),
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

  Future<void> _sharePerson(BuildContext context, Person person) async {
    try {
      await ShareUtils.sharePerson(person);
    } catch (_) {
      if (context.mounted) {
        _showSnackBar(context, 'לא ניתן לשתף כרגע');
      }
    }
  }

  Future<void> _showCardShareSheet(BuildContext context, Person person) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'שיתוף הכרטיס המלא',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'בחירת הנמען תיפתח ב-WhatsApp',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      final bool launched = await WhatsAppUtils.sharePersonCard(
                        person,
                      );
                      if (!launched && context.mounted) {
                        _showSnackBar(context, 'לא הצלחנו לפתוח את WhatsApp');
                      }
                    },
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 20),
                    label: const Text('שיתוף דרך WhatsApp'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                title: const Text('התאמה עם מועמד מתוך המאגר'),
                onTap: () => Navigator.of(dialogContext).pop('database'),
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1),
                title: const Text('התאמה עם אדם שאינו נמצא במאגר'),
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

class _InlinePersonEditForm extends StatelessWidget {
  const _InlinePersonEditForm({
    required this.formKey,
    required this.firstNameController,
    required this.lastNameController,
    required this.manualAgeController,
    required this.phoneController,
    required this.inquiryContactNameController,
    required this.inquiryContactPhoneController,
    required this.firstNameFocus,
    required this.lastNameFocus,
    required this.manualAgeFocus,
    required this.phoneFocus,
    required this.inquiryContactNameFocus,
    required this.inquiryContactPhoneFocus,
    required this.onSavePressed,
    required this.onFieldChanged,
    required this.selectedGender,
    required this.selectedReligiousLevel,
    required this.selectedReligiousLevelOther,
    required this.onGenderChanged,
    required this.onReligiousLevelChanged,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController manualAgeController;
  final TextEditingController phoneController;
  final TextEditingController inquiryContactNameController;
  final TextEditingController inquiryContactPhoneController;
  final FocusNode firstNameFocus;
  final FocusNode lastNameFocus;
  final FocusNode manualAgeFocus;
  final FocusNode phoneFocus;
  final FocusNode inquiryContactNameFocus;
  final FocusNode inquiryContactPhoneFocus;
  final VoidCallback onSavePressed;
  final VoidCallback onFieldChanged;
  final Gender selectedGender;
  final ReligiousLevel? selectedReligiousLevel;
  final String? selectedReligiousLevelOther;
  final ValueChanged<Gender> onGenderChanged;
  final ValueChanged<ReligiousLevelChoice> onReligiousLevelChanged;

  Widget? _saveSuffix(FocusNode node) {
    if (!node.hasFocus) return null;
    return IconButton(
      icon: const Icon(Icons.check),
      tooltip: 'שמירה',
      onPressed: onSavePressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Form(
      key: formKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextFormField(
              controller: firstNameController,
              focusNode: firstNameFocus,
              textInputAction: TextInputAction.next,
              onChanged: (_) => onFieldChanged(),
              decoration: InputDecoration(
                labelText: 'שם פרטי',
                suffixIcon: _saveSuffix(firstNameFocus),
              ),
              validator: _requiredText('יש להזין שם פרטי'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: lastNameController,
              focusNode: lastNameFocus,
              textInputAction: TextInputAction.next,
              onChanged: (_) => onFieldChanged(),
              decoration: InputDecoration(
                labelText: 'שם משפחה',
                suffixIcon: _saveSuffix(lastNameFocus),
              ),
              validator: _requiredText('יש להזין שם משפחה'),
            ),
            const SizedBox(height: 20),
            Text('מגדר', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Gender.values.map((Gender gender) {
                return ChoiceChip(
                  label: Text(gender.displayName),
                  selected: selectedGender == gender,
                  onSelected: (bool selected) {
                    if (selected) {
                      onGenderChanged(gender);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            ReligiousLevelPicker(
              selected: ReligiousLevelChoice(
                selectedReligiousLevel,
                selectedReligiousLevelOther,
              ),
              onChanged: onReligiousLevelChanged,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: manualAgeController,
              focusNode: manualAgeFocus,
              keyboardType: TextInputType.number,
              onChanged: (_) => onFieldChanged(),
              decoration: InputDecoration(
                labelText: 'גיל',
                suffixIcon: _saveSuffix(manualAgeFocus),
              ),
              validator: (String? value) {
                final String trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) {
                  return null;
                }
                final int? parsed = int.tryParse(trimmed);
                if (parsed == null || parsed < 10 || parsed > 120) {
                  return 'יש להזין גיל בין 10 ל-120';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: phoneController,
              focusNode: phoneFocus,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.phone,
              onChanged: (_) => onFieldChanged(),
              decoration: InputDecoration(
                labelText: 'טלפון',
                suffixIcon: _saveSuffix(phoneFocus),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'איש קשר לבירורים',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final DeviceContactChoice? choice =
                        await DeviceContactPickerSheet.show(context);
                    if (choice == null) {
                      return;
                    }
                    inquiryContactNameController.text = choice.name;
                    inquiryContactPhoneController.text = choice.phone;
                    onFieldChanged();
                  },
                  icon: const Icon(Icons.contacts_outlined, size: 18),
                  label: const Text('ייבוא מאנשי הקשר'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: inquiryContactNameController,
                    focusNode: inquiryContactNameFocus,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => onFieldChanged(),
                    decoration: InputDecoration(
                      labelText: 'שם',
                      isDense: true,
                      suffixIcon: _saveSuffix(inquiryContactNameFocus),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: inquiryContactPhoneController,
                    focusNode: inquiryContactPhoneFocus,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => onFieldChanged(),
                    decoration: InputDecoration(
                      labelText: 'טלפון',
                      isDense: true,
                      suffixIcon: _saveSuffix(inquiryContactPhoneFocus),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  FormFieldValidator<String> _requiredText(String message) {
    return (String? value) {
      if (value == null || value.trim().isEmpty) {
        return message;
      }
      return null;
    };
  }
}

class _ProfileSummaryHeader extends StatelessWidget {
  const _ProfileSummaryHeader({
    required this.person,
    required this.onAvatarTap,
    required this.onStatusChanged,
  });

  final Person person;
  final VoidCallback onAvatarTap;
  final ValueChanged<ProfileStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String summary = _personSummary(person);

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
              GestureDetector(
                onTap: onAvatarTap,
                child: Hero(
                  tag: 'person-${person.id}',
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _profileWarmSurfaceColor(theme),
                      shape: BoxShape.circle,
                    ),
                    child: PersonAvatar(person: person, radius: 54),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                person.fullName.trim(),
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
                status: person.profileStatus,
                onStatusChanged: onStatusChanged,
              ),
              const SizedBox(height: 10),
              Text(
                _relativeUpdatedLabel(person.updatedAt),
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
                  'רק לעיניך — עדיין אין הערות. הוסיפו משהו שתרצו לזכור.',
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
                  child: Text('הצג הכל (${entries.length})'),
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
            decoration: const InputDecoration(hintText: 'משהו שתרצו לזכור...'),
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

/// Inline preview of the person's send-card. Expanding keeps the complete card
/// inside the profile and exposes its WhatsApp share action above the text.
class _WhatsAppCardSection extends StatelessWidget {
  const _WhatsAppCardSection({
    super.key,
    required this.person,
    required this.expanded,
    required this.onToggleFull,
    required this.onShare,
    required this.onRequestDetails,
    required this.onEditMessage,
  });

  final Person person;
  final bool expanded;
  final VoidCallback onToggleFull;
  final VoidCallback onShare;
  final VoidCallback onRequestDetails;
  final VoidCallback onEditMessage;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String description = (person.description ?? '').trim();
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (hasCard) ...<Widget>[
              AnimatedCrossFade(
                firstChild: Text(
                  description,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _profileTextColor(theme),
                    height: 1.5,
                  ),
                ),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: IconButton(
                        onPressed: onShare,
                        icon: const Icon(Icons.share_outlined),
                        tooltip: 'שיתוף הכרטיס המלא',
                        color: theme.colorScheme.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _profileTextColor(theme),
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
                crossFadeState: expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 180),
                sizeCurve: Curves.easeOut,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onToggleFull,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(expanded ? 'סגירת הכרטיס המלא' : 'הצג כרטיס מלא'),
                ),
              ),
            ] else ...<Widget>[
              Text(
                'אין עדיין כרטיס מלא או תמונה — רק פרטים בסיסיים.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _profileMutedColor(theme),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: onRequestDetails,
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
                    label: const Text('בקש פרטים ב-WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _profileTextColor(theme),
                      side: BorderSide(
                        color: _profileMutedColor(theme).withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onEditMessage,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('עריכת נוסח'),
                    style: TextButton.styleFrom(
                      foregroundColor: _profileMutedColor(theme),
                    ),
                  ),
                ],
              ),
            ],
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
abstract final class _MatchPreviewSheet {
  static Future<bool?> show(
    BuildContext context, {
    required Person source,
    required Person candidate,
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
                          'רעיון להצעה',
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
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        icon: const Icon(Icons.favorite_border),
                        label: const Text('פתח רעיון'),
                      ),
                    ),
                  ),
                ),
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
  const _SuggestionsPage({required this.personId});

  final String personId;

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
    // Within each tier, candidates that pause matches (תפוס/בהפסקה) drop
    // after the available ones.
    List<Person> availableFirst(List<Person> people) => <Person>[
      ...people.where((Person p) => !p.profileStatus.pausesMatches),
      ...people.where((Person p) => p.profileStatus.pausesMatches),
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
      backgroundColor: _profileCanvasColor(theme),
      appBar: AppBar(
        backgroundColor: _profileCanvasColor(theme),
        foregroundColor: _profileTextColor(theme),
        centerTitle: true,
        title: Text('התאמות · ${person.firstName.trim()}'),
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
      return MatchSuggestionUtils.isSuggestedCandidate(
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

  MatchProposalFilters _defaultSuggestionFilters(Person sourcePerson) {
    final ({int minAge, int maxAge})? femaleAgeRange =
        sourcePerson.gender == Gender.male
        ? MatchSuggestionUtils.femaleAgeRangeForMale(sourcePerson.age)
        : null;

    return MatchProposalFilters(
      minAge: femaleAgeRange?.minAge,
      maxAge: femaleAgeRange?.maxAge,
      religiousLevels: MatchSuggestionUtils.religiousLevelsFor(
        sourcePerson.religiousLevel,
      ),
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

    if (context.mounted) {
      _showSnackBar(context, 'ההתאמה הועברה לסוף הרשימה');
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
                  Icon(Icons.chevron_left, color: _profileMutedColor(theme)),
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
                      if (hasCard) ...<Widget>[
                        const SizedBox(width: 4),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: expanded ? 'סגירת כרטיס' : 'הצגת כרטיס',
                          icon: AnimatedRotation(
                            turns: expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              color: _profileMutedColor(theme),
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              if (!_expandedIds.remove(candidate.id)) {
                                _expandedIds.add(candidate.id);
                              }
                            });
                          },
                        ),
                      ],
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

/// Inline quick view of a candidate's send-card: primary photo + card text,
/// shown under the suggestion row without leaving the profile.
class _CandidateQuickCard extends StatelessWidget {
  const _CandidateQuickCard({required this.candidate});

  final Person candidate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String description = (candidate.description ?? '').trim();
    final String? photoPath = candidate.photosPaths.isEmpty
        ? null
        : candidate.photosPaths.first;
    final File? photoFile = photoPath == null ? null : File(photoPath);
    final bool hasPhoto = photoFile != null && photoFile.existsSync();

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
          if (hasPhoto)
            Image.file(
              photoFile,
              height: 220,
              cacheWidth: 720,
              fit: BoxFit.cover,
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

/// A dedicated full page for editing the person's card: the send-card text
/// and the personal details. Saves automatically when leaving the page.
class _PersonCardEditPage extends StatefulWidget {
  const _PersonCardEditPage({required this.personId});

  final String personId;

  @override
  State<_PersonCardEditPage> createState() => _PersonCardEditPageState();
}

class _PersonCardEditPageState extends State<_PersonCardEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _manualAgeController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _inquiryContactNameController =
      TextEditingController();
  final TextEditingController _inquiryContactPhoneController =
      TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  final FocusNode _firstNameFocus = FocusNode();
  final FocusNode _lastNameFocus = FocusNode();
  final FocusNode _manualAgeFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _inquiryContactNameFocus = FocusNode();
  final FocusNode _inquiryContactPhoneFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();

  Gender _gender = Gender.unknown;
  ReligiousLevel? _religiousLevel;
  String? _religiousLevelOther;
  int _avatarIndex = 0;
  bool _isSaving = false;

  List<String> _photoPaths = <String>[];

  /// Photos copied in during this edit. They are deleted again if the edit is
  /// abandoned, so the app's photo folder does not collect orphans.
  final Set<String> _newPhotoPaths = <String>{};

  List<FocusNode> get _focusNodes => <FocusNode>[
    _firstNameFocus,
    _lastNameFocus,
    _manualAgeFocus,
    _phoneFocus,
    _inquiryContactNameFocus,
    _inquiryContactPhoneFocus,
    _descriptionFocus,
  ];

  @override
  void initState() {
    super.initState();
    final Person? person = context.read<PersonRepository>().getById(
      widget.personId,
    );
    if (person != null) {
      _firstNameController.text = person.firstName;
      _lastNameController.text = person.lastName;
      // Show the current (auto-advancing) manual age so re-saving re-anchors
      // it.
      _manualAgeController.text = person.age?.toString() ?? '';
      _phoneController.text = person.phone ?? '';
      _inquiryContactNameController.text = person.inquiryContactName ?? '';
      _inquiryContactPhoneController.text = person.inquiryContactPhone ?? '';
      _descriptionController.text = person.description ?? '';
      _gender = person.gender;
      _religiousLevel = person.religiousLevel;
      _religiousLevelOther = person.religiousLevelOther;
      _avatarIndex = person.avatarIndex;
      _photoPaths = List<String>.from(person.photosPaths);
    }
    for (final FocusNode node in _focusNodes) {
      node.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    for (final FocusNode node in _focusNodes) {
      node
        ..removeListener(_handleFocusChange)
        ..dispose();
    }
    _firstNameController.dispose();
    _lastNameController.dispose();
    _manualAgeController.dispose();
    _phoneController.dispose();
    _inquiryContactNameController.dispose();
    _inquiryContactPhoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  String? _normalizedText(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<bool> _save({bool showSnackBar = true}) async {
    final PersonRepository repository = context.read<PersonRepository>();
    final Person? person = repository.getById(widget.personId);
    if (person == null) {
      return true;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return false;
    }

    setState(() => _isSaving = true);
    try {
      final int? manualAge = int.tryParse(_manualAgeController.text.trim());
      person
        ..firstName = _firstNameController.text.trim()
        ..lastName = _lastNameController.text.trim()
        ..gender = _gender
        ..setManualAge(manualAge)
        ..religiousLevel = _religiousLevel
        ..religiousLevelOther = _religiousLevelOther
        ..phone = _normalizedText(_phoneController.text)
        ..inquiryContactName = _normalizedText(
          _inquiryContactNameController.text,
        )
        ..inquiryContactPhone = _normalizedText(
          _inquiryContactPhoneController.text,
        )
        ..description = _normalizedText(_descriptionController.text)
        ..avatarIndex = _avatarIndex
        ..photosPaths = List<String>.from(_photoPaths);
      await repository.update(person);
      _newPhotoPaths.clear();

      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('השינויים נשמרו')));
      }
      return true;
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickPhotos() async {
    final List<String> copiedPhotoPaths = await PhotoPickerService.pickPhotos(
      context,
      personId: widget.personId,
    );
    if (copiedPhotoPaths.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _photoPaths = List<String>.from(_photoPaths)..addAll(copiedPhotoPaths);
      _newPhotoPaths.addAll(copiedPhotoPaths);
    });
  }

  void _setPrimaryPhoto(int index) {
    if (index <= 0 || index >= _photoPaths.length) {
      return;
    }

    setState(() {
      final List<String> reordered = List<String>.from(_photoPaths);
      reordered.insert(0, reordered.removeAt(index));
      _photoPaths = reordered;
    });
  }

  void _removePhoto(int index) {
    if (index < 0 || index >= _photoPaths.length) {
      return;
    }

    setState(() {
      final List<String> remaining = List<String>.from(_photoPaths);
      final String removed = remaining.removeAt(index);
      _photoPaths = remaining;
      // Only files added during this edit are deleted from disk; an existing
      // photo is just detached from the card.
      if (_newPhotoPaths.remove(removed)) {
        PhotoPickerService.deletePhotoFiles(<String>[removed]);
      }
    });
  }

  Future<void> _saveAndPop() async {
    final NavigatorState navigator = Navigator.of(context);
    final bool saved = await _save(showSnackBar: false);
    if (saved && mounted) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop || _isSaving) {
          return;
        }
        await _saveAndPop();
      },
      child: Scaffold(
        backgroundColor: _profileCanvasColor(theme),
        appBar: AppBar(
          backgroundColor: _profileCanvasColor(theme),
          foregroundColor: _profileTextColor(theme),
          title: const Text('עריכת כרטיס'),
          centerTitle: true,
          actions: <Widget>[
            IconButton(
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              tooltip: 'שמירה',
              onPressed: _isSaving ? null : _saveAndPop,
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
            children: <Widget>[
              _Section(
                title: 'תמונות',
                child: PersonPhotoEditor(
                  photoPaths: _photoPaths,
                  onAddPhoto: _pickPhotos,
                  onSetPrimary: _setPrimaryPhoto,
                  onRemove: _removePhoto,
                  gender: _gender,
                  avatarIndex: _avatarIndex,
                  onAvatarChanged: (int index) {
                    setState(() => _avatarIndex = index);
                  },
                ),
              ),
              _Section(
                title: 'עריכת כרטיסייה',
                child: TextFormField(
                  controller: _descriptionController,
                  focusNode: _descriptionFocus,
                  textInputAction: TextInputAction.newline,
                  maxLines: 10,
                  minLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'טקסט לשיתוף בוואטסאפ (5-10 משפטים)',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              _InlinePersonEditForm(
                formKey: _formKey,
                firstNameController: _firstNameController,
                lastNameController: _lastNameController,
                manualAgeController: _manualAgeController,
                phoneController: _phoneController,
                inquiryContactNameController: _inquiryContactNameController,
                inquiryContactPhoneController: _inquiryContactPhoneController,
                firstNameFocus: _firstNameFocus,
                lastNameFocus: _lastNameFocus,
                manualAgeFocus: _manualAgeFocus,
                phoneFocus: _phoneFocus,
                inquiryContactNameFocus: _inquiryContactNameFocus,
                inquiryContactPhoneFocus: _inquiryContactPhoneFocus,
                onSavePressed: () => _save(),
                onFieldChanged: () {},
                selectedGender: _gender,
                selectedReligiousLevel: _religiousLevel,
                selectedReligiousLevelOther: _religiousLevelOther,
                onGenderChanged: (Gender gender) {
                  setState(() => _gender = gender);
                },
                onReligiousLevelChanged: (ReligiousLevelChoice choice) {
                  setState(() {
                    _religiousLevel = choice.level;
                    _religiousLevelOther = choice.customLabel;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
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
                  decoration: const InputDecoration(hintText: 'הוסיפו הערה...'),
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
