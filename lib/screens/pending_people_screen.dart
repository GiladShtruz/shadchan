import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

class PendingPeopleScreen extends StatefulWidget {
  const PendingPeopleScreen({super.key});

  @override
  State<PendingPeopleScreen> createState() => _PendingPeopleScreenState();
}

class _PendingPeopleScreenState extends State<PendingPeopleScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _manualAgeController = TextEditingController();
  final Set<String> _skippedPersonIds = <String>{};

  String? _editingPersonId;
  ProfileStatus _selectedProfileStatus = ProfileStatus.available;
  Gender _selectedGender = Gender.unknown;
  ReligiousLevel? _selectedReligiousLevel;
  bool _isSaving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _manualAgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PersonRepository repository = context.watch<PersonRepository>();
    final List<Person> pendingPeople = repository.getPending();
    final Person? person = _currentPerson(pendingPeople);

    if (person != null && _editingPersonId != person.id) {
      _populateFromPerson(person);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('בהמתנה לעדכון'),
        centerTitle: true,
        actions: <Widget>[
          if (person != null)
            TextButton.icon(
              onPressed: () => context.push('/people/${person.id}'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('לכרטיס המלא'),
            ),
        ],
      ),
      body: person == null
          ? const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'אין אנשים להצגה כרגע',
              subtitle:
                  'אנשים שמיובאים מאנשי הקשר יופיעו כאן עד שתוסיפו להם פרטים',
            )
          : _PendingPersonEditor(
              formKey: _formKey,
              person: person,
              remainingCount: pendingPeople.length,
              firstNameController: _firstNameController,
              lastNameController: _lastNameController,
              manualAgeController: _manualAgeController,
              selectedProfileStatus: _selectedProfileStatus,
              selectedGender: _selectedGender,
              selectedReligiousLevel: _selectedReligiousLevel,
              onProfileStatusChanged: (ProfileStatus status) {
                setState(() {
                  _selectedProfileStatus = status;
                });
              },
              onGenderChanged: (Gender gender) {
                setState(() {
                  _selectedGender = gender;
                });
              },
              onReligiousLevelChanged: (ReligiousLevel? level) {
                setState(() {
                  _selectedReligiousLevel = level;
                });
              },
              onWhatsAppPressed: () => _openWhatsApp(person),
            ),
      bottomNavigationBar: person == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : () => _skip(person),
                        icon: const Icon(Icons.skip_next),
                        label: const Text('דלג'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () => _save(repository, person),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: const Text('שמור'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Person? _currentPerson(List<Person> pendingPeople) {
    for (final Person person in pendingPeople) {
      if (!_skippedPersonIds.contains(person.id)) {
        return person;
      }
    }
    return null;
  }

  void _populateFromPerson(Person person) {
    _editingPersonId = person.id;
    _firstNameController.text = person.firstName;
    _lastNameController.text = person.lastName;
    _manualAgeController.text = person.manualAge?.toString() ?? '';
    _selectedProfileStatus = person.profileStatus;
    _selectedGender = person.gender;
    _selectedReligiousLevel = person.religiousLevel;
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

  Future<void> _save(PersonRepository repository, Person person) async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final int? manualAge = int.tryParse(_manualAgeController.text.trim());
      person
        ..firstName = _firstNameController.text.trim()
        ..lastName = _lastNameController.text.trim()
        ..profileStatus = _selectedProfileStatus
        ..gender = _selectedGender
        ..religiousLevel = _selectedReligiousLevel
        ..manualAge = manualAge;

      await repository.update(person);
      _skippedPersonIds.remove(person.id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('הפרטים נשמרו')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _skip(Person person) {
    setState(() {
      _skippedPersonIds.add(person.id);
      _editingPersonId = null;
    });
  }
}

class _PendingPersonEditor extends StatelessWidget {
  const _PendingPersonEditor({
    required this.formKey,
    required this.person,
    required this.remainingCount,
    required this.firstNameController,
    required this.lastNameController,
    required this.manualAgeController,
    required this.selectedProfileStatus,
    required this.selectedGender,
    required this.selectedReligiousLevel,
    required this.onProfileStatusChanged,
    required this.onGenderChanged,
    required this.onReligiousLevelChanged,
    required this.onWhatsAppPressed,
  });

  final GlobalKey<FormState> formKey;
  final Person person;
  final int remainingCount;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController manualAgeController;
  final ProfileStatus selectedProfileStatus;
  final Gender selectedGender;
  final ReligiousLevel? selectedReligiousLevel;
  final ValueChanged<ProfileStatus> onProfileStatusChanged;
  final ValueChanged<Gender> onGenderChanged;
  final ValueChanged<ReligiousLevel?> onReligiousLevelChanged;
  final VoidCallback onWhatsAppPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasPhone = PhoneUtils.toWhatsAppNumber(person.phone) != null;

    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: <Widget>[
          Row(
            children: <Widget>[
              PersonAvatar(person: person, radius: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      person.fullName.trim().isEmpty
                          ? 'איש קשר ללא שם'
                          : person.fullName.trim(),
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'נותרו $remainingCount בהמתנה',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: firstNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'שם'),
            validator: _requiredText('יש להזין שם'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: lastNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'שם משפחה'),
          ),
          const SizedBox(height: 20),
          _ChoiceSection<ProfileStatus>(
            title: 'סטטוס',
            values: ProfileStatus.values,
            selectedValue: selectedProfileStatus,
            labelFor: (ProfileStatus status) =>
                '${status.emoji} ${status.displayName}',
            onChanged: onProfileStatusChanged,
          ),
          const SizedBox(height: 20),
          _ChoiceSection<Gender>(
            title: 'מגדר',
            values: Gender.values,
            selectedValue: selectedGender,
            labelFor: (Gender gender) => gender.displayName,
            onChanged: onGenderChanged,
          ),
          const SizedBox(height: 20),
          Text('סגנון דתי', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ReligiousLevel.values.map((ReligiousLevel level) {
              final bool selected = selectedReligiousLevel == level;
              return ChoiceChip(
                label: Text(level.displayName),
                selected: selected,
                onSelected: (bool value) {
                  onReligiousLevelChanged(value && !selected ? level : null);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: manualAgeController,
            textInputAction: TextInputAction.done,
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
          const SizedBox(height: 28),
          Text(
            'תרצה לבקש פרטים בווצאפ?',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: hasPhone ? onWhatsAppPressed : null,
            icon: const FaIcon(FontAwesomeIcons.whatsapp),
            label: Text(hasPhone ? 'לחץ לפתיחת צ׳אט' : 'אין מספר טלפון תקין'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  theme.colorScheme.surfaceContainerHighest,
              disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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

class _ChoiceSection<T> extends StatelessWidget {
  const _ChoiceSection({
    required this.title,
    required this.values,
    required this.selectedValue,
    required this.labelFor,
    required this.onChanged,
  });

  final String title;
  final List<T> values;
  final T selectedValue;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((T value) {
            return ChoiceChip(
              label: Text(labelFor(value)),
              selected: selectedValue == value,
              onSelected: (bool selected) {
                if (selected) {
                  onChanged(value);
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
