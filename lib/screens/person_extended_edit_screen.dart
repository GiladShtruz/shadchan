import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/screens/photo_edit_screen.dart';
import 'package:shadchan/services/ai_card_parser.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/card_parser.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_preferences.dart';
import 'package:shadchan/utils/profile_palette.dart';
import 'package:shadchan/widgets/device_contact_picker_sheet.dart';
import 'package:shadchan/widgets/religious_level_picker.dart';

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
  });

  final String personId;

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
  final TextEditingController _prefCity = TextEditingController();
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
          _prefCity,
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

  /// Only the basics start open: it is the area the profile itself already
  /// edits, and the one the required fields live in.
  final Set<_Area> _open = <_Area>{_Area.basics};

  /// Required fields the matchmaker was just told about. Cleared as each one is
  /// filled, so the marks fade as the problem goes away.
  Set<String> _missing = <String>{};

  bool _readingWithAi = false;
  bool _loaded = false;

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
    _loadFrom(context.read<PersonRepository>().getById(widget.personId));
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
      _prefCity,
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
    _description.text = person.description ?? '';
    _contactName.text = person.inquiryContactName ?? '';
    _contactPhone.text = person.inquiryContactPhone ?? '';
    _gender = person.gender;
    _religiousLevel = person.religiousLevel;
    _religiousLevelOther = person.religiousLevelOther;
    _maritalStatus = person.maritalStatus;
    _region = person.region;
    _photoPaths = List<String>.from(person.photosPaths);
    _additionalContacts = List<MatchContact>.from(person.additionalContacts);

    // Falls back to the default for their own style, so the area is never blank
    // and the matchmaker sees what the app would do on their behalf.
    final MatchPreferences preferences = MatchPreferences.forPerson(person);
    _prefMinAge.text = preferences.minAge?.toString() ?? '';
    _prefMaxAge.text = preferences.maxAge?.toString() ?? '';
    _prefMinHeight.text = preferences.minHeightCm?.toString() ?? '';
    _prefMaxHeight.text = preferences.maxHeightCm?.toString() ?? '';
    _prefCity.text = preferences.city ?? '';
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

  void _handleDescriptionChanged() {
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
    final PersonRepository repository = context.read<PersonRepository>();
    final Person? person = repository.getById(widget.personId);
    if (person == null) {
      return;
    }

    person
      ..firstName = _firstName.text.trim()
      ..lastName = _lastName.text.trim()
      ..gender = _gender
      ..setManualAge(_number(_age))
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
      ..photosPaths = List<String>.from(_photoPaths)
      ..preferredMinAge = _number(_prefMinAge)
      ..preferredMaxAge = _number(_prefMaxAge)
      ..preferredMinHeightCm = _number(_prefMinHeight)
      ..preferredMaxHeightCm = _number(_prefMaxHeight)
      ..preferredCity = _text(_prefCity)
      ..preferredRegions = _prefRegions.toList()
      ..preferredMaritalStatuses = _prefMaritalStatuses.toList()
      ..preferredReligiousLevels = _prefLevels.toList()
      ..preferredReligiousLevelOtherLabels = _prefOtherLabels.toList();

    await repository.update(person);
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
      if (_number(_age) == null) 'age',
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

    if (widget.isNewFriend) {
      final Set<String> missing = _missingRequiredFields();
      if (missing.isNotEmpty) {
        setState(() {
          _missing = missing;
          _open.add(_Area.basics);
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'כדי להוסיף את החבר למאגר, יש להשלים שם מלא, גיל, מגדר '
                'וסגנון דתי.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        return;
      }
    }

    Navigator.of(context).pop();
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
    final Person? person = repository.getById(widget.personId);

    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('עריכת כרטיס'), centerTitle: true),
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
          title: const Text('עריכת כרטיס'),
          centerTitle: true,
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
              _buildNotes(theme, repository.getNotesForPerson(person.id)),
              _buildContacts(theme),
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
        AiCardParser.isAvailable &&
        FirebaseBootstrap.readyListenable.value &&
        _description.text.trim().isNotEmpty;

    return _area(
      area: _Area.sendCard,
      title: 'כרטיסייה לשליחה',
      icon: Icons.article_outlined,
      subtitle: 'הטקסט שנשלח לאחרים. הפרטים שלמטה יתמלאו ממנו אוטומטית.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _description,
            focusNode: _focusNodes[_description],
            minLines: 5,
            maxLines: 12,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'הדביקו כאן את הכרטיסייה',
              alignLabelWithHint: true,
            ),
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('לא הצלחנו לקרוא את הכרטיסייה')),
          );
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
                ChoiceChip(
                  label: Text(gender.displayName),
                  selected: _gender == gender,
                  onSelected: (bool selected) => _commit(() {
                    _gender = selected ? gender : Gender.unknown;
                    _missing = _missing.difference(<String>{'gender'});
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _field(
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
          _field(controller: _city, label: 'עיר או יישוב'),
          const SizedBox(height: 16),
          // The candidate's *own* number. The card used to offer only the
          // "איש קשר להעברת הצעות" phone further down, so a person created
          // from "הוספת שם מחוץ למאגר" — who arrives with nothing but a name —
          // had no way to be given one at all.
          _field(controller: _phone, label: 'טלפון', phone: true),
          const SizedBox(height: 16),
          _label(theme, 'אזור בארץ'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Region region in Region.values)
                ChoiceChip(
                  label: Text(region.displayName),
                  selected: _region == region,
                  onSelected: (bool selected) =>
                      _commit(() => _region = selected ? region : null),
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
              for (final MaritalStatus status in MaritalStatus.values)
                ChoiceChip(
                  label: Text(status.filterLabel),
                  selected: _maritalStatus == status,
                  onSelected: (bool selected) =>
                      _commit(() => _maritalStatus = selected ? status : null),
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
            showSettingsShortcut: false,
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
        ],
      ),
    );
  }

  Widget _buildLookingFor(ThemeData theme) {
    final ReligiousLevelsProvider levels = context
        .watch<ReligiousLevelsProvider>();

    return _area(
      area: _Area.looking,
      title: 'מה המועמד מחפש',
      icon: Icons.filter_alt_outlined,
      subtitle: 'לפי אלה יוצגו ההתאמות עבורו. משנה רק אותו, לא את שאר המאגר.',
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
          _field(controller: _prefCity, label: 'עיר מועדפת'),
          const SizedBox(height: 16),
          _label(theme, 'אזורים בארץ'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Region region in Region.values)
                FilterChip(
                  label: Text(region.displayName),
                  selected: _prefRegions.contains(region),
                  onSelected: (bool selected) => _commit(() {
                    if (selected) {
                      _prefRegions.add(region);
                    } else {
                      _prefRegions.remove(region);
                    }
                  }),
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
              for (final MaritalStatus status in MaritalStatus.values)
                FilterChip(
                  label: Text(status.filterLabel),
                  selected: _prefMaritalStatuses.contains(status),
                  onSelected: (bool selected) => _commit(() {
                    if (selected) {
                      _prefMaritalStatuses.add(status);
                    } else {
                      _prefMaritalStatuses.remove(status);
                    }
                  }),
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
              for (final ReligiousLevel level in levels.enabledLevels)
                FilterChip(
                  label: Text(level.displayName),
                  selected: _prefLevels.contains(level),
                  onSelected: (bool selected) => _commit(() {
                    if (selected) {
                      _prefLevels.add(level);
                    } else {
                      _prefLevels.remove(level);
                    }
                  }),
                ),
              for (final String label in levels.customLabels)
                FilterChip(
                  label: Text(label),
                  selected: _prefOtherLabels.contains(label),
                  onSelected: (bool selected) => _commit(() {
                    if (selected) {
                      _prefOtherLabels.add(label);
                      _prefLevels.add(ReligiousLevel.other);
                    } else {
                      _prefOtherLabels.remove(label);
                      if (_prefOtherLabels.isEmpty) {
                        _prefLevels.remove(ReligiousLevel.other);
                      }
                    }
                  }),
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
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: _addNote,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('הוספת הערה'),
            ),
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
      title: 'איש קשר להעברת הצעות',
      icon: Icons.contact_phone_outlined,
      subtitle:
          'אם אינך בקשר ישיר עם המועמד, אפשר להוסיף חבר משותף או אדם שדרכו '
          'ניתן להעביר לו הצעות.',
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
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
            const SizedBox(width: 10),
            // The small plus lives beside the photos rather than under a full
            // width button, so adding a fourth photo is not a bigger gesture
            // than adding the first.
            Column(
              children: <Widget>[
                Material(
                  color: ProfilePalette.accent(theme).withValues(alpha: 0.12),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onAdd,
                    child: SizedBox.square(
                      dimension: 40,
                      child: Icon(
                        Icons.add,
                        color: ProfilePalette.accent(theme),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'הוספה',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ProfilePalette.muted(theme),
                  ),
                ),
              ],
            ),
          ],
        ),
        // The strip carries **every** photo, the main one included, and it is
        // the only place the order is set. Two things were wrong before.
        //
        // The main photo was not in it, so no photo in the strip could ever be
        // promoted to the face of the card — the one reorder anybody actually
        // wants. And each thumbnail wrapped a `GestureDetector` with its own
        // `onLongPress` for deleting *inside* the drag listener, so the inner
        // detector won the long press in the gesture arena and the drag never
        // started. Deleting has its own button on the thumbnail now, and the
        // long press does the one thing it is advertised to do.
        if (paths.length > 1) ...<Widget>[
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: paths.length,
              onReorder: onReorder,
              itemBuilder: (BuildContext context, int index) {
                return Padding(
                  key: ValueKey<String>(paths[index]),
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ReorderableDelayedDragStartListener(
                    index: index,
                    child: _PhotoThumb(
                      path: paths[index],
                      isPrimary: index == 0,
                      onTap: () => onOpen(index),
                      onRemove: () => onLongPress(index),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'לחיצה פותחת לעריכה · לחיצה ארוכה וגרירה משנה את הסדר · '
            'הראשונה היא תמונת הכרטיסייה',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ProfilePalette.muted(theme),
            ),
          ),
        ],
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
    return Image.file(
      file,
      width: width,
      height: height,
      fit: BoxFit.cover,
      cacheWidth: (width * 3).round(),
    );
  }
}

/// One photo in the reorder strip: tap to edit, long-press to drag, and a
/// small × of its own to remove it.
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.path,
    required this.isPrimary,
    required this.onTap,
    required this.onRemove,
  });

  final String path;
  final bool isPrimary;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              GestureDetector(
                onTap: onTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _PhotoGallery._photoOrPlaceholder(
                    context,
                    path,
                    width: 68,
                    height: 76,
                  ),
                ),
              ),
              PositionedDirectional(
                top: -6,
                end: -6,
                child: Material(
                  color: theme.colorScheme.surface,
                  shape: CircleBorder(
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onRemove,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.close,
                        size: 13,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (isPrimary)
            Text(
              'ראשית',
              style: theme.textTheme.labelSmall?.copyWith(
                color: ProfilePalette.accent(theme),
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
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
              child: hasPhoto
                  ? Image.file(File(path), fit: BoxFit.cover)
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
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'ראשית',
                  style: TextStyle(color: Colors.white, fontSize: 10),
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
