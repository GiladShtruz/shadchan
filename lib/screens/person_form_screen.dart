import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/hebrew_date_utils.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/services/incoming_shared_profile_service.dart';
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
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _inquiryContactNameController =
      TextEditingController();
  final TextEditingController _inquiryContactPhoneController =
      TextEditingController();
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final Uuid _uuid = const Uuid();
  late final String _draftPersonId = _uuid.v4();

  Gender _selectedGender = Gender.male;
  DateTime? _birthDate;
  int? _hebrewBirthYear;
  int? _hebrewBirthMonth;
  int? _hebrewBirthDay;
  _BirthDateCalendar _birthDateCalendar = _BirthDateCalendar.gregorian;
  ReligiousLevel? _selectedReligiousLevel;
  ProfileStatus _selectedProfileStatus = ProfileStatus.available;
  Person? _person;
  _PersonFormSnapshot? _initialSnapshot;
  final Set<String> _newPhotoPaths = <String>{};
  List<String> _photoPaths = <String>[];
  bool _didLoadInitialData = false;
  bool _isSaving = false;
  bool _isImportingIncomingPhotos = false;

  bool get _isEditMode =>
      widget.personId != null && widget.personId!.isNotEmpty;

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
    _cityController.dispose();
    _phoneController.dispose();
    _inquiryContactNameController.dispose();
    _inquiryContactPhoneController.dispose();
    _sourceController.dispose();
    _notesController.dispose();
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
            title: Text(_isEditMode ? 'עריכת פרטים' : 'הוספת איש קשר'),
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
            label: const Text('שמור'),
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
            TextFormField(
              controller: _firstNameController,
              textInputAction: TextInputAction.next,
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
              decoration: const InputDecoration(labelText: 'שם משפחה'),
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return 'יש להזין שם משפחה';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _PhotoEditor(
              photoPaths: _photoPaths,
              onAddPhoto: _pickPhotos,
              onSetPrimary: _setPrimaryPhoto,
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
                    });
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
                final bool selected = _selectedReligiousLevel == level;
                return ChoiceChip(
                  label: Text(level.displayName),
                  selected: selected,
                  onSelected: (bool value) {
                    setState(() {
                      _selectedReligiousLevel = value && !selected
                          ? level
                          : null;
                    });
                  },
                );
              }).toList(),
            ),
            if (_birthDate == null) ...<Widget>[
              const SizedBox(height: 20),
              TextFormField(
                controller: _manualAgeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'גיל (הערכה)'),
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
              onTap: _pickBirthDate,
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
                            _birthDateCalendar == _BirthDateCalendar.hebrew
                                ? 'תאריך לידה (עברי)'
                                : 'תאריך לידה (לועזי)',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _birthDatePrimaryText(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _birthDate != null
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (_birthDateSecondaryText()
                              case final String txt) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              txt,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_birthDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'ניקוי תאריך',
                        onPressed: () {
                          setState(() {
                            _birthDate = null;
                            _hebrewBirthYear = null;
                            _hebrewBirthMonth = null;
                            _hebrewBirthDay = null;
                          });
                        },
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
                  selected: _birthDateCalendar == _BirthDateCalendar.gregorian,
                  onSelected: (bool v) {
                    if (!v) return;
                    setState(() {
                      _birthDateCalendar = _BirthDateCalendar.gregorian;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('לוח עברי'),
                  selected: _birthDateCalendar == _BirthDateCalendar.hebrew,
                  onSelected: (bool v) {
                    if (!v) return;
                    setState(() {
                      _birthDateCalendar = _BirthDateCalendar.hebrew;
                    });
                  },
                ),
              ],
            ),
            if (_birthDate != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'גיל: ${AppDateUtils.calculateAge(_birthDate!)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text('איש קשר לבירורים', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _inquiryContactNameController,
                    textInputAction: TextInputAction.next,
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
                    decoration: const InputDecoration(
                      labelText: 'טלפון',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('סטטוס', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ProfileStatus.values.map((ProfileStatus status) {
                final bool selected = _selectedProfileStatus == status;
                return ChoiceChip(
                  label: Text('${status.emoji} ${status.displayName}'),
                  selected: selected,
                  onSelected: (bool value) {
                    if (!value) {
                      return;
                    }
                    setState(() {
                      _selectedProfileStatus = status;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _descriptionController,
              textInputAction: TextInputAction.newline,
              maxLines: 10,
              minLines: 5,
              decoration: const InputDecoration(
                labelText: 'כרטיסייה לשליחה',
                hintText: 'טקסט לשיתוף בוואטסאפ (5-10 משפטים)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
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
      final String f = HebrewDateUtils.format(
        year: _hebrewBirthYear!,
        month: _hebrewBirthMonth!,
        day: _hebrewBirthDay!,
      );
      if (f.isNotEmpty) return f;
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
      final String f = HebrewDateUtils.format(
        year: _hebrewBirthYear!,
        month: _hebrewBirthMonth!,
        day: _hebrewBirthDay!,
      );
      if (f.isNotEmpty) return f;
    }
    return null;
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
    final int? manualAge = _birthDate == null
        ? int.tryParse(_manualAgeController.text.trim())
        : null;

    try {
      if (_isEditMode && _person != null) {
        _person!
          ..firstName = firstName
          ..lastName = lastName
          ..gender = _selectedGender
          ..birthDate = _birthDate
          ..manualAge = manualAge
          ..religiousLevel = _selectedReligiousLevel
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
          ..profileStatus = _selectedProfileStatus
          ..hebrewBirthYear = _hebrewBirthYear
          ..hebrewBirthMonth = _hebrewBirthMonth
          ..hebrewBirthDay = _hebrewBirthDay
          ..photosPaths = List<String>.from(_photoPaths);

        await repository.update(_person!);
      } else {
        final DateTime now = DateTime.now();
        final Person person = Person(
          id: _draftPersonId,
          firstName: firstName,
          lastName: lastName,
          gender: _selectedGender,
          birthDate: _birthDate,
          manualAge: manualAge,
          religiousLevel: _selectedReligiousLevel,
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
          profileStatus: _selectedProfileStatus,
          hebrewBirthYear: _hebrewBirthYear,
          hebrewBirthMonth: _hebrewBirthMonth,
          hebrewBirthDay: _hebrewBirthDay,
          photosPaths: List<String>.from(_photoPaths),
          createdAt: now,
          updatedAt: now,
        );

        await repository.add(person);
      }

      if (!mounted) {
        return;
      }

      _initialSnapshot = _currentSnapshot();
      _newPhotoPaths.clear();
      context.pop();
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
    _manualAgeController.text = person.manualAge?.toString() ?? '';
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
    _birthDate = person.birthDate;
    _selectedReligiousLevel = person.religiousLevel;
    _selectedProfileStatus = person.profileStatus;
    _photoPaths = List<String>.from(person.photosPaths);
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
    } else if (_birthDate != null &&
        (_hebrewBirthYear == null ||
            _hebrewBirthMonth == null ||
            _hebrewBirthDay == null)) {
      final ({int year, int month, int day})? h = HebrewDateUtils.fromGregorian(
        _birthDate!,
      );
      _hebrewBirthYear = h?.year;
      _hebrewBirthMonth = h?.month;
      _hebrewBirthDay = h?.day;
    }
  }

  void _applyIncomingDraft(IncomingSharedProfileDraft? draft) {
    if (draft == null || !draft.hasContent) {
      return;
    }

    if (!_isEditMode) {
      _selectedGender = Gender.unknown;
    }

    final String? sharedText = draft.text?.trim();
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
      birthDate: _birthDate == null
          ? null
          : DateTime(_birthDate!.year, _birthDate!.month, _birthDate!.day),
      manualAge: _birthDate == null
          ? int.tryParse(_manualAgeController.text.trim())
          : null,
      religiousLevel: _selectedReligiousLevel,
      city: _normalizedText(_cityController.text),
      phone: _normalizedText(_phoneController.text),
      inquiryContactName: _normalizedText(_inquiryContactNameController.text),
      inquiryContactPhone: _normalizedText(_inquiryContactPhoneController.text),
      source: _normalizedText(_sourceController.text),
      notes: _normalizedText(_notesController.text),
      description: _normalizedText(_descriptionController.text),
      profileStatus: _selectedProfileStatus,
      hebrewBirthYear: _hebrewBirthYear,
      hebrewBirthMonth: _hebrewBirthMonth,
      hebrewBirthDay: _hebrewBirthDay,
      photoPaths: _photoPaths,
    );
  }

  Future<void> _pickPhotos() async {
    final bool hasPermission = await _ensureMediaPermission();
    if (!hasPermission || !mounted) {
      return;
    }

    try {
      final List<XFile> pickedFiles = await ImagePicker().pickMultiImage();
      if (pickedFiles.isEmpty || !mounted) {
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
      final String personId = _person?.id ?? _draftPersonId;

      for (int index = 0; index < pickedFiles.length; index++) {
        final XFile pickedFile = pickedFiles[index];
        final String targetPath =
            '${photosDirectory.path}${Platform.pathSeparator}${personId}_${timestamp}_$index.jpg';
        await File(pickedFile.path).copy(targetPath);
        copiedPhotoPaths.add(targetPath);
      }

      setState(() {
        _photoPaths = List<String>.from(_photoPaths)..addAll(copiedPhotoPaths);
        _newPhotoPaths.addAll(copiedPhotoPaths);
      });

      final String saveActionText = _isEditMode ? 'לעדכן' : 'ליצור';
      _showSnackBar(
        copiedPhotoPaths.length == 1
            ? 'התמונה נוספה לטופס. יש לשמור כדי $saveActionText את איש הקשר'
            : '${copiedPhotoPaths.length} תמונות נוספו לטופס. יש לשמור כדי $saveActionText את איש הקשר',
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }

      if (_looksLikePermissionError(error)) {
        await _showPermissionExplanationDialog();
        return;
      }

      _showSnackBar('לא הצלחנו לבחור תמונה כרגע');
    } catch (_) {
      if (mounted) {
        _showSnackBar('לא הצלחנו לשמור את התמונה');
      }
    }
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

      final String saveActionText = _isEditMode ? 'לעדכן' : 'ליצור';
      _showSnackBar(
        copiedPhotoPaths.length == 1
            ? 'התמונה ששותפה נוספה לטופס. יש לשמור כדי $saveActionText את איש הקשר'
            : '${copiedPhotoPaths.length} תמונות ששותפו נוספו לטופס. יש לשמור כדי $saveActionText את איש הקשר',
      );
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

  Future<bool> _ensureMediaPermission() async {
    if (Platform.isAndroid) {
      return true;
    }

    final PermissionStatus status = await Permission.photos.request();

    if (status.isGranted || status.isLimited) {
      return true;
    }

    if (mounted) {
      await _showPermissionExplanationDialog(
        openSettingsAction: status.isPermanentlyDenied || status.isRestricted,
      );
    }

    return false;
  }

  bool _looksLikePermissionError(PlatformException error) {
    final String combined = '${error.code} ${error.message ?? ''}'
        .toLowerCase();
    return combined.contains('denied') || combined.contains('permission');
  }

  Future<void> _showPermissionExplanationDialog({
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _deleteNewPhotos() {
    for (final String path in _newPhotoPaths) {
      final File file = File(path);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {
          // Best-effort cleanup for photos copied during an abandoned edit.
        }
      }
    }
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

class _PersonFormSnapshot {
  _PersonFormSnapshot({
    required this.firstName,
    required this.lastName,
    required this.gender,
    required this.birthDate,
    required this.manualAge,
    required this.religiousLevel,
    required this.city,
    required this.phone,
    required this.inquiryContactName,
    required this.inquiryContactPhone,
    required this.source,
    required this.notes,
    required this.description,
    required this.profileStatus,
    required this.hebrewBirthYear,
    required this.hebrewBirthMonth,
    required this.hebrewBirthDay,
    required List<String> photoPaths,
  }) : photoPaths = List<String>.unmodifiable(photoPaths);

  final String firstName;
  final String lastName;
  final Gender gender;
  final DateTime? birthDate;
  final int? manualAge;
  final ReligiousLevel? religiousLevel;
  final String? city;
  final String? phone;
  final String? inquiryContactName;
  final String? inquiryContactPhone;
  final String? source;
  final String? notes;
  final String? description;
  final ProfileStatus profileStatus;
  final int? hebrewBirthYear;
  final int? hebrewBirthMonth;
  final int? hebrewBirthDay;
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
        other.birthDate == birthDate &&
        other.manualAge == manualAge &&
        other.religiousLevel == religiousLevel &&
        other.city == city &&
        other.phone == phone &&
        other.inquiryContactName == inquiryContactName &&
        other.inquiryContactPhone == inquiryContactPhone &&
        other.source == source &&
        other.notes == notes &&
        other.description == description &&
        other.profileStatus == profileStatus &&
        other.hebrewBirthYear == hebrewBirthYear &&
        other.hebrewBirthMonth == hebrewBirthMonth &&
        other.hebrewBirthDay == hebrewBirthDay &&
        listEquals(other.photoPaths, photoPaths);
  }

  @override
  int get hashCode {
    return Object.hash(
      firstName,
      lastName,
      gender,
      birthDate,
      manualAge,
      religiousLevel,
      city,
      phone,
      inquiryContactName,
      inquiryContactPhone,
      source,
      notes,
      description,
      profileStatus,
      hebrewBirthYear,
      hebrewBirthMonth,
      hebrewBirthDay,
      Object.hashAll(photoPaths),
    );
  }
}

enum _BirthDateCalendar { gregorian, hebrew }

class _PhotoEditor extends StatelessWidget {
  const _PhotoEditor({
    required this.photoPaths,
    required this.onAddPhoto,
    required this.onSetPrimary,
  });

  final List<String> photoPaths;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onSetPrimary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('תמונות', style: theme.textTheme.titleMedium)),
            TextButton.icon(
              onPressed: onAddPhoto,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('הוספת תמונות'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (photoPaths.isEmpty)
          Text(
            'אין תמונות',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photoPaths.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (BuildContext context, int index) {
                final File file = File(photoPaths[index]);
                return Stack(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: file.existsSync()
                          ? Image.file(
                              file,
                              width: 80,
                              height: 96,
                              cacheWidth: 160,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 80,
                              height: 96,
                              color: theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                    PositionedDirectional(
                      top: 4,
                      end: 4,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          tooltip: index == 0
                              ? 'זו התמונה הראשית'
                              : 'בחר כתמונה ראשית',
                          onPressed: index == 0
                              ? null
                              : () => onSetPrimary(index),
                          icon: Icon(
                            index == 0 ? Icons.star : Icons.star_border,
                            color: index == 0 ? Colors.amber : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (index == 0)
                      PositionedDirectional(
                        bottom: 4,
                        start: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
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
                );
              },
            ),
          ),
      ],
    );
  }
}
