import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/hebrew_date_utils.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:uuid/uuid.dart';

class PersonFormScreen extends StatefulWidget {
  const PersonFormScreen({super.key, this.personId});

  final String? personId;

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
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final Uuid _uuid = const Uuid();

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
  bool _didLoadInitialData = false;
  bool _isSaving = false;

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
                onPressed: _isSaving ? null : _save,
              ),
            ],
          ),
          body: _buildBody(theme),
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
            Text('מגדר', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: Gender.values
                  .where((Gender g) => g != Gender.unknown)
                  .map((Gender gender) {
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
                          if (_birthDateSecondaryText() case final String txt)
                            ...<Widget>[
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
                  selected:
                      _birthDateCalendar == _BirthDateCalendar.gregorian,
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
            if (_birthDate == null) ...<Widget>[
              const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              textInputAction: TextInputAction.newline,
              maxLines: 5,
              minLines: 3,
              decoration: const InputDecoration(
                labelText: 'הערות פרטיות',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'הערות אלה לא ישותפו לעולם',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _descriptionController,
              textInputAction: TextInputAction.newline,
              maxLines: 10,
              minLines: 5,
              decoration: const InputDecoration(
                labelText: 'תיאור',
                hintText: 'תיאור לשיתוף בוואטסאפ (5-10 משפטים)',
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
        HebrewDateUtils.fromGregorian(now) ??
        (year: 5785, month: 1, day: 1);
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
                        items: List<DropdownMenuItem<int>>.generate(
                          101,
                          (int i) {
                            final int y = todayHebrew.year - i;
                            return DropdownMenuItem<int>(
                              value: y,
                              child: Text('$y'),
                            );
                          },
                        ),
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
                  onPressed: () => Navigator.of(ctx).pop(
                    (year: selYear, month: selMonth, day: selDay),
                  ),
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
          ..profileStatus = _selectedProfileStatus
          ..hebrewBirthYear = _hebrewBirthYear
          ..hebrewBirthMonth = _hebrewBirthMonth
          ..hebrewBirthDay = _hebrewBirthDay;

        await repository.update(_person!);
      } else {
        final DateTime now = DateTime.now();
        final Person person = Person(
          id: _uuid.v4(),
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
          profileStatus: _selectedProfileStatus,
          hebrewBirthYear: _hebrewBirthYear,
          hebrewBirthMonth: _hebrewBirthMonth,
          hebrewBirthDay: _hebrewBirthDay,
          createdAt: now,
          updatedAt: now,
        );

        await repository.add(person);
      }

      if (!mounted) {
        return;
      }

      _initialSnapshot = _currentSnapshot();
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
    _sourceController.text = person.source ?? '';
    _notesController.text = person.notes ?? '';
    _descriptionController.text = person.description ?? '';
    _selectedGender =
        person.gender == Gender.unknown ? Gender.male : person.gender;
    _birthDate = person.birthDate;
    _selectedReligiousLevel = person.religiousLevel;
    _selectedProfileStatus = person.profileStatus;
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
      final ({int year, int month, int day})? h =
          HebrewDateUtils.fromGregorian(_birthDate!);
      _hebrewBirthYear = h?.year;
      _hebrewBirthMonth = h?.month;
      _hebrewBirthDay = h?.day;
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
      source: _normalizedText(_sourceController.text),
      notes: _normalizedText(_notesController.text),
      description: _normalizedText(_descriptionController.text),
      profileStatus: _selectedProfileStatus,
      hebrewBirthYear: _hebrewBirthYear,
      hebrewBirthMonth: _hebrewBirthMonth,
      hebrewBirthDay: _hebrewBirthDay,
    );
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
  const _PersonFormSnapshot({
    required this.firstName,
    required this.lastName,
    required this.gender,
    required this.birthDate,
    required this.manualAge,
    required this.religiousLevel,
    required this.city,
    required this.phone,
    required this.source,
    required this.notes,
    required this.description,
    required this.profileStatus,
    required this.hebrewBirthYear,
    required this.hebrewBirthMonth,
    required this.hebrewBirthDay,
  });

  final String firstName;
  final String lastName;
  final Gender gender;
  final DateTime? birthDate;
  final int? manualAge;
  final ReligiousLevel? religiousLevel;
  final String? city;
  final String? phone;
  final String? source;
  final String? notes;
  final String? description;
  final ProfileStatus profileStatus;
  final int? hebrewBirthYear;
  final int? hebrewBirthMonth;
  final int? hebrewBirthDay;

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
        other.source == source &&
        other.notes == notes &&
        other.description == description &&
        other.profileStatus == profileStatus &&
        other.hebrewBirthYear == hebrewBirthYear &&
        other.hebrewBirthMonth == hebrewBirthMonth &&
        other.hebrewBirthDay == hebrewBirthDay;
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
      source,
      notes,
      description,
      profileStatus,
      hebrewBirthYear,
      hebrewBirthMonth,
      hebrewBirthDay,
    );
  }
}

enum _BirthDateCalendar { gregorian, hebrew }
