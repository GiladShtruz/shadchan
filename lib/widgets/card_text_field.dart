import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/utils/invisible_marks.dart';

/// Takes the app's own credit line out of a pasted card — see
/// [CommunityLinks.stripCredit]. Only a paste can bring one in, so ordinary
/// typing passes straight through, caret and all.
class CardCreditFormatter extends TextInputFormatter {
  const CardCreditFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // One keystroke at a time is typing, never a credit arriving.
    if (newValue.text.length - oldValue.text.length < 8) {
      return newValue;
    }
    final String stripped = CommunityLinks.stripCredit(newValue.text);
    if (stripped == newValue.text) {
      return newValue;
    }
    // The caret stays where the paste ended, less what was taken out before
    // it; the credit is always at the foot of what was pasted.
    final int removed = newValue.text.length - stripped.length;
    final int caret = (newValue.selection.extentOffset - removed).clamp(
      0,
      stripped.length,
    );
    return TextEditingValue(
      text: stripped,
      selection: TextSelection.collapsed(offset: caret),
    );
  }
}

/// The field a card's free text is typed or pasted into — the same field in
/// the manual add form and in the full card editor.
///
/// Everything here is about the caret behaving in Hebrew the way it does in
/// any ordinary text box:
/// * it **grows with its text** instead of scrolling inside the page — two
///   scrollables fight over every drag of the caret handle, and the page wins;
/// * **no letter spacing**, which moves hit-testing into the middle of a
///   Hebrew letter;
/// * WhatsApp's **invisible direction marks** are kept out ([InvisibleMarks]):
///   each is a real position with no width, so the caret steps onto it and
///   seems to stop;
/// * the app's own credit line is taken out of a pasted card
///   ([CardCreditFormatter]).
class CardTextField extends StatelessWidget {
  const CardTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.onChanged,
    this.hintText,
    this.labelText,
    this.minLines = 5,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final String? hintText;
  final String? labelText;
  final int minLines;

  /// What a card's text is before it goes into the field — a shared text, a
  /// saved description: no invisible marks, no credit line.
  static String clean(String text) =>
      CommunityLinks.stripCredit(InvisibleMarks.strip(text));

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      inputFormatters: const <TextInputFormatter>[
        InvisibleMarksFormatter(),
        CardCreditFormatter(),
      ],
      style: theme.textTheme.bodyLarge?.copyWith(letterSpacing: 0, height: 1.4),
      scrollPadding: const EdgeInsets.only(bottom: 120),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        alignLabelWithHint: true,
      ),
    );
  }
}
