import 'package:flutter/material.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

/// "משפט קצר עליי" — the one optional line on the matchmaker's own profile,
/// and the examples that explain it better than any label could.
///
/// **The examples show the size of the answer, and nothing more.** "ספרו על
/// עצמכם" in a text box gets an empty text box: the question is too wide to
/// answer in a sentence, and nobody wants to be the one who wrote the wrong
/// kind of thing. Two real fragments — one about why somebody does this, one
/// about what they actually work on — draw the register of the answer in less
/// space than an instruction would.
///
/// **They are not choices.** They used to be chips, and a row of chips under a
/// field is read as a menu: people tapped one, and the community filled up with
/// three sentences written by the app. So they are one quiet grey line now,
/// trailing off in an ellipsis — the shape of an example rather than of an
/// option — and the only way to fill the field is to write in it.
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
    '{עוסק|עוסקת} בשידוכים במגזר מסוים',
  ];

  static List<String> examplesFor(Gender? gender) => <String>[
    for (final String template in exampleTemplates) template.forGender(gender),
  ];

  /// The whole hint as one line: the fragments joined by a comma and left
  /// hanging, so it reads as "something along these lines" rather than as two
  /// sentences on offer.
  static String exampleLineFor(Gender? gender) =>
      'למשל: ${examplesFor(gender).join(', ')}...';
}

/// The examples, as one quiet line under the field.
///
/// Shown under the input on both surfaces that carry it, so the field is
/// explained in exactly the same way whether it is met during sign-up or a
/// month later on the profile. Deliberately the smallest, palest type on the
/// screen: it is a caption on somebody else's answer, not a control.
class AboutMeExamples extends StatelessWidget {
  const AboutMeExamples({super.key, required this.gender});

  final Gender? gender;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        AboutMe.exampleLineFor(gender),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          fontStyle: FontStyle.italic,
          height: 1.35,
        ),
      ),
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
            AboutMeExamples(gender: widget.gender),
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
