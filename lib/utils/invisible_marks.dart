import 'package:flutter/services.dart';

/// The invisible characters a WhatsApp card arrives full of: direction marks
/// (LRM, RLM, ALM), embeddings and overrides, isolates, zero-width spaces and
/// the byte-order mark.
///
/// **They are why a caret "sticks" in pasted Hebrew.** Each one is a real
/// position in the text with no width on screen, so the caret steps onto it
/// and appears not to move, and every embedding flips the direction of the run
/// after it — which is what puts a tap that lands on a full stop at the other
/// end of the line. None of them carries meaning in a free-text card; the
/// zero-width joiner is deliberately left alone, because emoji sequences are
/// built out of it.
abstract final class InvisibleMarks {
  static final RegExp _pattern = RegExp(
    r'[\u200B\u200C\u200E\u200F\u061C\u202A-\u202E\u2066-\u2069\uFEFF]',
  );

  static String strip(String text) => text.replaceAll(_pattern, '');
}

/// Strips [InvisibleMarks] out of whatever is typed or pasted, keeping the
/// caret and selection on the same visible characters they were on.
class InvisibleMarksFormatter extends TextInputFormatter {
  const InvisibleMarksFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String text = newValue.text;
    if (!InvisibleMarks._pattern.hasMatch(text)) {
      return newValue;
    }

    // Where every surviving character lands, so each offset can be moved back
    // by exactly the number of marks removed in front of it.
    final List<int> shift = List<int>.filled(text.length + 1, 0);
    final StringBuffer out = StringBuffer();
    int removed = 0;
    for (int i = 0; i < text.length; i++) {
      shift[i] = removed;
      final String ch = text[i];
      if (InvisibleMarks._pattern.hasMatch(ch)) {
        removed++;
      } else {
        out.write(ch);
      }
    }
    shift[text.length] = removed;

    int map(int offset) {
      if (offset < 0 || offset > text.length) {
        return offset;
      }
      return offset - shift[offset];
    }

    final TextSelection sel = newValue.selection;
    return TextEditingValue(
      text: out.toString(),
      selection: sel.isValid
          ? sel.copyWith(
              baseOffset: map(sel.baseOffset),
              extentOffset: map(sel.extentOffset),
            )
          : sel,
    );
  }
}
