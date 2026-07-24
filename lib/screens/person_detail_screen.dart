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
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/widgets/device_contact_picker_sheet.dart';
import 'package:shadchan/widgets/person_avatar.dart';
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

class _PersonDetailScreenState extends State<PersonDetailScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  final ScrollController _scrollController = ScrollController();

  /// Whether the profile header was scrolled away, so the AppBar shows a
  /// compact bar with the person's name only.
  bool _showCollapsedTitle = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
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
    _tabController.dispose();
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

  Future<void> _openCardViewPage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return _PersonCardViewPage(personId: widget.personId);
        },
      ),
    );
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
    final List<MatchIdea> openMatches = relatedMatches
        .where((MatchIdea match) => !match.status.isArchived)
        .toList();
    final List<MatchIdea> rejectedMatches = relatedMatches
        .where((MatchIdea match) => match.status == MatchStatus.rejected)
        .toList();
    final List<PersonNote> personNotes = personRepository.getNotesForPerson(
      person.id,
    );
    final int personNotesCount = _personNotesCount(person, personNotes);

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
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.whatsapp),
            tooltip: 'וואטסאפ',
            onPressed: () => _openWhatsAppMessage(context, person),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'שיתוף',
            onPressed: () => _sharePerson(context, person),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'עריכת כרטיס',
            onPressed: () => _openCardEditPage(context),
          ),
          PopupMenuButton<String>(
            onSelected: (String value) async {
              switch (value) {
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
                if (hasContact) ...<PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'shareContact',
                    child: Text('שיתוף פרטי איש הקשר'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'whatsappContact',
                    child: Text('וואטסאפ לאיש הקשר'),
                  ),
                  const PopupMenuDivider(),
                ],
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('מחיקת כרטיס'),
                ),
              ];
            },
          ),
        ],
      ),
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) =>
            <Widget>[
              SliverToBoxAdapter(
                child: _ProfileSummaryHeader(
                  person: person,
                  onAvatarTap: () => _openCardViewPage(context),
                  onStatusChanged: (ProfileStatus status) =>
                      personRepository.updateProfileStatus(person.id, status),
                ),
              ),
              SliverToBoxAdapter(
                child: _PersonNotesButton(
                  noteCount: personNotesCount,
                  onPressed: () => _openPersonNotes(context, person),
                ),
              ),
              SliverToBoxAdapter(
                child: _AddProposalButton(
                  onPressed: () => _openAddProposal(context, person),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedTabBarDelegate(
                  backgroundColor: _profileCanvasColor(theme),
                  tabBar: TabBar(
                    controller: _tabController,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: const <Widget>[
                      Tab(text: 'התאמות'),
                      Tab(text: 'הצעות'),
                    ],
                  ),
                ),
              ),
            ],
        body: TabBarView(
          controller: _tabController,
          children: <Widget>[
            _SuggestedMatchesTab(
              sourcePerson: person,
              suggestedPeople: suggestedPeople,
              matchRepository: matchRepository,
              hasCustomFilters: savedSuggestionFilters != null,
              onFilterPressed: () => _openSuggestionFilters(context, person),
              onAccept: (Person candidate) =>
                  _acceptSuggestion(context, person, candidate),
              onReject: (Person candidate) =>
                  _rejectSuggestion(context, person, candidate),
            ),
            _ProposalsTab(
              person: person,
              openMatches: openMatches,
              rejectedMatches: rejectedMatches,
              personRepository: personRepository,
            ),
          ],
        ),
      ),
    );
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

    if (filters.religiousLevels.isNotEmpty &&
        !filters.religiousLevels.contains(candidate.religiousLevel)) {
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

    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && context.mounted) {
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

class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  _PinnedTabBarDelegate({required this.tabBar, required this.backgroundColor});

  final TabBar tabBar;
  final Color backgroundColor;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(color: backgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(_PinnedTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar ||
        backgroundColor != oldDelegate.backgroundColor;
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
            ],
          ),
        ),
      ),
    );
  }
}

/// "הוסף הצעה" — the shortcut from a profile straight into a new idea.
class _AddProposalButton extends StatelessWidget {
  const _AddProposalButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = _profileMutedColor(theme);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: _profileSurfaceColor(theme),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: muted.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.favorite_border, color: muted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'הוסף הצעה',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: _profileTextColor(theme),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.chevron_left, color: muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonNotesButton extends StatelessWidget {
  const _PersonNotesButton({required this.noteCount, required this.onPressed});

  final int noteCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = _profileMutedColor(theme);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: _profileSurfaceColor(theme),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: muted.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.notes_outlined, color: muted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'הערות אישיות',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: _profileTextColor(theme),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? theme.colorScheme.surfaceContainerHighest
                      : _profileBlushLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  noteCount > 0 ? noteCount.toString() : 'רק לעיניך',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.brightness == Brightness.dark
                        ? theme.colorScheme.onSurfaceVariant
                        : AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_left, color: muted),
            ],
          ),
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
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.surfaceContainerHighest
                  : _profileWarmSurfaceColor(theme),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _profileMutedColor(theme).withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(widget.status.emoji),
                const SizedBox(width: 6),
                Text(
                  widget.status.displayName,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: _profileTextColor(theme),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: _profileMutedColor(theme),
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
                    return ActionChip(
                      avatar: Text(status.emoji),
                      label: Text(status.displayName),
                      onPressed: () => widget.onStatusChanged(status),
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

/// The הצעות tab: proposals that were actually opened for this person —
/// open ideas first, and separately ideas that were opened and rejected.
/// Suggestions dismissed before a proposal was opened do not appear here.
class _ProposalsTab extends StatelessWidget {
  const _ProposalsTab({
    required this.person,
    required this.openMatches,
    required this.rejectedMatches,
    required this.personRepository,
  });

  final Person person;
  final List<MatchIdea> openMatches;
  final List<MatchIdea> rejectedMatches;
  final PersonRepository personRepository;

  @override
  Widget build(BuildContext context) {
    if (openMatches.isEmpty && rejectedMatches.isEmpty) {
      return const _TabEmptyState(
        icon: Icons.lightbulb_outline,
        title: 'אין הצעות עדיין',
        subtitle: 'הצעות שנפתחות מתוך ההתאמות יופיעו כאן',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      children: <Widget>[
        if (openMatches.isNotEmpty)
          _MatchesGroup(
            title: 'רעיונות פתוחים',
            person: person,
            matches: openMatches,
            personRepository: personRepository,
          ),
        if (rejectedMatches.isNotEmpty)
          _MatchesGroup(
            title: 'רעיונות שנשללו',
            person: person,
            matches: rejectedMatches,
            personRepository: personRepository,
          ),
      ],
    );
  }
}

class _MatchesGroup extends StatelessWidget {
  const _MatchesGroup({
    required this.title,
    required this.person,
    required this.matches,
    required this.personRepository,
  });

  final String title;
  final Person person;
  final List<MatchIdea> matches;
  final PersonRepository personRepository;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: _profileTextColor(theme),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _RelatedMatchesSection(
          person: person,
          matches: matches,
          personRepository: personRepository,
        ),
      ],
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
    required this.onAccept,
    required this.onReject,
  });

  final Person sourcePerson;
  final List<Person> suggestedPeople;
  final MatchRepository matchRepository;
  final bool hasCustomFilters;
  final VoidCallback onFilterPressed;
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
    required this.onAccept,
    required this.onReject,
  });

  final Person sourcePerson;
  final List<Person> suggestedPeople;
  final MatchRepository matchRepository;
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
                    : context.push('/people/${candidate.id}'),
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
                        icon: Icons.add,
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

String _personSummary(Person person) {
  final List<String> parts = <String>[
    if (person.age != null) 'גיל ${person.age}',
    if (person.religiousLevelLabel.isNotEmpty) person.religiousLevelLabel,
    if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
  ];
  return parts.isEmpty ? 'פרטים חסרים' : parts.join(' · ');
}

int _personNotesCount(Person person, List<PersonNote> notes) {
  final bool hasLegacyNote = (person.notes ?? '').trim().isNotEmpty;
  return notes.length + (hasLegacyNote ? 1 : 0);
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

/// The enlarged card page opened by tapping the profile square: a full-screen
/// photo pager with arrows, the send-card below, and share/WhatsApp/edit
/// actions on top.
class _PersonCardViewPage extends StatefulWidget {
  const _PersonCardViewPage({required this.personId});

  final String personId;

  @override
  State<_PersonCardViewPage> createState() => _PersonCardViewPageState();
}

class _PersonCardViewPageState extends State<_PersonCardViewPage> {
  final PageController _pageController = PageController();
  int _photoIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPhoto(int index, int count) {
    if (index < 0 || index >= count) {
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _openWhatsApp(Person person) async {
    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('לא הצלחנו לפתוח את וואטסאפ')),
        );
    }
  }

  Future<void> _share(Person person) async {
    try {
      await ShareUtils.sharePerson(person);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('לא ניתן לשתף כרגע')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository repository = context.watch<PersonRepository>();
    final Person? person = repository.getById(widget.personId);

    if (person == null) {
      return Scaffold(
        appBar: AppBar(centerTitle: true),
        body: const Center(child: Text('האדם לא נמצא')),
      );
    }

    final List<String> photos = person.photosPaths
        .where((String path) => File(path).existsSync())
        .toList();
    final String description = (person.description ?? '').trim();
    final double photoHeight = MediaQuery.of(context).size.height * 0.78;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black38,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          person.fullName.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'שיתוף',
            onPressed: () => _share(person),
          ),
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.whatsapp),
            tooltip: 'וואטסאפ',
            onPressed: () => _openWhatsApp(person),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'עריכת כרטיס',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) {
                    return _PersonCardEditPage(personId: person.id);
                  },
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          SizedBox(
            height: photoHeight,
            child: photos.isEmpty
                ? Center(child: PersonAvatar(person: person, radius: 80))
                : Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      PageView.builder(
                        controller: _pageController,
                        itemCount: photos.length,
                        onPageChanged: (int index) =>
                            setState(() => _photoIndex = index),
                        itemBuilder: (BuildContext context, int index) {
                          return Image.file(
                            File(photos[index]),
                            fit: BoxFit.contain,
                          );
                        },
                      ),
                      if (photos.length > 1) ...<Widget>[
                        // In RTL the pager advances leftwards, so the left
                        // arrow goes forward and the right arrow goes back.
                        if (_photoIndex + 1 < photos.length)
                          Positioned(
                            left: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _PhotoArrowButton(
                                icon: Icons.chevron_left,
                                onPressed: () =>
                                    _goToPhoto(_photoIndex + 1, photos.length),
                              ),
                            ),
                          ),
                        if (_photoIndex > 0)
                          Positioned(
                            right: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _PhotoArrowButton(
                                icon: Icons.chevron_right,
                                onPressed: () =>
                                    _goToPhoto(_photoIndex - 1, photos.length),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 14,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List<Widget>.generate(photos.length, (
                              int index,
                            ) {
                              return Container(
                                width: index == _photoIndex ? 9 : 7,
                                height: index == _photoIndex ? 9 : 7,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: index == _photoIndex
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _profileSurfaceColor(theme),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'כרטיס לשליחה',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: _profileTextColor(theme),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  description.isEmpty
                      ? 'עדיין אין כרטיסייה לשליחה'
                      : description,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: description.isEmpty
                        ? _profileMutedColor(theme)
                        : _profileTextColor(theme),
                    height: 1.58,
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

class _PhotoArrowButton extends StatelessWidget {
  const _PhotoArrowButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white, size: 30),
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

class _RelatedMatchesSection extends StatelessWidget {
  const _RelatedMatchesSection({
    required this.person,
    required this.matches,
    required this.personRepository,
  });

  final Person person;
  final List<MatchIdea> matches;
  final PersonRepository personRepository;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return Text(
        'אין הצעות עדיין',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    return Column(
      children: matches.map((MatchIdea match) {
        final String otherPersonId = match.personAId == person.id
            ? match.personBId
            : match.personAId;
        final Person? otherPerson = personRepository.getById(otherPersonId);
        final String otherName = otherPerson?.fullName.trim().isNotEmpty == true
            ? otherPerson!.fullName.trim()
            : 'אדם נמחק';

        final ThemeData theme = Theme.of(context);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: _profileSurfaceColor(theme),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () => context.push('/matches/${match.id}'),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(14),
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
                    const SizedBox(width: 10),
                    _StatusChip(status: match.status),
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
