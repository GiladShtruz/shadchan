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

  @override
  void initState() {
    super.initState();
    _gender = widget.person.gender;
    _religiousLevel = widget.person.religiousLevel;
    _nameController = TextEditingController(text: widget.person.fullName);
    _ageController = TextEditingController(
      text: widget.person.manualAge?.toString() ?? '',
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(onPressed: _save, child: const Text('שמירה')),
      ],
    );
  }

  void _openFullCard() {
    Navigator.of(context).pop();
    context.push('/people/${widget.person.id}/edit');
  }

  Future<void> _save() async {
    final String ageText = _ageController.text.trim();
    int? manualAge;
    if (ageText.isNotEmpty) {
      final int? parsed = int.tryParse(ageText);
      if (parsed == null || parsed < 10 || parsed > 120) {
        setState(() => _ageError = 'יש להזין גיל בין 10 ל-120');
        return;
      }
      manualAge = parsed;
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

    final PersonRepository repository = context.read<PersonRepository>();
    final Person person = widget.person
      ..firstName = firstName
      ..lastName = lastName
      ..gender = _gender
      ..religiousLevel = _religiousLevel
      ..manualAge = manualAge;
    await repository.update(person);

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('הפרטים נשמרו')));
  }
}
