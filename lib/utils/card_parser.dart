import 'package:shadchan/utils/enums.dart';

/// The fields a shidduch card ("כרטיסייה") can yield. Every field is nullable:
/// the parser only reports what it is reasonably confident about, so the form
/// can leave anything it misses untouched instead of overwriting good data.
class ParsedCard {
  const ParsedCard({
    this.firstName,
    this.lastName,
    this.age,
    this.gender,
    this.city,
    this.heightCm,
    this.maritalStatus,
    this.inquiryContactName,
    this.inquiryContactPhone,
  });

  final String? firstName;
  final String? lastName;
  final int? age;
  final Gender? gender;
  final String? city;
  final int? heightCm;
  final MaritalStatus? maritalStatus;
  final String? inquiryContactName;
  final String? inquiryContactPhone;

  bool get isEmpty =>
      firstName == null &&
      lastName == null &&
      age == null &&
      gender == null &&
      city == null &&
      heightCm == null &&
      maritalStatus == null &&
      inquiryContactName == null &&
      inquiryContactPhone == null;

  bool get isNotEmpty => !isEmpty;
}

/// Extracts structured details out of a free-text Hebrew shidduch card.
///
/// Cards arrive from WhatsApp in wildly different shapes, so parsing runs in two
/// passes: labelled lines first (`גיל: 27`), which are unambiguous, then
/// free-text heuristics over the whole message for whatever is still missing
/// (`בחור בן 27 מירושלים, גובה 1.78`). Values that fail a sanity check (an age
/// of 300, a height of 40) are dropped rather than guessed at.
abstract final class CardParser {
  static ParsedCard parse(String rawText) {
    final String text = rawText.trim();
    if (text.isEmpty) {
      return const ParsedCard();
    }

    final Map<String, String> labels = _readLabelledValues(text);

    final String? name = _pickLabel(labels, _nameLabels);
    final ({String? first, String? last}) splitName = _splitName(
      name ?? _guessNameFromFirstLine(text),
    );

    final Gender? gender = _parseGender(
      _pickLabel(labels, _genderLabels),
      text,
    );

    final ({String? name, String? phone}) contact = _parseInquiryContact(
      _pickLabel(labels, _contactLabels),
      text,
    );

    return ParsedCard(
      firstName: splitName.first,
      lastName: splitName.last,
      age: _parseAge(_pickLabel(labels, _ageLabels), text),
      gender: gender,
      city: _parseCity(_pickLabel(labels, _cityLabels), text),
      heightCm: _parseHeight(_pickLabel(labels, _heightLabels), text),
      maritalStatus: _parseMaritalStatus(
        _pickLabel(labels, _maritalLabels),
        text,
      ),
      inquiryContactName: contact.name,
      inquiryContactPhone: contact.phone,
    );
  }

  /// Applies this parser's plausibility rules to a card that was produced
  /// somewhere else — today, by the Gemini fallback in `AiCardParser`.
  ///
  /// A language model will happily return an age of 300 or a height of 40
  /// because the card said so, and it has no equivalent of the checks the
  /// regex passes above run inline. Routing its output through here means both
  /// parsers reject the same nonsense, so the form cannot be filled with a
  /// value the local parser would have thrown away. Anything implausible
  /// becomes null rather than an error: a card with one bad field should still
  /// contribute its good ones.
  static ParsedCard sanitize(ParsedCard card) {
    return ParsedCard(
      firstName: _cleanText(card.firstName),
      lastName: _cleanText(card.lastName),
      age: _isPlausibleAge(card.age) ? card.age : null,
      gender: card.gender,
      city: _cleanText(card.city),
      // Passed through the same reader the regex pass uses, so a model that
      // answers in metres ("1.78") lands on the same centimetres as a model
      // that answers in centimetres.
      heightCm: _heightFrom(card.heightCm?.toString()),
      maritalStatus: card.maritalStatus,
      inquiryContactName: _cleanText(card.inquiryContactName),
      inquiryContactPhone: _normalizePhone(card.inquiryContactPhone),
    );
  }

  static String? _cleanText(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  // --- Label pass ---------------------------------------------------------

  static const List<String> _nameLabels = <String>[
    'שם מלא',
    'השם',
    'שם',
    'שמה',
    'שמו',
  ];
  static const List<String> _ageLabels = <String>[
    'גיל',
    'גילה',
    'גילו',
    'בת/בן',
  ];
  static const List<String> _heightLabels = <String>['גובה', 'גבהה', 'גבהו'];
  static const List<String> _cityLabels = <String>[
    'מקום מגורים',
    'עיר מגורים',
    'מגורים',
    'מיקום',
    'עיר',
    'ישוב',
    'יישוב',
    'אזור',
    'גרה ב',
    'גר ב',
  ];
  static const List<String> _maritalLabels = <String>[
    'מצב משפחתי',
    'סטטוס משפחתי',
    'מצב אישי',
  ];
  static const List<String> _genderLabels = <String>['מגדר', 'מין'];
  static const List<String> _contactLabels = <String>[
    'איש קשר לבירורים',
    'לבירורים',
    'בירורים',
    'איש קשר',
    'ליצירת קשר',
    'לפרטים',
    'טלפון',
    'נייד',
    'פלאפון',
  ];

  /// Maps every `תווית: ערך` line in the card to its value. Keys are stored
  /// normalized (no leading bullets/emojis, no trailing colon) so lookups do
  /// not care how the sender decorated the line.
  static Map<String, String> _readLabelledValues(String text) {
    final Map<String, String> values = <String, String>{};

    for (final String rawLine in text.split(RegExp(r'[\r\n]+'))) {
      final String line = _stripDecoration(rawLine);
      final int separator = _labelSeparatorIndex(line);
      if (separator <= 0) {
        continue;
      }

      final String key = _normalizeLabel(line.substring(0, separator));
      final String value = line.substring(separator + 1).trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      // A label repeated in one card keeps its first occurrence, which is the
      // subject's own detail — later repeats usually belong to a relative.
      values.putIfAbsent(key, () => value);
    }

    return values;
  }

  /// Index of the `:` (or `-`) that separates a label from its value, or -1.
  /// Only a short leading segment counts as a label, so a dash inside a
  /// sentence or a time like `20:30` is not mistaken for one.
  static int _labelSeparatorIndex(String line) {
    final int colon = line.indexOf(':');
    if (colon > 0 && colon <= 20 && !_containsDigit(line.substring(0, colon))) {
      return colon;
    }

    final int dash = line.indexOf(RegExp(r'\s[-–]\s'));
    if (dash > 0 && dash <= 20 && !_containsDigit(line.substring(0, dash))) {
      // Point at the dash itself so the caller's `+ 1` skips it.
      return line.indexOf(RegExp(r'[-–]'), dash);
    }

    return -1;
  }

  static String? _pickLabel(Map<String, String> labels, List<String> keys) {
    for (final String key in keys) {
      final String normalized = _normalizeLabel(key);
      final String? exact = labels[normalized];
      if (exact != null && exact.isNotEmpty) {
        return exact;
      }
    }
    // Fall back to a label that merely starts with one of the keys, e.g.
    // "גובה משוער" for "גובה".
    for (final String key in keys) {
      final String normalized = _normalizeLabel(key);
      for (final MapEntry<String, String> entry in labels.entries) {
        if (entry.key.startsWith(normalized) && entry.value.isNotEmpty) {
          return entry.value;
        }
      }
    }
    return null;
  }

  static String _normalizeLabel(String value) {
    return _stripDecoration(value)
        .replaceAll(RegExp(r'[:\-–]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Removes bullets, emojis and stray punctuation that WhatsApp cards use to
  /// decorate their lines, leaving the Hebrew/Latin text and digits.
  static String _stripDecoration(String value) {
    return value
        .replaceAll(RegExp(r'^[\s\*\-–•·▪️◾️✅✔️📌📍🔹🔸➖‏‎]+'), '')
        .replaceAll(RegExp(r'[\*_]'), '')
        .trim();
  }

  static bool _containsDigit(String value) => RegExp(r'\d').hasMatch(value);

  // --- Name ---------------------------------------------------------------

  /// Cards very often open with just the person's name on its own line. Only
  /// accept that line when it looks like a name: two to four words, no digits,
  /// and no label separator.
  static String? _guessNameFromFirstLine(String text) {
    for (final String rawLine in text.split(RegExp(r'[\r\n]+'))) {
      final String line = _stripDecoration(rawLine);
      if (line.isEmpty) {
        continue;
      }
      if (_containsDigit(line) || line.contains(':')) {
        return null;
      }
      final List<String> words = line.split(RegExp(r'\s+'));
      if (words.length < 2 || words.length > 4) {
        return null;
      }
      return line;
    }
    return null;
  }

  static ({String? first, String? last}) _splitName(String? value) {
    final String name = (value ?? '')
        .replaceAll(RegExp(r'[,\.]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.isEmpty) {
      return (first: null, last: null);
    }

    final List<String> words = name.split(' ');
    if (words.length == 1) {
      return (first: words.first, last: null);
    }
    // Everything after the first word is the family name, so compound surnames
    // like "בן דוד" survive intact.
    return (first: words.first, last: words.sublist(1).join(' '));
  }

  // --- Age ----------------------------------------------------------------

  static int? _parseAge(String? labelled, String text) {
    final int? fromLabel = _firstIntIn(labelled);
    if (_isPlausibleAge(fromLabel)) {
      return fromLabel;
    }

    // "בן 27" / "בת 24" is the usual free-text phrasing. `\b` is useless here —
    // it is defined over `[A-Za-z0-9_]`, so it never fires between Hebrew
    // letters — hence the explicit start/separator prefix.
    final RegExpMatch? match = RegExp(
      r'(?:^|[\s,.])(?:בן|בת)\s+(\d{1,3})',
    ).firstMatch(text);
    final int? fromText = int.tryParse(match?.group(1) ?? '');
    return _isPlausibleAge(fromText) ? fromText : null;
  }

  static int? _firstIntIn(String? value) {
    if (value == null) {
      return null;
    }
    final RegExpMatch? match = RegExp(r'\d{1,3}').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static bool _isPlausibleAge(int? value) =>
      value != null && value >= 15 && value <= 99;

  // --- Height -------------------------------------------------------------

  static int? _parseHeight(String? labelled, String text) {
    final int? fromLabel = _heightFrom(labelled);
    if (fromLabel != null) {
      return fromLabel;
    }
    // Free text: only trust a height that is adjacent to the word "גובה", so a
    // random 175 elsewhere in the card is not read as one.
    final RegExpMatch? match = RegExp(
      r'גוב[הן]\D{0,10}(\d+(?:[.,]\d{1,2})?)',
    ).firstMatch(text);
    return _heightFrom(match?.group(1));
  }

  /// Accepts both notations senders use — `1.78`/`1,78` meters and `178` cm —
  /// and normalizes to whole centimeters.
  static int? _heightFrom(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final RegExpMatch? match = RegExp(
      r'(\d+(?:[.,]\d{1,2})?)',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }

    final double? parsed = double.tryParse(
      match.group(1)!.replaceAll(',', '.'),
    );
    if (parsed == null) {
      return null;
    }

    final int cm = parsed < 3 ? (parsed * 100).round() : parsed.round();
    return (cm >= 120 && cm <= 220) ? cm : null;
  }

  // --- Marital status -----------------------------------------------------

  static MaritalStatus? _parseMaritalStatus(String? labelled, String text) {
    return _maritalFrom(labelled) ?? _maritalFrom(text);
  }

  static MaritalStatus? _maritalFrom(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    if (RegExp(r'גרוש').hasMatch(value)) {
      return MaritalStatus.divorced;
    }
    if (RegExp(r'אלמן|אלמנה').hasMatch(value)) {
      return MaritalStatus.widowed;
    }
    if (RegExp(r'רווק|רוו?קה').hasMatch(value)) {
      return MaritalStatus.single;
    }
    return null;
  }

  // --- Gender -------------------------------------------------------------

  static Gender? _parseGender(String? labelled, String text) {
    final Gender? fromLabel = _genderFrom(labelled);
    if (fromLabel != null) {
      return fromLabel;
    }
    return _genderFrom(text);
  }

  static Gender? _genderFrom(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    // Feminine markers are checked first: "בחורה" contains "בחור", so testing
    // the masculine form first would misread every women's card.
    // A trailing `(?![א-ת])` stands in for `\b`, which does not apply to Hebrew.
    if (RegExp(
      r'בחורה|נקבה|רווקה|גרושה|אלמנה|היא(?![א-ת])|בת\s+\d|גרה(?![א-ת])|מתגוררת',
    ).hasMatch(value)) {
      return Gender.female;
    }
    if (RegExp(
      r'בחור|זכר|רווק|גרוש|אלמן|הוא(?![א-ת])|בן\s+\d|גר(?![א-ת])|מתגורר',
    ).hasMatch(value)) {
      return Gender.male;
    }
    return null;
  }

  // --- City ---------------------------------------------------------------

  static String? _parseCity(String? labelled, String text) {
    final String? fromLabel = _cleanCity(labelled);
    if (fromLabel != null) {
      return fromLabel;
    }

    final RegExpMatch? match = RegExp(
      r'(?:גר|גרה|מתגורר|מתגוררת|מגורים)\s+ב([^\n,\.]{2,30})',
    ).firstMatch(text);
    return _cleanCity(match?.group(1));
  }

  static String? _cleanCity(String? value) {
    final String city = (value ?? '')
        .replaceAll(RegExp(r'^ב(?=[א-ת])'), '')
        .replaceAll(RegExp(r'[,\.]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (city.isEmpty || city.length > 30 || _containsDigit(city)) {
      return null;
    }
    return city;
  }

  // --- Inquiry contact ----------------------------------------------------

  static ({String? name, String? phone}) _parseInquiryContact(
    String? labelled,
    String text,
  ) {
    // Prefer the labelled line, which usually holds both the name and number
    // ("לבירורים: אמא שרה 052-1234567"). Otherwise take the first phone number
    // anywhere in the card, with no name attached.
    final String source = (labelled != null && labelled.isNotEmpty)
        ? labelled
        : text;
    final RegExpMatch? phoneMatch = _phonePattern.firstMatch(source);
    final String? phone = _normalizePhone(phoneMatch?.group(0));

    if (labelled == null || labelled.isEmpty) {
      return (name: null, phone: phone);
    }

    final String name = labelled
        .replaceAll(_phonePattern, '')
        .replaceAll(RegExp(r'[\-–,\.:]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return (
      name: (name.isEmpty || name.length > 40) ? null : name,
      phone: phone,
    );
  }

  static final RegExp _phonePattern = RegExp(
    r'(?:\+?972|0)[\s\-.]?\d{1,2}[\s\-.]?\d{3}[\s\-.]?\d{4}',
  );

  /// Reduces a matched number to digits and puts it in local `0…` form, so
  /// numbers shared as `+972-52-123-4567` match ones stored as `0521234567`.
  static String? _normalizePhone(String? raw) {
    if (raw == null) {
      return null;
    }

    String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('972')) {
      digits = '0${digits.substring(3)}';
    }
    if (!digits.startsWith('0') || digits.length < 9 || digits.length > 10) {
      return null;
    }
    return digits;
  }
}
