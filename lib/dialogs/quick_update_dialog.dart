import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// Quick editor for the fields most often missing on imported contacts:
/// name, gender, religious level and age. Offers a shortcut to the full card.
class QuickUpdateDialog extends StatefulWidget {
  const QuickUpdateDialog({super.key, required this.person});

  final Person person;

  static Future<void> show(BuildContext context, Person person) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext _) => QuickUpdateDialog(person: person),
    );
  }

  @override
  State<QuickUpdateDialog> createState() => _QuickUpdateDialogState();
}

class _QuickUpdateDialogState extends State<QuickUpdateDialog> {
  late Gender _gender;
  late ReligiousLevel? _religiousLevel;
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  String? _ageError;
  Timer? _autoSaveTimer;
  late final PersonRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = context.read<PersonRepository>();
    _gender = widget.person.gender;
    _religiousLevel = widget.person.religiousLevel;
    _nameController = TextEditingController(text: widget.person.fullName);
    _ageController = TextEditingController(
      text: widget.person.manualAge?.toString() ?? '',
    );
    // Basic details save automatically while typing.
    _nameController.addListener(_scheduleAutoSave);
    _ageController.addListener(_scheduleAutoSave);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    // Flush any pending edits the debounce hadn't written yet (e.g. when the
    // dialog is dismissed by tapping outside).
    if (_pendingAutoSave) {
      unawaited(_persist(updateUi: false));
    }
    _nameController
      ..removeListener(_scheduleAutoSave)
      ..dispose();
    _ageController
      ..removeListener(_scheduleAutoSave)
      ..dispose();
    super.dispose();
  }

  bool _pendingAutoSave = false;

  void _scheduleAutoSave() {
    _pendingAutoSave = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_persist());
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      // Keep the dialog from running into the screen edges and let the whole
      // thing scroll, so nothing gets clipped when the keyboard is open.
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      scrollable: true,
      title: const Text('עדכון פרטים'),
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
              decoration: const InputDecoration(labelText: 'שם'),
            ),
            const SizedBox(height: 16),
            Text('מגדר', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Gender.values.map((Gender gender) {
                return ChoiceChip(
                  label: Text(gender.displayName),
                  selected: _gender == gender,
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() => _gender = gender);
                      unawaited(_persist());
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('סגנון דתי', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReligiousLevel.values.map((ReligiousLevel level) {
                final bool selected = _religiousLevel == level;
                return ChoiceChip(
                  label: Text(level.displayName),
                  selected: selected,
                  onSelected: (bool value) {
                    setState(() => _religiousLevel = value ? level : null);
                    unawaited(_persist());
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'גיל (הערכה)',
                errorText: _ageError,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _openFullCard,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('עריכת פרטים נוספים'),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        FilledButton(onPressed: _finish, child: const Text('סיום')),
      ],
    );
  }

  Future<void> _openFullCard() async {
    _autoSaveTimer?.cancel();
    // Carry over everything already typed in the basic fields so the full card
    // doesn't ask for it again.
    final bool ageValid = await _persist();
    if (!ageValid || !mounted) {
      return;
    }
    Navigator.of(context).pop();
    context.push('/people/${widget.person.id}/edit');
  }

  Future<void> _finish() async {
    _autoSaveTimer?.cancel();
    final bool ageValid = await _persist();
    if (!ageValid || !mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  /// Writes the current basic fields to the person. Saving is automatic, so
  /// this runs on every change (debounced), on chip selection, and before
  /// leaving the dialog. Returns whether the age field was valid; name, gender
  /// and religious level are always saved, and the age only when valid.
  Future<bool> _persist({bool updateUi = true}) async {
    _pendingAutoSave = false;

    final String ageText = _ageController.text.trim();
    int? manualAge;
    bool ageValid = true;
    if (ageText.isNotEmpty) {
      final int? parsed = int.tryParse(ageText);
      if (parsed == null || parsed < 10 || parsed > 120) {
        ageValid = false;
      } else {
        manualAge = parsed;
      }
    }
    if (updateUi && mounted) {
      setState(
        () => _ageError = ageValid ? null : 'יש להזין גיל בין 10 ל-120',
      );
    }

    // The dialog exposes a single "name" field; split it back into the
    // first / last name pair the model stores (everything after the first
    // space becomes the last name).
    final String fullName = _nameController.text.trim();
    final int spaceIndex = fullName.indexOf(' ');
    final String firstName = spaceIndex == -1
        ? fullName
        : fullName.substring(0, spaceIndex).trim();
    final String lastName = spaceIndex == -1
        ? ''
        : fullName.substring(spaceIndex + 1).trim();

    final Person person = widget.person
      ..firstName = firstName
      ..lastName = lastName
      ..gender = _gender
      ..religiousLevel = _religiousLevel;
    if (ageValid) {
      person.manualAge = manualAge;
    }
    await _repository.update(person);
    return ageValid;
  }
}
