import 'package:flutter/material.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

/// "משפט קצר עליי" — the one optional line on the matchmaker's own profile,
/// and the examples that explain it better than any label could.
///
/// **The examples are the feature.** "ספרו על עצמכם" in a text box gets an
/// empty text box: the question is too wide to answer in a sentence, and
/// nobody wants to be the one who wrote the wrong kind of thing. Two real
/// lines — one about why somebody does this, one about what they actually work
/// on — draw the size and the register of the answer in less space than an
/// instruction would, and tapping one writes it in so the field is never
/// intimidatingly blank.
///
/// **Optional, everywhere it appears.** Sign-up shows it below the required
/// answers and never blocks on it, and the profile keeps it editable forever —
/// which is the other half of the promise: a line written in a hurry on the
/// first launch is not a line anybody is stuck with.
abstract final class AboutMe {
  static const String label = 'משפט קצר עליי';

  static const String optionalHint = 'לא חובה — אפשר להוסיף או לשנות בכל רגע';

  static const String placeholder = 'למשל: אוהב לחבר בין אנשים';

  /// Kept as templates so each one is written in the matchmaker's own gender —
  /// an example addressed to the wrong person is an example nobody copies.
  static const List<String> exampleTemplates = <String>[
    '{אוהב|אוהבת} לחבר בין אנשים',
    '{עוסק|עוסקת} בשידוכים בעיקר במגזר הדתי־לאומי בגילאי 25–30',
    '{מאמין|מאמינה} שלכל אחד יש את הזיווג שלו, ולפעמים צריך רק מי שיציג',
  ];

  static List<String> examplesFor(Gender? gender) => <String>[
    for (final String template in exampleTemplates) template.forGender(gender),
  ];
}

/// The examples, as chips that write themselves into the field.
///
/// Shown under the input on both surfaces that carry it, so the field is
/// explained in exactly the same way whether it is met during sign-up or a
/// month later on the profile.
class AboutMeExamples extends StatelessWidget {
  const AboutMeExamples({
    super.key,
    required this.gender,
    required this.onPick,
  });

  final Gender? gender;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'דוגמאות:',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String example in AboutMe.examplesFor(gender))
              ActionChip(
                label: Text(example),
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => onPick(example),
              ),
          ],
        ),
      ],
    );
  }
}

/// The editor reached from the profile, for a line that already exists or one
/// that was skipped during sign-up.
///
/// Deliberately the same field and the same examples the sign-up shows, in a
/// sheet rather than a screen: it is one line, and a whole page for one line is
/// a page nobody opens twice.
class AboutMeSheet extends StatefulWidget {
  const AboutMeSheet({super.key, required this.initialText, this.gender});

  final String initialText;
  final Gender? gender;

  /// Answers with the new line, `''` for a line that was cleared, or null when
  /// the sheet was dismissed without saving.
  static Future<String?> show(
    BuildContext context, {
    required String initialText,
    Gender? gender,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) =>
          AboutMeSheet(initialText: initialText, gender: gender),
    );
  }

  @override
  State<AboutMeSheet> createState() => _AboutMeSheetState();
}

class _AboutMeSheetState extends State<AboutMeSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, keyboard + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              AboutMe.label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AboutMe.optionalHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: widget.initialText.isEmpty,
              minLines: 2,
              maxLines: 4,
              maxLength: 140,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: AboutMe.placeholder,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 4),
            AboutMeExamples(
              gender: widget.gender,
              onPick: (String example) => setState(() {
                _controller.text = example;
                _controller.selection = TextSelection.collapsed(
                  offset: example.length,
                );
              }),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ביטול'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_controller.text.trim()),
                    child: const Text('שמירה'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
