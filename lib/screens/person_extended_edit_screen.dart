import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadchan/widgets/card_announce_switch.dart';
import 'package:shadchan/widgets/card_text_field.dart';
import 'package:shadchan/widgets/person_tags_editor.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/person_detail_screen.dart'
    show recordVoiceNote;
import 'package:shadchan/screens/photo_edit_screen.dart';
import 'package:shadchan/services/ai_card_parser.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/card_parser.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/match_preferences.dart';
import 'package:shadchan/utils/profile_palette.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/device_contact_picker_sheet.dart';
import 'package:shadchan/widgets/religious_level_picker.dart';
import 'package:shadchan/widgets/voice_note_player.dart';

/// The full card: everything about one candidate, in one page.
///
/// It is written as a stack of collapsible areas rather than a long form. A
/// matchmaker adding a friend fills in four things and leaves; a matchmaker
/// coming back a month later is looking for one area and should not scroll
/// through the other five to reach it.
///
/// There is no save button. Every field writes itself when it is left, which is
/// the only rule that survives someone backing out mid-edit. The ✓ in the app
/// bar means "I'm done here", not "save".
class PersonExtendedEditScreen extends StatefulWidget {
  const PersonExtendedEditScreen({
    super.key,
    required this.personId,
    this.isNewFriend = false,
  }) : ownerCard = false,
       onFinished = null;

  /// The signed-in user's own card, edited by its owner.
  ///
  /// The same page, not a second form: a card owner sees exactly the areas a
  /// matchmaker sees for a friend, minus the two that are the matchmaker's
  /// alone — "הערות אישיות – לעיניי בלבד" and "איש קשר להעברת הצעות" — and
  /// with a date of birth in place of an age and no phone field (the number
  /// is the account's, not the card's).
  const PersonExtendedEditScreen.ownerCard({super.key, this.onFinished})
    : personId = PersonalCardProvider.cardId,
      isNewFriend = false,
      ownerCard = true;

  final String personId;

  /// Whether this edits the user's own card rather than a friend in the
  /// matchmaker's database.
  final bool ownerCard;

  /// Called instead of popping when the owner is done — the first card is
  /// written inside sign-up, where there is nothing to pop back to.
  final VoidCallback? onFinished;

  /// True when this is the last step of adding someone to the database. Only
  /// then does the ✓ insist on a full name, an age, a gender and a style — an
  /// older record that predates the rule must never be trapped in this page.
  final bool isNewFriend;

  @override
  State<PersonExtendedEditScreen> createState() =>
      _PersonExtendedEditScreenState();
}

/// The areas of the page, in the order they are drawn.
enum _Area { sendCard, photos, basics, looking, notes, contacts }

class _PersonExtendedEditScreenState extends State<PersonExtendedEditScreen> {
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _age = TextEditingController();
  final TextEditingController _height = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _prefMinAge = TextEditingController();
  final TextEditingController _prefMaxAge = TextEditingController();
  final TextEditingController _prefMinHeight = TextEditingController();
  final TextEditingController _prefMaxHeight = TextEditingController();
  final TextEditingController _contactName = TextEditingController();
  final TextEditingController _contactPhone = TextEditingController();
  final TextEditingController _newNote = TextEditingController();

  late final Map<TextEditingController, FocusNode> _focusNodes =
      <TextEditingController, FocusNode>{
        for (final TextEditingController controller in <TextEditingController>[
          _firstName,
          _lastName,
          _age,
          _height,
          _city,
          _phone,
          _description,
          _prefMinAge,
          _prefMaxAge,
          _prefMinHeight,
          _prefMaxHeight,
          _contactName,
          _contactPhone,
        ])
          controller: FocusNode(),
      };

  Gender _gender = Gender.unknown;
  ReligiousLevel? _religiousLevel;
  String? _religiousLevelOther;
  MaritalStatus? _maritalStatus;
  Region? _region;

  final Set<Region> _prefRegions = <Region>{};
  final Set<MaritalStatus> _prefMaritalStatuses = <MaritalStatus>{};
  final Set<ReligiousLevel> _prefLevels = <ReligiousLevel>{};
  final Set<String> _prefOtherLabels = <String>{};

  List<String> _photoPaths = <String>[];
  final Set<String> _newPhotoPaths = <String>{};
  List<MatchContact> _additionalContacts = <MatchContact>[];
  List<String> _tags = <String>[];

  /// Only the basics start open: it is the area the profile itself already
  /// edits, and the one the required fields live in.
  final Set<_Area> _open = <_Area>{_Area.basics};

  /// Required fields the matchmaker was just told about. Cleared as each one is
  /// filled, so the marks fade as the problem goes away.
  Set<String> _missing = <String>{};

  /// Set once a new friend has been thrown away, so nothing writes the record
  /// back on the way out.
  bool _discarded = false;

  bool _readingWithAi = false;
  bool _loaded = false;

  /// The owner's date of birth. Only drawn in [PersonExtendedEditScreen.ownerCard].
  DateTime? _birthDate;

  /// The height warning is a question asked once per visit, not a gate.
  bool _heightWarningShown = false;

  bool get _owner => widget.ownerCard;

  /// The owner is writing their card for the first time: the moment to ask
  /// whether matchmaker friends should hear about it.
  bool _firstCard = false;

  @override
  void initState() {
    super.initState();
    for (final FocusNode node in _focusNodes.values) {
      node.addListener(_handleFocusChanged);
    }
    _description.addListener(_handleDescriptionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    // Read before the first save writes a card.
    _firstCard = _owner && context.read<PersonalCardProvider>().card == null;
    _loadFrom(_readPerson());
  }

  /// The record this page edits: the friend in the database, or the owner's
  /// own card — a first draft when there is none yet.
  Person? _readPerson() {
    if (_owner) {
      final PersonalCardProvider cards = context.read<PersonalCardProvider>();
      return cards.card ?? cards.draftFrom(context.read<UserProfileProvider>());
    }
    return context.read<PersonRepository>().getById(widget.personId);
  }

  Future<void> _writePerson(Person person) {
    if (_owner) {
      return context.read<PersonalCardProvider>().save(person);
    }
    return context.read<PersonRepository>().update(person);
  }

  @override
  void dispose() {
    for (final FocusNode node in _focusNodes.values) {
      node
        ..removeListener(_handleFocusChanged)
        ..dispose();
    }
    _description.removeListener(_handleDescriptionChanged);
    for (final TextEditingController controller in <TextEditingController>[
      _firstName,
      _lastName,
      _age,
      _height,
      _city,
      _phone,
      _description,
      _prefMinAge,
      _prefMaxAge,
      _prefMinHeight,
      _prefMaxHeight,
      _contactName,
      _contactPhone,
      _newNote,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _loadFrom(Person? person) {
    if (person == null) {
      return;
    }
    _firstName.text = person.firstName;
    _lastName.text = person.lastName;
    _age.text = person.age?.toString() ?? '';
    _height.text = person.heightCm?.toString() ?? '';
    _city.text = person.city ?? '';
    _phone.text = person.phone ?? '';
    _description.text = CardTextField.clean(person.description ?? '');
    _lastParsedText = _description.text;
    _contactName.text = person.inquiryContactName ?? '';
    _contactPhone.text = person.inquiryContactPhone ?? '';
    _gender = person.gender;
    _religiousLevel = person.religiousLevel;
    _religiousLevelOther = person.religiousLevelOther;
    _maritalStatus = person.maritalStatus;
    _region = person.region;
    _birthDate = person.birthDate;
    _photoPaths = List<String>.from(person.photosPaths);
    _additionalContacts = List<MatchContact>.from(person.additionalContacts);
    _tags = List<String>.from(person.tags);

    // Falls back to the default for their own style, so the area is never blank
    // and the matchmaker sees what the app would do on their behalf.
    final MatchPreferences preferences = MatchPreferences.forPerson(person);
    _prefMinAge.text = preferences.minAge?.toString() ?? '';
    _prefMaxAge.text = preferences.maxAge?.toString() ?? '';
    _prefMinHeight.text = preferences.minHeightCm?.toString() ?? '';
    _prefMaxHeight.text = preferences.maxHeightCm?.toString() ?? '';
    _prefRegions.addAll(preferences.regions);
    _prefMaritalStatuses.addAll(preferences.maritalStatuses);
    _prefLevels.addAll(preferences.religiousLevels);
    _prefOtherLabels.addAll(preferences.religiousLevelOtherLabels);
  }

  // ------------------------------------------------------------------ saving

  /// Leaving a field is the save. Nothing else is: a page with autosave *and* a
  /// save button teaches that the autosave is not to be trusted.
  void _handleFocusChanged() {
    final bool anyFocused = _focusNodes.values.any(
      (FocusNode node) => node.hasFocus,
    );
    if (!anyFocused) {
      _save();
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// The text last read into the fields — the controller also notifies on
  /// every caret move, and a tap is no reason to parse the card again.
  String? _lastParsedText;

  void _handleDescriptionChanged() {
    // An owner writes a few sentences about themselves; nothing in them is a
    // label to be read into the fields below.
    if (_owner || _description.text == _lastParsedText) {
      return;
    }
    _lastParsedText = _description.text;
    final ParsedCard parsed = CardParser.parse(_description.text);
    if (parsed.isEmpty) {
      return;
    }
    _applyParsedCard(parsed);
  }

  /// Fills in what the pasted card actually says, and only that.
  ///
  /// A card giving one name fills the first-name field and leaves the surname
  /// empty rather than splitting a single word across both — a surname invented
  /// from nothing is worse than a blank one, because nobody goes back to check
  /// a field that already looks filled.
  void _applyParsedCard(ParsedCard parsed) {
    bool changed = false;

    void fill(TextEditingController controller, String? value) {
      final String text = (value ?? '').trim();
      if (text.isEmpty || controller.text.trim().isNotEmpty) {
        return;
      }
      controller.text = text;
      changed = true;
    }

    fill(_firstName, parsed.firstName);
    fill(_lastName, parsed.lastName);
    fill(_age, parsed.age?.toString());
    fill(_height, parsed.heightCm?.toString());
    fill(_city, parsed.city);
    fill(_contactName, parsed.inquiryContactName);
    fill(_contactPhone, parsed.inquiryContactPhone);

    if (_gender == Gender.unknown && parsed.gender != null) {
      _gender = parsed.gender!;
      changed = true;
    }
    if (_maritalStatus == null && parsed.maritalStatus != null) {
      _maritalStatus = parsed.maritalStatus;
      changed = true;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  String? _text(TextEditingController controller) {
    final String trimmed = controller.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _number(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  Future<void> _save() async {
    if (_discarded) {
      return;
    }
    final Person? person = _readPerson();
    if (person == null) {
      return;
    }

    person
      ..firstName = _firstName.text.trim()
      ..lastName = _lastName.text.trim()
      ..gender = _gender;
    if (_owner) {
      // The age is the date of birth; a manual age alongside it could only
      // ever disagree with it.
      person
        ..birthDate = _birthDate
        ..setManualAge(null);
    } else {
      person.setManualAge(_number(_age));
    }
    person
      ..heightCm = _number(_height)
      ..city = _text(_city)
      ..phone = _text(_phone)
      ..region = _region
      ..maritalStatus = _maritalStatus
      ..religiousLevel = _religiousLevel
      ..religiousLevelOther = _religiousLevelOther
      ..description = _text(_description)
      ..inquiryContactName = _text(_contactName)
      ..inquiryContactPhone = _text(_contactPhone)
      ..additionalContacts = List<MatchContact>.from(_additionalContacts)
      ..tags = List<String>.from(_tags)
      ..photosPaths = List<String>.from(_photoPaths)
      ..preferredMinAge = _number(_prefMinAge)
      ..preferredMaxAge = _number(_prefMaxAge)
      ..preferredMinHeightCm = _number(_prefMinHeight)
      ..preferredMaxHeightCm = _number(_prefMaxHeight)
      // "עיר מועדפת" is gone from the card; a value left over from before
      // is dropped on the next save rather than filtering silently.
      ..preferredCity = null
      ..preferredRegions = _prefRegions.toList()
      ..preferredMaritalStatuses = _prefMaritalStatuses.toList()
      ..preferredReligiousLevels = _prefLevels.toList()
      ..preferredReligiousLevelOtherLabels = _prefOtherLabels.toList();

    await _writePerson(person);
    _newPhotoPaths.clear();
    if (mounted && _missing.isNotEmpty) {
      setState(() => _missing = _missingRequiredFields());
    }
  }

  /// Applies a change made by a control rather than a field — chips, pickers,
  /// photos — which have no "leaving the field" moment of their own.
  void _commit(VoidCallback change) {
    setState(change);
    _save();
  }

  // -------------------------------------------------------------- validation

  Set<String> _missingRequiredFields() {
    return <String>{
      if (_firstName.text.trim().isEmpty) 'firstName',
      if (_lastName.text.trim().isEmpty) 'lastName',
      if (_owner ? _birthDate == null : _number(_age) == null) 'age',
      if (_gender == Gender.unknown) 'gender',
      if (_religiousLevel == null) 'religiousLevel',
    };
  }

  Future<void> _finish() async {
    FocusScope.of(context).unfocus();
    await _save();
    if (!mounted) {
      return;
    }

    if (widget.isNewFriend || _owner) {
      final Set<String> missing = _missingRequiredFields();
      if (missing.isNotEmpty) {
        setState(() {
          _missing = missing;
          _open.add(_Area.basics);
        });
        // **A new friend's card is never a trap.** Leaving with a required
        // field still empty is allowed — after one clear sentence saying what
        // it costs, and the choice to stay.
        if (widget.isNewFriend && !_owner) {
          if (await _confirmLeaveWithoutSaving()) {
            await _discardNewFriend();
          }
          return;
        }
        AppNotice.show(
          context,
          'כדי לשמור את הכרטיס, יש להשלים שם מלא, תאריך לידה, מגדר '
          'וסגנון דתי.',
          duration: Duration(seconds: 4),
        );
        return;
      }
    }

    if (_owner && _number(_height) == null && !_heightWarningShown) {
      _heightWarningShown = true;
      final bool fillIn = await _askAboutHeight();
      if (!mounted) {
        return;
      }
      if (fillIn) {
        setState(() => _open.add(_Area.basics));
        _focusNodes[_height]?.requestFocus();
        return;
      }
    }

    final VoidCallback? onFinished = widget.onFinished;
    if (onFinished != null) {
      onFinished();
      return;
    }
    // True says "finished with ✓", which is when the caller confirms.
    Navigator.of(context).pop(true);
  }

  /// "אם תצא עכשיו, החבר לא יישמר." — stay, or leave without the friend.
  Future<bool> _confirmLeaveWithoutSaving() async {
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('חסרים פרטים'),
        content: Text(
          'אם {תצא|תצאי} עכשיו, ${_gender == Gender.female ? 'החברה' : 'החבר'} '
                  'לא ${_gender == Gender.female ? 'תישמר' : 'יישמר'}.'
              .forGender(dialogContext.userGender),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('יציאה בלי שמירה'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('להישאר בעריכה'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  /// Throws the half-written friend away and leaves, telling the flow that
  /// opened this page that nobody was added.
  Future<void> _discardNewFriend() async {
    final PersonRepository repository = context.read<PersonRepository>();
    _discarded = true;
    await repository.delete(widget.personId);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(false);
  }

  /// A gentle word, not a gate: the card is saved either way.
  Future<bool> _askAboutHeight() async {
    final bool? fillIn = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('לא מילאת גובה'),
        content: Text(
          'בלי הפרט הזה {ייתכן שתופיע|ייתכן שתופיעי} בפחות התאמות אצל שדכנים '
                  'שמשתמשים בסינון לפי גובה.'
              .forGender(_gender),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('להמשיך בלי'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('מילוי גובה'),
          ),
        ],
      ),
    );
    return fillIn ?? false;
  }

  // ----------------------------------------------------------------- photos

  Future<void> _addPhotos() async {
    final List<String> added = await PhotoPickerService.pickPhotos(
      context,
      personId: widget.personId,
    );
    if (added.isEmpty || !mounted) {
      return;
    }
    _commit(() {
      _photoPaths = <String>[..._photoPaths, ...added];
      _newPhotoPaths.addAll(added);
    });
  }

  /// Tapping the main photo replaces it, which is what "the picture is wrong"
  /// means nine times out of ten.
  Future<void> _replacePrimary() async {
    final String? picked = await PhotoPickerService.pickSinglePhoto(
      context,
      namePrefix: widget.personId,
    );
    if (picked == null || !mounted) {
      return;
    }
    _commit(() {
      _photoPaths = <String>[picked, ..._photoPaths];
      _newPhotoPaths.add(picked);
    });
  }

  Future<void> _editPhoto(int index) async {
    if (index < 0 || index >= _photoPaths.length) {
      return;
    }
    final String? edited = await PhotoEditScreen.open(
      context,
      _photoPaths[index],
    );
    if (edited == null || !mounted) {
      return;
    }
    _commit(() {
      final List<String> next = List<String>.from(_photoPaths);
      next[index] = edited;
      _photoPaths = next;
      _newPhotoPaths.add(edited);
    });
  }

  Future<void> _confirmRemovePhoto(int index) async {
    final bool? remove = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: const Text('מחיקת התמונה'),
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          ),
        );
      },
    );
    if (remove != true || !mounted) {
      return;
    }
    _commit(() {
      final List<String> next = List<String>.from(_photoPaths);
      final String removed = next.removeAt(index);
      _photoPaths = next;
      // Only a file copied in during this edit is deleted from disk; an older
      // photo is merely detached from the card.
      if (_newPhotoPaths.remove(removed)) {
        PhotoPickerService.deletePhotoFiles(<String>[removed]);
      }
    });
  }

  void _reorderPhotos(int oldIndex, int newIndex) {
    _commit(() {
      final List<String> next = List<String>.from(_photoPaths);
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      next.insert(newIndex, next.removeAt(oldIndex));
      _photoPaths = next;
    });
  }

  // --------------------------------------------------------------- contacts

  Future<void> _pickContactFromPhone({required bool additional}) async {
    final DeviceContactChoice? picked = await DeviceContactPickerSheet.show(
      context,
    );
    if (picked == null || !mounted) {
      return;
    }
    if (additional) {
      _commit(
        () => _additionalContacts = <MatchContact>[
          ..._additionalContacts,
          MatchContact(name: picked.name, phone: picked.phone),
        ],
      );
      return;
    }
    _contactName.text = picked.name;
    _contactPhone.text = picked.phone;
    _commit(() {});
  }

  /// The candidate's own number, picked from the phone's contacts.
  Future<void> _pickOwnPhoneFromContacts() async {
    FocusScope.of(context).unfocus();
    final DeviceContactChoice? picked = await DeviceContactPickerSheet.show(
      context,
    );
    if (picked == null || !mounted) {
      return;
    }
    _phone.text = picked.phone;
    _commit(() {});
  }

  void _addManualAdditionalContact() {
    _commit(
      () => _additionalContacts = <MatchContact>[
        ..._additionalContacts,
        const MatchContact(name: '', phone: ''),
      ],
    );
  }

  void _updateAdditionalContact(int index, {String? name, String? phone}) {
    final MatchContact current = _additionalContacts[index];
    final List<MatchContact> next = List<MatchContact>.from(
      _additionalContacts,
    );
    next[index] = MatchContact(
      name: name ?? current.name,
      phone: phone ?? current.phone,
    );
    _additionalContacts = next;
  }

  // ------------------------------------------------------------------ notes

  Future<void> _addNote() async {
    final String text = _newNote.text.trim();
    if (text.isEmpty) {
      return;
    }
    await context.read<PersonRepository>().addNote(widget.personId, text);
    if (!mounted) {
      return;
    }
    setState(_newNote.clear);
    FocusScope.of(context).unfocus();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository repository = context.watch<PersonRepository>();
    if (_owner) {
      context.watch<PersonalCardProvider>();
    }
    final Person? person = _readPerson();

    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('עריכת כרטיס')),
        body: const Center(child: Text('איש הקשר לא נמצא')),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        _finish();
      },
      child: Scaffold(
        backgroundColor: ProfilePalette.canvas(theme),
        appBar: AppBar(
          backgroundColor: ProfilePalette.canvas(theme),
          foregroundColor: ProfilePalette.text(theme),
          titleTextStyle: ProfilePalette.appBarTitleStyle(theme),
          title: Text(_owner ? 'הכרטיס שלי' : 'עריכת כרטיס'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'סיום',
              onPressed: _finish,
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
            children: <Widget>[
              _buildSendCard(theme),
              _buildPhotos(theme),
              _buildBasics(theme),
              _buildLookingFor(theme),
              // The matchmaker's own working notes and the go-between for
              // proposals are the matchmaker's alone; they never belong to
              // the card, so they are not on the owner's page at all.
              if (!_owner) ...<Widget>[
                _buildNotes(theme, repository.getNotesForPerson(person.id)),
                _buildContacts(theme),
              ],
              if (_firstCard) const CardAnnounceSwitch(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _area({
    required _Area area,
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
  }) {
    return _CollapsibleArea(
      title: title,
      subtitle: subtitle,
      icon: icon,
      expanded: _open.contains(area),
      onToggle: () => setState(() {
        if (!_open.remove(area)) {
          _open.add(area);
        }
      }),
      child: child,
    );
  }

  Widget _buildSendCard(ThemeData theme) {
    final bool canReadWithAi =
        !_owner &&
        AiCardParser.isAvailable &&
        FirebaseBootstrap.readyListenable.value &&
        _description.text.trim().isNotEmpty;

    return _area(
      area: _Area.sendCard,
      title: 'כרטיסייה לשליחה',
      icon: Icons.article_outlined,
      subtitle: _owner
          ? 'כמה משפטים {עליך|עלייך} שאפשר להעביר {למי שמתעניין|למי שמתעניינת}.'
                .forGender(_gender)
          : 'הטקסט שנשלח לאחרים. הפרטים שלמטה יתמלאו ממנו אוטומטית.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Grows with its text rather than scrolling inside the page's own
          // list (two scrollables fight over a drag on the caret handle), with
          // no letter spacing (it shifts hit-testing into the middle of a
          // Hebrew letter) and with WhatsApp's invisible direction marks kept
          // out — see [InvisibleMarks].
          CardTextField(
            controller: _description,
            focusNode: _focusNodes[_description],
            hintText: _owner
                ? 'מה חשוב לי, במה אני {עוסק|עוסקת}, מה אני {אוהב|אוהבת} לעשות'
                      .forGender(_gender)
                : 'הדביקו כאן את הכרטיסייה',
          ),
          if (canReadWithAi)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _readingWithAi ? null : _readCardWithAi,
                icon: _readingWithAi
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high_outlined, size: 18),
                label: const Text('קריאת הכרטיסייה עם AI'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _readCardWithAi() async {
    setState(() => _readingWithAi = true);
    try {
      final ParsedCard parsed = await AiCardParser.parse(_description.text);
      if (!mounted) {
        return;
      }
      _applyParsedCard(parsed);
      await _save();
    } on AiParseException catch (_) {
      if (mounted) {
        AppNotice.show(context, 'לא הצלחנו לקרוא את הכרטיסייה');
      }
    } finally {
      if (mounted) {
        setState(() => _readingWithAi = false);
      }
    }
  }

  Widget _buildPhotos(ThemeData theme) {
    return _area(
      area: _Area.photos,
      title: 'תמונות',
      icon: Icons.photo_library_outlined,
      child: _PhotoGallery(
        paths: _photoPaths,
        onTapPrimary: _replacePrimary,
        onAdd: _addPhotos,
        onOpen: _editPhoto,
        onLongPress: _confirmRemovePhoto,
        onReorder: _reorderPhotos,
      ),
    );
  }

  Widget _buildBasics(ThemeData theme) {
    return _area(
      area: _Area.basics,
      title: 'פרטים בסיסיים',
      icon: Icons.badge_outlined,
      subtitle: 'לפי אלה עובדים הסינון וההתאמות.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _field(
                  controller: _firstName,
                  label: 'שם פרטי',
                  missing: _missing.contains('firstName'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  controller: _lastName,
                  label: 'שם משפחה',
                  missing: _missing.contains('lastName'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label(theme, 'מגדר', missing: _missing.contains('gender')),
          const SizedBox(height: 6),
          // Only the two real answers. "לא מוגדר" was a value a record could
          // sit in forever, and a candidate with no gender can be matched with
          // nobody, so it is not offered — it stays unanswered instead.
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final Gender gender in <Gender>[Gender.male, Gender.female])
                TagChip(
                  label: gender.displayName,
                  selected: _gender == gender,
                  onTap: () {
                    final bool selected = !(_gender == gender);
                    _commit(() {
                      _gender = selected ? gender : Gender.unknown;
                      _missing = _missing.difference(<String>{'gender'});
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _owner
                    ? _BirthDateField(
                        value: _birthDate,
                        missing: _missing.contains('age'),
                        onPicked: (DateTime picked) => _commit(() {
                          _birthDate = picked;
                          _missing = _missing.difference(<String>{'age'});
                        }),
                      )
                    : _field(
                        controller: _age,
                        label: 'גיל',
                        numeric: true,
                        missing: _missing.contains('age'),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  controller: _height,
                  label: 'גובה (ס״מ)',
                  numeric: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _field(controller: _city, label: 'עיר / יישוב'),
          if (!_owner) ...<Widget>[
            const SizedBox(height: 16),
            // The candidate's *own* number. The card used to offer only the
            // "איש קשר להעברת הצעות" phone further down, so a person created
            // from "הוספת שם מחוץ למאגר" — who arrives with nothing but a name —
            // had no way to be given one at all.
            _label(theme, 'יצירת קשר'),
            const SizedBox(height: 2),
            Text(
              switch (_gender) {
                Gender.male => 'הטלפון של החבר',
                Gender.female => 'הטלפון של החברה',
                _ => 'הטלפון של החבר/ה',
              },
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedInk,
              ),
            ),
            const SizedBox(height: 8),
            _field(controller: _phone, label: 'טלפון', phone: true),
            // With no number yet, the phone's own contacts are the quickest
            // place to find one.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _phone,
              builder: (BuildContext context, TextEditingValue value, _) {
                if (value.text.trim().isNotEmpty) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _pickOwnPhoneFromContacts,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    icon: const Icon(Icons.contact_phone_outlined, size: 18),
                    label: const Text('הוספת מספר מאנשי הקשר'),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          _label(theme, 'אזור בארץ'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              // An older, finer region stays visible until it is replaced —
              // it is never mapped onto one of the four from the city.
              for (final Region region in <Region>[
                if (Regions.isLegacy(_region)) _region!,
                ...Regions.selectable,
              ])
                TagChip(
                  label: region.displayName,
                  selected: _region == region,
                  onTap: () {
                    final bool selected = !(_region == region);
                    _commit(() => _region = selected ? region : null);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label(theme, 'מצב משפחתי'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              // The candidate's own status, in the candidate's own gender:
              // "רווקה", not "רווקים". The plural belongs on a filter that
              // covers a whole group; this chip describes one person, and
              // reading a woman's card and being told "גרושים" is simply wrong.
              for (final MaritalStatus status in MaritalStatus.values)
                TagChip(
                  label: status.displayNameFor(_gender),
                  selected: _maritalStatus == status,
                  onTap: () {
                    final bool selected = !(_maritalStatus == status);
                    _commit(() => _maritalStatus = selected ? status : null);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label(
            theme,
            'סגנון דתי',
            missing: _missing.contains('religiousLevel'),
          ),
          const SizedBox(height: 6),
          ReligiousLevelPicker(
            selected: ReligiousLevelChoice(
              _religiousLevel,
              _religiousLevelOther,
            ),
            showTitle: false,
            onChanged: (ReligiousLevelChoice choice) => _commit(() {
              _religiousLevel = choice.level;
              _religiousLevelOther = choice.customLabel;
              _missing = _missing.difference(<String>{'religiousLevel'});
              // The candidate's own style is what the default match filter is
              // built from, so a style chosen here refreshes an untouched one.
              if (_prefLevels.isEmpty && _prefOtherLabels.isEmpty) {
                _prefLevels.addAll(
                  MatchPreferences.defaultReligiousLevelsFor(choice.level),
                );
                final String label = (choice.customLabel ?? '').trim();
                if (choice.level == ReligiousLevel.other && label.isNotEmpty) {
                  _prefOtherLabels.add(label);
                }
              }
            }),
          ),
          // Tags are one more detail of the friend, next to the height, the
          // place and the style — not a folded area of their own. They are
          // the matchmaker's private words, so a card owner never sees them.
          if (!_owner) ...<Widget>[
            const SizedBox(height: 16),
            _label(theme, 'תגיות'),
            const SizedBox(height: 2),
            Text(
              'לסידור וסינון המאגר שלך. לא מופיעות בכרטיס שנשלח.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedInk,
              ),
            ),
            const SizedBox(height: 8),
            PersonTagsEditor(
              selected: _tags,
              onChanged: (List<String> tags) => _commit(() => _tags = tags),
            ),
          ],
        ],
      ),
    );
  }

  /// The gender of whoever this candidate is going to be matched with. With no
  /// gender chosen yet there is nothing to mirror, so the labels fall back to
  /// the masculine form — which is what Hebrew does when it does not know.
  Gender get _oppositeGender => switch (_gender) {
    Gender.male => Gender.female,
    Gender.female => Gender.male,
    Gender.unknown => Gender.male,
  };

  Widget _buildLookingFor(ThemeData theme) {
    return _area(
      area: _Area.looking,
      title: _owner
          ? '{מה אני מחפש|מה אני מחפשת}'.forGender(_gender)
          : 'מה המועמד מחפש',
      icon: Icons.filter_alt_outlined,
      subtitle: _owner
          ? 'לפי זה שדכנים יראו לך התאמות.'
          : 'לפי אלה יוצגו ההתאמות עבורו. משנה רק אותו, לא את שאר המאגר.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _RangeRow(
            label: 'טווח גיל',
            from: _prefMinAge,
            to: _prefMaxAge,
            fromFocus: _focusNodes[_prefMinAge]!,
            toFocus: _focusNodes[_prefMaxAge]!,
          ),
          const SizedBox(height: 12),
          _RangeRow(
            label: 'טווח גובה (ס״מ)',
            from: _prefMinHeight,
            to: _prefMaxHeight,
            fromFocus: _focusNodes[_prefMinHeight]!,
            toFocus: _focusNodes[_prefMaxHeight]!,
          ),
          const SizedBox(height: 16),
          _label(theme, 'אזורים בארץ'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Region region in <Region>[
                ..._prefRegions.where(Regions.isLegacy),
                ...Regions.selectable,
              ])
                TagChip(
                  label: region.displayName,
                  selected: _prefRegions.contains(region),
                  onTap: () {
                    final bool selected = !(_prefRegions.contains(region));
                    _commit(() {
                      if (selected) {
                        _prefRegions.add(region);
                      } else {
                        _prefRegions.remove(region);
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label(theme, 'מצב משפחתי'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              // What they are looking for is a person of the *other* gender,
              // so these read "גרושה" on a man's card and "גרוש" on a woman's.
              for (final MaritalStatus status in MaritalStatus.values)
                TagChip(
                  label: status.displayNameFor(_oppositeGender),
                  selected: _prefMaritalStatuses.contains(status),
                  onTap: () {
                    final bool selected = !(_prefMaritalStatuses.contains(
                      status,
                    ));
                    _commit(() {
                      if (selected) {
                        _prefMaritalStatuses.add(status);
                      } else {
                        _prefMaritalStatuses.remove(status);
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label(theme, 'סגנונות דתיים מתאימים'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ReligiousLevel level in <ReligiousLevel>[
                ..._prefLevels.where(
                  (ReligiousLevel level) =>
                      ReligiousLevels.isLegacy(level) &&
                      level != ReligiousLevel.other,
                ),
                ...ReligiousLevels.global,
              ])
                TagChip(
                  label: level.displayName,
                  selected: _prefLevels.contains(level),
                  onTap: () {
                    final bool selected = !(_prefLevels.contains(level));
                    _commit(() {
                      if (selected) {
                        _prefLevels.add(level);
                      } else {
                        _prefLevels.remove(level);
                      }
                    });
                  },
                ),
              // Labels a matchmaker once typed for "אחר" are no longer
              // offered, but a card that already asks for one keeps showing it
              // until it is taken off.
              for (final String label in _prefOtherLabels.toList())
                TagChip(
                  label: label,
                  selected: _prefOtherLabels.contains(label),
                  onTap: () {
                    final bool selected = !(_prefOtherLabels.contains(label));
                    _commit(() {
                      if (selected) {
                        _prefOtherLabels.add(label);
                        _prefLevels.add(ReligiousLevel.other);
                      } else {
                        _prefOtherLabels.remove(label);
                        if (_prefOtherLabels.isEmpty) {
                          _prefLevels.remove(ReligiousLevel.other);
                        }
                      }
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotes(ThemeData theme, List<PersonNote> notes) {
    final List<PersonNote> visible = notes
        .where((PersonNote note) => !note.isAutomatic)
        .toList()
        .reversed
        .toList();

    return _area(
      area: _Area.notes,
      title: 'הערות אישיות – לעיניי בלבד',
      icon: Icons.lock_outline,
      subtitle: 'לא מופיעות בכרטיסייה שנשלחת לאחרים.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _newNote,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'הערה חדשה',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          // A note can be spoken as well as typed — the same recorder and
          // caption the profile's own notes use.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _addNote,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('הוספת הערה'),
              ),
              OutlinedButton.icon(
                onPressed: () => recordVoiceNote(context, widget.personId),
                icon: const Icon(Icons.mic_none_rounded, size: 18),
                label: const Text('הקלטה'),
              ),
            ],
          ),
          if (visible.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            // Every note stays its own dated entry rather than being folded
            // into one growing paragraph, so an old thought keeps its date and
            // can be read on its own.
            for (final PersonNote note in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ProfilePalette.warmSurface(theme),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _noteDate(note.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ProfilePalette.muted(theme),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (note.isVoice)
                        VoiceNotePlayer(
                          fileName: note.audioFile!,
                          durationMs: note.audioDurationMs,
                          compact: true,
                        ),
                      if (note.text.trim().isNotEmpty)
                        Text(
                          note.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _noteDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year}';
  }

  Widget _buildContacts(ThemeData theme) {
    return _area(
      area: _Area.contacts,
      title: 'איש קשר להעברת ההצעה',
      icon: Icons.contact_phone_outlined,
      subtitle: 'מישהו שמכיר אותו/ה אישית ויכול לחבר ביניכם',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _field(controller: _contactName, label: 'שם'),
          const SizedBox(height: 12),
          _field(controller: _contactPhone, label: 'טלפון', phone: true),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _pickContactFromPhone(additional: false),
              icon: const Icon(Icons.contacts_outlined, size: 18),
              label: const Text('בחירה מאנשי הקשר'),
            ),
          ),
          for (int i = 0; i < _additionalContacts.length; i++) ...<Widget>[
            const Divider(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    initialValue: _additionalContacts[i].name,
                    decoration: const InputDecoration(labelText: 'שם'),
                    onChanged: (String value) =>
                        _updateAdditionalContact(i, name: value),
                    onEditingComplete: _save,
                    onTapOutside: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: _additionalContacts[i].phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'טלפון'),
                    onChanged: (String value) =>
                        _updateAdditionalContact(i, phone: value),
                    onEditingComplete: _save,
                    onTapOutside: (_) => _save(),
                  ),
                ),
                IconButton(
                  tooltip: 'הסרה',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _commit(() {
                    _additionalContacts = List<MatchContact>.from(
                      _additionalContacts,
                    )..removeAt(i);
                  }),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          // Deliberately quiet: a second contact is the exception, and a
          // prominent button would suggest a list is expected.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 4,
              children: <Widget>[
                TextButton(
                  onPressed: _addManualAdditionalContact,
                  style: TextButton.styleFrom(
                    foregroundColor: ProfilePalette.muted(theme),
                    textStyle: theme.textTheme.bodySmall,
                  ),
                  child: const Text('הוספת איש קשר נוסף'),
                ),
                TextButton(
                  onPressed: () => _pickContactFromPhone(additional: true),
                  style: TextButton.styleFrom(
                    foregroundColor: ProfilePalette.muted(theme),
                    textStyle: theme.textTheme.bodySmall,
                  ),
                  child: const Text('מאנשי הקשר'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(ThemeData theme, String text, {bool missing = false}) {
    return Row(
      children: <Widget>[
        Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: missing
                ? theme.colorScheme.error
                : ProfilePalette.text(theme),
          ),
        ),
        if (missing) ...<Widget>[
          const SizedBox(width: 6),
          Icon(Icons.error_outline, size: 15, color: theme.colorScheme.error),
        ],
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool numeric = false,
    bool phone = false,
    bool missing = false,
  }) {
    return TextField(
      controller: controller,
      focusNode: _focusNodes[controller],
      keyboardType: numeric
          ? TextInputType.number
          : phone
          ? TextInputType.phone
          : TextInputType.text,
      inputFormatters: numeric
          ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
          : null,
      onChanged: (_) {
        if (missing) {
          setState(() => _missing = _missingRequiredFields());
        }
      },
      decoration: InputDecoration(
        labelText: label,
        // A gentle mark, not an error state: the field is not wrong, it is
        // simply still needed.
        helperText: missing ? 'נדרש' : null,
        helperStyle: TextStyle(color: Theme.of(context).colorScheme.error),
        enabledBorder: missing
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.7),
                ),
              )
            : null,
      ),
    );
  }
}

/// One area of the page: a header that opens and closes it.
class _CollapsibleArea extends StatelessWidget {
  const _CollapsibleArea({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ProfilePalette.surface(theme),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ProfilePalette.muted(theme).withValues(alpha: 0.18),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 20, color: ProfilePalette.accent(theme)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ProfilePalette.text(theme),
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: ProfilePalette.muted(theme),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (subtitle != null) ...<Widget>[
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ProfilePalette.muted(theme),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  child,
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A "from … to" pair. Two short number fields rather than a range slider: the
/// matchmaker knows the numbers, and a two-handled bar is a worse way to type
/// 24 and 29 than typing 24 and 29.
class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.label,
    required this.from,
    required this.to,
    required this.fromFocus,
    required this.toFocus,
  });

  final String label;
  final TextEditingController from;
  final TextEditingController to;
  final FocusNode fromFocus;
  final FocusNode toFocus;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Widget box(TextEditingController controller, FocusNode focus, String hint) {
      return SizedBox(
        width: 74,
        child: TextField(
          controller: controller,
          focusNode: focus,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            isDense: true,
            labelText: hint,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 12,
            ),
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: ProfilePalette.text(theme),
            ),
          ),
        ),
        box(from, fromFocus, 'מ־'),
        const SizedBox(width: 8),
        box(to, toFocus, 'עד'),
      ],
    );
  }
}

/// The photos area: one clear main photo with the rest beside it.
class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({
    required this.paths,
    required this.onTapPrimary,
    required this.onAdd,
    required this.onOpen,
    required this.onLongPress,
    required this.onReorder,
  });

  final List<String> paths;
  final VoidCallback onTapPrimary;
  final VoidCallback onAdd;
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onLongPress;
  final ReorderCallback onReorder;

  /// The main photo on top, and under it one strip of every *other* photo
  /// followed by the "+" that adds more. The main photo is shown once — it
  /// used to lead the strip as well — and a star on each thumbnail makes that
  /// one the main photo instead.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: _PrimaryPhoto(
                path: paths.isEmpty ? null : paths.first,
                onTap: paths.isEmpty ? onTapPrimary : () => onOpen(0),
                onLongPress: paths.isEmpty ? null : () => onLongPress(0),
                onReplace: onTapPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Long press and drag still orders the others; the strip's own
        // indices are one behind the full list's, since the main photo is not
        // in it.
        SizedBox(
          height: 84,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            itemCount: paths.length > 1 ? paths.length - 1 : 0,
            onReorder: (int oldIndex, int newIndex) =>
                onReorder(oldIndex + 1, newIndex + 1),
            footer: _AddPhotoTile(onTap: onAdd),
            itemBuilder: (BuildContext context, int index) {
              final int photo = index + 1;
              return Padding(
                key: ValueKey<String>(paths[photo]),
                padding: const EdgeInsetsDirectional.only(end: 8, top: 6),
                child: ReorderableDelayedDragStartListener(
                  index: index,
                  child: _PhotoThumb(
                    path: paths[photo],
                    onTap: () => onOpen(photo),
                    onMakePrimary: () => onReorder(photo, 0),
                    onRemove: () => onLongPress(photo),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static Widget _photoOrPlaceholder(
    BuildContext context,
    String path, {
    required double width,
    required double height,
  }) {
    final File file = File(path);
    if (!file.existsSync()) {
      return Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined),
      );
    }
    // Whole, in its own proportion — a thumbnail that cuts the photo reads as
    // a photo that was cut.
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Image.file(
        file,
        width: width,
        height: height,
        fit: BoxFit.contain,
        cacheWidth: (width * 3).round(),
      ),
    );
  }
}

/// The "+" at the end of the photo strip — a thumbnail-sized square, so adding
/// a photo sits exactly where the new one will appear.
class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = ProfilePalette.accent(theme);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 64,
            height: 72,
            child: Icon(Icons.add_rounded, color: accent, size: 28),
          ),
        ),
      ),
    );
  }
}

/// One of the other photos: tap to edit, long-press to drag, the star to make
/// it the main photo, and a small × to remove it.
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.path,
    required this.onTap,
    required this.onMakePrimary,
    required this.onRemove,
  });

  final String path;
  final VoidCallback onTap;
  final VoidCallback onMakePrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: 64,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _PhotoGallery._photoOrPlaceholder(
                context,
                path,
                width: 64,
                height: 72,
              ),
            ),
          ),
          PositionedDirectional(
            top: -6,
            end: -6,
            child: _ThumbBadge(
              icon: Icons.close,
              color: theme.colorScheme.error,
              tooltip: 'הסרת התמונה',
              onTap: onRemove,
            ),
          ),
          PositionedDirectional(
            bottom: 3,
            start: 3,
            child: _ThumbBadge(
              icon: Icons.star_border_rounded,
              color: AppColors.secondary,
              tooltip: 'קביעה כתמונה ראשית',
              onTap: onMakePrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbBadge extends StatelessWidget {
  const _ThumbBadge({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surface,
        shape: CircleBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(icon, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}

class _PrimaryPhoto extends StatelessWidget {
  const _PrimaryPhoto({
    required this.path,
    required this.onTap,
    required this.onLongPress,
    required this.onReplace,
  });

  final String? path;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? path = this.path;
    final bool hasPhoto = path != null && File(path).existsSync();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              // The whole photo, in its own proportion — never cut to fit the
              // frame. Showing it `cover` here made every new photo look
              // cropped to 3:4 on the way in, which read as a crop the app
              // insisted on. Cropping is the optional "חיתוך" below.
              child: hasPhoto
                  ? ColoredBox(
                      color: ProfilePalette.warmSurface(theme),
                      child: Image.file(File(path), fit: BoxFit.contain),
                    )
                  : Container(
                      color: ProfilePalette.warmSurface(theme),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.add_a_photo_outlined,
                            color: ProfilePalette.muted(theme),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'בחירת תמונה ראשית',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ProfilePalette.muted(theme),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          if (hasPhoto)
            PositionedDirectional(
              top: 6,
              start: 6,
              child: Material(
                color: Colors.black54,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.crop_rounded, size: 15, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'חיתוך (לא חובה)',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (hasPhoto)
            PositionedDirectional(
              bottom: 6,
              start: 6,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onReplace,
                  child: const SizedBox.square(
                    dimension: 34,
                    child: Icon(
                      Icons.photo_library_outlined,
                      size: 17,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          if (hasPhoto)
            PositionedDirectional(
              bottom: 6,
              end: 6,
              // The filled star says "this is the main photo"; the outlined
              // star on every other thumbnail is how another one takes its
              // place.
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: AppColors.secondaryDarkDm,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The colour the areas sit on. Exported for the profile page, which draws the
/// same paper behind its own cards.
const Color extendedEditorCanvas = AppColors.background;

/// The owner's date of birth: a tappable field that opens the date picker.
///
/// A calendar rather than three typed numbers — an age is derived from it and
/// a Hebrew birthday later, so a typo here is a wrong birthday for years.
class _BirthDateField extends StatelessWidget {
  const _BirthDateField({
    required this.value,
    required this.missing,
    required this.onPicked,
  });

  final DateTime? value;
  final bool missing;
  final ValueChanged<DateTime> onPicked;

  Future<void> _pick(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 15, now.month, now.day),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'תאריך לידה',
      cancelText: 'ביטול',
      confirmText: 'אישור',
    );
    if (picked != null) {
      onPicked(DateUtils.dateOnly(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? date = value;
    String two(int n) => n.toString().padLeft(2, '0');
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isEmpty: date == null,
        decoration: InputDecoration(
          labelText: 'תאריך לידה',
          errorText: missing ? 'חובה' : null,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          date == null
              ? ''
              : '${two(date.day)}.${two(date.month)}.${date.year}'
                    ' (${Person.ageOn(date, DateTime.now())})',
        ),
      ),
    );
  }
}
