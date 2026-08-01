import 'package:shadchan/utils/card_parser.dart';
import 'package:shadchan/utils/enums.dart';

/// The fields an import can report a source for. Only the ones a model is
/// actually tempted to derive are listed — there is no reason to track where a
/// city came from, because a city is either written on the card or it is not.
enum ParsedField { firstName, lastName, age, gender }

/// One person as an import read them, together with what had to be worked out
/// rather than read.
///
/// The distinction is the whole point. A model that reports `gender: female`
/// because the card said בת and one that reports it because the name is נועה
/// produce identical JSON, and only the second is a guess. Recording which is
/// which is what lets a bulk import send the guesses to a human and let the
/// rest through, instead of choosing between reviewing eighty records by hand
/// and trusting eighty records blindly.
class ParsedPerson {
  const ParsedPerson({
    required this.card,
    this.inferredFields = const <ParsedField>{},
    this.photoPath,
    this.religiousLevel,
    this.religiousLevelOther,
    this.phone,
    this.description,
  });

  final ParsedCard card;

  /// The closest style the app knows, and the source's own wording when none
  /// of them fits. Both are kept: "דתייה עם סימני שאלה" is not any of the
  /// listed levels, and flattening it to the nearest one would put a claim in
  /// the record that nobody made.
  final ReligiousLevel? religiousLevel;
  final String? religiousLevelOther;

  final String? phone;

  /// The card, word for word.
  ///
  /// Taken from the source rather than from the model: a real card runs to
  /// paragraphs about what someone is like and what they are looking for, and
  /// no set of fields holds that. Copying it verbatim means the structured
  /// fields can be wrong without anything being lost.
  final String? description;

  /// A photo from the same export, already extracted to this device.
  ///
  /// Only ever a local path. The image itself is never sent anywhere — the
  /// model sees a file *name* sitting between two messages and says whose it
  /// is from the conversation around it, which is enough to attach the right
  /// picture without an image ever leaving the phone.
  final String? photoPath;

  /// Fields the import filled from something other than an explicit statement
  /// on the card — today, a gender worked out from a first name.
  final Set<ParsedField> inferredFields;

  /// A record may skip review only when the three fields the app cannot work
  /// without are all present *and* all read rather than derived.
  ///
  /// Name, gender and age are what a matchmaker needs before a person is any
  /// use in a proposal; anything thinner is a stub the user has to finish
  /// anyway, so it is better caught at import than found later in the list.
  /// Deriving one of the three is enough on its own — an inferred gender is
  /// exactly the mistake that stays invisible until a proposal is built on it.
  bool get needsReview {
    for (final ParsedField field in _requiredForDirectImport) {
      if (!_isStated(field)) {
        return true;
      }
    }
    return false;
  }

  bool _isStated(ParsedField field) =>
      _hasValue(field) && !inferredFields.contains(field);

  bool _hasValue(ParsedField field) => switch (field) {
    ParsedField.firstName => (card.firstName ?? '').isNotEmpty,
    ParsedField.lastName => (card.lastName ?? '').isNotEmpty,
    ParsedField.age => card.age != null,
    ParsedField.gender => card.gender != null,
  };

  static const Set<ParsedField> _requiredForDirectImport = <ParsedField>{
    ParsedField.firstName,
    ParsedField.age,
    ParsedField.gender,
  };
}
