import 'dart:async';
import 'dart:io';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shadchan/dialogs/voice_recorder_sheet.dart';
import 'package:shadchan/widgets/app_glyphs.dart';
import 'package:shadchan/widgets/voice_note_player.dart';
import 'package:shadchan/widgets/match_state_tag.dart';
import 'package:shadchan/widgets/sketch_actions.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/match_preferences.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/dialogs/match_quick_actions.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_invite.dart';
import 'package:shadchan/widgets/card_link_panel.dart';
import 'package:shadchan/widgets/candidate_card_view.dart';
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
import 'package:shadchan/utils/contact_channel.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/profile_status_choices.dart';
import 'package:shadchan/widgets/person_photo_carousel.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/person_navigation.dart';
import 'package:shadchan/widgets/first_visit_tip.dart';
import 'package:shadchan/utils/app_navigation.dart';

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
  // An existing friend's card finished with ✓: say so, with the way to their
  // matches. A new friend is confirmed by the flow that added them.
  if (kept == true && !isNewFriend && context.mounted) {
    final Person? saved = context.read<PersonRepository>().getById(personId);
    if (saved != null && saved.gender != Gender.unknown) {
      final BuildContext root = Navigator.of(
        context,
        rootNavigator: true,
      ).context;
      AppNotice.show(
        context,
        'הכרטיס עודכן',
        actionLabel: 'לראות התאמות',
        onAction: () => openSuggestionsFor(root, personId),
      );
    }
  }
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

  /// The one-time hint about sharing a photo and a few words from WhatsApp.
  /// Taken when the first profile is opened, so it never comes back.
  bool _showShareTip = FirstVisitTips.takeFirstVisit(
    FirstVisitTopic.friendProfile,
  );

  final GlobalKey _cardSectionKey = GlobalKey();
  final GlobalKey _notesSectionKey = GlobalKey();
  final GlobalKey _requestSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    // The old `/people/:id/edit` route: the card's own editor, straight away.
    if (widget.initiallyEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _editCard(context);
        }
      });
    }
    final String? focus = widget.focus;
    if (focus == 'card' || focus == 'notes' || focus == 'request') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        // "request": where access to the friend's card is asked for. With no
        // card text the request sits inside the card tile itself; otherwise
        // it is the panel under the actions.
        final bool hasText =
            context
                .read<PersonRepository>()
                .getById(widget.personId)
                ?.description
                ?.trim()
                .isNotEmpty ??
            false;
        final BuildContext? target = switch (focus) {
          'notes' => _notesSectionKey,
          'request' when hasText => _requestSectionKey,
          _ => _cardSectionKey,
        }.currentContext;
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

  /// "עריכה" — the whole card, in the one editor, behind the warning a card
  /// that follows its owner needs.
  Future<void> _editCard(BuildContext context) async {
    final Person? person = context.read<PersonRepository>().getById(
      widget.personId,
    );
    if (person == null || !await confirmEditSyncedCard(context, person)) {
      return;
    }
    if (context.mounted) {
      await _openCardEditPage(context);
    }
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
        appBar: AppBar(title: const Text('פרטי איש קשר')),

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
    final List<PersonEvent> personEvents = _liveHistory(
      personRepository.getHistoryForPerson(person.id),
      context.read<MatchRepository>(),
    );

    return Scaffold(
      backgroundColor: _profileCanvasColor(theme),
      appBar: AppBar(
        backgroundColor: _profileCanvasColor(theme),
        foregroundColor: _profileTextColor(theme),
        titleTextStyle: _profileAppBarTitleStyle(theme),
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
                case 'extendedEdit':
                  await _editCard(context);
                case 'mazelTov':
                  await _changeProfileStatus(
                    context,
                    person,
                    ProfileStatus.mazelTov,
                  );
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
                      Text('עריכה'),
                    ],
                  ),
                ),
                // "מזל טוב" is not one of the status banner's three answers;
                // this is where it is marked by hand.
                if (person.profileStatus != ProfileStatus.mazelTov)
                  PopupMenuItem<String>(
                    value: 'mazelTov',
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.celebration_outlined),
                        const SizedBox(width: 10),
                        // Longer than the other rows: wraps rather than
                        // overflowing the menu on a narrow phone.
                        Flexible(
                          child: Text(
                            '{התארס/התחתן|התארסה/התחתנה} – מזל טוב!'.forGender(
                              person.gender,
                            ),
                          ),
                        ),
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
              _FriendCardTile(
                key: _cardSectionKey,
                person: person,
                initiallyExpanded: widget.focus == 'card',
                onOpenCard: (int index) => PersonCardViewer.open(
                  context,
                  person.id,
                  initialIndex: index < 0 ? 0 : index,
                ),
                onEdit: () => _editCard(context),
              ),
              if (person.hidden)
                _OutsideDatabaseBanner(
                  person: person,
                  onAdd: () => _admitToDatabase(context, person),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: ProfileStatusChoices(
                  title: 'סטטוס',
                  compact: true,
                  status: person.profileStatus,
                  gender: person.gender,
                  onSelected: (ProfileStatus status) =>
                      _changeProfileStatus(context, person, status),
                ),
              ),
              _ProfileInlineActions(
                person: person,
                inquiry: inquiry,
                whatsappLabel: _firstNameOr(person, 'WhatsApp'),
                onWhatsApp: () => _openWhatsAppMessage(context, person),
                onSms: () => ContactChannels.openSms(person.phone),
                onCompleteCard: () => _editCard(context),
                onMatches: () => _openSuggestions(context, person),
                onAddProposal: () => _openAddProposal(context, person),
              ),
              // Where this card's details come from, and the one next step:
              // ask for access, wait, or invite the friend to write a card.
              KeyedSubtree(
                key: _requestSectionKey,
                child: CardLinkPanel(person: person),
              ),
              // Above the card it is about: most of what a profile needs is
              // already sitting in a WhatsApp chat.
              if (_showShareTip)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: FirstVisitTip(
                    icon: Icons.share_outlined,
                    headline:
                        '{שתף|שתפי} בקלות מ־WhatsApp ל׳שדכן׳ כרטיס של '
                                '${person.gender == Gender.female ? 'חברה' : 'חבר'} '
                                'שלך'
                            .forGender(context.userGender),
                    lines: const <String>[
                      'בווטסאפ: לחיצה ארוכה על התמונה ← שיתוף ← שדכן, ובוחרים '
                          'להוסיף לכרטיס קיים.',
                    ],
                    onDismiss: () => setState(() => _showShareTip = false),
                  ),
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

  /// Changes the global profile status — the same flow the chips on the ideas
  /// page run: busy and break statuses offer a compact "check again" reminder,
  /// and an idea the change sent to "בהמתנה" is then opened in the waiting
  /// list, on top of this profile.
  Future<void> _changeProfileStatus(
    BuildContext context,
    Person person,
    ProfileStatus status,
  ) {
    return MatchQuickActions.setPersonStatus(context, person, status);
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

/// Long running text — a card read in full — in near-black rather than the
/// heading slate.
Color _profileBodyColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.onSurface
      : AppColors.onSurface;
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

/// One of the matchmaker's tags on a friend's profile: a small read-only
/// pill, washed in the friend's own accent.
class _ProfileTagPill extends StatelessWidget {
  const _ProfileTagPill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.sell_outlined, size: 13, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The top of a friend's profile: **the card itself**, as the personal area
/// shows a single's own — the name in their colour and the facts under it,
/// every photo in a pager (a tap opens the full-screen card on that photo),
/// the card's text, and "עריכה" / "שיתוף" along its foot.
///
/// It replaced a round avatar with three small squares under it and, further
/// down, a separate box holding the text — three places for one card.
class _FriendCardTile extends StatefulWidget {
  const _FriendCardTile({
    super.key,
    required this.person,
    required this.initiallyExpanded,
    required this.onOpenCard,
    required this.onEdit,
  });

  final Person person;
  final bool initiallyExpanded;

  /// Opens the full-screen card on the photo at the given index.
  final ValueChanged<int> onOpenCard;
  final VoidCallback onEdit;

  @override
  State<_FriendCardTile> createState() => _FriendCardTileState();
}

class _FriendCardTileState extends State<_FriendCardTile> {
  /// Past this many lines the text folds, with a link to the rest — the tile
  /// opens a page, it should not be the whole of it.
  static const int _foldedLines = 8;

  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Person person = widget.person;
    final Color accent = person.gender == Gender.unknown
        ? _profileTextColor(theme)
        : AppColors.genderAccent(person.gender, dark: dark);
    final List<String> facts = <String>[
      if (person.age != null)
        '${person.gender == Gender.female ? 'בת' : 'בן'} ${person.age}',
      if (person.heightCm != null) '${person.heightCm} ס״מ',
      if (person.maritalStatus != null)
        person.maritalStatus!.displayNameFor(person.gender),
      if (person.religiousLevelLabel.isNotEmpty) person.religiousLevelLabel,
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ];
    final String description = (person.description ?? '').trim();
    final List<String> photos = person.photosPaths
        .where((String path) => File(path).existsSync())
        .toList();
    final bool shareable = WhatsAppUtils.hasSendableCard(person);
    final TextStyle? bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.55,
      color: _profileBodyColor(theme),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: HomePaperCard(
        stripe: accent,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              person.fullName.trim(),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: accent,
                height: 1.15,
              ),
            ),
            if (facts.isNotEmpty) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                facts.join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _profileMutedColor(theme),
                ),
              ),
            ],
            // The matchmaker's own tags, with the other details of the
            // friend. Private words, so they stay on this page and are never
            // part of the card that is sent.
            if (person.tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final String tag in person.tags)
                    _ProfileTagPill(label: tag, accent: accent),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (photos.isNotEmpty)
              PersonPhotoCarousel(
                photosPaths: photos,
                height: 300,
                fit: BoxFit.contain,
                borderRadius: BorderRadius.circular(16),
                backgroundColor: dark
                    ? theme.colorScheme.surfaceContainerHighest
                    : AppColors.secondaryLight,
                onTapIndex: (int index) => widget.onOpenCard(
                  person.photosPaths.indexOf(photos[index]),
                ),
              )
            else
              Center(
                child: GestureDetector(
                  onTap: () => widget.onOpenCard(0),
                  child: Hero(
                    tag: 'person-${person.id}',
                    child: PersonAvatar(person: person, radius: 48),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (description.isNotEmpty)
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final TextPainter painter = TextPainter(
                    text: TextSpan(text: description, style: bodyStyle),
                    maxLines: _foldedLines,
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout(maxWidth: constraints.maxWidth);
                  final bool folds = painter.didExceedMaxLines;
                  painter.dispose();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        description,
                        maxLines: _expanded || !folds ? null : _foldedLines,
                        overflow: _expanded || !folds
                            ? null
                            : TextOverflow.ellipsis,
                        style: bodyStyle,
                      ),
                      if (folds)
                        TextButton(
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            _expanded ? 'הצגת פחות' : 'הצגת הכרטיס המלא',
                          ),
                        ),
                    ],
                  );
                },
              )
            else
              // No card text here yet: the invitation to write one — or, for
              // a friend who already keeps a card of their own, the request
              // for access to it. See [FriendCardInvite].
              FriendCardInvite(
                person: person,
                onManualEntry: widget.onEdit,
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: _profileMutedColor(theme),
                  height: 1.5,
                ),
              ),
            // An empty card already offers "הזנה ידנית של כרטיס" above; a
            // second "עריכה" under it would be the same button twice.
            if (description.isNotEmpty ||
                person.cardOwnerUid != null ||
                shareable) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('עריכה'),
                    ),
                  ),
                  if (shareable) ...<Widget>[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Builder(
                        builder: (BuildContext anchor) => OutlinedButton.icon(
                          onPressed: () => ShareUtils.sharePerson(
                            person,
                            origin: ShareUtils.originOf(anchor),
                          ),
                          icon: const Icon(Icons.share_outlined, size: 18),
                          label: const Text('שיתוף'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 8),
            Center(
              child: Text(
                _relativeUpdatedLabel(person.updatedAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _profileMutedColor(theme),
                ),
              ),
            ),
          ],
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

/// "איש קשר להצעת רעיון: רבקה כהן | WhatsApp" — a divider, then a direct link
/// into the chat.
class _InquiryLine extends StatelessWidget {
  const _InquiryLine({required this.contact});

  final MatchContact contact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = contact.name.trim().isEmpty
        ? contact.phone.trim()
        : contact.name.trim();

    const Color whatsappGreen = Color(0xFF1EA952);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: 'איש קשר להצעת רעיון: ',
                    style: TextStyle(color: _profileMutedColor(theme)),
                  ),
                  TextSpan(text: name),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: _profileTextColor(theme),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: _profileMutedColor(theme).withValues(alpha: 0.35),
          ),
          InkWell(
            onTap: () => WhatsAppUtils.openChatWithPhone(contact.phone),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const FaIcon(
                    FontAwesomeIcons.whatsapp,
                    size: 15,
                    color: whatsappGreen,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'WhatsApp',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: whatsappGreen,
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

/// The profile's three actions — the friend's own WhatsApp (named for them),
/// התאמות and הוספת רעיון. Sharing the card lives on the card tile above.
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
              // The app's own sign: two cards and a heart.
              icon: const MatchCardsIcon(size: 22),
              label: 'התאמות',
              onPressed: onMatches,
              emphasized: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ProfileActionButton(
              // A plain bulb: an idea, not a sparkle.
              icon: const IdeaBulbIcon(size: 22, heart: false),
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
    // The emphasised button is this person's own: the deep member of their
    // colour — the palette's rose on a woman's page, blue on a man's — on the
    // light wash of the same colour, with no frame round it.
    final Color color = emphasized
        ? _profileAccentColor(context)
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
            border: emphasized
                ? null
                : Border.all(
                    color: _profileMutedColor(
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
              // Three tiles share the row, so a label shrinks to fit rather
              // than losing its end.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: emphasized || foregroundColor == null
                        ? color
                        : _profileTextColor(theme),
                    fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
                  ),
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

/// "הערות אישיות" on the profile: a short conversation with oneself about this
/// friend.
///
/// **Newest first, with the writing line fixed at the foot.** A note is looked
/// up far more often than it is scrolled back to, so the latest one sits at
/// the top and the older ones follow down the card; the field to write the
/// next one stays under them, at the bottom of the box. However many there are, the card
/// never grows past [_maxListHeight]: past that the messages scroll inside it,
/// so a friend with a year of notes does not push the rest of the profile a
/// screen further down.
class _PersonalNotesCard extends StatefulWidget {
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

  /// The tallest the list of messages gets before it scrolls on its own.
  static const double _maxListHeight = 320;

  @override
  State<_PersonalNotesCard> createState() => _PersonalNotesCardState();
}

class _PersonalNotesCardState extends State<_PersonalNotesCard> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = _profileMutedColor(theme);
    final Person person = widget.person;
    final List<_PersonNoteEntry> entries = _noteEntriesFor(
      person,
      widget.notes,
    ).reversed.toList();

    // The whole box is the way into the full notes page — there is no
    // separate "מסך מלא" link. The messages and the writing line inside it
    // keep their own taps.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Material(
        color: _profileSurfaceColor(theme),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: widget.onShowAll,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: muted.withValues(alpha: 0.14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'הערות אישיות',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: _profileTextColor(theme),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
                    child: Text(
                      // "רק לעיניך" is a promise about notes that exist. With none
                      // written it is reassurance nobody asked for, in front of an
                      // empty box.
                      'עדיין אין הערות. {כתוב|כתבי} כאן משהו {שתרצה|שתרצי} '
                              'לזכור, או {הקלט|הקליטי} הערה קולית.'
                          .forGender(context.userGender),
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  )
                else ...<Widget>[
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: _PersonalNotesCard._maxListHeight,
                    ),
                    child: Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _noteChatChildren(
                            context,
                            person,
                            entries,
                            maxLines: 6,
                            onOpenVoice: widget.onOpenVoice,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                // **The writing line stays at the foot of the box**, under the
                // newest-first messages however far they have been scrolled —
                // it is always in the same place to reach for.
                const SizedBox(height: 8),
                _NoteComposer(personId: person.id),
                // A recording that already exists is nearly always sitting in a
                // WhatsApp chat with this friend. One tap there, and the share
                // sheet brings it back here. Quiet, under the writing line.
                if (PhoneUtils.toWhatsAppNumber(person.phone) != null)
                  _VoiceFromWhatsAppLink(person: person),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every note on a friend, oldest first — the order a conversation is read in.
List<_PersonNoteEntry> _noteEntriesFor(Person person, List<PersonNote> notes) {
  final List<_PersonNoteEntry> entries = <_PersonNoteEntry>[
    for (final PersonNote note in notes)
      _PersonNoteEntry(
        noteId: note.id,
        text: note.text,
        createdAt: note.createdAt,
        isAutomatic: note.isAutomatic,
        audioFile: note.audioFile,
        audioDurationMs: note.audioDurationMs,
      ),
  ];
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
  entries.sort(
    (_PersonNoteEntry a, _PersonNoteEntry b) =>
        a.createdAt.compareTo(b.createdAt),
  );
  return entries;
}

/// The messages, with a small day chip wherever the day changes.
List<Widget> _noteChatChildren(
  BuildContext context,
  Person person,
  List<_PersonNoteEntry> entries, {
  int? maxLines,
  ValueChanged<String>? onOpenVoice,
  String? focusNoteId,
  Key? focusKey,
}) {
  final List<Widget> children = <Widget>[];
  DateTime? lastDay;
  for (final _PersonNoteEntry entry in entries) {
    final DateTime day = DateTime(
      entry.createdAt.year,
      entry.createdAt.month,
      entry.createdAt.day,
    );
    if (lastDay == null || day != lastDay) {
      children.add(_NoteDayChip(day: day));
      lastDay = day;
    }
    final bool focused = focusNoteId != null && entry.noteId == focusNoteId;
    children.add(
      _NoteBubble(
        key: focused ? focusKey : null,
        entry: entry,
        maxLines: maxLines,
        highlighted: focused,
        onTap: entry.isVoice
            ? (onOpenVoice == null || entry.noteId == null
                  ? null
                  : () => onOpenVoice(entry.noteId!))
            : () => _showNoteReader(context, person, entry),
        onLongPress: () => _onNoteLongPress(context, person, entry),
      ),
    );
  }
  return children;
}

/// A long press is the way to change a message: a written note opens its
/// editor (with delete), and a recording or an automatic line asks before it
/// is deleted.
Future<void> _onNoteLongPress(
  BuildContext context,
  Person person,
  _PersonNoteEntry entry,
) async {
  if (entry.isVoice) {
    return _confirmDeleteVoice(context, entry);
  }
  if (!entry.isAutomatic) {
    return _editPersonNote(context, person, entry);
  }
  final String? id = entry.noteId;
  if (id == null) {
    return;
  }
  final PersonRepository repository = context.read<PersonRepository>();
  final bool confirmed = await ConfirmDialog.show(
    context,
    title: 'מחיקת הערה',
    message: 'למחוק את ההערה?',
    confirmText: 'מחיקה',
    isDestructive: true,
  );
  if (confirmed) {
    await repository.deleteNote(id);
  }
}

String _noteDayLabel(DateTime day) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int days = today.difference(day).inDays;
  if (days == 0) {
    return 'היום';
  }
  if (days == 1) {
    return 'אתמול';
  }
  return DateFormat('dd.MM.yyyy').format(day);
}

class _NoteDayChip extends StatelessWidget {
  const _NoteDayChip({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = _profileMutedColor(theme);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: muted.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _noteDayLabel(day),
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// One message. What the matchmaker wrote or recorded is a bubble in the
/// friend's own accent wash; a line the app wrote is a quiet centred strip.
class _NoteBubble extends StatelessWidget {
  const _NoteBubble({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    this.maxLines,
    this.highlighted = false,
  });

  final _PersonNoteEntry entry;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  /// Where the text is cut in the profile's short preview; null shows it all.
  final int? maxLines;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = _profileMutedColor(theme);
    final String time = DateFormat('HH:mm').format(entry.createdAt);

    if (entry.isAutomatic) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Center(
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                '${entry.text} · $time',
                textAlign: TextAlign.center,
                maxLines: maxLines,
                overflow: maxLines == null ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final Color accent = _profileAccentColor(context);
    final String caption = entry.text.trim();
    const Radius round = Radius.circular(16);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.74,
          ),
          child: Material(
            color: _profileAccentWash(context),
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadiusDirectional.only(
                topStart: round,
                topEnd: round,
                bottomStart: round,
                bottomEnd: Radius.circular(4),
              ),
              side: highlighted
                  ? BorderSide(color: accent, width: 1.6)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (entry.isVoice) ...<Widget>[
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
                            maxLines: maxLines,
                            overflow: maxLines == null
                                ? null
                                : TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _profileTextColor(theme),
                              height: 1.4,
                            ),
                          ),
                        ),
                    ] else
                      Text(
                        entry.text,
                        maxLines: maxLines,
                        overflow: maxLines == null
                            ? null
                            : TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _profileTextColor(theme),
                          height: 1.4,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        time,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The writing field at the foot of the notes, always there, with the
/// microphone beside it. The round button records while the field is empty
/// and sends once something is typed — the shape every chat app has taught.
class _NoteComposer extends StatefulWidget {
  const _NoteComposer({required this.personId});

  final String personId;

  @override
  State<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<_NoteComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  bool get _canSend => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _send() async {
    final String text = _controller.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<PersonRepository>().addNote(widget.personId, text);
      _controller.clear();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = _profileMutedColor(theme);
    final Color accent = _profileAccentColor(context);
    final bool canSend = _canSend;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _profileTextColor(theme),
            ),
            decoration: InputDecoration(
              hintText: 'כתיבת הערה…',
              isDense: true,
              filled: true,
              fillColor: muted.withValues(alpha: 0.07),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox.square(
          dimension: 44,
          child: IconButton.filled(
            tooltip: canSend ? 'שליחה' : 'הקלטת הערה קולית',
            style: IconButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            onPressed: _sending
                ? null
                : canSend
                ? _send
                : () => recordVoiceNote(context, widget.personId),
            icon: Icon(
              canSend ? Icons.send_rounded : Icons.mic_rounded,
              size: 21,
            ),
          ),
        ),
      ],
    );
  }
}

/// "שתף ושמור הקלטה קיימת מ־WhatsApp" — kept right at the top of the notes.
class _VoiceFromWhatsAppLink extends StatelessWidget {
  const _VoiceFromWhatsAppLink({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () => _shareVoiceFromWhatsApp(context, person),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          foregroundColor: _profileMutedColor(theme),
          textStyle: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w400,
          ),
        ),
        icon: FaIcon(
          FontAwesomeIcons.whatsapp,
          size: 13,
          color: _profileMutedColor(theme),
        ),
        label: const Text('שתף ושמור הקלטה קיימת מ־WhatsApp'),
      ),
    );
  }
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
        'ב־WhatsApp: לחיצה ארוכה על ההקלטה ← שיתוף ← שדכן.\n'
        'ההקלטה תישמר בהערות של החבר.',
      ),
      // The two buttons as one pair in the middle of the foot.
      actionsAlignment: MainAxisAlignment.center,
      actions: <Widget>[
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
          label: const Text('WhatsApp'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('ביטול'),
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

//// One idea row: the other side, where the idea stands, and the same two
/// buttons on every row — share (one side's card to the other) and WhatsApp
/// (a chat with either side). A button with nothing to do is drawn faded
/// rather than left out, so the columns line up down the list.
///
/// Tapping the row opens the two cards side by side, as it does everywhere
/// else two people are weighed against each other.
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

  static const BoxConstraints _buttonSize = BoxConstraints.tightFor(
    width: 38,
    height: 38,
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Person? other = otherPerson;
    final String otherName = other?.fullName.trim().isNotEmpty == true
        ? other!.fullName.trim()
        : 'אדם נמחק';

    bool hasPhone(Person? p) => (p?.phone ?? '').trim().isNotEmpty;
    final bool canShare =
        other != null &&
        ((hasPhone(other) && WhatsAppUtils.hasSendableCard(person)) ||
            (hasPhone(person) && WhatsAppUtils.hasSendableCard(other)));
    final bool canChat = hasPhone(person) || hasPhone(other);
    final Color muted = _profileMutedColor(theme);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (other == null) {
            AppNavigation.open(context, '/matches/${match.id}');
            return;
          }
          openMatchComparison(
            context,
            source: person,
            candidate: other,
            showOpenIdeaAction: false,
          );
        },
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 6, 8),
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
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsetsDirectional.only(start: 8, end: 2),
                color: muted.withValues(alpha: 0.22),
              ),
              IconButton(
                tooltip: 'שיתוף כרטיס',
                iconSize: 19,
                constraints: _buttonSize,
                padding: EdgeInsets.zero,
                color: _profileAccentColor(context),
                disabledColor: muted.withValues(alpha: 0.35),
                // Level, not tilted — the plane as the icon draws it.
                icon: const Icon(Icons.send_outlined),
                onPressed: canShare
                    ? () => MatchQuickActions.shareSideCard(
                        context,
                        match,
                        first: person,
                        second: other,
                      )
                    : null,
              ),
              IconButton(
                tooltip: 'WhatsApp',
                iconSize: 19,
                constraints: _buttonSize,
                padding: EdgeInsets.zero,
                color: const Color(0xFF1EA952),
                disabledColor: muted.withValues(alpha: 0.35),
                icon: const FaIcon(FontAwesomeIcons.whatsapp),
                onPressed: canChat
                    ? () => MatchQuickActions.chatWithSide(
                        context,
                        match,
                        first: person,
                        second: other,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
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
                // The card itself is read at length here, side by side with
                // the other one — in the page's near-black body ink, not the
                // slate the headings wear, which reads as grey over a long
                // paragraph.
                color: description.isEmpty
                    ? _profileMutedColor(theme)
                    : _profileBodyColor(theme),
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
        appBar: AppBar(title: const Text('התאמות')),
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
    // Order the suggestions in tiers: candidates that already have an
    // open/בהמתנה proposal with this person come first, then the remaining
    // active suggestions, then candidates whose opened proposal was rejected,
    // and at the very end everybody marked "לא מתאים".
    //
    // **"לא מתאים" wins over every other tier.** It used to be checked after
    // the open-proposal tier, so turning down a candidate who had an idea open
    // with this person did nothing at all — the card stayed at the top and the
    // button looked broken. It is also checked before the rejected tier, so the
    // one just dismissed is really last, in the order things were dismissed
    // rather than by when their cards were edited.
    final List<String> dismissedOrder = SuggestionDismissals.dismissedInOrder(
      person.id,
    );
    final Set<String> dismissedIds = dismissedOrder.toSet();
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
      if (dismissedIds.contains(candidate.id)) {
        dismissedSuggestions.add(candidate);
      } else if (existingStatus == MatchStatus.rejected) {
        rejectedSuggestions.add(candidate);
      } else if (existingStatus == MatchStatus.idea ||
          existingStatus == MatchStatus.checking ||
          existingStatus == MatchStatus.unavailable) {
        prioritizedSuggestions.add(candidate);
      } else {
        activeSuggestions.add(candidate);
      }
    }
    dismissedSuggestions.sort(
      (Person a, Person b) =>
          dismissedOrder.indexOf(a.id).compareTo(dismissedOrder.indexOf(b.id)),
    );
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
      ...availableFirst(rejectedSuggestions),
      ...dismissedSuggestions,
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
        elevation: 0,
        automaticallyImplyLeading: !widget.asSheet,
        leading: widget.asSheet
            ? IconButton(
                tooltip: 'סגירה',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        centerTitle: true,
        title: Text('התאמות · ${person.fullName.trim()}'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _SuggestionSearchField(
              controller: _searchController,
              onChanged: (String value) => setState(() => _query = value),
              filtersActive: savedSuggestionFilters != null,
              onFilterPressed: () => _openSuggestionFilters(context, person),
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
                      dismissedIds: dismissedIds,
                      matchRepository: matchRepository,
                      hasCustomFilters: savedSuggestionFilters != null,
                      onOpenPreview: (Person candidate) =>
                          _openMatchPreview(context, person, candidate),
                      onAccept: (Person candidate) =>
                          _acceptSuggestion(context, person, candidate),
                      onReject: (Person candidate) =>
                          _rejectSuggestion(context, person, candidate),
                      onRestore: (Person candidate) =>
                          _restoreSuggestion(person, candidate),
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
      AppNavigation.open(context, '/matches/${existing.id}');
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
      // Everybody who fits the basics by default; anything narrower is set
      // in the filter sheet behind the icon beside the search field.
      return MatchSuggestionUtils.matchesBasicPreferences(
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
    if (!MatchProposalFilters.matchesTags(candidate, filters)) {
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
      AppNavigation.open(context, '/matches/${existingMatch.id}');
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
    // **No confirmation dialog, an undo instead** — the same answer "רעיונות
    // שהמאגר מציע לך" gives. The dialog is what made this button feel broken:
    // tap, a question, and then the card quietly reappearing somewhere below.
    // Now the tap is the act, the next match slides up into its place at
    // once, and a bottom notice says where it went with a way back.
    //
    // The candidate drops to the end of the suggestions list on *both* cards
    // and stops being offered by the database. No rejected proposal is created,
    // so the pair never shows up under רעיונות שנשללו — this is a decision
    // about a suggestion, not about an idea that was ever opened.
    final OverlayState? notices = AppNotice.capture(context);
    final bool wasDismissedHere = SuggestionDismissals.isDismissed(
      sourcePerson.id,
      candidate.id,
    );
    final bool wasDismissedThere = SuggestionDismissals.isDismissed(
      candidate.id,
      sourcePerson.id,
    );
    await SuggestionDismissals.dismiss(sourcePerson.id, candidate.id);
    await SuggestionDismissals.dismiss(candidate.id, sourcePerson.id);
    if (!mounted) {
      return;
    }
    setState(() {});
    AppNotice.showOn(
      notices,
      '${candidate.fullName.trim()} ${candidate.gender == Gender.female ? 'הועברה' : 'הועבר'} לסוף הרשימה',
      atBottom: true,
      actionLabel: 'ביטול',
      onAction: () async {
        // Only what this tap wrote is taken back: a side that had already
        // been turned down before stays turned down.
        if (!wasDismissedHere) {
          await SuggestionDismissals.restore(sourcePerson.id, candidate.id);
        }
        if (!wasDismissedThere) {
          await SuggestionDismissals.restore(candidate.id, sourcePerson.id);
        }
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  /// Takes a candidate back out of "לא מתאים", on both cards.
  Future<void> _restoreSuggestion(Person sourcePerson, Person candidate) async {
    await SuggestionDismissals.restore(sourcePerson.id, candidate.id);
    await SuggestionDismissals.restore(candidate.id, sourcePerson.id);
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
    required this.filtersActive,
    required this.onFilterPressed,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// A filter of the matchmaker's own is set — the icon carries a dot.
  final bool filtersActive;
  final VoidCallback onFilterPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = _profileAccentColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
      child: Row(
        children: <Widget>[
          Expanded(child: _field(theme)),
          const SizedBox(width: 6),
          // The filter is one icon beside the search, not a banner of its
          // own: the list gets the room.
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              IconButton(
                tooltip: 'סינון',
                onPressed: onFilterPressed,
                style: IconButton.styleFrom(
                  backgroundColor: _profileSurfaceColor(theme),
                  foregroundColor: filtersActive
                      ? accent
                      : _profileMutedColor(theme),
                ),
                icon: const Icon(Icons.tune_rounded),
              ),
              if (filtersActive)
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(ThemeData theme) {
    return Builder(
      builder: (BuildContext context) => TextField(
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
    required this.dismissedIds,
    required this.matchRepository,
    required this.hasCustomFilters,
    required this.onOpenPreview,
    required this.onAccept,
    required this.onReject,
    required this.onRestore,
  });

  final Person sourcePerson;
  final List<Person> suggestedPeople;

  /// The candidates marked "לא מתאים" — the tail of [suggestedPeople].
  final Set<String> dismissedIds;
  final MatchRepository matchRepository;
  final bool hasCustomFilters;
  final ValueChanged<Person> onOpenPreview;
  final ValueChanged<Person> onAccept;
  final ValueChanged<Person> onReject;
  final ValueChanged<Person> onRestore;

  @override
  Widget build(BuildContext context) {
    if (sourcePerson.gender == Gender.unknown) {
      return _SuggestionTabScaffold(
        header: const SizedBox(height: 4),
        child: const _TabEmptyState(
          icon: Icons.wc_outlined,
          title: 'צריך לבחור מגדר',
          subtitle: 'אחרי עדכון מגדר יוצגו התאמות אוטומטיות',
        ),
      );
    }

    // The automatic list follows what the friend wrote in their own card;
    // saying so is what makes the filter icon read as the way past it.
    final Widget header =
        !hasCustomFilters &&
            MatchSuggestionUtils.followsOwnerWishes(sourcePerson)
        ? _OwnerWishesNote(person: sourcePerson)
        : const SizedBox(height: 4);

    if (suggestedPeople.isEmpty) {
      return _SuggestionTabScaffold(
        header: header,
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
        header,
        Expanded(
          child: _SuggestedMatchesList(
            sourcePerson: sourcePerson,
            suggestedPeople: suggestedPeople,
            dismissedIds: dismissedIds,
            matchRepository: matchRepository,
            onOpenPreview: onOpenPreview,
            onAccept: onAccept,
            onReject: onReject,
            onRestore: onRestore,
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
    required this.dismissedIds,
    required this.matchRepository,
    required this.onOpenPreview,
    required this.onAccept,
    required this.onReject,
    required this.onRestore,
  });

  final Person sourcePerson;
  final List<Person> suggestedPeople;
  final Set<String> dismissedIds;
  final MatchRepository matchRepository;
  final ValueChanged<Person> onOpenPreview;
  final ValueChanged<Person> onAccept;
  final ValueChanged<Person> onReject;
  final ValueChanged<Person> onRestore;

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
        final bool dismissed = widget.dismissedIds.contains(candidate.id);
        final bool firstDismissed =
            dismissed &&
            (index == 0 ||
                !widget.dismissedIds.contains(
                  widget.suggestedPeople[index - 1].id,
                ));
        final VoidCallback onThirdAction = dismissed
            ? () => widget.onRestore(candidate)
            : () => widget.onReject(candidate);

        final Widget row = Material(
          color: _profileSurfaceColor(theme),
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: <Widget>[
              InkWell(
                onTap: () => existingMatch != null
                    ? AppNavigation.open(
                        context,
                        '/matches/${existingMatch.id}',
                      )
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
                        restoresInstead: dismissed,
                        onFullCard: () => setState(() {
                          if (!_expandedIds.remove(candidate.id)) {
                            _expandedIds.add(candidate.id);
                          }
                        }),
                        onOpenIdea: () => widget.onAccept(candidate),
                        onNotSuitable: onThirdAction,
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
                              final String? label =
                                  state == CardInviteState.noCard
                                  ? CardInviteFlow.detailsRequestLabel
                                  : CardInviteFlow.labelFor(state);
                              return SketchActionBar(
                                compact: true,
                                fullCardLabel:
                                    label ?? CardInviteFlow.detailsRequestLabel,
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
                                restoresInstead: dismissed,
                                onOpenIdea: () => widget.onAccept(candidate),
                                onNotSuitable: onThirdAction,
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

        // Keyed by the person: rows move when somebody is turned down, and
        // without a key a row's `FutureBuilder` would keep the previous
        // occupant's answer for a frame and draw the wrong first action.
        return KeyedSubtree(
          key: ValueKey<String>(candidate.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The turned-down tail says what it is, so a card that moved
              // there reads as "done" rather than as "still here".
              if (firstDismissed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                  child: Text(
                    'סומנו כלא מתאימים',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _profileMutedColor(theme),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (dismissed) Opacity(opacity: 0.6, child: row) else row,
            ],
          ),
        );
      },
    );
  }
}

/// One quiet line over a friend's matches when the automatic list follows
/// what they themselves asked for in their personal card.
class _OwnerWishesNote extends StatelessWidget {
  const _OwnerWishesNote({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = person.firstName.trim().isNotEmpty
        ? person.firstName.trim()
        : person.fullName.trim();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 8),
      child: Text(
        'ההתאמות מסוננות לפי מה ש$name {מחפש|מחפשת} בכרטיס האישי. '
                'אפשר לשנות בסינון.'
            .forGender(person.gender),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
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

class _PersonNotesPage extends StatefulWidget {
  const _PersonNotesPage({required this.personId, this.focusNoteId});

  final String personId;

  /// A recording tapped on the profile: the page opens scrolled to it.
  final String? focusNoteId;

  @override
  State<_PersonNotesPage> createState() => _PersonNotesPageState();
}

/// The whole conversation, newest at the bottom above a writing field pinned
/// to the foot of the screen.
class _PersonNotesPageState extends State<_PersonNotesPage> {
  final GlobalKey _focusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.focusNoteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? target = _focusKey.currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(
            target,
            alignment: 0.4,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final Person? person = personRepository.getById(widget.personId);

    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('הערות אישיות')),
        body: const Center(child: Text('איש הקשר לא נמצא')),
      );
    }

    final List<_PersonNoteEntry> entries = _noteEntriesFor(
      person,
      personRepository.getNotesForPerson(person.id),
    );

    return Scaffold(
      backgroundColor: _profileSurfaceColor(theme),
      appBar: AppBar(title: Text('הערות אישיות · ${person.firstName.trim()}')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _PersonalNotesNotice(),
            ),
            if (PhoneUtils.toWhatsAppNumber(person.phone) != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _VoiceFromWhatsAppLink(person: person),
              ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'עדיין אין הערות. {כתוב|כתבי} למטה או {הקלט|הקליטי} '
                                  'הערה קולית.'
                              .forGender(context.userGender),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _profileMutedColor(theme),
                          ),
                        ),
                      ),
                    )
                  // Reversed so the page opens at the newest message, the way
                  // a conversation does.
                  : SingleChildScrollView(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _noteChatChildren(
                          context,
                          person,
                          entries,
                          focusNoteId: widget.focusNoteId,
                          focusKey: _focusKey,
                        ),
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: _profileSurfaceColor(theme),
                border: Border(
                  top: BorderSide(
                    color: _profileMutedColor(theme).withValues(alpha: 0.14),
                  ),
                ),
              ),
              child: _NoteComposer(personId: person.id),
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
    final Color muted = _profileMutedColor(theme);

    return Row(
      children: <Widget>[
        Icon(Icons.lock_outline, size: 16, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'ההערות כאן הן לצפייה אישית שלך בלבד.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
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
    case PersonEventType.cardSyncedMinor:
      return AppColors.onSurfaceVariant;
    case PersonEventType.reminderSet:
      return AppColors.profileOnBreak;
  }
}

/// A profile's history without "נפתח רעיון עם…" lines about ideas that no
/// longer exist — deleted ones from before deleting started taking those
/// lines with it.
List<PersonEvent> _liveHistory(
  List<PersonEvent> events,
  MatchRepository matches,
) {
  return <PersonEvent>[
    for (final PersonEvent event in events)
      if (event.type != PersonEventType.proposalOpened ||
          event.relatedMatchId == null ||
          matches.getById(event.relatedMatchId!) != null)
        event,
  ];
}

/// One entry in a profile's history: a line, and the lines that belong to the
/// same act.
///
/// **Closing an idea writes two lines** — "נסגר רעיון עם תאיר" and, a
/// millisecond later, why ("מהבירור עלה כי הוא יותר דוס"). Stored apart they
/// read as two unrelated events; drawn here they are one: the first line is
/// the entry's title and the rest is its body. Grouping happens at draw time,
/// so the pairs already on every phone read the same way as new ones.
class _HistoryEntry {
  _HistoryEntry(this.events);

  /// Oldest first: the line written first is the title.
  final List<PersonEvent> events;

  PersonEvent get head => events.first;

  /// When the entry happened — the first of its lines.
  DateTime get at => head.createdAt;

  Iterable<PersonEvent> get details => events.skip(1);
}

/// How far apart two lines of one act can be written. The repository stamps
/// them a millisecond apart; a minute leaves room for a slow phone without
/// reaching the next thing the matchmaker did with that idea.
const Duration _historySameActWindow = Duration(minutes: 1);

/// Folds [events] (newest first, as the repository returns them) into
/// entries: consecutive lines of the same idea, the same kind and the same
/// moment become one entry. Everything else stays a line of its own.
List<_HistoryEntry> _groupHistory(List<PersonEvent> events) {
  final List<List<PersonEvent>> groups = <List<PersonEvent>>[];
  for (final PersonEvent event in events) {
    final List<PersonEvent>? last = groups.isEmpty ? null : groups.last;
    final PersonEvent? previous = last?.last;
    final bool sameAct =
        previous != null &&
        event.relatedMatchId != null &&
        event.relatedMatchId == previous.relatedMatchId &&
        event.type == previous.type &&
        previous.createdAt.difference(event.createdAt).abs() <=
            _historySameActWindow;
    if (sameAct) {
      last!.add(event);
    } else {
      groups.add(<PersonEvent>[event]);
    }
  }
  return <_HistoryEntry>[
    for (final List<PersonEvent> group in groups)
      _HistoryEntry(
        group..sort(
          (PersonEvent a, PersonEvent b) => a.createdAt.compareTo(b.createdAt),
        ),
      ),
  ];
}

/// The inline "היסטוריה" feed: the last handful of meaningful events, and —
/// only when there is more than that — a link to the rest.
class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.events, required this.onShowAll});

  final List<PersonEvent> events;
  final VoidCallback onShowAll;

  static const int _previewCount = 6;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final List<_HistoryEntry> entries = _groupHistory(events);
    final List<_HistoryEntry> preview = entries.take(_previewCount).toList();

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
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'היסטוריה',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: _profileTextColor(theme),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final _HistoryEntry entry in preview)
              _HistoryRow(entry: entry),
            if (entries.length > preview.length)
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
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

/// One entry in the history timeline: a type-coloured dot, the event,
/// whatever belongs to it underneath at reading size, and the date small at
/// the far edge. A long press offers to delete the entry — all of its lines.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final _HistoryEntry entry;

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
      for (final PersonEvent event in entry.events) {
        await repository.deleteEvent(event.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonEvent head = entry.head;
    final Color color = _eventColor(head.type);
    final PersonRepository people = context.read<PersonRepository>();
    Person? relatedOf(PersonEvent event) {
      final String? id = event.relatedPersonId;
      return id == null ? null : people.getById(id);
    }

    return InkWell(
      onLongPress: () => _confirmDelete(context),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _historyText(head, relatedOf(head)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    // Regular weight: the only bold in the section is its
                    // "היסטוריה" heading, and a size under the page's reading
                    // text: the history is looked through, not read.
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _profileTextColor(theme),
                      fontWeight: FontWeight.w400,
                      height: 1.3,
                    ),
                  ),
                  for (final PersonEvent detail in entry.details)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _historyText(detail, relatedOf(detail)),
                        maxLines: 3,
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
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _eventDateShort(entry.at),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _profileMutedColor(theme),
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
        : _liveHistory(
            personRepository.getHistoryForPerson(person.id),
            context.read<MatchRepository>(),
          );
    final List<_HistoryEntry> filtered = _groupHistory(
      events,
    ).where((_HistoryEntry entry) => _filter.matches(entry.head)).toList();

    return Scaffold(
      backgroundColor: _profileCanvasColor(theme),
      appBar: AppBar(
        backgroundColor: _profileCanvasColor(theme),
        foregroundColor: _profileTextColor(theme),
        titleTextStyle: _profileAppBarTitleStyle(theme),
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
                          _HistoryRow(entry: filtered[index]),
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
