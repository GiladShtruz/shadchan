import 'dart:async';
import 'dart:io';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shadchan/dialogs/voice_recorder_sheet.dart';
import 'package:shadchan/widgets/voice_note_player.dart';
import 'package:shadchan/widgets/match_state_tag.dart';
import 'package:shadchan/widgets/sketch_actions.dart';
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
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_invite.dart';
import 'package:shadchan/widgets/card_link_panel.dart';
import 'package:shadchan/widgets/candidate_card_view.dart';
import 'package:shadchan/widgets/extended_filter_toggle.dart';
import 'package:shadchan/widgets/religious_level_picker.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/person_extended_edit_screen.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/delete_person_dialog.dart';
import 'package:shadchan/dialogs/person_card_viewer.dart';
import 'package:shadchan/dialogs/home_board_actions.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/utils/contact_channel.dart';
import 'package:shadchan/widgets/contact_channel_button.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';
import 'package:shadchan/widgets/person_photo_carousel.dart';
import 'package:shadchan/widgets/section_header.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/person_navigation.dart';
import 'package:shadchan/widgets/first_visit_tip.dart';

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
///
/// Returns false when a new friend was left without being saved — the card
/// editor then threw the record away — and true otherwise.
Future<bool> openExtendedPersonEditor(
  BuildContext context,
  String personId, {
  bool isNewFriend = false,
}) async {
  final Person? person = context.read<PersonRepository>().getById(personId);
  if (person != null && !await confirmEditSyncedCard(context, person)) {
    return true;
  }
  if (!context.mounted) {
    return true;
  }
  final bool? kept = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (BuildContext context) => PersonExtendedEditScreen(
        personId: personId,
        isNewFriend: isNewFriend,
      ),
    ),
  );
  return kept ?? true;
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
    this.focus,
  });

  final String personId;
  final bool initiallyEditing;

  /// Where to open: `card` (the full card, expanded), `notes`, or `details`.
  /// Set by a home-search result, so the profile opens on the words that
  /// were found.
  final String? focus;

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

  /// The one-time hint about sharing a photo and a few words from WhatsApp.
  /// Taken when the first profile is opened, so it never comes back.
  bool _showShareTip = FirstVisitTips.takeFirstVisit(
    FirstVisitTopic.friendProfile,
  );

  final GlobalKey _cardSectionKey = GlobalKey();
  final GlobalKey _notesSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    if (widget.initiallyEditing) {
      _editingDetails = true;
    }
    final String? focus = widget.focus;
    if (focus == 'card') {
      _showFullCard = true;
    }
    if (focus == 'card' || focus == 'notes') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? target =
            (focus == 'card' ? _cardSectionKey : _notesSectionKey)
                .currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(
            target,
            alignment: 0.05,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
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
    final MatchContact? inquiry = _inquiryContactFor(person, relatedMatches);
    final List<PersonNote> personNotes = personRepository.getNotesForPerson(
      person.id,
    );
    final List<PersonEvent> personEvents = personRepository.getHistoryForPerson(
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
            onPressed: () => ShareUtils.sharePerson(
              person,
              origin: ShareUtils.originOf(context),
            ),
            icon: const Icon(Icons.ios_share_rounded),
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
                  final bool deleted = await DeletePersonFlow.run(
                    context,
                    person,
                  );
                  if (!deleted) {
                    return;
                  }
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
      // Everything below here is drawn in this person's own colour — see
      // [ProfilePersonAccent].
      body: ProfilePersonAccent(
        gender: person.gender,
        child: SafeArea(
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
                onEdit: () async {
                  if (!await confirmEditSyncedCard(context, person)) {
                    return;
                  }
                  setState(() {
                    _editingDetails = true;
                    _editingFullCard = false;
                  });
                },
                onEditingDone: () => setState(() => _editingDetails = false),
                onExtendedEdit: () async {
                  setState(() {
                    _editingDetails = false;
                    _editingFullCard = false;
                  });
                  await _openCardEditPage(context);
                },
              ),
              _ProfilePhotoStrip(
                person: person,
                onOpen: (int index) => PersonCardViewer.open(
                  context,
                  person.id,
                  initialIndex: index,
                ),
              ),
              if (person.hidden)
                _OutsideDatabaseBanner(
                  person: person,
                  onAdd: () => _admitToDatabase(context, person),
                ),
              _ProfileInlineActions(
                person: person,
                inquiry: inquiry,
                whatsappLabel: _firstNameOr(person, 'WhatsApp'),
                onWhatsApp: () => _openWhatsAppMessage(context, person),
                onSms: () => ContactChannels.openSms(person.phone),
                onCompleteCard: () async {
                  if (await confirmEditSyncedCard(context, person)) {
                    setState(() => _editingDetails = true);
                  }
                },
                onMatches: () => _openSuggestions(context, person),
                onAddProposal: () => _openAddProposal(context, person),
              ),
              // Where this card's details come from, and the one next step:
              // ask for access, wait, or invite the friend to write a card.
              CardLinkPanel(person: person),
              // Above the card it is about: most of what a profile needs is
              // already sitting in a WhatsApp chat.
              if (_showShareTip)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: FirstVisitTip(
                    icon: Icons.ios_share_rounded,
                    headline:
                        '{שתף|שתפי} מתוך הווטסאפ תמונה וכמה מילים על '
                                '${person.gender == Gender.female ? 'החברה' : 'החבר'} '
                                'שלך!'
                            .forGender(context.userGender),
                    lines: const <String>[
                      'בווטסאפ: לחיצה ארוכה על התמונה ← שיתוף ← שדכן, ובוחרים '
                          'להוסיף לכרטיס קיים.',
                    ],
                    onDismiss: () => setState(() => _showShareTip = false),
                  ),
                ),
              _WhatsAppCardSection(
                key: _cardSectionKey,
                person: person,
                editing: _editingFullCard,
                expanded: _showFullCard,
                onToggleFull: () {
                  setState(() => _showFullCard = !_showFullCard);
                },
                onEditCard: () async {
                  if (!await confirmEditSyncedCard(context, person)) {
                    return;
                  }
                  setState(() {
                    _editingFullCard = true;
                    _editingDetails = false;
                  });
                },
                onEditingDone: () => setState(() => _editingFullCard = false),
              ),
              // A card with no number of its own, but somebody to ask about
              // it: that person, one tap from WhatsApp, directly under the
              // card — rather than a button asking for details nobody has.
              if (inquiry != null) _InquiryLine(contact: inquiry),
              if (inquiry == null || person.proposalContacts.length > 1)
                _ProposalContactsCard(person: person),
              _PersonalNotesCard(
                key: _notesSectionKey,
                person: person,
                notes: personNotes,
                onShowAll: () => _openPersonNotes(context, person),
                onOpenVoice: (String noteId) =>
                    _openPersonNotes(context, person, focusNoteId: noteId),
              ),
              _IdeasSection(
                person: person,
                matches: relatedMatches,
                personRepository: personRepository,
              ),
              _HistorySection(
                events: personEvents,
                onShowAll: () => _openPersonHistory(context, person),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPersonHistory(BuildContext context, Person person) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ProfilePersonAccent(
          gender: person.gender,
          child: _PersonHistoryPage(personId: person.id),
        ),
      ),
    );
  }

  Future<void> _openSuggestions(BuildContext context, Person person) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ProfilePersonAccent(
          gender: person.gender,
          child: _SuggestionsPage(personId: person.id),
        ),
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
    if (status == ProfileStatus.mazelTov && context.mounted) {
      await offerMazelTovWhatsApp(context, person);
    }

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

  Future<void> _admitToDatabase(BuildContext context, Person person) async {
    await context.read<PersonRepository>().admitToDatabase(person.id);
    if (context.mounted) {
      _showSnackBar(context, 'הכרטיסייה נוספה למאגר שלך');
    }
  }

  Future<void> _openPersonNotes(
    BuildContext context,
    Person person, {
    String? focusNoteId,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return ProfilePersonAccent(
            gender: person.gender,
            child: _PersonNotesPage(
              personId: person.id,
              focusNoteId: focusNoteId,
            ),
          );
        },
      ),
    );
  }

  /// Opens a new idea for this person.
  ///
  /// **There is no question in the way any more.** It used to raise a dialog
  /// asking "מתוך המאגר או מחוץ למאגר" before anything happened, which is a
  /// choice the next screen already offers: the picker lists the candidates who
  /// fit this person, searches the whole database, and carries "הוספת שם מחוץ
  /// למאגר" along its bottom edge. Asking first meant a tap, a decision and a
  /// screen before the matchmaker saw a single name.
  Future<void> _openAddProposal(BuildContext context, Person person) async {
    context.push('/matches/add?preSelectedPersonId=${person.id}&pick=database');
  }

  /// Shares the contact's name and phone on their own, separately from the
  /// candidate's card.
  Future<void> _shareInquiryContact(BuildContext context, Person person) async {
    try {
      final bool shared = await ShareUtils.shareInquiryContact(
        person,
        origin: ShareUtils.originOf(context),
      );
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

  void _showSnackBar(BuildContext context, String message) {
    AppNotice.show(context, message);
  }
}

const Color _profileCanvasLight = AppColors.background;
const Color _profileSurfaceLight = AppColors.surface;
const Color _profileSurfaceWarmLight = AppColors.secondaryLight;
// The page's one accent — what used to be a pale blue on every card, whoever
// it belonged to — is picked per person now. See [ProfilePersonAccent].
const Color _profileTextLight = AppColors.headingInk;
const Color _profileMutedLight = AppColors.mutedInk;

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

/// **Whose card is open, published to the whole page.**
///
/// The profile was drawn in the brand's blue whoever it belonged to: the chips,
/// the links, the rail down the notes, the wash behind the emphasised button —
/// all of it the same pale sky, on a girl's card as much as on a boy's. Every
/// other surface in the app already tells the two apart (the accent bar on a
/// row, the ring round an avatar, the two edges of a proposal card), so the one
/// page that is entirely *about* one person was the one page that would not say
/// which.
///
/// It is an inherited fact rather than a parameter because the colour is wanted
/// a dozen levels down, in chips and rails and counters that have no business
/// knowing whose page they are on — and a page pushed from here (the notes, the
/// history) carries it by being wrapped in one of its own.
class ProfilePersonAccent extends InheritedWidget {
  const ProfilePersonAccent({
    super.key,
    required this.gender,
    required super.child,
  });

  final Gender gender;

  /// Unknown outside a profile, which reads as the app's own blue.
  static Gender of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<ProfilePersonAccent>()
            ?.gender ??
        Gender.unknown;
  }

  @override
  bool updateShouldNotify(covariant ProfilePersonAccent oldWidget) {
    return oldWidget.gender != gender;
  }
}

/// The ink a link or a selected chip on this page is written in — the brand
/// blue on a man's card, the palette's rose on a woman's.
Color _profileAccentColor(BuildContext context) {
  return AppColors.genderAccent(
    ProfilePersonAccent.of(context),
    dark: Theme.of(context).brightness == Brightness.dark,
  );
}

/// The light wash of that same accent: what was `primaryContainer` — the pale
/// blue — everywhere on this page.
Color _profileAccentWash(BuildContext context) {
  return AppColors.genderSurface(
    ProfilePersonAccent.of(context),
    dark: Theme.of(context).brightness == Brightness.dark,
  );
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
    required this.onExtendedEdit,
  });

  final Person person;
  final bool editing;
  final VoidCallback onAvatarTap;
  final ValueChanged<ProfileStatus> onStatusChanged;
  final VoidCallback onEdit;
  final VoidCallback onEditingDone;
  final VoidCallback onExtendedEdit;

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

  /// Adds photos from the avatar circle. They go to the **front**, so the one
  /// just chosen becomes the face on the card — but nothing already there is
  /// dropped.
  ///
  /// This used to pick one photo and overwrite the first slot, which quietly
  /// deleted the existing profile picture: the only way to add a photo without
  /// losing one was the extended editor, and nothing on this control said so.
  Future<void> _pickPrimaryPhoto() async {
    final List<String> paths = await PhotoPickerService.pickPhotos(
      context,
      personId: widget.person.id,
    );
    if (paths.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _newPhotoPaths.addAll(paths);
      _photoPaths = <String>[...paths, ..._photoPaths];
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
    AppNotice.show(context, message);
  }

  void _cancel() {
    _resetDraft();
    widget.onEditingDone();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String summary = _personSummary(widget.person);
    final List<ReligiousLevelChoice> religiousChoices = <ReligiousLevelChoice>[
      for (final ReligiousLevel level in ReligiousLevels.global)
        ReligiousLevelChoice(level),
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
                              tooltip: 'הוספת תמונות',
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
              // Everything the quick edit does not cover — phone included —
              // lives one tap away in the full card editor. Offering it right
              // here as well as in the top-left menu means the matchmaker who
              // opened this editor to change a detail it does not hold never
              // has to go looking for where that detail lives.
              if (widget.editing) ...<Widget>[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _saving ? null : widget.onExtendedEdit,
                  icon: const Icon(Icons.edit_note_outlined, size: 18),
                  label: const Text('עריכה מורחבת'),
                  style: TextButton.styleFrom(
                    foregroundColor: _profileMutedColor(theme),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _ProfileStatusSwitcher(
                status: widget.person.profileStatus,
                gender: widget.person.gender,
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

/// Shown on a card that is not in המאגר שלי yet — the state
/// "הוספת שם מחוץ למאגר" leaves a person in when the matchmaker answers
/// "לא עכשיו".
///
/// It exists because that state was previously invisible *and* permanent: the
/// card worked, it could be put in a proposal, and it simply never appeared in
/// any list. Filling in a detail now admits it on its own; this says so, and
/// offers the one tap for somebody who wants it in with nothing filled at all.
/// Every other photo on the card, under the face at the top of the profile.
///
/// The header shows one photo and it is round, so until now the second, third
/// and fourth pictures of somebody existed only inside the full-screen viewer
/// — which had to be guessed at, because nothing on the profile said there was
/// more than one. The strip says so, and a tap opens that photo full screen
/// with the card still under it.
///
/// Draws nothing when there is only the face, and nothing at all when the
/// files behind the paths are gone — a row of broken-image boxes says less
/// than no row.
class _ProfilePhotoStrip extends StatelessWidget {
  const _ProfilePhotoStrip({required this.person, required this.onOpen});

  final Person person;

  /// Called with the photo's index in `person.photosPaths`, so the viewer can
  /// open on the one that was tapped.
  final ValueChanged<int> onOpen;

  static const double _height = 96;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Indexed against the person's own list, not against the filtered one:
    // the viewer pages over the same "files that exist" list, so a missing
    // file in the middle must shift the rest here too.
    final List<({int index, String path})> photos =
        <({int index, String path})>[];
    for (final String path in person.photosPaths) {
      if (!File(path).existsSync()) {
        continue;
      }
      photos.add((index: photos.length, path: path));
    }

    // The first photo is the face at the top of the page; this row is the rest.
    if (photos.length < 2) {
      return const SizedBox.shrink();
    }
    final List<({int index, String path})> rest = photos.sublist(1);

    return Container(
      color: _profileCanvasColor(theme),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
            child: Text(
              'תמונות נוספות',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: _profileMutedColor(theme),
              ),
            ),
          ),
          SizedBox(
            height: _height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: rest.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int position) {
                final ({int index, String path}) photo = rest[position];
                return GestureDetector(
                  onTap: () => onOpen(photo.index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(photo.path),
                      width: _height,
                      height: _height,
                      cacheWidth: (_height * 3).round(),
                      fit: BoxFit.cover,
                      errorBuilder:
                          (BuildContext context, Object _, StackTrace? _) {
                            return Container(
                              width: _height,
                              height: _height,
                              color: _profileWarmSurfaceColor(theme),
                            );
                          },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OutsideDatabaseBanner extends StatelessWidget {
  const _OutsideDatabaseBanner({required this.person, required this.onAdd});

  final Person person;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = AppColors.genderAccent(
      person.gender,
      dark: theme.brightness == Brightness.dark,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.person_add_alt_outlined, size: 20, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'הכרטיסייה הזו עדיין לא במאגר שלך. היא תתווסף אליו '
                'ברגע שיתמלא בה פרט כלשהו.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _profileTextColor(theme),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(foregroundColor: accent),
              child: const Text('הוספה למאגר'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who to ask about [person] when they have a card but no number of their
/// own: their own "איש קשר להעברת הצעות" first, then anybody attached to one
/// of their ideas. Null when they can be written to directly, have no card,
/// or nobody with a number is around them.
MatchContact? _inquiryContactFor(Person person, List<MatchIdea> matches) {
  if (ContactChannels.forPerson(person) != ContactChannel.none ||
      !hasCandidateCard(person)) {
    return null;
  }
  bool reachable(MatchContact contact) =>
      PhoneUtils.toWhatsAppNumber(contact.phone) != null;
  for (final MatchContact contact in person.proposalContacts) {
    if (reachable(contact)) {
      return contact;
    }
  }
  for (final MatchIdea match in matches) {
    for (final MatchContact contact in match.relatedContacts) {
      if (reachable(contact)) {
        return contact;
      }
    }
  }
  return null;
}

/// "איש קשר להעברת ההצעה: רבקה כהן" with a WhatsApp button beside the name.
class _InquiryLine extends StatelessWidget {
  const _InquiryLine({required this.contact});

  final MatchContact contact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = contact.name.trim().isEmpty
        ? contact.phone.trim()
        : contact.name.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              'להעברת ההצעה: $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: _profileTextColor(theme),
              ),
            ),
          ),
          IconButton(
            tooltip: 'WhatsApp עם $name',
            visualDensity: VisualDensity.compact,
            onPressed: () => WhatsAppUtils.openChatWithPhone(contact.phone),
            icon: const FaIcon(
              FontAwesomeIcons.whatsapp,
              size: 18,
              color: Color(0xFF25D366),
            ),
          ),
        ],
      ),
    );
  }
}

/// The profile's three primary actions, placed in the scrolling content so the
/// app-level bottom navigation remains the only persistent bottom bar.
class _ProfileInlineActions extends StatelessWidget {
  const _ProfileInlineActions({
    required this.person,
    this.inquiry,
    required this.whatsappLabel,
    required this.onWhatsApp,
    required this.onSms,
    required this.onCompleteCard,
    required this.onMatches,
    required this.onAddProposal,
  });

  final Person person;

  /// Somebody to ask about a card with no number — see [_inquiryContactFor].
  /// When there is one, "השלמת פרטים" is not offered: the line under the card
  /// is the way to reach them.
  final MatchContact? inquiry;
  final String whatsappLabel;
  final VoidCallback onWhatsApp;
  final VoidCallback onSms;
  final VoidCallback onCompleteCard;
  final VoidCallback onMatches;
  final VoidCallback onAddProposal;

  @override
  Widget build(BuildContext context) {
    // The first action follows the number, not the app's favourite messenger.
    final ({Widget icon, String label, VoidCallback onTap, Color? ink})
    messaging = switch (ContactChannels.forPerson(person)) {
      ContactChannel.whatsapp => (
        icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 21),
        label: whatsappLabel,
        onTap: onWhatsApp,
        ink: _whatsappGreen,
      ),
      ContactChannel.sms => (
        icon: const Icon(Icons.sms_outlined, size: 21),
        label: 'הודעה',
        onTap: onSms,
        ink: _profileAccentColor(context),
      ),
      ContactChannel.none => (
        icon: const Icon(Icons.edit_outlined, size: 20),
        label: 'השלמת פרטים',
        onTap: onCompleteCard,
        ink: null,
      ),
    };

    final bool showMessaging =
        inquiry == null ||
        ContactChannels.forPerson(person) != ContactChannel.none;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Row(
        children: <Widget>[
          if (showMessaging) ...<Widget>[
            Expanded(
              child: _ProfileActionButton(
                icon: messaging.icon,
                label: messaging.label,
                onPressed: messaging.onTap,
                foregroundColor: messaging.ink,
              ),
            ),
            const SizedBox(width: 8),
          ],
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
              label: 'הוספת רעיון',
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
          ? _profileAccentWash(context)
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
                  ? _profileAccentColor(context).withValues(alpha: 0.30)
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
              'איש קשר להעברת ההצעה',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: _profileTextColor(theme),
              ),
            ),
            Text(
              'מישהו שמכיר ${person.gender == Gender.female ? 'אותה' : 'אותו'} '
              'אישית ויכול לחבר ביניכם',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _profileMutedColor(theme),
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
    super.key,
    required this.person,
    required this.notes,
    required this.onShowAll,
    required this.onOpenVoice,
  });

  final Person person;
  final List<PersonNote> notes;
  final VoidCallback onShowAll;

  /// Opens the notes page on one recording, scrolled to it.
  final ValueChanged<String> onOpenVoice;

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
                      color: _profileAccentWash(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      entries.length.toString(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _profileAccentColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.mic_none_rounded),
                  tooltip: 'הקלטת הערה',
                  visualDensity: VisualDensity.compact,
                  color: muted,
                  onPressed: () => recordVoiceNote(context, person.id),
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
            // A recording that already exists is nearly always sitting in a
            // WhatsApp chat with this friend. One tap there, and the share
            // sheet brings it back here.
            if (PhoneUtils.toWhatsAppNumber(person.phone) != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _shareVoiceFromWhatsApp(context, person),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    foregroundColor: muted,
                    textStyle: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const FaIcon(
                    FontAwesomeIcons.whatsapp,
                    size: 14,
                    color: _whatsappGreen,
                  ),
                  label: const Text('שתף ושמור הקלטה קיימת מ־WhatsApp'),
                ),
              ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
                child: Text(
                  // "רק לעיניך" is a promise about notes that exist. With none
                  // written it is reassurance nobody asked for, in front of an
                  // empty box.
                  'עדיין אין הערות. {הוסף|הוסיפי} משהו {שתרצה|שתרצי} לזכור.'
                      .forGender(context.userGender),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              )
            else
              for (final _PersonNoteEntry entry in preview)
                _NotePreviewRow(
                  entry: entry,
                  onTap: () => entry.isVoice && entry.noteId != null
                      ? onOpenVoice(entry.noteId!)
                      : _showNoteReader(context, person, entry),
                  // Deleting a recording is a long press and nothing else — a
                  // tap on a row is for listening, never for losing it.
                  onLongPress: entry.isVoice
                      ? () => _confirmDeleteVoice(context, entry)
                      : null,
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
        audioFile: note.audioFile,
        audioDurationMs: note.audioDurationMs,
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
            decoration: const InputDecoration(hintText: 'משהו שחשוב לזכור...'),
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

/// The first [count] words of [text], with an ellipsis when there is more.
String _firstWords(String text, int count) {
  final List<String> words = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  if (words.length <= count) {
    return text.trim();
  }
  return '${words.take(count).join(' ')}…';
}

/// Opens WhatsApp on this friend's chat, where the recording already is,
/// after one line saying what to do there.
Future<void> _shareVoiceFromWhatsApp(
  BuildContext context,
  Person person,
) async {
  final bool? go = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('שמירת הקלטה מ־WhatsApp'),
      content: const Text(
        'בצ׳אט: לחיצה ארוכה על ההקלטה ← שיתוף ← שדכן. ההקלטה תישמר '
        'בהערות של החבר.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('ביטול'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
          label: const Text('לצ׳אט'),
        ),
      ],
    ),
  );
  if (go != true) {
    return;
  }
  final bool opened = await WhatsAppUtils.openChatWithPhone(person.phone);
  if (!opened && context.mounted) {
    AppNotice.show(context, 'לא הצלחנו לפתוח את וואטסאפ');
  }
}

/// Asks, then deletes one recording. Only ever reached by a long press.
Future<void> _confirmDeleteVoice(
  BuildContext context,
  _PersonNoteEntry entry,
) async {
  final String? id = entry.noteId;
  if (id == null) {
    return;
  }
  final PersonRepository repository = context.read<PersonRepository>();
  final bool confirmed = await ConfirmDialog.show(
    context,
    title: 'מחיקת הקלטה',
    message: 'למחוק את ההקלטה?',
    confirmText: 'מחיקה',
    isDestructive: true,
  );
  if (confirmed) {
    await repository.deleteNote(id);
  }
}

/// One note, large and quiet, to be read rather than edited.
///
/// **A tap on a note reads it.** It used to open straight into a small
/// scrolling dialog already in edit mode, so reading a long note meant
/// scrolling a text field with the keyboard up and a cursor in it. Now the
/// whole note is laid out at a comfortable size, and editing is one small
/// pencil in the corner.
Future<void> _showNoteReader(
  BuildContext context,
  Person person,
  _PersonNoteEntry entry,
) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      final ThemeData theme = Theme.of(dialogContext);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        backgroundColor: _profileSurfaceColor(theme),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        DateFormat(
                          'dd.MM.yyyy · HH:mm',
                        ).format(entry.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _profileMutedColor(theme),
                        ),
                      ),
                    ),
                    if (!entry.isAutomatic)
                      IconButton(
                        tooltip: 'עריכת ההערה',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        color: _profileMutedColor(theme),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await _editPersonNote(context, person, entry);
                        },
                      ),
                    IconButton(
                      tooltip: 'סגירה',
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      color: _profileMutedColor(theme),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: SelectableText(
                      entry.text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 18,
                        height: 1.65,
                        color: _profileTextColor(theme),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The note's editor: the text, "שמירה", and the way to delete it.
Future<void> _editPersonNote(
  BuildContext context,
  Person person,
  _PersonNoteEntry entry,
) async {
  if (entry.isAutomatic || entry.isVoice) {
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
            onPressed: () =>
                Navigator.of(dialogContext).pop(const _NoteEditResult.delete()),
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

/// Result of the inline note editor: either a saved text or a delete request.
class _NoteEditResult {
  const _NoteEditResult.save(this.text) : delete = false;
  const _NoteEditResult.delete() : text = '', delete = true;

  final String text;
  final bool delete;
}

/// A single compact note item in the inline preview: the first twenty words
/// of a written note, or a recording with its caption.
class _NotePreviewRow extends StatelessWidget {
  const _NotePreviewRow({
    required this.entry,
    required this.onTap,
    this.onLongPress,
  });

  final _PersonNoteEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// How much of a written note the profile shows before the tap.
  static const int previewWords = 20;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = _profileMutedColor(theme);
    final String caption = entry.text.trim();

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Icon(
                entry.isVoice
                    ? Icons.mic_none_rounded
                    : entry.isAutomatic
                    ? Icons.auto_awesome_outlined
                    : Icons.circle,
                size: entry.isVoice || entry.isAutomatic ? 14 : 7,
                color: muted,
              ),
            ),
            const SizedBox(width: 10),
            if (entry.isVoice)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    VoiceNotePlayer(
                      fileName: entry.audioFile!,
                      durationMs: entry.audioDurationMs,
                      compact: true,
                    ),
                    if (caption.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              Expanded(
                child: Text(
                  _firstWords(entry.text, previewWords),
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
    required this.gender,
    required this.onStatusChanged,
  });

  final ProfileStatus status;

  /// Whose card this is: the tag is written in their own colour — see
  /// [ProfileStatusTag].
  final Gender gender;

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
    final Color statusColor = AppColors.genderAccent(
      widget.gender,
      dark: Theme.of(context).brightness == Brightness.dark,
    );

    // **The word and a small arrow, nothing drawn round them.** It was a
    // tinted, framed pill — one more box on a page of boxes — for what is a
    // single word the matchmaker can tap to change.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _StatusWord(status: widget.status, gender: widget.gender),
                const SizedBox(width: 2),
                // After the word, which in RTL is its left.
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
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
                        child: _StatusWord(
                          status: status,
                          gender: widget.gender,
                        ),
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

/// "פנויה" / "תפוס" / "בהפסקה" — the word alone, in the state's own colour
/// and the person's own grammatical gender, exactly as the idea cards write it.
class _StatusWord extends StatelessWidget {
  const _StatusWord({required this.status, required this.gender});

  final ProfileStatus status;
  final Gender gender;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      status.displayNameFor(gender),
      maxLines: 1,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.profileStatusColor(status),
      ),
    );
  }
}

/// Inline preview of the person's send-card. Its quick edit mode keeps this
/// exact surface in place and swaps only the text for an editor.
class _WhatsAppCardSection extends StatefulWidget {
  const _WhatsAppCardSection({
    super.key,
    required this.person,
    required this.editing,
    required this.expanded,
    required this.onToggleFull,
    required this.onEditCard,
    required this.onEditingDone,
  });

  final Person person;
  final bool editing;
  final bool expanded;
  final VoidCallback onToggleFull;
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
            // Reading, the body only gives up its end-side corner to the
            // pencil. Editing, it gives up a *lane above itself* instead: two
            // controls side by side in the end-side inset would have taken 80
            // of the card's ~300 points away from the field, which is the one
            // thing on this card that wants every point it can get.
            Padding(
              key: ValueKey<String>(
                'candidate-full-card-body-${widget.person.id}',
              ),
              padding: widget.editing
                  ? const EdgeInsetsDirectional.only(top: 26)
                  : const EdgeInsetsDirectional.only(end: 38),
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
                        // One action where there used to be two: the
                        // invitation to write a card of their own. A friend who
                        // already keeps one is offered access instead, by the
                        // card panel above — see [CardInviteFlow].
                        CardInviteButton(
                          person: widget.person,
                          onlyInvite: true,
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

/// Which of the three shelves an idea sits on, and in what order they are read.
///
/// **Coarser than [MatchStatus], and ordered by usefulness rather than by the
/// enum.** A matchmaker opening somebody's page is looking for what is live
/// first, then for what is parked, and only then for what is over — so that is
/// the order, and every stored status is folded onto one of the three. It is
/// the same fold [MatchStatus.stateLabel] makes for the chip, one step
/// coarser: "יוצאים" is an idea that is very much open.
enum _IdeaGroup {
  open('פתוחות'),
  waiting('בהמתנה'),
  closed('סגורות');

  const _IdeaGroup(this.label);

  final String label;

  static _IdeaGroup of(MatchStatus status) {
    switch (status) {
      case MatchStatus.idea:
      case MatchStatus.checking:
      case MatchStatus.dating:
        return _IdeaGroup.open;
      case MatchStatus.unavailable:
        return _IdeaGroup.waiting;
      case MatchStatus.rejected:
      case MatchStatus.dated:
      case MatchStatus.married:
        return _IdeaGroup.closed;
    }
  }
}

/// The inline "רעיונות" section on the profile page: **every** idea ever opened
/// for this person, with the status of each.
///
/// **It used to be "הצעות פתוחות", and that was the wrong half.** A closed idea
/// is the single most useful thing on this page when the question is "have we
/// already tried this?" — and it was the one thing the profile would not say.
/// Somebody who had been turned down twice looked identical to somebody nobody
/// had ever thought of, and the only way to tell them apart was to go to
/// רעיונות and search the name.
///
/// So the whole history is here, ordered פתוחות → בהמתנה → סגורות, which is the
/// order the question is actually asked in. Within a shelf the most recently
/// touched comes first.
///
/// **Five, and then a chevron.** A prolific candidate can carry twenty ideas,
/// and twenty rows in the middle of a profile is a second screen wedged into
/// the first. Five is enough to show the whole of a normal person's history and
/// enough of a busy one's to see the shape of it; the rest is one tap away and
/// stays open once it has been asked for.
///
/// The filter above them is drawn only when there is more than one shelf to
/// choose between — a chip row offering to narrow three rows down to three rows
/// is furniture.
class _IdeasSection extends StatefulWidget {
  const _IdeasSection({
    required this.person,
    required this.matches,
    required this.personRepository,
  });

  final Person person;

  /// Every idea this person is a side of, open or not.
  final List<MatchIdea> matches;

  final PersonRepository personRepository;

  @override
  State<_IdeasSection> createState() => _IdeasSectionState();
}

class _IdeasSectionState extends State<_IdeasSection> {
  /// How many rows are shown before the chevron.
  static const int _collapsedCount = 5;

  /// Null is "הכל".
  _IdeaGroup? _filter;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.matches.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);

    // פתוחות, then בהמתנה, then סגורות; newest first inside each.
    final List<MatchIdea> ordered = List<MatchIdea>.from(widget.matches)
      ..sort((MatchIdea a, MatchIdea b) {
        final int byGroup = _IdeaGroup.of(
          a.status,
        ).index.compareTo(_IdeaGroup.of(b.status).index);
        return byGroup != 0 ? byGroup : b.updatedAt.compareTo(a.updatedAt);
      });

    final Set<_IdeaGroup> present = <_IdeaGroup>{
      for (final MatchIdea match in ordered) _IdeaGroup.of(match.status),
    };
    // A filter that was chosen and then emptied — the last open idea was
    // closed while the page was on screen — falls back to הכל rather than to a
    // section that looks broken.
    final _IdeaGroup? filter = present.contains(_filter) ? _filter : null;

    final List<MatchIdea> shelf = filter == null
        ? ordered
        : ordered
              .where((MatchIdea m) => _IdeaGroup.of(m.status) == filter)
              .toList();
    final bool collapsible = shelf.length > _collapsedCount;
    final List<MatchIdea> shown = collapsible && !_expanded
        ? shelf.take(_collapsedCount).toList()
        : shelf;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Text(
              'רעיונות (${ordered.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                color: _profileTextColor(theme),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (present.length > 1) ...<Widget>[
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                children: <Widget>[
                  _IdeaFilterChip(
                    label: 'הכל',
                    selected: filter == null,
                    onTap: () => setState(() {
                      _filter = null;
                      _expanded = false;
                    }),
                  ),
                  for (final _IdeaGroup group in _IdeaGroup.values)
                    if (present.contains(group))
                      _IdeaFilterChip(
                        label: group.label,
                        selected: filter == group,
                        onTap: () => setState(() {
                          _filter = group;
                          _expanded = false;
                        }),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
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
                for (int index = 0; index < shown.length; index++) ...<Widget>[
                  _IdeaRow(
                    match: shown[index],
                    person: widget.person,
                    otherPerson: widget.personRepository.getById(
                      shown[index].personAId == widget.person.id
                          ? shown[index].personBId
                          : shown[index].personAId,
                    ),
                  ),
                  if (index + 1 < shown.length)
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: _profileMutedColor(theme).withValues(alpha: 0.12),
                    ),
                ],
                if (collapsible) ...<Widget>[
                  Divider(
                    height: 1,
                    indent: 14,
                    endIndent: 14,
                    color: _profileMutedColor(theme).withValues(alpha: 0.12),
                  ),
                  _IdeaExpander(
                    expanded: _expanded,
                    hidden: shelf.length - _collapsedCount,
                    onTap: () => setState(() => _expanded = !_expanded),
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

/// One shelf of the filter row.
class _IdeaFilterChip extends StatelessWidget {
  const _IdeaFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = _profileAccentColor(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.14)
            : _profileSurfaceColor(theme),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? accent.withValues(alpha: 0.55)
                : _profileMutedColor(theme).withValues(alpha: 0.20),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: selected ? accent : _profileMutedColor(theme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The last row of the list when there is more of it: how much is hidden, and
/// a chevron that turns over.
class _IdeaExpander extends StatelessWidget {
  const _IdeaExpander({
    required this.expanded,
    required this.hidden,
    required this.onTap,
  });

  final bool expanded;

  /// How many rows the collapsed list is not showing.
  final int hidden;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  expanded ? 'הצגה מקוצרת' : 'עוד $hidden רעיונות',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _profileAccentColor(context),
                  ),
                ),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: _profileAccentColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One compact idea row: the other side, where the idea stands, and a single
/// WhatsApp shortcut for that other side.
class _IdeaRow extends StatelessWidget {
  const _IdeaRow({
    required this.match,
    required this.otherPerson,
    required this.person,
  });

  final MatchIdea match;
  final Person? otherPerson;

  /// Whose profile this is — the other half of the idea.
  final Person person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String otherName = otherPerson?.fullName.trim().isNotEmpty == true
        ? otherPerson!.fullName.trim()
        : 'אדם נמחק';
    final Person? other = otherPerson;
    // Both cards together, for an idea that is still open and has at least one
    // card worth sending.
    final bool canShareBoth =
        !match.status.isArchived &&
        other != null &&
        (ShareUtils.hasShareableCard(person) ||
            ShareUtils.hasShareableCard(other));

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
              if (canShareBoth)
                Builder(
                  builder: (BuildContext buttonContext) => IconButton(
                    tooltip: 'שיתוף שני הכרטיסים',
                    iconSize: 18,
                    constraints: const BoxConstraints.tightFor(
                      width: 38,
                      height: 38,
                    ),
                    padding: EdgeInsets.zero,
                    color: _profileMutedColor(theme),
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => ShareUtils.shareCouple(
                      person,
                      other,
                      origin: ShareUtils.originOf(buttonContext),
                    ),
                  ),
                ),
              if (otherPerson != null)
                ContactChannelButton(
                  person: otherPerson!,
                  size: 18,
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  onWhatsApp: () => _openWhatsApp(context, otherPerson!),
                  onEdit: () => openPersonProfile(
                    context,
                    otherPerson!.id,
                    editing: true,
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
      AppNotice.show(context, 'אין מספר טלפון תקין לפתיחת וואטסאפ');
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
    // Taken before the dialog goes up, so closing the comparison and opening a
    // profile is one gesture on the navigator the caller lives in rather than
    // on the dialog's own route.
    final NavigatorState navigator = Navigator.of(context);

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
                          'השוואת כרטיסים',
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
                Expanded(
                  child: _MatchPreviewHalf(
                    person: source,
                    onOpenProfile: () =>
                        _openProfile(dialogContext, navigator, source.id),
                  ),
                ),
                Divider(
                  height: 1,
                  color: _profileMutedColor(theme).withValues(alpha: 0.2),
                ),
                Expanded(
                  child: _MatchPreviewHalf(
                    person: candidate,
                    onOpenProfile: () =>
                        _openProfile(dialogContext, navigator, candidate.id),
                  ),
                ),
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

  /// Closes the comparison and lands on that person's own card.
  ///
  /// Popped first and pushed second, rather than pushing the profile over the
  /// dialog: a page under a dialog is a page nobody can scroll, and coming back
  /// from the profile should return to the list the comparison was opened from
  /// — not to a comparison of two cards that has already been answered.
  static void _openProfile(
    BuildContext dialogContext,
    NavigatorState navigator,
    String personId,
  ) {
    Navigator.of(dialogContext).pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            PersonDetailScreen(personId: personId),
      ),
    );
  }
}

/// One half of the match preview: a person's photos, name, summary and their
/// full send-card text, scrolling on its own.
///
/// **The whole half is a way into that person's card.** While two people are
/// side by side, the question that comes up most is "רגע, מי זה?" — and until
/// this was tappable the only answer was to close the comparison, find the
/// person in a list and open them, by which point the pair being weighed up was
/// gone. Tapping anywhere on a half now closes the comparison and opens that
/// person; the chevron by the name says so without adding a control.
class _MatchPreviewHalf extends StatelessWidget {
  const _MatchPreviewHalf({required this.person, required this.onOpenProfile});

  final Person person;

  /// Opens [person]'s profile. Both halves have one — either side is a door.
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String description = (person.description ?? '').trim();
    final List<String> photos = person.photosPaths
        .where((String path) => File(path).existsSync())
        .toList();

    return GestureDetector(
      // Opaque so a tap on the padding — the empty space either side of the
      // text — counts too, and `behavior` rather than an `InkWell` so the
      // photo carousel inside keeps its own swipe.
      behavior: HitTestBehavior.opaque,
      onTap: onOpenProfile,
      child: SingleChildScrollView(
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
                // `chevron_right` and not `chevron_left`: Material's directional
                // icons mirror themselves, so in this RTL app this is the one
                // that points the way the tap goes.
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: _profileMutedColor(theme),
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
                // The photo is the largest thing on the half and the thing a
                // finger actually lands on, so it opens the card too. A
                // `GestureDetector` further out cannot see it — the pager
                // claims the area — which left the one obvious target as the
                // one dead spot.
                onTap: onOpenProfile,
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
            if (description.isEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: CardInviteButton(person: person, dense: true),
              ),
            ],
          ],
        ),
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

  /// Whether the list is narrowed to the candidate's *extended* filter — the
  /// height, city, region, marital status and age range recorded under "עריכה
  /// מורחבת".
  ///
  /// **Off by default, and that is the change.** The list used to open on the
  /// extended answer, which meant a card that had been filled in properly was
  /// punished for it: everybody with no height recorded vanished, and a page
  /// headed "התאמות" showed four people out of six hundred with nothing on
  /// screen explaining why. The default is the basic filter — gender, age,
  /// religious style — and this is one tap away above the list, on the cards
  /// that actually have something extended to apply.
  bool _extendedFilter = false;

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
    // Only offered where it would actually change the list. A card with
    // nothing extended recorded narrows to exactly the same people, and a
    // toggle that does nothing is worse than no toggle.
    final bool canNarrow =
        savedSuggestionFilters == null &&
        MatchSuggestionUtils.hasExtendedPreferences(person);
    final List<Person> matchingCandidates = personRepository
        .getAll()
        .where(
          (Person candidate) => _matchesSuggestionFilters(
            source: person,
            candidate: candidate,
            filters: savedSuggestionFilters,
            extended: canNarrow && _extendedFilter,
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
                      canNarrow: canNarrow,
                      narrowed: _extendedFilter,
                      onNarrowChanged: (bool value) =>
                          setState(() => _extendedFilter = value),
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
    required bool extended,
  }) {
    if (filters == null) {
      // Everybody who fits the basics by default; everything on the card only
      // when "סינון מורחב" is on. See [_extendedFilter].
      return extended
          ? MatchSuggestionUtils.matchesOwnPreferences(
              source: source,
              candidate: candidate,
            )
          : MatchSuggestionUtils.matchesBasicPreferences(
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

    if (!MatchProposalFilters.matchesHeight(candidate, filters)) {
      return false;
    }
    if (filters.maritalStatuses.isNotEmpty &&
        !filters.maritalStatuses.contains(candidate.maritalStatus)) {
      return false;
    }
    if (!MatchProposalFilters.matchesRegion(candidate, filters)) {
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

  /// What the filter sheet opens showing when nothing has been saved by hand:
  /// **everything the automatic filter is already applying.**
  ///
  /// This used to carry the age range and the religious styles alone, while
  /// `MatchSuggestionUtils.matchesOwnPreferences` was quietly also filtering on
  /// height and marital status. The result was a sheet that looked blank on a
  /// list that was anything but — somebody opening it to loosen one rule was
  /// shown a form that implied nothing was set, and confirming it changed the
  /// list for reasons they never saw. Everything the sheet can show, it now
  /// shows.
  ///
  /// Once a matchmaker has saved their own filters, those win: the sheet reads
  /// them itself in `MatchProposalFilterSheet.show`, and this is only the
  /// fallback.
  MatchProposalFilters _defaultSuggestionFilters(Person sourcePerson) {
    final MatchPreferences preferences = MatchPreferences.forPerson(
      sourcePerson,
    );
    // The age range the card sets, and where it sets none, the default the
    // automatic list already uses — for a woman as well as for a man, so the
    // sheet never opens blank on a list that is filtered by age.
    final ({int minAge, int maxAge})? defaultAgeRange =
        switch (sourcePerson.gender) {
          Gender.male => MatchSuggestionUtils.femaleAgeRangeForMale(
            sourcePerson.age,
          ),
          Gender.female => MatchSuggestionUtils.maleAgeRangeForFemale(
            sourcePerson.age,
          ),
          Gender.unknown => null,
        };

    return MatchProposalFilters(
      minAge: preferences.minAge ?? defaultAgeRange?.minAge,
      maxAge: preferences.maxAge ?? defaultAgeRange?.maxAge,
      minHeight: preferences.minHeightCm,
      maxHeight: preferences.maxHeightCm,
      maritalStatuses: preferences.maritalStatuses,
      regions: preferences.regions,
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
      title: 'הוספת רעיון',
      message:
          'האם לפתוח רעיון בין ${sourcePerson.fullName.trim()} '
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
      message: 'ההתאמה תעבור לסוף הרשימה אצל שני הצדדים, ולא תוצע שוב.',
      confirmText: 'לא מתאים',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    // The candidate drops to the end of the suggestions list on *both* cards
    // and stops being offered by the database. No rejected proposal is created,
    // so the pair never shows up under רעיונות שנשללו — this is a decision
    // about a suggestion, not about an idea that was ever opened.
    await SuggestionDismissals.dismiss(sourcePerson.id, candidate.id);
    await SuggestionDismissals.dismiss(candidate.id, sourcePerson.id);
    if (mounted) {
      setState(() {});
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    AppNotice.show(context, message);
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
/// automatic filter. Tapping one opens the match preview overlay, and anybody
/// with a card carries the same expander the suggestions list does.
class _SearchResultsList extends StatefulWidget {
  const _SearchResultsList({
    required this.results,
    required this.onOpenPreview,
  });

  final List<Person> results;
  final ValueChanged<Person> onOpenPreview;

  @override
  State<_SearchResultsList> createState() => _SearchResultsListState();
}

class _SearchResultsListState extends State<_SearchResultsList> {
  final Set<String> _expandedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    if (widget.results.isEmpty) {
      return const _TabEmptyState(
        icon: Icons.search_off,
        title: 'לא נמצאו תוצאות',
        subtitle: 'אפשר לנסות שם אחר',
      );
    }

    final ThemeData theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
      itemCount: widget.results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final Person candidate = widget.results[index];
        final bool hasCard = hasCandidateCard(candidate);
        final bool expanded = _expandedIds.contains(candidate.id);

        return Material(
          color: _profileSurfaceColor(theme),
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: <Widget>[
              InkWell(
                onTap: () => widget.onOpenPreview(candidate),
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
                      if (hasCard) ...<Widget>[
                        CandidateCardButton(
                          expanded: expanded,
                          onPressed: () => setState(() {
                            if (!_expandedIds.remove(candidate.id)) {
                              _expandedIds.add(candidate.id);
                            }
                          }),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Icon(
                        Icons.chevron_right,
                        color: _profileMutedColor(theme),
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: CandidateQuickCard(
                    candidate: candidate,
                    surfaceColor: _profileWarmSurfaceColor(theme),
                    textColor: _profileTextColor(theme),
                  ),
                ),
            ],
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
    required this.canNarrow,
    required this.narrowed,
    required this.onNarrowChanged,
    required this.onFilterPressed,
    required this.onOpenPreview,
    required this.onAccept,
    required this.onReject,
  });

  final Person sourcePerson;
  final List<Person> suggestedPeople;
  final MatchRepository matchRepository;
  final bool hasCustomFilters;
  final bool canNarrow;
  final bool narrowed;
  final ValueChanged<bool> onNarrowChanged;
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
          canNarrow: canNarrow,
          narrowed: narrowed,
          onNarrowChanged: onNarrowChanged,
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
          canNarrow: canNarrow,
          narrowed: narrowed,
          onNarrowChanged: onNarrowChanged,
          onFilterPressed: onFilterPressed,
        ),
        child: _TabEmptyState(
          icon: Icons.favorite_border,
          title: 'לא נמצאו התאמות',
          subtitle: hasCustomFilters
              ? 'אפשר לשנות את הסינון ולנסות שוב'
              : narrowed
              ? 'אף אחד לא עומד בסינון המורחב — אפשר לכבות אותו למעלה'
              : 'אין כרגע אנשים שעומדים בסינון האוטומטי',
        ),
      );
    }

    return Column(
      children: <Widget>[
        _SuggestionFilterHeader(
          count: suggestedPeople.length,
          hasCustomFilters: hasCustomFilters,
          canNarrow: canNarrow,
          narrowed: narrowed,
          onNarrowChanged: onNarrowChanged,
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

  /// Where each card-less candidate stands with a card of their own, worked
  /// out once per visit — see [CardInviteFlow].
  final Map<String, Future<CardInviteState>> _inviteStates =
      <String, Future<CardInviteState>>{};

  Future<CardInviteState> _inviteStateFor(Person candidate) {
    return _inviteStates.putIfAbsent(
      candidate.id,
      () => CardInviteFlow.stateFor(
        context.read<CardAccessProvider>(),
        candidate,
      ),
    );
  }

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
        final bool hasCard = hasCandidateCard(candidate);
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
                        onTap: () => openPersonProfile(context, candidate.id),
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
                    ],
                  ),
                ),
              ),
              // The three answers, drawn by hand, under the person they are
              // about: the card, the idea, or not suitable.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                // No card to open: the first answer becomes the invitation to
                // write one — or, for a friend who keeps one already, the
                // request for access to it.
                child: hasCard
                    ? SketchActionBar(
                        compact: true,
                        fullCardExpanded: expanded,
                        onFullCard: () => setState(() {
                          if (!_expandedIds.remove(candidate.id)) {
                            _expandedIds.add(candidate.id);
                          }
                        }),
                        onOpenIdea: () => widget.onAccept(candidate),
                        onNotSuitable: () => widget.onReject(candidate),
                      )
                    : FutureBuilder<CardInviteState>(
                        future: _inviteStateFor(candidate),
                        builder:
                            (
                              BuildContext context,
                              AsyncSnapshot<CardInviteState> snapshot,
                            ) {
                              final CardInviteState state =
                                  snapshot.data ?? CardInviteState.noCard;
                              final String? label = CardInviteFlow.labelFor(
                                state,
                              );
                              return SketchActionBar(
                                compact: true,
                                fullCardLabel: label ?? 'להזמין למלא כרטיס',
                                onFullCard:
                                    state == CardInviteState.pending ||
                                        label == null
                                    ? null
                                    : () async {
                                        await CardInviteFlow.run(
                                          context,
                                          candidate,
                                        );
                                        if (mounted) {
                                          setState(
                                            () => _inviteStates.remove(
                                              candidate.id,
                                            ),
                                          );
                                        }
                                      },
                                onOpenIdea: () => widget.onAccept(candidate),
                                onNotSuitable: () => widget.onReject(candidate),
                              );
                            },
                      ),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: CandidateQuickCard(
                    candidate: candidate,
                    surfaceColor: _profileWarmSurfaceColor(theme),
                    textColor: _profileTextColor(theme),
                  ),
                ),
            ],
          ),
        );
      },
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
    required this.canNarrow,
    required this.narrowed,
    required this.onNarrowChanged,
    required this.onFilterPressed,
  });

  final int count;
  final bool hasCustomFilters;

  /// Whether this candidate has an extended filter worth offering at all.
  final bool canNarrow;
  final bool narrowed;
  final ValueChanged<bool> onNarrowChanged;
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
        child: Column(
          children: <Widget>[
            if (canNarrow) ...<Widget>[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ExtendedFilterToggle(
                  selected: narrowed,
                  onChanged: onNarrowChanged,
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    hasCustomFilters
                        ? 'סינון אישי פעיל'
                        : narrowed
                        ? 'סינון מורחב'
                        : 'סינון בסיסי',
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
                  icon: Icon(
                    hasCustomFilters ? Icons.tune : Icons.tune_outlined,
                  ),
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
                    Icon(icon, size: 56, color: _profileAccentColor(context)),
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
  const _PersonNotesPage({required this.personId, this.focusNoteId});

  final String personId;

  /// A recording tapped on the profile: the page opens scrolled to it.
  final String? focusNoteId;

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
            _PersonNotesSection(
              person: person,
              notes: notes,
              focusNoteId: focusNoteId,
            ),
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
  const _PersonNotesSection({
    required this.person,
    required this.notes,
    this.focusNoteId,
  });

  final Person person;
  final List<PersonNote> notes;
  final String? focusNoteId;

  @override
  State<_PersonNotesSection> createState() => _PersonNotesSectionState();
}

class _PersonNotesSectionState extends State<_PersonNotesSection> {
  final TextEditingController _controller = TextEditingController();
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm');
  final GlobalKey _focusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleChanged);
    if (widget.focusNoteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? target = _focusKey.currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(
            target,
            alignment: 0.3,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
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
          color: _profileAccentWash(context),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(entries.length.toString()),
      ),
      child: Column(
        children: <Widget>[
          _PersonNotesTimeline(
            entries: entries,
            dateFormat: _dateFormat,
            focusNoteId: widget.focusNoteId,
            focusKey: _focusKey,
            onRead: (_PersonNoteEntry entry) =>
                _showNoteReader(context, widget.person, entry),
            onEdit: _editNote,
            onDelete: _deleteNote,
            onDeleteVoice: (_PersonNoteEntry entry) =>
                _confirmDeleteVoice(context, entry),
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
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'הקלטת הערה',
                onPressed: () => recordVoiceNote(context, widget.person.id),
                icon: Icon(
                  Icons.mic_none_rounded,
                  color: _profileAccentColor(context),
                ),
              ),
              IconButton(
                onPressed: _canSend ? _addNote : null,
                icon: Icon(
                  Icons.send,
                  color: _canSend
                      ? _profileAccentColor(context)
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
        audioFile: note.audioFile,
        audioDurationMs: note.audioDurationMs,
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

  Future<void> _editNote(_PersonNoteEntry entry) {
    return _editPersonNote(context, widget.person, entry);
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
    this.audioFile,
    this.audioDurationMs,
  });

  /// A voice note's recording, when this entry is one.
  final String? audioFile;
  final int? audioDurationMs;
  bool get isVoice => (audioFile ?? '').isNotEmpty;

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
    required this.onRead,
    required this.onEdit,
    required this.onDelete,
    required this.onDeleteVoice,
    this.focusNoteId,
    this.focusKey,
  });

  final List<_PersonNoteEntry> entries;
  final DateFormat dateFormat;
  final ValueChanged<_PersonNoteEntry> onRead;
  final ValueChanged<_PersonNoteEntry> onEdit;
  final ValueChanged<_PersonNoteEntry> onDelete;

  /// A recording is deleted by a long press and in no other way.
  final ValueChanged<_PersonNoteEntry> onDeleteVoice;

  /// The recording the page was opened on, marked and scrolled to.
  final String? focusNoteId;
  final Key? focusKey;

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
          child: Container(width: 2, color: _profileAccentWash(context)),
        ),
        Column(
          children: entries.map((_PersonNoteEntry entry) {
            final bool focused =
                focusNoteId != null && entry.noteId == focusNoteId;
            return Padding(
              key: focused ? focusKey : null,
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
                          color: _profileAccentColor(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      shape: focused
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: _profileAccentColor(context),
                                width: 1.6,
                              ),
                            )
                          : null,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: entry.isVoice ? null : () => onRead(entry),
                        onLongPress: entry.isVoice
                            ? () => onDeleteVoice(entry)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (entry.isVoice) ...<Widget>[
                                VoiceNotePlayer(
                                  fileName: entry.audioFile!,
                                  durationMs: entry.audioDurationMs,
                                ),
                                if (entry.text.trim().isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.text.trim(),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ] else if (entry.isAutomatic)
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
                                  if (!entry.isVoice)
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

/// An event's line with the other side's full name in it.
///
/// Lines written before history used full names said "נפתח רעיון עם אהבה".
/// Where the line names the related person by first name alone — after "עם",
/// or at its start ("שושנה דחתה…") — that name is widened to the full one as it
/// is drawn, so old and new entries read the same. Anything else is left as
/// written.
String _historyText(PersonEvent event, Person? related) {
  if (related == null) {
    return event.text;
  }
  final String first = related.firstName.trim();
  final String full = related.fullName.trim();
  if (first.isEmpty || full == first) {
    return event.text;
  }
  for (final String prefix in const <String>[
    'נפתח רעיון עם ',
    'נסגר רעיון עם ',
  ]) {
    if (event.text == '$prefix$first') {
      return '$prefix$full';
    }
  }
  if (event.text.startsWith('$first ') && !event.text.startsWith(full)) {
    return '$full${event.text.substring(first.length)}';
  }
  return event.text;
}

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
    case PersonEventType.cardSynced:
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
/// the event text. A long press offers to delete the line.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event});

  final PersonEvent event;

  Future<void> _confirmDelete(BuildContext context) async {
    final PersonRepository repository = context.read<PersonRepository>();
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'מחיקה מההיסטוריה',
      message: 'למחוק את השורה הזאת מההיסטוריה?',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (confirmed) {
      await repository.deleteEvent(event.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = _eventColor(event.type);
    final String? relatedId = event.relatedPersonId;
    final Person? related = relatedId == null
        ? null
        : context.read<PersonRepository>().getById(relatedId);

    return InkWell(
      onLongPress: () => _confirmDelete(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
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
                _historyText(event, related),
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
      ),
    );
  }
}

/// The filters on the full history screen.
enum _HistoryFilter {
  all('הכל'),
  proposals('רעיונות'),
  dated('יצאו'),
  rejected('שלילות');

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
    }
  }
}

/// The full history screen for a person, with the filter row from the spec
/// (הכל / רעיונות / יצאו / שלילות). Notes are not history and are not here.
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
        : personRepository.getHistoryForPerson(person.id);
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
    return MatchStateTag(status: status);
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

/// Records a voice note for [personId] and files it with their notes.
Future<void> recordVoiceNote(BuildContext context, String personId) async {
  final PersonRepository repository = context.read<PersonRepository>();
  final VoiceRecording? recording = await VoiceRecorderSheet.record(context);
  if (recording == null) {
    return;
  }
  final String caption = context.mounted
      ? await VoiceNoteCaption.ask(context)
      : '';
  await repository.addVoiceNote(
    personId,
    fileName: recording.fileName,
    durationMs: recording.durationMs,
    text: caption,
  );
}
