import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/religious_level_picker.dart';

/// How the matchmaker left the quick-details dialog.
enum QuickUpdateOutcome {
  /// Backed out — the staged draft is thrown away.
  cancelled,

  /// The basic details were enough. The friend joins the database and the
  /// matchmaker stays where they were, adding the next person.
  added,

  /// They want the full card. Everything typed here is kept, the friend joins
  /// the database, and the extended editor opens on top — which ends on the new
  /// friend's profile rather than back in the add-friends list.
  openFullEditor;

  bool get isAdded => this != QuickUpdateOutcome.cancelled;
}

/// Collects the minimum details required before an imported contact may enter
/// the database. The passed [person] is only mutated after a valid confirmation;
/// cancelling leaves the draft untouched.
class QuickUpdateDialog extends StatefulWidget {
  const QuickUpdateDialog({
    super.key,
    required this.person,
    this.stepIndex,
    this.stepCount,
  });

  final Person person;
  final int? stepIndex;
  final int? stepCount;

  static Future<QuickUpdateOutcome> show(
    BuildContext context,
    Person person, {
    int? stepIndex,
    int? stepCount,
  }) async {
    return await showDialog<QuickUpdateOutcome>(
          context: context,
          barrierDismissible: false,
          builder: (_) => QuickUpdateDialog(
            person: person,
            stepIndex: stepIndex,
            stepCount: stepCount,
          ),
        ) ??
        QuickUpdateOutcome.cancelled;
  }

  @override
  State<QuickUpdateDialog> createState() => _QuickUpdateDialogState();
}

class _QuickUpdateDialogState extends State<QuickUpdateDialog> {
  late Gender _gender;
  late ReligiousLevel? _religiousLevel;
  String? _religiousLevelOther;
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;

  String? _nameError;
  String? _genderError;
  String? _religiousLevelError;
  String? _ageError;

  @override
  void initState() {
    super.initState();
    _gender = widget.person.gender;
    _religiousLevel = widget.person.religiousLevel;
    _religiousLevelOther = widget.person.religiousLevelOther;
    _nameController = TextEditingController(text: widget.person.fullName);
    _ageController = TextEditingController(
      text: widget.person.age?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      scrollable: true,
      title: _buildTitle(theme),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'שם',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 16),
            Text('מגדר', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              // Only the two real answers; "לא מוגדר" is not an outcome the
              // matchmaker should be able to choose.
              children: <Gender>[Gender.male, Gender.female].map((
                Gender gender,
              ) {
                return ChoiceChip(
                  label: Text(gender.displayName),
                  selected: _gender == gender,
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() {
                        _gender = gender;
                        _genderError = null;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            if (_genderError != null) ...<Widget>[
              const SizedBox(height: 6),
              _ErrorText(_genderError!),
            ],
            const SizedBox(height: 16),
            ReligiousLevelPicker(
              selected: ReligiousLevelChoice(
                _religiousLevel,
                _religiousLevelOther,
              ),
              showSettingsShortcut: false,
              onChanged: (ReligiousLevelChoice choice) {
                setState(() {
                  _religiousLevel = choice.level;
                  _religiousLevelOther = choice.customLabel;
                  _religiousLevelError = null;
                });
              },
            ),
            if (_religiousLevelError != null) ...<Widget>[
              const SizedBox(height: 6),
              _ErrorText(_religiousLevelError!),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              onChanged: (_) {
                if (_ageError != null) {
                  setState(() => _ageError = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'גיל (הערכה)',
                errorText: _ageError,
              ),
            ),
            const SizedBox(height: 20),
            // Offered rather than required: the whole point of this dialog is
            // that a friend can join on four fields. Everything typed above is
            // carried across, so choosing the full card is never a fresh start.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openFullEditor,
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('לעדכון פרטים מלאים'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                    color: theme.brightness == Brightness.dark
                        ? theme.colorScheme.primary
                        : AppColors.primaryDark,
                    width: 1.4,
                  ),
                  foregroundColor: theme.brightness == Brightness.dark
                      ? theme.colorScheme.primary
                      : AppColors.primaryDark,
                  textStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(QuickUpdateOutcome.cancelled),
          child: const Text('ביטול'),
        ),
        FilledButton(onPressed: _confirm, child: Text(_finishLabel)),
      ],
    );
  }

  Widget _buildTitle(ThemeData theme) {
    final int? stepIndex = widget.stepIndex;
    final int? stepCount = widget.stepCount;
    if (stepIndex == null || stepCount == null || stepCount < 2) {
      return const Text('עדכון פרטים');
    }

    return Row(
      children: <Widget>[
        const Expanded(child: Text('עדכון פרטים')),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$stepIndex מתוך $stepCount',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.onSurface
                  : AppColors.primaryDark,
            ),
          ),
        ),
      ],
    );
  }

  String get _finishLabel {
    final int? stepIndex = widget.stepIndex;
    final int? stepCount = widget.stepCount;
    if (stepIndex != null && stepCount != null && stepIndex < stepCount) {
      return 'הוספה והבא';
    }
    return 'הוספה';
  }

  /// Hands over to the full card without demanding the four fields first —
  /// whatever is already typed is written onto the draft, and the extended
  /// editor is where the required details are enforced.
  void _openFullEditor() {
    _applyToPerson(int.tryParse(_ageController.text.trim()));
    Navigator.of(context).pop(QuickUpdateOutcome.openFullEditor);
  }

  void _confirm() {
    final String fullName = _nameController.text.trim();
    final int? age = int.tryParse(_ageController.text.trim());
    final bool validName = fullName.isNotEmpty;
    final bool validGender = _gender != Gender.unknown;
    final bool validReligiousLevel = _religiousLevel != null;
    final bool validAge = age != null && age >= 10 && age <= 120;

    if (!validName || !validGender || !validReligiousLevel || !validAge) {
      setState(() {
        _nameError = validName ? null : 'יש להזין שם';
        _genderError = validGender ? null : 'יש לבחור מגדר';
        _religiousLevelError = validReligiousLevel
            ? null
            : 'יש לבחור סגנון דתי';
        _ageError = validAge ? null : 'יש להזין גיל בין 10 ל-120';
      });
      return;
    }

    _applyToPerson(age);
    Navigator.of(context).pop(QuickUpdateOutcome.added);
  }

  /// Writes whatever has been entered onto the draft. Both exits use it, so the
  /// full editor always opens on the details already given here.
  void _applyToPerson(int? age) {
    final String fullName = _nameController.text.trim();
    final int spaceIndex = fullName.indexOf(' ');
    widget.person
      ..firstName = spaceIndex == -1
          ? fullName
          : fullName.substring(0, spaceIndex).trim()
      ..lastName = spaceIndex == -1
          ? ''
          : fullName.substring(spaceIndex + 1).trim()
      ..gender = _gender
      ..religiousLevel = _religiousLevel
      ..religiousLevelOther = _religiousLevelOther
      ..setManualAge(age);
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
