import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/enums.dart';

/// Quick editor for the three fields most often missing on imported contacts:
/// gender, religious level and age. Offers a shortcut to the full card.
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
  late final TextEditingController _ageController;
  String? _ageError;

  @override
  void initState() {
    super.initState();
    _gender = widget.person.gender;
    _religiousLevel = widget.person.religiousLevel;
    _ageController = TextEditingController(
      text: widget.person.manualAge?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        widget.person.fullName.trim().isEmpty
            ? 'עדכון פרטים'
            : widget.person.fullName.trim(),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('מגדר', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
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

    final PersonRepository repository = context.read<PersonRepository>();
    final Person person = widget.person
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
