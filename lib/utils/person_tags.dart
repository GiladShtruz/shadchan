/// The small vocabulary rules behind a matchmaker's own tags.
///
/// Tags are the matchmaker's private language for their database — "עירוניסט",
/// "חו״ל", "חי בין עולמות" — and live only on their own records. The one thing
/// that ever leaves the phone is the *word*, never who it is on, and only when
/// [isCommunityShareable] says the word is general enough to be an inspiration
/// to another matchmaker rather than a label for somebody's own circle.
abstract final class PersonTags {
  /// Longest tag accepted. A tag is a word or two, not a note.
  static const int maxLength = 30;

  /// Shown to a matchmaker who has no tags of their own yet — as examples to
  /// start from, never as "the popular tags".
  static const List<String> starters = <String>[
    'עירוניסט/ית',
    'רוחני/ת',
    'ליברלי/ת',
    'טבע',
    'חו״ל',
    'חי/ה בין עולמות',
    'אמנות',
  ];

  /// A tag as it is stored: trimmed, inner whitespace collapsed, Hebrew
  /// geresh/gershayim look-alikes unified so "חו"ל" and "חו״ל" are one tag.
  static String normalize(String raw) {
    return raw
        .replaceAll('"', '״')
        .replaceAll("'", '׳')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// The key two spellings of one tag share, for comparing and de-duplicating.
  static String keyOf(String tag) =>
      normalize(tag).replaceAll(RegExp('[״׳"\'\\-_./ ]'), '').toLowerCase();

  static bool sameTag(String a, String b) => keyOf(a) == keyOf(b);

  /// Words that name a specific circle — an institution, a unit, a workplace,
  /// a community. A tag containing one describes where people come from, which
  /// identifies them; it stays with the matchmaker who wrote it.
  static const List<String> _circleWords = <String>[
    'ישיבה',
    'ישיבת',
    'מדרשה',
    'מדרשת',
    'אולפנה',
    'אולפנת',
    'מכינה',
    'מכינת',
    'סמינר',
    'כולל',
    'קהילה',
    'קהילת',
    'בית כנסת',
    'בית הכנסת',
    'גרעין',
    'יחידה',
    'יחידת',
    'גדוד',
    'חטיבה',
    'חטיבת',
    'סיירת',
    'שייטת',
    '8200',
    'מקום עבודה',
    'מהעבודה',
    'משרד',
    'אוניברסיטה',
    'אוניברסיטת',
    'מכללה',
    'מכללת',
    'תיכון',
    'בית ספר',
    'ביה״ס',
    'אולפן',
    'סניף',
    'שבט',
    'מחזור',
    'שכונה',
    'שכונת',
    'מהשכונה',
    'מהצבא',
    'מהישיבה',
    'מהמדרשה',
    'מהאולפנה',
    'מהסמינר',
    'מהקהילה',
    'מהגרעין',
    'מהמכינה',
    'מהתיכון',
    'מהסניף',
    'מהלימודים',
    // Youth movements are circles too.
    'בני עקיבא',
    'עזרא',
    'אריאל',
    'נוער',
  ];

  /// "חברים מ־X", "חברה מהעבודה", "חבר של" — a label for the matchmaker's own
  /// circle whatever X is.
  static final RegExp _circlePhrase = RegExp(
    r'(^|\s)(חבר|חברה|חברים|חברות|מכרים|מכר|מכרה)\s+(מ|של|מה)',
  );

  /// Places, which say where somebody lives rather than what they are like.
  /// Not exhaustive by design: the matchmaker's own cities are checked too,
  /// through [knownPlaces] in [isCommunityShareable].
  static const Set<String> _places = <String>{
    'ירושלים',
    'תל אביב',
    'תל-אביב',
    'חיפה',
    'באר שבע',
    'בני ברק',
    'פתח תקווה',
    'פתח תקוה',
    'ראשון לציון',
    'אשדוד',
    'אשקלון',
    'נתניה',
    'חולון',
    'בת ים',
    'רמת גן',
    'גבעתיים',
    'הרצליה',
    'רעננה',
    'כפר סבא',
    'הוד השרון',
    'רחובות',
    'נס ציונה',
    'לוד',
    'רמלה',
    'מודיעין',
    'מודיעין עילית',
    'בית שמש',
    'אלעד',
    'ביתר',
    'ביתר עילית',
    'אפרת',
    'גוש עציון',
    'מעלה אדומים',
    'אריאל',
    'קרני שומרון',
    'עמנואל',
    'קדומים',
    'שילה',
    'עלי',
    'בית אל',
    'חברון',
    'קריית ארבע',
    'קרית ארבע',
    'צפת',
    'טבריה',
    'עפולה',
    'נהריה',
    'עכו',
    'כרמיאל',
    'מעלות',
    'קריית שמונה',
    'קרית שמונה',
    'רמת הגולן',
    'קצרין',
    'חדרה',
    'זכרון יעקב',
    'פרדס חנה',
    'יבנה',
    'גדרה',
    'קריית גת',
    'קרית גת',
    'קריית מלאכי',
    'שדרות',
    'נתיבות',
    'אופקים',
    'דימונה',
    'ירוחם',
    'אילת',
    'ערד',
    'רמת בית שמש',
    'גבעת שמואל',
    'קריית אונו',
    'קרית אונו',
    'אור יהודה',
    'יהוד',
    'ראש העין',
    'שוהם',
    'חשמונאים',
    'כוכב יעקב',
    'טלמון',
    'נווה דניאל',
    'אלון שבות',
    'תקוע',
    'נוקדים',
    'מצפה רמון',
    'יקנעם',
    'נוף הגליל',
    'מגדל העמק',
    'עתלית',
    'טירת כרמל',
    'קריית ים',
    'קריית ביאליק',
    'קריית מוצקין',
    'קריית אתא',
    'נשר',
    'רכסים',
    'קריית ספר',
  };

  /// Whether [tag] may be offered to other matchmakers as inspiration.
  ///
  /// A reasonable filter, not a perfect one — what it is for is keeping the
  /// obvious personal-circle labels ("חברים מהישיבה", "בית אל", "מחזור 12") out
  /// of the shared pool, while general words ("חו״ל", "טבע") pass. Geography as
  /// a *style* is fine; a named place is not. [knownPlaces] adds the cities the
  /// matchmaker's own database already uses.
  static bool isCommunityShareable(
    String tag, {
    Iterable<String> knownPlaces = const <String>[],
  }) {
    final String value = normalize(tag);
    if (value.length < 2 || value.length > 24) {
      return false;
    }
    // Numbers name years, units and classes.
    if (RegExp(r'\d').hasMatch(value)) {
      return false;
    }
    if (_circlePhrase.hasMatch(value)) {
      return false;
    }
    for (final String word in _circleWords) {
      if (value.contains(word)) {
        return false;
      }
    }
    final String key = keyOf(value);
    for (final String place in <String>[..._places, ...knownPlaces]) {
      final String placeKey = keyOf(place);
      if (placeKey.length < 2) {
        continue;
      }
      // The place itself, or "מ/ב + place" ("מבית אל", "בצפת").
      if (key == placeKey ||
          key == 'מ$placeKey' ||
          key == 'ב$placeKey' ||
          (placeKey.length >= 4 && key.contains(placeKey))) {
        return false;
      }
    }
    return true;
  }
}
