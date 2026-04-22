import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/core/constants/enums.dart';
import 'package:shadchan/core/utils/date_utils.dart';
import 'package:shadchan/core/utils/hebrew_date_utils.dart';
import 'package:shadchan/data/models/person.dart';
import 'package:shadchan/data/repositories/person_repository.dart';
import 'package:shadchan/presentation/shared/widgets/confirm_dialog.dart';
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
                          Text('תאריך לידה', style: theme.textTheme.labelLarge),
                          const SizedBox(height: 4),
                          Text(
                            _birthDate != null
                                ? AppDateUtils.formatDate(_birthDate!)
                                : 'לא הוזן',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _birthDate != null
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
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
                          });
                        },
                      )
                    else
                      const Icon(Icons.calendar_today_outlined),
                  ],
                ),
              ),
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
            const SizedBox(height: 16),
            Text('תאריך לידה עברי', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickHebrewBirthDate,
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
                      child: Text(
                        _hebrewBirthYear != null &&
                                _hebrewBirthMonth != null &&
                                _hebrewBirthDay != null
                            ? HebrewDateUtils.format(
                                year: _hebrewBirthYear!,
                                month: _hebrewBirthMonth!,
                                day: _hebrewBirthDay!,
                              )
                            : 'לא הוזן',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (_hebrewBirthYear != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'ניקוי תאריך עברי',
                        onPressed: () {
                          setState(() {
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

  Future<void> _pickHebrewBirthDate() async {
    final DateTime now = DateTime.now();
    final DateTime initialGregorian =
        _hebrewBirthYear != null &&
            _hebrewBirthMonth != null &&
            _hebrewBirthDay != null
        ? (HebrewDateUtils.toGregorian(
                year: _hebrewBirthYear!,
                month: _hebrewBirthMonth!,
                day: _hebrewBirthDay!,
              ) ??
              DateTime(now.year - 22, now.month, now.day))
        : DateTime(now.year - 22, now.month, now.day);

    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: initialGregorian.isAfter(now) ? now : initialGregorian,
      firstDate: DateTime(now.year - 100, now.month, now.day),
      lastDate: now,
      locale: const Locale('he'),
      helpText: 'בחר תאריך לועזי — יומר לעברי',
    );

    if (selectedDate == null) {
      return;
    }

    final ({int year, int month, int day})? hebrew =
        HebrewDateUtils.fromGregorian(selectedDate);
    if (hebrew == null) {
      return;
    }

    setState(() {
      _hebrewBirthYear = hebrew.year;
      _hebrewBirthMonth = hebrew.month;
      _hebrewBirthDay = hebrew.day;
    });
  }

  Future<void> _pickBirthDate() async {
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

    setState(() {
      _birthDate = selectedDate;
    });
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
    _selectedGender = person.gender;
    _birthDate = person.birthDate;
    _selectedReligiousLevel = person.religiousLevel;
    _selectedProfileStatus = person.profileStatus;
    _hebrewBirthYear = person.hebrewBirthYear;
    _hebrewBirthMonth = person.hebrewBirthMonth;
    _hebrewBirthDay = person.hebrewBirthDay;
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
