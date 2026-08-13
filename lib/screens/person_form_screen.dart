import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/card_parser.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/device_contact_picker_sheet.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/reminder_picker_sheet.dart';
import 'package:shadchan/services/ai_card_parser.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/incoming_shared_profile_service.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/widgets/person_photo_editor.dart';
import 'package:shadchan/widgets/religious_level_picker.dart';
import 'package:uuid/uuid.dart';

class PersonFormScreen extends StatefulWidget {
  const PersonFormScreen({super.key, this.personId, this.incomingDraft});

  final String? personId;
  final IncomingSharedProfileDraft? incomingDraft;

  @override
  State<PersonFormScreen> createState() => _PersonFormScreenState();
}

class _PersonFormScreenState extends State<PersonFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _manualAgeController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _inquiryContactNameController =
      TextEditingController();
  final TextEditingController _inquiryContactPhoneController =
      TextEditingController();
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  // A free-text personal note added on save straight to the person's notes
  // timeline ("אזור ההערות בכרטיס"). Starts empty even when editing, since it
  // appends a new note rather than showing the existing ones.
  final TextEditingController _personalNotesController =
      TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final Uuid _uuid = const Uuid();
  late final String _draftPersonId = _uuid.v4();

  Gender _selectedGender = Gender.male;
  ReligiousLevel? _selectedReligiousLevel;
  String? _religiousLevelOther;
  ProfileStatus _selectedProfileStatus = ProfileStatus.available;
  MaritalStatus? _selectedMaritalStatus;

  /// Fields last written by the card parser rather than by the user. They may
  /// be overwritten by a later parse; anything the user typed themselves is
  /// never touched.
  final Set<String> _autoFilledFields = <String>{};
  Person? _person;
  _PersonFormSnapshot? _initialSnapshot;
  final Set<String> _newPhotoPaths = <String>{};
  List<String> _photoPaths = <String>[];
  bool _didLoadInitialData = false;
  bool _isSaving = false;
  bool _isReadingWithAi = false;
  bool _cardHasText = false;
  bool _isImportingIncomingPhotos = false;

  bool get _isEditMode =>
      widget.personId != null && widget.personId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Watching the controller rather than the onChanged callback catches every
    // way the card text arrives — typed, loaded from an existing person, or
    // filled from an incoming share — so the AI button's visibility can never
    // fall out of step with the field.
    _descriptionController.addListener(_syncCardHasText);
    // Warmed here rather than on tap: bringing Firebase up takes a moment, and
    // the button should be ready by the time a pasted card fails to parse.
    unawaited(FirebaseBootstrap.ensureReady());
  }

  void _syncCardHasText() {
    final bool hasText = _descriptionController.text.trim().isNotEmpty;
    if (hasText != _cardHasText) {
      setState(() => _cardHasText = hasText);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadInitialData) {
      return;
    }

    if (_isEditMode) {
      _person = context.read<PersonRepository>().getById(widget.personId!);
      if (_person != null) {
        _populateFromPerson(_person!);
      }
    }

    _applyIncomingDraft(widget.incomingDraft);
    _initialSnapshot = _currentSnapshot();
    _didLoadInitialData = true;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _manualAgeController.dispose();
    _heightController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    _inquiryContactNameController.dispose();
    _inquiryContactPhoneController.dispose();
    _sourceController.dispose();
    _notesController.dispose();
    _personalNotesController.dispose();
    _descriptionController.removeListener(_syncCardHasText);
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }

        final bool shouldPop = await _handleWillPop();
        if (shouldPop && context.mounted) {
          if (_hasUnsavedChanges) {
            _deleteNewPhotos();
          }
          context.pop(result);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _handleBackPressed,
            ),
            title: Text(_isEditMode ? 'עריכת פרטים' : 'הוספת כרטיס'),
            centerTitle: true,
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.check),
                tooltip: 'שמירה',
                onPressed: _isSaving || _isImportingIncomingPhotos
                    ? null
                    : _save,
              ),
            ],
          ),

          body: _buildBody(theme),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _isSaving || _isImportingIncomingPhotos ? null : _save,
            icon: _isSaving || _isImportingIncomingPhotos
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('שמירה'),
            shape: const StadiumBorder(),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isEditMode && _person == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.person_off_outlined,
                size: 72,
                color: theme.colorScheme.primaryContainer,
              ),
              const SizedBox(height: 16),
              Text(
                'האדם לא נמצא',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text('חזרה'),
              ),
            ],
          ),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _PersonFormIntro(isEditMode: _isEditMode),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: theme.colorScheme.outlineVariant),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.045),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _FormSectionHeading(
                    icon: Icons.badge_outlined,
                    title: 'הכרטיס והתמונות',
                    subtitle: 'אפשר להתחיל מהכרטיס ולתת לפרטים להתמלא',
                  ),
                  const SizedBox(height: 16),
                  PersonPhotoEditor(
                    photoPaths: _photoPaths,
                    onAddPhoto: _pickPhotos,
                    onSetPrimary: _setPrimaryPhoto,
                  ),
                  const SizedBox(height: 20),
                  // Pasting the card here fills the fields below through
                  // [CardParser], so the common case is paste-then-review.
                  TextFormField(
                    controller: _descriptionController,
                    textInputAction: TextInputAction.newline,
                    maxLines: 10,
                    minLines: 5,
                    onChanged: _handleCardTextChanged,
                    decoration: const InputDecoration(
                      labelText: 'כרטיסייה לשליחה',
                      hintText: 'הדבק כרטיסייה כאן',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.auto_fix_high_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'הפרטים שלמטה יתמלאו אוטומטית מהכרטיסייה. אפשר לתקן הכל ידנית.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Offered only once there is something to read, and only where
                  // Firebase came up. The card text is sent to Gemini, so this stays
                  // a deliberate tap rather than something that happens on its own.
                  if (_cardHasText)
                    ValueListenableBuilder<bool>(
                      valueListenable: FirebaseBootstrap.readyListenable,
                      builder: (BuildContext context, bool ready, _) {
                        if (!ready) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: _isReadingWithAi
                                  ? null
                                  : _readCardWithAi,
                              icon: _isReadingWithAi
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.auto_awesome_outlined,
                                      size: 18,
                                    ),
                              label: Text(
                                _isReadingWithAi
                                    ? 'קורא…'
                                    : 'לא זוהו פרטים? קרא עם AI',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  const _FormSectionDivider(),
                  const _FormSectionHeading(
                    icon: Icons.person_outline_rounded,
                    title: 'פרטים אישיים',
                    subtitle: 'המידע שיעזור להכיר ולחשוב על התאמה',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _firstNameController,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _autoFilledFields.remove('firstName'),
                    decoration: const InputDecoration(labelText: 'שם פרטי'),
                    validator: (String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'יש להזין שם פרטי';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _lastNameController,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _autoFilledFields.remove('lastName'),
                    decoration: const InputDecoration(labelText: 'שם משפחה'),
                    validator: (String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'יש להזין שם משפחה';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  ReligiousLevelPicker(
                    selected: ReligiousLevelChoice(
                      _selectedReligiousLevel,
                      _religiousLevelOther,
                    ),
                    onChanged: (ReligiousLevelChoice choice) {
                      setState(() {
                        _selectedReligiousLevel = choice.level;
                        _religiousLevelOther = choice.customLabel;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  Text('סטטוס', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _ProfileStatusSelector(
                    selected: _selectedProfileStatus,
                    options: <ProfileStatus>[
                      ProfileStatus.available,
                      ProfileStatus.busy,
                      ProfileStatus.onBreak,
                      if (_isEditMode &&
                          _selectedProfileStatus == ProfileStatus.mazelTov)
                        ProfileStatus.mazelTov,
                    ],
                    onSelected: (ProfileStatus status) {
                      setState(() => _selectedProfileStatus = status);
                    },
                  ),
                  const SizedBox(height: 20),
                  Text('מגדר', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: Gender.values.map((Gender gender) {
                      return ChoiceChip(
                        label: Text(gender.displayName),
                        selected: _selectedGender == gender,
                        onSelected: (bool selected) {
                          if (!selected) {
                            return;
                          }

                          setState(() {
                            _selectedGender = gender;
                            _autoFilledFields.remove('gender');
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _manualAgeController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _autoFilledFields.remove('age'),
                    decoration: const InputDecoration(
                      labelText: 'גיל',
                      helperText: 'הגיל מתעדכן אוטומטית פעם בשנה',
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
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _autoFilledFields.remove('height'),
                    decoration: const InputDecoration(
                      labelText: 'גובה',
                      suffixText: 'ס״מ',
                      hintText: 'לדוגמה: 170',
                    ),
                    validator: (String? value) {
                      final String trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) {
                        return null;
                      }

                      final int? parsed = int.tryParse(trimmed);
                      if (parsed == null || parsed < 120 || parsed > 220) {
                        return 'יש להזין גובה בסנטימטרים (120-220)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  Text('מצב משפחתי', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: MaritalStatus.values.map((MaritalStatus status) {
                      final bool selected = _selectedMaritalStatus == status;
                      return ChoiceChip(
                        label: Text(status.displayNameFor(_selectedGender)),
                        selected: selected,
                        onSelected: (bool value) {
                          setState(() {
                            _selectedMaritalStatus = value && !selected
                                ? status
                                : null;
                            _autoFilledFields.remove('maritalStatus');
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _cityController,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _autoFilledFields.remove('city'),
                    decoration: const InputDecoration(labelText: 'מיקום'),
                  ),
                  const _FormSectionDivider(),
                  const _FormSectionHeading(
                    icon: Icons.contact_phone_outlined,
                    title: 'יצירת קשר',
                    subtitle: 'הטלפון של המועמד ופרטי איש הקשר לבירורים',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'טלפון',
                      hintText: 'לדוגמה: 050-1234567',
                      suffixIcon: IconButton(
                        tooltip: 'בחירה מאנשי הקשר',
                        icon: const Icon(Icons.contacts_outlined),
                        onPressed: _pickPhoneFromDevice,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        'איש קשר לבירורים',
                        style: theme.textTheme.titleMedium,
                      ),
                      TextButton.icon(
                        onPressed: _pickInquiryContactFromDevice,
                        icon: const Icon(Icons.contacts_outlined, size: 18),
                        label: const Text('בחירה מאנשי הקשר'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _inquiryContactNameController,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) =>
                              _autoFilledFields.remove('contactName'),
                          decoration: const InputDecoration(
                            labelText: 'שם',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _inquiryContactPhoneController,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.phone,
                          onChanged: (_) =>
                              _autoFilledFields.remove('contactPhone'),
                          decoration: const InputDecoration(
                            labelText: 'טלפון',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const _FormSectionDivider(),
                  const _FormSectionHeading(
                    icon: Icons.notes_rounded,
                    title: 'הערה אישית',
                    subtitle: 'מידע פנימי שיופיע ביומן הכרטיס',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _personalNotesController,
                    textInputAction: TextInputAction.newline,
                    maxLines: 5,
                    minLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'הערות אישיות',
                      hintText: 'הערה שתתווסף ליומן ההערות בכרטיס',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Re-reads the pasted card and fills any field the user has not typed into
  /// themselves. Fields the parser filled earlier are refreshed, so correcting
  /// the pasted text corrects the form with it.
  void _handleCardTextChanged(String value) {
    final ParsedCard parsed = CardParser.parse(value);
    if (parsed.isEmpty) {
      return;
    }
    _applyParsedCard(parsed);
  }

  /// Sends the pasted card to Gemini, for the messy ones [CardParser] cannot
  /// read. Only ever runs on an explicit tap: the local parser re-runs on every
  /// keystroke, and this must not.
  Future<void> _readCardWithAi() async {
    if (_isReadingWithAi) {
      return;
    }
    setState(() => _isReadingWithAi = true);
    try {
      final ParsedCard parsed = await AiCardParser.parse(
        _descriptionController.text,
      );
      if (!mounted) {
        return;
      }
      _applyParsedCard(parsed);
    } on AiParseException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_aiFailureMessage(error.reason))));
    } finally {
      if (mounted) {
        setState(() => _isReadingWithAi = false);
      }
    }
  }

  String _aiFailureMessage(AiParseFailure reason) {
    switch (reason) {
      case AiParseFailure.empty:
        return 'לא נמצאו פרטים בכרטיסייה. אפשר למלא ידנית.';
      case AiParseFailure.network:
        return 'לא הצלחנו להתחבר. בדוק את החיבור לאינטרנט ונסה שוב.';
      case AiParseFailure.unavailable:
        return 'הקריאה החכמה אינה זמינה כרגע.';
      case AiParseFailure.attestation:
        return 'המכשיר הזה לא מאושר לשימוש ב‑AI.';
      case AiParseFailure.unknown:
        return 'משהו השתבש בקריאת הכרטיסייה. אפשר למלא ידנית.';
    }
  }

  /// Fills the form from a parsed card, whoever parsed it. Shared by the local
  /// [CardParser] pass and the Gemini fallback so a card read by the model can
  /// never reach a field by a route the local parser does not also take.
  void _applyParsedCard(ParsedCard parsed) {
    setState(() {
      _applyParsedText('firstName', _firstNameController, parsed.firstName);
      _applyParsedText('lastName', _lastNameController, parsed.lastName);
      _applyParsedText('age', _manualAgeController, parsed.age?.toString());
      _applyParsedText(
        'height',
        _heightController,
        parsed.heightCm?.toString(),
      );
      _applyParsedText('city', _cityController, parsed.city);
      // The "איש קשר לבירורים" line inside a pasted card belongs to whoever
      // sent the card, so it is deliberately not copied into the contact
      // fields — those are filled by hand or from the device contacts.

      if (parsed.gender != null && _canAutoFillChoice('gender')) {
        _selectedGender = parsed.gender!;
        _autoFilledFields.add('gender');
      }
      if (parsed.maritalStatus != null &&
          (_selectedMaritalStatus == null ||
              _autoFilledFields.contains('maritalStatus'))) {
        _selectedMaritalStatus = parsed.maritalStatus;
        _autoFilledFields.add('maritalStatus');
      }
    });
  }

  void _applyParsedText(
    String key,
    TextEditingController controller,
    String? value,
  ) {
    if (value == null || value.isEmpty) {
      return;
    }
    if (controller.text.trim().isNotEmpty && !_autoFilledFields.contains(key)) {
      return;
    }
    if (controller.text == value) {
      return;
    }
    controller.text = value;
    _autoFilledFields.add(key);
  }

  /// A choice chip counts as "free to fill" while it still holds the default
  /// the form opened with, or while the parser owns it.
  bool _canAutoFillChoice(String key) =>
      _autoFilledFields.contains(key) || !_userTouchedGender;

  bool get _userTouchedGender =>
      !_autoFilledFields.contains('gender') &&
      _selectedGender != Gender.male &&
      _selectedGender != Gender.unknown;

  Future<void> _pickInquiryContactFromDevice() async {
    FocusScope.of(context).unfocus();
    final DeviceContactChoice? choice = await DeviceContactPickerSheet.show(
      context,
    );
    if (choice == null || !mounted) {
      return;
    }

    setState(() {
      _inquiryContactNameController.text = choice.name;
      _inquiryContactPhoneController.text = choice.phone;
      _autoFilledFields.removeAll(<String>['contactName', 'contactPhone']);
    });
  }

  /// Fills the person's own phone number from the device contacts.
  Future<void> _pickPhoneFromDevice() async {
    FocusScope.of(context).unfocus();
    final DeviceContactChoice? choice = await DeviceContactPickerSheet.show(
      context,
    );
    if (choice == null || !mounted) {
      return;
    }

    setState(() {
      _phoneController.text = choice.phone;
      // An empty name field is a good sign this contact is the person, so fill
      // it in too rather than making the user type it twice.
      if (_firstNameController.text.trim().isEmpty &&
          _lastNameController.text.trim().isEmpty &&
          choice.name.trim().isNotEmpty) {
        final List<String> words = choice.name.trim().split(RegExp(r'\s+'));
        _firstNameController.text = words.first;
        _lastNameController.text = words.length > 1
            ? words.sublist(1).join(' ')
            : '';
        _autoFilledFields.removeAll(<String>['firstName', 'lastName']);
      }
    });
  }

  Future<void> _handleBackPressed() async {
    final bool shouldPop = await _handleWillPop();
    if (shouldPop && mounted) {
      if (_hasUnsavedChanges) {
        _deleteNewPhotos();
      }
      context.pop();
    }
  }

  Future<bool> _handleWillPop() async {
    FocusScope.of(context).unfocus();

    if (!_hasUnsavedChanges) {
      return true;
    }

    return ConfirmDialog.show(
      context,
      title: 'לצאת בלי לשמור?',
      message: 'יש שינויים שלא נשמרו. האם לצאת בכל זאת?',
      confirmText: 'יציאה',
      cancelText: 'המשך עריכה',
      isDestructive: true,
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (_isImportingIncomingPhotos) {
      _showSnackBar('רק רגע, התמונה ששותפה עדיין מתווספת לטופס');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final PersonRepository repository = context.read<PersonRepository>();
    final String firstName = _firstNameController.text.trim();
    final String lastName = _lastNameController.text.trim();
    final int? manualAge = int.tryParse(_manualAgeController.text.trim());
    final int? heightCm = int.tryParse(_heightController.text.trim());
    final bool shouldOfferStatusReminder =
        _selectedProfileStatus.pausesMatches &&
        (!_isEditMode ||
            _initialSnapshot?.profileStatus != _selectedProfileStatus);

    try {
      if (_isEditMode && _person != null) {
        _person!
          ..firstName = firstName
          ..lastName = lastName
          ..gender = _selectedGender
          ..setManualAge(manualAge)
          ..religiousLevel = _selectedReligiousLevel
          ..religiousLevelOther = _religiousLevelOther
          ..city = _normalizedText(_cityController.text)
          ..phone = _normalizedText(_phoneController.text)
          ..source = _normalizedText(_sourceController.text)
          ..notes = _normalizedText(_notesController.text)
          ..description = _normalizedText(_descriptionController.text)
          ..inquiryContactName = _normalizedText(
            _inquiryContactNameController.text,
          )
          ..inquiryContactPhone = _normalizedText(
            _inquiryContactPhoneController.text,
          )
          ..heightCm = heightCm
          ..maritalStatus = _selectedMaritalStatus
          ..profileStatus = _selectedProfileStatus
          ..photosPaths = List<String>.from(_photoPaths);

        await repository.update(_person!);
      } else {
        final DateTime now = DateTime.now();
        final Person person = Person(
          id: _draftPersonId,
          firstName: firstName,
          lastName: lastName,
          gender: _selectedGender,
          manualAge: manualAge,
          manualAgeUpdatedAt: manualAge != null ? now : null,
          religiousLevel: _selectedReligiousLevel,
          religiousLevelOther: _religiousLevelOther,
          city: _normalizedText(_cityController.text),
          phone: _normalizedText(_phoneController.text),
          source: _normalizedText(_sourceController.text),
          notes: _normalizedText(_notesController.text),
          description: _normalizedText(_descriptionController.text),
          inquiryContactName: _normalizedText(
            _inquiryContactNameController.text,
          ),
          inquiryContactPhone: _normalizedText(
            _inquiryContactPhoneController.text,
          ),
          heightCm: heightCm,
          maritalStatus: _selectedMaritalStatus,
          profileStatus: _selectedProfileStatus,
          photosPaths: List<String>.from(_photoPaths),
          createdAt: now,
          updatedAt: now,
        );

        await repository.add(person);
      }

      // A personal note typed in the form is appended straight to the person's
      // notes timeline ("אזור ההערות בכרטיס").
      final String personalNote = _personalNotesController.text.trim();
      if (personalNote.isNotEmpty) {
        final String personId = _person?.id ?? _draftPersonId;
        await repository.addNote(personId, personalNote);
      }

      if (!mounted) {
        return;
      }

      _personalNotesController.clear();
      _initialSnapshot = _currentSnapshot();
      _newPhotoPaths.clear();

      // Saving always lands on the person's own profile, so the details (and
      // any photo just added) can be seen straight away.
      final String savedPersonId = _person?.id ?? _draftPersonId;
      if (shouldOfferStatusReminder) {
        final ReminderChoice? reminder = await ReminderPickerSheet.show(
          context,
          title: 'מתי להזכיר לך לבדוק שוב?',
          allowSkip: true,
          recommendedLabel: 'עוד חודש',
          intervalsBuilder: ReminderPickerSheet.statusCheckIntervals,
        );
        if (reminder?.date != null) {
          await repository.setPersonReminder(savedPersonId, reminder!.date!);
        }
        if (!mounted) {
          return;
        }
      }
      context.pushReplacement('/people/$savedPersonId');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _populateFromPerson(Person person) {
    _firstNameController.text = person.firstName;
    _lastNameController.text = person.lastName;
    // Show the up-to-date age (manual age advances over time) so editing it
    // re-anchors from the value the user actually sees. Legacy records whose
    // age came from a birth date show that computed age instead, and saving
    // converts it into a plain stored age.
    _manualAgeController.text = person.age?.toString() ?? '';
    _heightController.text = person.heightCm?.toString() ?? '';
    _cityController.text = person.city ?? '';
    _phoneController.text = person.phone ?? '';
    _inquiryContactNameController.text = person.inquiryContactName ?? '';
    _inquiryContactPhoneController.text = person.inquiryContactPhone ?? '';
    _sourceController.text = person.source ?? '';
    _notesController.text = person.notes ?? '';
    _descriptionController.text = person.description ?? '';
    _selectedGender = person.gender == Gender.unknown
        ? Gender.male
        : person.gender;
    _selectedReligiousLevel = person.religiousLevel;
    _religiousLevelOther = person.religiousLevelOther;
    _selectedProfileStatus = person.profileStatus;
    _selectedMaritalStatus = person.maritalStatus;
    _photoPaths = List<String>.from(person.photosPaths);
  }

  void _applyIncomingDraft(IncomingSharedProfileDraft? draft) {
    if (draft == null || !draft.hasContent) {
      return;
    }

    if (!_isEditMode) {
      _selectedGender = Gender.unknown;
    }

    // A share that carries photos never fills the card text: what rides along
    // with an image is the sender's attribution, not profile information.
    final String? sharedText = draft.filePaths.isEmpty
        ? draft.text?.trim()
        : null;
    if (sharedText != null && sharedText.isNotEmpty) {
      final String existingDescription = _descriptionController.text.trim();
      if (existingDescription.isEmpty) {
        _descriptionController.text = sharedText;
      } else if (!existingDescription.contains(sharedText)) {
        _descriptionController.text = '$existingDescription\n\n$sharedText';
      }
    }

    if (draft.filePaths.isNotEmpty) {
      unawaited(_copyIncomingPhotos(draft.filePaths));
    }
  }

  _PersonFormSnapshot _currentSnapshot() {
    return _PersonFormSnapshot(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      gender: _selectedGender,
      manualAge: int.tryParse(_manualAgeController.text.trim()),
      heightCm: int.tryParse(_heightController.text.trim()),
      maritalStatus: _selectedMaritalStatus,
      religiousLevel: _selectedReligiousLevel,
      city: _normalizedText(_cityController.text),
      phone: _normalizedText(_phoneController.text),
      inquiryContactName: _normalizedText(_inquiryContactNameController.text),
      inquiryContactPhone: _normalizedText(_inquiryContactPhoneController.text),
      source: _normalizedText(_sourceController.text),
      notes: _normalizedText(_notesController.text),
      personalNote: _normalizedText(_personalNotesController.text),
      description: _normalizedText(_descriptionController.text),
      profileStatus: _selectedProfileStatus,
      photoPaths: _photoPaths,
    );
  }

  Future<void> _pickPhotos() async {
    final List<String> copiedPhotoPaths = await PhotoPickerService.pickPhotos(
      context,
      personId: _person?.id ?? _draftPersonId,
    );
    if (copiedPhotoPaths.isEmpty || !mounted) {
      return;
    }

    // No "remember to save" banner here — it covered the save button, and the
    // new photos are already visible in the editor above.
    setState(() {
      _photoPaths = List<String>.from(_photoPaths)..addAll(copiedPhotoPaths);
      _newPhotoPaths.addAll(copiedPhotoPaths);
    });
  }

  Future<void> _copyIncomingPhotos(List<String> sourcePaths) async {
    _isImportingIncomingPhotos = true;
    try {
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
      final String personId = _person?.id ?? _draftPersonId;

      for (int index = 0; index < sourcePaths.length; index++) {
        final File sourceFile = File(sourcePaths[index]);
        if (!sourceFile.existsSync()) {
          continue;
        }

        final String extension = _extensionForPath(sourceFile.path);
        final String targetPath =
            '${photosDirectory.path}${Platform.pathSeparator}${personId}_${timestamp}_shared_$index$extension';
        await sourceFile.copy(targetPath);
        copiedPhotoPaths.add(targetPath);
      }

      if (copiedPhotoPaths.isEmpty || !mounted) {
        return;
      }

      setState(() {
        _photoPaths = List<String>.from(_photoPaths)..addAll(copiedPhotoPaths);
        _newPhotoPaths.addAll(copiedPhotoPaths);
      });
    } catch (_) {
      if (mounted) {
        _showSnackBar('לא הצלחנו להוסיף את התמונה ששותפה');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImportingIncomingPhotos = false;
        });
      } else {
        _isImportingIncomingPhotos = false;
      }
    }
  }

  String _extensionForPath(String path) {
    final String fileName = path.split(RegExp(r'[\\/]')).last;
    final int dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return '.jpg';
    }

    final String extension = fileName.substring(dotIndex).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)
        ? extension
        : '.jpg';
  }

  void _setPrimaryPhoto(int index) {
    if (index <= 0 || index >= _photoPaths.length) {
      return;
    }

    setState(() {
      final List<String> reorderedPhotoPaths = List<String>.from(_photoPaths);
      final String selectedPhotoPath = reorderedPhotoPaths.removeAt(index);
      reorderedPhotoPaths.insert(0, selectedPhotoPath);
      _photoPaths = reorderedPhotoPaths;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _deleteNewPhotos() {
    PhotoPickerService.deletePhotoFiles(_newPhotoPaths);
    _newPhotoPaths.clear();
  }

  String? _normalizedText(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get _hasUnsavedChanges {
    final _PersonFormSnapshot? initialSnapshot = _initialSnapshot;
    if (initialSnapshot == null) {
      return false;
    }

    return initialSnapshot != _currentSnapshot();
  }
}

class _PersonFormIntro extends StatelessWidget {
  const _PersonFormIntro({required this.isEditMode});

  final bool isEditMode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[
            theme.colorScheme.primaryContainer,
            Color.alphaBlend(
              theme.colorScheme.secondaryContainer.withValues(alpha: 0.62),
              theme.colorScheme.surface,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.78),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isEditMode ? Icons.edit_note_rounded : Icons.person_add_alt_1,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  isEditMode ? 'עדכון הכרטיס' : 'כרטיס חדש למאגר',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isEditMode
                      ? 'כל הפרטים נשמרים מקומית וניתנים לעדכון בכל זמן'
                      : 'אפשר להוסיף רק את מה שידוע עכשיו ולהשלים בהמשך',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
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

class _FormSectionHeading extends StatelessWidget {
  const _FormSectionHeading({
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormSectionDivider extends StatelessWidget {
  const _FormSectionDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _ProfileStatusSelector extends StatelessWidget {
  const _ProfileStatusSelector({
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  final ProfileStatus selected;
  final List<ProfileStatus> options;
  final ValueChanged<ProfileStatus> onSelected;

  IconData _iconFor(ProfileStatus status) {
    switch (status) {
      case ProfileStatus.available:
        return Icons.person_outline_rounded;
      case ProfileStatus.busy:
        return Icons.hourglass_top_rounded;
      case ProfileStatus.onBreak:
        return Icons.coffee_outlined;
      case ProfileStatus.mazelTov:
        return Icons.celebration_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = options.length > 3 ? 2 : options.length;
        final double width =
            (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final ProfileStatus status in options)
              SizedBox(
                width: width,
                child: Material(
                  color: selected == status
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onSelected(status),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 68),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected == status
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.45,
                                )
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            _iconFor(status),
                            size: 21,
                            color: selected == status
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            status.displayName,
                            maxLines: 1,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: selected == status
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PersonFormSnapshot {
  _PersonFormSnapshot({
    required this.firstName,
    required this.lastName,
    required this.gender,
    required this.manualAge,
    required this.heightCm,
    required this.maritalStatus,
    required this.religiousLevel,
    required this.city,
    required this.phone,
    required this.inquiryContactName,
    required this.inquiryContactPhone,
    required this.source,
    required this.notes,
    required this.personalNote,
    required this.description,
    required this.profileStatus,
    required List<String> photoPaths,
  }) : photoPaths = List<String>.unmodifiable(photoPaths);

  final String firstName;
  final String lastName;
  final Gender gender;
  final int? manualAge;
  final int? heightCm;
  final MaritalStatus? maritalStatus;
  final ReligiousLevel? religiousLevel;
  final String? city;
  final String? phone;
  final String? inquiryContactName;
  final String? inquiryContactPhone;
  final String? source;
  final String? notes;
  final String? personalNote;
  final String? description;
  final ProfileStatus profileStatus;
  final List<String> photoPaths;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is _PersonFormSnapshot &&
        other.firstName == firstName &&
        other.lastName == lastName &&
        other.gender == gender &&
        other.manualAge == manualAge &&
        other.heightCm == heightCm &&
        other.maritalStatus == maritalStatus &&
        other.religiousLevel == religiousLevel &&
        other.city == city &&
        other.phone == phone &&
        other.inquiryContactName == inquiryContactName &&
        other.inquiryContactPhone == inquiryContactPhone &&
        other.source == source &&
        other.notes == notes &&
        other.personalNote == personalNote &&
        other.description == description &&
        other.profileStatus == profileStatus &&
        listEquals(other.photoPaths, photoPaths);
  }

  @override
  int get hashCode {
    return Object.hash(
      firstName,
      lastName,
      gender,
      manualAge,
      heightCm,
      maritalStatus,
      religiousLevel,
      city,
      phone,
      inquiryContactName,
      inquiryContactPhone,
      source,
      notes,
      personalNote,
      description,
      profileStatus,
      Object.hashAll(photoPaths),
    );
  }
}
