import 'dart:async';
import 'dart:io';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/hebrew_date_utils.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/dialogs/photo_viewer.dart';
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
    with WidgetsBindingObserver {
  final GlobalKey<FormState> _editFormKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _manualAgeController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _inquiryContactNameController =
      TextEditingController();
  final TextEditingController _inquiryContactPhoneController =
      TextEditingController();
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _isSavingEdit = false;
  String? _editingPersonId;
  Timer? _autoSaveTimer;
  Gender _selectedGender = Gender.unknown;
  DateTime? _birthDate;
  int? _hebrewBirthYear;
  int? _hebrewBirthMonth;
  int? _hebrewBirthDay;
  _BirthDateCalendar _birthDateCalendar = _BirthDateCalendar.gregorian;
  ReligiousLevel? _selectedReligiousLevel;

  final FocusNode _firstNameFocus = FocusNode();
  final FocusNode _lastNameFocus = FocusNode();
  final FocusNode _manualAgeFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _inquiryContactNameFocus = FocusNode();
  final FocusNode _inquiryContactPhoneFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();

  String _origFirstName = '';
  String _origLastName = '';
  String _origManualAge = '';
  String _origCity = '';
  String _origPhone = '';
  String _origInquiryContactName = '';
  String _origInquiryContactPhone = '';
  String _origSource = '';
  String _origDescription = '';
  Gender _origGender = Gender.unknown;
  DateTime? _origBirthDate;
  ReligiousLevel? _origReligiousLevel;
  int? _origHebrewBirthYear;
  int? _origHebrewBirthMonth;
  int? _origHebrewBirthDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final FocusNode node in <FocusNode>[
      _firstNameFocus,
      _lastNameFocus,
      _manualAgeFocus,
      _phoneFocus,
      _inquiryContactNameFocus,
      _inquiryContactPhoneFocus,
      _descriptionFocus,
    ]) {
      node.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _manualAgeController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    _inquiryContactNameController.dispose();
    _inquiryContactPhoneController.dispose();
    _sourceController.dispose();
    _descriptionController.dispose();
    for (final FocusNode node in <FocusNode>[
      _firstNameFocus,
      _lastNameFocus,
      _manualAgeFocus,
      _phoneFocus,
      _inquiryContactNameFocus,
      _inquiryContactPhoneFocus,
      _descriptionFocus,
    ]) {
      node
        ..removeListener(_handleFocusChange)
        ..dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _autoSaveTimer?.cancel();
      unawaited(_saveCurrentInlineEdit(showSnackBar: false, unfocus: false));
    }
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() {});
    if (!_hasFocusedInlineField) {
      _autoSaveTimer?.cancel();
      unawaited(_saveCurrentInlineEdit(showSnackBar: false, unfocus: false));
    }
  }

  bool get _hasFocusedInlineField {
    return _firstNameFocus.hasFocus ||
        _lastNameFocus.hasFocus ||
        _manualAgeFocus.hasFocus ||
        _phoneFocus.hasFocus ||
        _inquiryContactNameFocus.hasFocus ||
        _inquiryContactPhoneFocus.hasFocus ||
        _descriptionFocus.hasFocus;
  }

  bool get _hasChanges {
    return _firstNameController.text != _origFirstName ||
        _lastNameController.text != _origLastName ||
        _manualAgeController.text != _origManualAge ||
        _cityController.text != _origCity ||
        _phoneController.text != _origPhone ||
        _inquiryContactNameController.text != _origInquiryContactName ||
        _inquiryContactPhoneController.text != _origInquiryContactPhone ||
        _sourceController.text != _origSource ||
        _descriptionController.text != _origDescription ||
        _selectedGender != _origGender ||
        _birthDate != _origBirthDate ||
        _selectedReligiousLevel != _origReligiousLevel ||
        _hebrewBirthYear != _origHebrewBirthYear ||
        _hebrewBirthMonth != _origHebrewBirthMonth ||
        _hebrewBirthDay != _origHebrewBirthDay;
  }

  void _captureOriginals() {
    _captureOriginalValues(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      manualAge: _manualAgeController.text,
      city: _cityController.text,
      phone: _phoneController.text,
      inquiryContactName: _inquiryContactNameController.text,
      inquiryContactPhone: _inquiryContactPhoneController.text,
      source: _sourceController.text,
      description: _descriptionController.text,
      gender: _selectedGender,
      birthDate: _birthDate,
      religiousLevel: _selectedReligiousLevel,
      hebrewBirthYear: _hebrewBirthYear,
      hebrewBirthMonth: _hebrewBirthMonth,
      hebrewBirthDay: _hebrewBirthDay,
    );
  }

  void _captureOriginalValues({
    required String firstName,
    required String lastName,
    required String manualAge,
    required String city,
    required String phone,
    required String inquiryContactName,
    required String inquiryContactPhone,
    required String source,
    required String description,
    required Gender gender,
    required DateTime? birthDate,
    required ReligiousLevel? religiousLevel,
    required int? hebrewBirthYear,
    required int? hebrewBirthMonth,
    required int? hebrewBirthDay,
  }) {
    _origFirstName = firstName;
    _origLastName = lastName;
    _origManualAge = manualAge;
    _origCity = city;
    _origPhone = phone;
    _origInquiryContactName = inquiryContactName;
    _origInquiryContactPhone = inquiryContactPhone;
    _origSource = source;
    _origDescription = description;
    _origGender = gender;
    _origBirthDate = birthDate;
    _origReligiousLevel = religiousLevel;
    _origHebrewBirthYear = hebrewBirthYear;
    _origHebrewBirthMonth = hebrewBirthMonth;
    _origHebrewBirthDay = hebrewBirthDay;
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
    final List<PersonNote> personNotes = personRepository.getNotesForPerson(
      person.id,
    );
    _ensureEditData(person);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop || _isSavingEdit) {
          return;
        }
        final NavigatorState navigator = Navigator.of(context);
        if (!_hasChanges) {
          navigator.pop();
          return;
        }
        final bool saved = await _saveInlineEdit(person, showSnackBar: false);
        if (!saved) return;
        if (mounted) navigator.pop();
      },
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          tooltip: 'שמירה',
          onPressed: _isSavingEdit ? null : () => _saveAndPop(person),
          icon: const Icon(Icons.save),
          label: const Text('שמירה'),
          shape: const StadiumBorder(),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        body: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              stretch: true,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Hero(
                    tag: 'person-${person.id}',
                    child: PersonAvatar(person: person, radius: 16),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      person.fullName.trim(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'שיתוף',
                  onPressed: () => _sharePerson(context, person),
                ),

                PopupMenuButton<String>(
                  onSelected: (String value) async {
                    if (value != 'delete') {
                      return;
                    }

                    final bool shouldDelete = await _confirmDelete(
                      context,
                      person,
                    );
                    if (!shouldDelete) {
                      return;
                    }

                    await personRepository.delete(person.id);
                    if (context.mounted) {
                      context.go('/people');
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('מחיקה'),
                      ),
                    ];
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _DetailHeader(person: person),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _ProfileStatusSection(
                      person: person,
                      repository: personRepository,
                    ),
                    _Section(
                      title: 'תמונות',
                      trailing: TextButton(
                        onPressed: () => _pickAndSavePhoto(context, person),
                        child: const Text('הוספת תמונות'),
                      ),
                      child: _PhotosSection(
                        person: person,
                        onTapPhoto: (int index) =>
                            _openPhotoViewer(context, person, index),
                        onSetPrimary: (int index) =>
                            _setPrimaryPhoto(context, person, index),
                      ),
                    ),
                    _Section(
                      title: 'כרטיסייה לשליחה',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextFormField(
                          controller: _descriptionController,
                          focusNode: _descriptionFocus,
                          textInputAction: TextInputAction.newline,
                          maxLines: 10,
                          minLines: 5,
                          onChanged: (_) => _handleInlineFieldChanged(),
                          decoration: InputDecoration(
                            hintText: 'טקסט לשיתוף בוואטסאפ (5-10 משפטים)',
                            alignLabelWithHint: true,
                            suffixIcon: _descriptionFocus.hasFocus
                                ? IconButton(
                                    icon: const Icon(Icons.check),
                                    tooltip: 'שמירה',
                                    onPressed: () => _saveInlineEdit(person),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _openMatchProposal(context, person),
                              icon: const Icon(Icons.favorite),
                              label: const Text('פתח הצעה'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: () =>
                                  _openWhatsAppMessage(context, person),
                              icon: const FaIcon(FontAwesomeIcons.whatsapp),
                              label: const Text('וואטסאפ'),
                            ),
                            const SizedBox(width: 12),
                            _FavoriteToggleButton(
                              isFavorite: person.isFavorite,
                              onPressed: () =>
                                  personRepository.toggleFavorite(person.id),
                              activeColor: colorScheme.secondary,
                              inactiveColor: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    _InlinePersonEditForm(
                      formKey: _editFormKey,
                      firstNameController: _firstNameController,
                      lastNameController: _lastNameController,
                      manualAgeController: _manualAgeController,
                      phoneController: _phoneController,
                      inquiryContactNameController:
                          _inquiryContactNameController,
                      inquiryContactPhoneController:
                          _inquiryContactPhoneController,
                      firstNameFocus: _firstNameFocus,
                      lastNameFocus: _lastNameFocus,
                      manualAgeFocus: _manualAgeFocus,
                      phoneFocus: _phoneFocus,
                      inquiryContactNameFocus: _inquiryContactNameFocus,
                      inquiryContactPhoneFocus: _inquiryContactPhoneFocus,
                      onSavePressed: () => _saveInlineEdit(person),
                      onFieldChanged: _handleInlineFieldChanged,
                      selectedGender: _selectedGender,
                      birthDate: _birthDate,
                      birthDateCalendar: _birthDateCalendar,
                      birthDatePrimaryText: _birthDatePrimaryText(),
                      birthDateSecondaryText: _birthDateSecondaryText(),
                      selectedReligiousLevel: _selectedReligiousLevel,
                      onGenderChanged: (Gender gender) {
                        setState(() => _selectedGender = gender);
                        unawaited(
                          _saveCurrentInlineEdit(
                            showSnackBar: false,
                            unfocus: false,
                          ),
                        );
                      },
                      onBirthDateTap: _pickBirthDate,
                      onBirthDateCleared: () {
                        setState(() {
                          _birthDate = null;
                          _hebrewBirthYear = null;
                          _hebrewBirthMonth = null;
                          _hebrewBirthDay = null;
                        });
                        unawaited(
                          _saveCurrentInlineEdit(
                            showSnackBar: false,
                            unfocus: false,
                          ),
                        );
                      },
                      onBirthDateCalendarChanged:
                          (_BirthDateCalendar calendar) {
                            setState(() => _birthDateCalendar = calendar);
                          },
                      onReligiousLevelChanged: (ReligiousLevel? level) {
                        setState(() => _selectedReligiousLevel = level);
                        unawaited(
                          _saveCurrentInlineEdit(
                            showSnackBar: false,
                            unfocus: false,
                          ),
                        );
                      },
                    ),
                    _PersonNotesSection(person: person, notes: personNotes),
                    _Section(
                      title: 'הצעות קשורות',
                      child: _RelatedMatchesSection(
                        person: person,
                        matches: relatedMatches,
                        personRepository: personRepository,
                      ),
                    ),
                    _Section(
                      title: 'פרטים נוספים',
                      child: Column(
                        children: <Widget>[
                          if (_birthdayMessage(person, theme)
                              case final Widget birthdayBanner)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: birthdayBanner,
                            ),
                          _DetailRow(
                            label: 'לבירורים',
                            value: _inquiryContactText(person),
                          ),
                          _DetailRow(
                            label: 'נוצר',
                            value: AppDateUtils.formatDate(person.createdAt),
                          ),
                          _DetailRow(
                            label: 'עודכן',
                            value: AppDateUtils.timeAgo(person.updatedAt),
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ensureEditData(Person person) {
    if (_editingPersonId == person.id) {
      return;
    }
    _populateInlineEdit(person);
  }

  void _handleInlineFieldChanged() {
    if (mounted) {
      setState(() {});
    }
    _scheduleInlineAutoSave();
  }

  void _scheduleInlineAutoSave({
    Duration delay = const Duration(milliseconds: 700),
  }) {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(delay, () {
      if (!mounted) return;
      unawaited(_saveCurrentInlineEdit(showSnackBar: false, unfocus: false));
    });
  }

  Future<bool> _saveCurrentInlineEdit({
    bool showSnackBar = true,
    bool unfocus = true,
  }) async {
    if (!mounted || !_hasChanges) {
      return true;
    }

    if (_isSavingEdit) {
      _scheduleInlineAutoSave(delay: const Duration(milliseconds: 300));
      return false;
    }

    final String? personId = _editingPersonId;
    if (personId == null) {
      return false;
    }

    final Person? person = context.read<PersonRepository>().getById(personId);
    if (person == null) {
      return false;
    }

    return _saveInlineEdit(
      person,
      showSnackBar: showSnackBar,
      unfocus: unfocus,
    );
  }

  Future<void> _saveAndPop(Person person) async {
    final bool saved = await _saveInlineEdit(person, showSnackBar: false);
    if (!saved || !mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  void _populateInlineEdit(Person person) {
    _editingPersonId = person.id;
    _firstNameController.text = person.firstName;
    _lastNameController.text = person.lastName;
    _manualAgeController.text = person.manualAge?.toString() ?? '';
    _cityController.text = person.city ?? '';
    _phoneController.text = person.phone ?? '';
    _inquiryContactNameController.text = person.inquiryContactName ?? '';
    _inquiryContactPhoneController.text = person.inquiryContactPhone ?? '';
    _sourceController.text = person.source ?? '';
    _descriptionController.text = person.description ?? '';
    _selectedGender = person.gender;
    _birthDate = person.birthDate;
    _selectedReligiousLevel = person.religiousLevel;
    _hebrewBirthYear = person.hebrewBirthYear;
    _hebrewBirthMonth = person.hebrewBirthMonth;
    _hebrewBirthDay = person.hebrewBirthDay;

    if (_birthDate == null &&
        _hebrewBirthYear != null &&
        _hebrewBirthMonth != null &&
        _hebrewBirthDay != null) {
      _birthDate = HebrewDateUtils.toGregorian(
        year: _hebrewBirthYear!,
        month: _hebrewBirthMonth!,
        day: _hebrewBirthDay!,
      );
      _birthDateCalendar = _BirthDateCalendar.hebrew;
    } else {
      _birthDateCalendar = _BirthDateCalendar.gregorian;
      if (_birthDate != null &&
          (_hebrewBirthYear == null ||
              _hebrewBirthMonth == null ||
              _hebrewBirthDay == null)) {
        final ({int year, int month, int day})? hebrew =
            HebrewDateUtils.fromGregorian(_birthDate!);
        _hebrewBirthYear = hebrew?.year;
        _hebrewBirthMonth = hebrew?.month;
        _hebrewBirthDay = hebrew?.day;
      }
    }
    _captureOriginals();
  }

  Future<bool> _saveInlineEdit(
    Person person, {
    bool showSnackBar = true,
    bool unfocus = true,
  }) async {
    _autoSaveTimer?.cancel();

    if (!_hasChanges) {
      return true;
    }

    if (unfocus) {
      FocusScope.of(context).unfocus();
    }

    if (!_editFormKey.currentState!.validate()) {
      return false;
    }

    setState(() {
      _isSavingEdit = true;
    });

    try {
      final String savedFirstName = _firstNameController.text.trim();
      final String savedLastName = _lastNameController.text.trim();
      final String savedManualAgeText = _manualAgeController.text.trim();
      final String savedCityText = _cityController.text;
      final String savedPhoneText = _phoneController.text;
      final String savedInquiryContactNameText =
          _inquiryContactNameController.text;
      final String savedInquiryContactPhoneText =
          _inquiryContactPhoneController.text;
      final String savedSourceText = _sourceController.text;
      final String savedDescriptionText = _descriptionController.text;
      final Gender savedGender = _selectedGender;
      final DateTime? savedBirthDate = _birthDate;
      final ReligiousLevel? savedReligiousLevel = _selectedReligiousLevel;
      final int? savedHebrewBirthYear = _hebrewBirthYear;
      final int? savedHebrewBirthMonth = _hebrewBirthMonth;
      final int? savedHebrewBirthDay = _hebrewBirthDay;
      final int? manualAge = savedBirthDate == null
          ? int.tryParse(savedManualAgeText)
          : null;
      person
        ..firstName = savedFirstName
        ..lastName = savedLastName
        ..gender = savedGender
        ..birthDate = savedBirthDate
        ..manualAge = manualAge
        ..religiousLevel = savedReligiousLevel
        ..city = _normalizedText(savedCityText)
        ..phone = _normalizedText(savedPhoneText)
        ..inquiryContactName = _normalizedText(savedInquiryContactNameText)
        ..inquiryContactPhone = _normalizedText(savedInquiryContactPhoneText)
        ..source = _normalizedText(savedSourceText)
        ..description = _normalizedText(savedDescriptionText)
        ..hebrewBirthYear = savedHebrewBirthYear
        ..hebrewBirthMonth = savedHebrewBirthMonth
        ..hebrewBirthDay = savedHebrewBirthDay;

      await context.read<PersonRepository>().update(person);

      if (!mounted) {
        return true;
      }

      _captureOriginalValues(
        firstName: savedFirstName,
        lastName: savedLastName,
        manualAge: savedManualAgeText,
        city: savedCityText,
        phone: savedPhoneText,
        inquiryContactName: savedInquiryContactNameText,
        inquiryContactPhone: savedInquiryContactPhoneText,
        source: savedSourceText,
        description: savedDescriptionText,
        gender: savedGender,
        birthDate: savedBirthDate,
        religiousLevel: savedReligiousLevel,
        hebrewBirthYear: savedHebrewBirthYear,
        hebrewBirthMonth: savedHebrewBirthMonth,
        hebrewBirthDay: savedHebrewBirthDay,
      );
      setState(() {
        _isSavingEdit = false;
      });
      if (showSnackBar) {
        _showSnackBar(context, 'השינויים נשמרו');
      }
      return true;
    } finally {
      if (mounted && _isSavingEdit) {
        setState(() {
          _isSavingEdit = false;
        });
      }
    }
  }

  String? _normalizedText(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _inquiryContactText(Person person) {
    final String name = (person.inquiryContactName ?? '').trim();
    final String phone = (person.inquiryContactPhone ?? '').trim();
    if (name.isEmpty && phone.isEmpty) {
      return '—';
    }
    if (name.isEmpty) {
      return phone;
    }
    if (phone.isEmpty) {
      return name;
    }
    return '$name · $phone';
  }

  Future<void> _pickBirthDate() async {
    if (_birthDateCalendar == _BirthDateCalendar.hebrew) {
      await _pickHebrewBirthDate();
      return;
    }
    await _pickGregorianBirthDate();
  }

  Future<void> _pickGregorianBirthDate() async {
    final DateTime now = DateTime.now();
    final DateTime initialDate =
        _birthDate ?? DateTime(now.year - 22, now.month, now.day);

    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(now) ? now : initialDate,
      firstDate: DateTime(now.year - 100, now.month, now.day),
      lastDate: now,
      locale: const Locale('he'),
    );

    if (selectedDate == null) {
      return;
    }

    final ({int year, int month, int day})? hebrew =
        HebrewDateUtils.fromGregorian(selectedDate);

    setState(() {
      _birthDate = selectedDate;
      _hebrewBirthYear = hebrew?.year;
      _hebrewBirthMonth = hebrew?.month;
      _hebrewBirthDay = hebrew?.day;
    });
    unawaited(_saveCurrentInlineEdit(showSnackBar: false, unfocus: false));
  }

  Future<void> _pickHebrewBirthDate() async {
    final DateTime now = DateTime.now();
    final ({int year, int month, int day})? picked =
        await _showHebrewDatePicker();
    if (picked == null) {
      return;
    }

    final DateTime? gregorian = HebrewDateUtils.toGregorian(
      year: picked.year,
      month: picked.month,
      day: picked.day,
    );
    if (gregorian == null || gregorian.isAfter(now)) {
      return;
    }

    setState(() {
      _birthDate = gregorian;
      _hebrewBirthYear = picked.year;
      _hebrewBirthMonth = picked.month;
      _hebrewBirthDay = picked.day;
    });
    unawaited(_saveCurrentInlineEdit(showSnackBar: false, unfocus: false));
  }

  Future<({int year, int month, int day})?> _showHebrewDatePicker() async {
    final DateTime now = DateTime.now();
    final ({int year, int month, int day}) todayHebrew =
        HebrewDateUtils.fromGregorian(now) ?? (year: 5785, month: 1, day: 1);
    final int initYear = _hebrewBirthYear ?? (todayHebrew.year - 22);
    final int initMonth = _hebrewBirthMonth ?? todayHebrew.month;
    final int initDay = _hebrewBirthDay ?? todayHebrew.day;

    int selYear = initYear;
    int selMonth = initMonth;
    int selDay = initDay;

    return showDialog<({int year, int month, int day})>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('בחר תאריך לידה עברי'),
              content: SizedBox(
                width: 320,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selDay,
                        decoration: const InputDecoration(labelText: 'יום'),
                        items: List<DropdownMenuItem<int>>.generate(
                          30,
                          (int i) => DropdownMenuItem<int>(
                            value: i + 1,
                            child: Text('${i + 1}'),
                          ),
                        ),
                        onChanged: (int? v) {
                          if (v != null) {
                            setDialogState(() => selDay = v);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selMonth,
                        decoration: const InputDecoration(labelText: 'חודש'),
                        items: List<DropdownMenuItem<int>>.generate(
                          13,
                          (int i) => DropdownMenuItem<int>(
                            value: i + 1,
                            child: Text(_hebrewMonthName(i + 1)),
                          ),
                        ),
                        onChanged: (int? v) {
                          if (v != null) {
                            setDialogState(() => selMonth = v);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selYear,
                        decoration: const InputDecoration(labelText: 'שנה'),
                        items: List<DropdownMenuItem<int>>.generate(101, (
                          int i,
                        ) {
                          final int y = todayHebrew.year - i;
                          return DropdownMenuItem<int>(
                            value: y,
                            child: Text('$y'),
                          );
                        }),
                        onChanged: (int? v) {
                          if (v != null) {
                            setDialogState(() => selYear = v);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('ביטול'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(
                    ctx,
                  ).pop((year: selYear, month: selMonth, day: selDay)),
                  child: const Text('אישור'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _hebrewMonthName(int month) {
    const List<String> names = <String>[
      'ניסן',
      'אייר',
      'סיוון',
      'תמוז',
      'אב',
      'אלול',
      'תשרי',
      'חשוון',
      'כסלו',
      'טבת',
      'שבט',
      'אדר',
      'אדר ב׳',
    ];
    if (month < 1 || month > names.length) return '$month';
    return names[month - 1];
  }

  String _birthDatePrimaryText() {
    if (_birthDate == null) return 'לא הוזן';
    if (_birthDateCalendar == _BirthDateCalendar.hebrew &&
        _hebrewBirthYear != null &&
        _hebrewBirthMonth != null &&
        _hebrewBirthDay != null) {
      final String formatted = HebrewDateUtils.format(
        year: _hebrewBirthYear!,
        month: _hebrewBirthMonth!,
        day: _hebrewBirthDay!,
      );
      if (formatted.isNotEmpty) return formatted;
    }
    return AppDateUtils.formatDate(_birthDate!);
  }

  String? _birthDateSecondaryText() {
    if (_birthDate == null) return null;
    if (_birthDateCalendar == _BirthDateCalendar.hebrew) {
      return AppDateUtils.formatDate(_birthDate!);
    }
    if (_hebrewBirthYear != null &&
        _hebrewBirthMonth != null &&
        _hebrewBirthDay != null) {
      final String formatted = HebrewDateUtils.format(
        year: _hebrewBirthYear!,
        month: _hebrewBirthMonth!,
        day: _hebrewBirthDay!,
      );
      if (formatted.isNotEmpty) return formatted;
    }
    return null;
  }

  Widget? _birthdayMessage(Person person, ThemeData theme) {
    final int? hebrewMonth = person.hebrewBirthMonth;
    final int? hebrewDay = person.hebrewBirthDay;
    if (hebrewMonth != null &&
        hebrewDay != null &&
        HebrewDateUtils.isBirthdayToday(month: hebrewMonth, day: hebrewDay)) {
      return Text(
        '🎉 היום יום ההולדת העברי!',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final DateTime? birthDate = person.birthDate;
    if (birthDate == null) {
      return null;
    }

    if (AppDateUtils.isBirthdayToday(birthDate)) {
      return Text(
        '🎉 היום יום ההולדת!',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final int? daysUntil = AppDateUtils.daysUntilBirthday(birthDate);
    if (daysUntil != null && daysUntil > 0 && daysUntil <= 7) {
      return Text(
        '🎂 יום הולדת בעוד $daysUntil ימים',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return null;
  }

  Future<void> _pickAndSavePhoto(BuildContext context, Person person) async {
    final PersonRepository repository = context.read<PersonRepository>();

    if (!context.mounted) {
      return;
    }

    final bool hasPermission = await _ensureMediaPermission(context);
    if (!hasPermission || !context.mounted) {
      return;
    }

    try {
      final List<XFile> pickedFiles = await ImagePicker().pickMultiImage();
      if (pickedFiles.isEmpty || !context.mounted) {
        return;
      }

      final Directory documentsDirectory =
          await getApplicationDocumentsDirectory();
      final Directory photosDirectory = Directory(
        '${documentsDirectory.path}${Platform.pathSeparator}photos',
      );

      if (!photosDirectory.existsSync()) {
        photosDirectory.createSync(recursive: true);
      }

      final List<String> copiedPhotoPaths = <String>[];
      final int timestamp = DateTime.now().millisecondsSinceEpoch;

      for (int index = 0; index < pickedFiles.length; index++) {
        final XFile pickedFile = pickedFiles[index];
        final String targetPath =
            '${photosDirectory.path}${Platform.pathSeparator}${person.id}_${timestamp}_$index.jpg';
        await File(pickedFile.path).copy(targetPath);
        copiedPhotoPaths.add(targetPath);
      }

      person.photosPaths = List<String>.from(person.photosPaths)
        ..addAll(copiedPhotoPaths);
      await repository.update(person);

      if (context.mounted) {
        _showSnackBar(
          context,
          copiedPhotoPaths.length == 1
              ? 'התמונה נוספה בהצלחה'
              : '${copiedPhotoPaths.length} תמונות נוספו בהצלחה',
        );
      }
    } on PlatformException catch (error) {
      if (!context.mounted) {
        return;
      }

      if (_looksLikePermissionError(error)) {
        await _showPermissionExplanationDialog(context);
        return;
      }

      _showSnackBar(context, 'לא הצלחנו לבחור תמונה כרגע');
    } catch (_) {
      if (context.mounted) {
        _showSnackBar(context, 'לא הצלחנו לשמור את התמונה');
      }
    }
  }

  Future<void> _setPrimaryPhoto(
    BuildContext context,
    Person person,
    int index,
  ) async {
    if (index <= 0 || index >= person.photosPaths.length) {
      return;
    }

    final List<String> reorderedPhotoPaths = List<String>.from(
      person.photosPaths,
    );
    final String selectedPhotoPath = reorderedPhotoPaths.removeAt(index);
    reorderedPhotoPaths.insert(0, selectedPhotoPath);

    person.photosPaths = reorderedPhotoPaths;
    await context.read<PersonRepository>().update(person);

    if (context.mounted) {
      _showSnackBar(context, 'התמונה הראשית עודכנה');
    }
  }

  Future<void> _openPhotoViewer(
    BuildContext context,
    Person person,
    int initialIndex,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return PhotoViewer(
            personId: person.id,
            photoPaths: person.photosPaths,
            initialIndex: initialIndex,
          );
        },
      ),
    );
  }

  Future<void> _openMatchProposal(
    BuildContext context,
    Person currentPerson,
  ) async {
    final bool saved = await _saveInlineEdit(
      currentPerson,
      showSnackBar: false,
    );
    if (!saved || !context.mounted) {
      return;
    }

    final Person personForProposal =
        context.read<PersonRepository>().getById(currentPerson.id) ??
        currentPerson;

    if (personForProposal.gender == Gender.unknown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש לבחור מגדר לאיש הקשר לפני יצירת הצעה'),
        ),
      );
      return;
    }

    final Gender oppositeGender = personForProposal.gender == Gender.male
        ? Gender.female
        : Gender.male;

    final MatchProposalFilters? filters = await MatchProposalFilterSheet.show(
      context,
      targetGender: oppositeGender,
    );
    if (filters == null || !context.mounted) {
      return;
    }

    final Person? selectedPerson = await PersonPickerSheet.show(
      context,
      title: 'בחרו:',
      filterGender: oppositeGender,
      excludeIds: <String>{personForProposal.id},
      minAge: filters.minAge,
      maxAge: filters.maxAge,
      religiousLevels: filters.religiousLevels,
      profileStatuses: filters.profileStatuses,
    );

    if (selectedPerson == null || !context.mounted) {
      return;
    }

    final Person male = personForProposal.gender == Gender.male
        ? personForProposal
        : selectedPerson;
    final Person female = personForProposal.gender == Gender.female
        ? personForProposal
        : selectedPerson;

    final MatchRepository matchRepository = context.read<MatchRepository>();
    final MatchIdea? existingMatch = matchRepository.findExisting(
      male.id,
      female.id,
    );

    if (existingMatch != null) {
      final bool shouldView = await _showDuplicateMatchDialog(
        context,
        nameA: male.fullName.trim(),
        nameB: female.fullName.trim(),
      );

      if (shouldView && context.mounted) {
        context.push('/matches/${existingMatch.id}');
      }
      return;
    }

    final MatchIdea? newMatch = await matchRepository.create(
      male.id,
      female.id,
    );
    if (newMatch != null && context.mounted) {
      context.push('/matches/${newMatch.id}');
    }
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

  Future<bool> _showDuplicateMatchDialog(
    BuildContext context, {
    required String nameA,
    required String nameB,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('כבר קיימת הצעה'),
          content: Text('כבר קיימת הצעה בין $nameA ל-$nameB'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('סגור'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('צפה בהצעה'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _ensureMediaPermission(BuildContext context) async {
    if (Platform.isAndroid) {
      // `image_picker` uses the system photo picker / intents on Android,
      // so pre-requesting gallery permissions here can incorrectly block
      // the flow on newer Android versions.
      return true;
    }

    final PermissionStatus status = await _requestGalleryPermission();

    if (status.isGranted || status.isLimited) {
      return true;
    }

    if (context.mounted) {
      await _showPermissionExplanationDialog(
        context,
        openSettingsAction: status.isPermanentlyDenied || status.isRestricted,
      );
    }

    return false;
  }

  Future<PermissionStatus> _requestGalleryPermission() async {
    return Permission.photos.request();
  }

  bool _looksLikePermissionError(PlatformException error) {
    final String combined = '${error.code} ${error.message ?? ''}'
        .toLowerCase();
    return combined.contains('denied') || combined.contains('permission');
  }

  Future<void> _showPermissionExplanationDialog(
    BuildContext context, {
    bool openSettingsAction = false,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('נדרשת הרשאה'),
          content: const Text(
            'כדי להוסיף תמונה צריך לאשר גישה לגלריה בהגדרות המכשיר.',
          ),
          actions: <Widget>[
            if (openSettingsAction)
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await openAppSettings();
                },
                child: const Text('פתיחת הגדרות'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('הבנתי'),
            ),
          ],
        );
      },
    );
  }
}

enum _BirthDateCalendar { gregorian, hebrew }

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
    required this.birthDate,
    required this.birthDateCalendar,
    required this.birthDatePrimaryText,
    required this.birthDateSecondaryText,
    required this.selectedReligiousLevel,
    required this.onGenderChanged,
    required this.onBirthDateTap,
    required this.onBirthDateCleared,
    required this.onBirthDateCalendarChanged,
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
  final DateTime? birthDate;
  final _BirthDateCalendar birthDateCalendar;
  final String birthDatePrimaryText;
  final String? birthDateSecondaryText;
  final ReligiousLevel? selectedReligiousLevel;
  final ValueChanged<Gender> onGenderChanged;
  final VoidCallback onBirthDateTap;
  final VoidCallback onBirthDateCleared;
  final ValueChanged<_BirthDateCalendar> onBirthDateCalendarChanged;
  final ValueChanged<ReligiousLevel?> onReligiousLevelChanged;

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
            Text('סגנון דתי', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReligiousLevel.values.map((ReligiousLevel level) {
                final bool selected = selectedReligiousLevel == level;
                return FilterChip(
                  label: Text(level.displayName),
                  selected: selected,
                  onSelected: (bool value) {
                    onReligiousLevelChanged(value && !selected ? level : null);
                  },
                );
              }).toList(),
            ),
            if (birthDate == null) ...<Widget>[
              const SizedBox(height: 16),
              TextFormField(
                controller: manualAgeController,
                focusNode: manualAgeFocus,
                keyboardType: TextInputType.number,
                onChanged: (_) => onFieldChanged(),
                decoration: InputDecoration(
                  labelText: 'גיל (הערכה)',
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
            ],
            const SizedBox(height: 20),
            Text('תאריך לידה', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            InkWell(
              onTap: onBirthDateTap,
              borderRadius: BorderRadius.circular(12),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color:
                      theme.inputDecorationTheme.fillColor ??
                      theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            birthDateCalendar == _BirthDateCalendar.hebrew
                                ? 'תאריך לידה (עברי)'
                                : 'תאריך לידה (לועזי)',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            birthDatePrimaryText,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: birthDate != null
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (birthDateSecondaryText
                              case final String text) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              text,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (birthDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'ניקוי תאריך',
                        onPressed: onBirthDateCleared,
                      )
                    else
                      const Icon(Icons.calendar_today_outlined),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('לוח לועזי'),
                  selected: birthDateCalendar == _BirthDateCalendar.gregorian,
                  onSelected: (bool selected) {
                    if (selected) {
                      onBirthDateCalendarChanged(_BirthDateCalendar.gregorian);
                    }
                  },
                ),
                ChoiceChip(
                  label: const Text('לוח עברי'),
                  selected: birthDateCalendar == _BirthDateCalendar.hebrew,
                  onSelected: (bool selected) {
                    if (selected) {
                      onBirthDateCalendarChanged(_BirthDateCalendar.hebrew);
                    }
                  },
                ),
              ],
            ),
            if (birthDate != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'גיל: ${AppDateUtils.calculateAge(birthDate!)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
            Text('איש קשר לבירורים', style: theme.textTheme.titleMedium),
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

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final File? photoFile = _firstExistingPhoto(person.photosPaths);

    if (photoFile != null) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.file(photoFile, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x00000000), Color(0x99000000)],
              ),
            ),
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.colorScheme.primary,
            theme.colorScheme.primaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            person.fullName.trim(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  File? _firstExistingPhoto(List<String> paths) {
    for (final String path in paths) {
      final File file = File(path);
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }
}

class _ProfileStatusSection extends StatelessWidget {
  const _ProfileStatusSection({required this.person, required this.repository});

  final Person person;
  final PersonRepository repository;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return _Section(
      title: 'סטטוס',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ProfileStatus.values.map((ProfileStatus status) {
              final bool selected = person.profileStatus == status;
              return ChoiceChip(
                label: Text('${status.emoji} ${status.displayName}'),
                selected: selected,
                onSelected: selected
                    ? null
                    : (_) => repository.updateProfileStatus(person.id, status),
                labelStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              );
            }).toList(),
          ),
        ),
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
          _PersonNotesTimeline(entries: entries, dateFormat: _dateFormat),
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
        text: note.text,
        createdAt: note.createdAt,
        isAutomatic: note.isAutomatic,
      );
    }).toList();

    final String legacyNotes = (widget.person.notes ?? '').trim();
    if (legacyNotes.isNotEmpty) {
      entries.add(
        _PersonNoteEntry(
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

  bool get _canSend => _controller.text.trim().isNotEmpty;

  void _handleChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _PersonNoteEntry {
  const _PersonNoteEntry({
    required this.text,
    required this.createdAt,
    required this.isAutomatic,
  });

  final String text;
  final DateTime createdAt;
  final bool isAutomatic;
}

class _PersonNotesTimeline extends StatelessWidget {
  const _PersonNotesTimeline({required this.entries, required this.dateFormat});

  final List<_PersonNoteEntry> entries;
  final DateFormat dateFormat;

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
                            Text(
                              dateFormat.format(entry.createdAt),
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

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({
    required this.person,
    required this.onTapPhoto,
    required this.onSetPrimary,
  });

  final Person person;
  final ValueChanged<int> onTapPhoto;
  final ValueChanged<int> onSetPrimary;

  @override
  Widget build(BuildContext context) {
    if (person.photosPaths.isEmpty) {
      return Text('אין תמונות', style: Theme.of(context).textTheme.bodyMedium);
    }

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: person.photosPaths.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int index) {
          final String path = person.photosPaths[index];
          final File file = File(path);
          return GestureDetector(
            onTap: () => onTapPhoto(index),
            child: Stack(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: file.existsSync()
                      ? Image.file(
                          file,
                          width: 100,
                          height: 120,
                          cacheWidth: 200,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 100,
                          height: 120,
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      tooltip: index == 0
                          ? 'זו התמונה הראשית'
                          : 'בחר כתמונה ראשית',
                      onPressed: index == 0 ? null : () => onSetPrimary(index),
                      icon: Icon(
                        index == 0 ? Icons.star : Icons.star_border,
                        color: index == 0 ? Colors.amber : Colors.white,
                      ),
                    ),
                  ),
                ),
                if (index == 0)
                  PositionedDirectional(
                    bottom: 6,
                    start: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'ראשית',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
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

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () => context.push('/matches/${match.id}'),
              title: Text(
                otherName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _StatusChip(status: match.status),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: title ?? '', trailing: trailing),
          child,
        ],
      ),
    );
  }
}

class _FavoriteToggleButton extends StatefulWidget {
  const _FavoriteToggleButton({
    required this.isFavorite,
    required this.onPressed,
    required this.activeColor,
    required this.inactiveColor,
  });

  final bool isFavorite;
  final Future<void> Function() onPressed;
  final Color activeColor;
  final Color inactiveColor;

  @override
  State<_FavoriteToggleButton> createState() => _FavoriteToggleButtonState();
}

class _FavoriteToggleButtonState extends State<_FavoriteToggleButton> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.isFavorite ? 'הסר ממועדפים' : 'הוסף למועדפים',
      onPressed: _handlePressed,
      icon: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 180),
        child: Icon(
          widget.isFavorite ? Icons.star : Icons.star_outline,
          color: widget.isFavorite ? widget.activeColor : widget.inactiveColor,
        ),
      ),
    );
  }

  Future<void> _handlePressed() async {
    setState(() {
      _scale = 1.3;
    });

    await widget.onPressed();
    if (!mounted) {
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _scale = 1;
      });
    });
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );

    if (isLast) {
      return row;
    }

    return Column(
      children: <Widget>[
        row,
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
      ],
    );
  }
}
