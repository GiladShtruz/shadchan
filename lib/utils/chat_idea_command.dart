import 'package:shadchan/models/person.dart';

/// Two names read out of a free sentence, in the order they were written.
typedef NamePair = (String, String);

/// "פתח רעיון בין יעל כהן לאורי לוי" — a matchmaker writing in a chat what
/// they want done, in their own words.
///
/// This is the local reading: fast, free, offline, and good for the way
/// people actually write it. When it cannot find two names, the chat asks
/// Gemini to read the sentence (`AiChatCommand`); either way the names are
/// then **resolved against real cards**, and anything ambiguous is asked
/// before anything is sent. Pure, so it is tested.
abstract final class ChatIdeaCommand {
  static final RegExp _verb = RegExp(
    r'(?:^|\s)(?:פתח|פתחי|תפתח|תפתחי|לפתוח|נפתח|הצע|הציעי|תציע|תציעי|להציע|שלח|שלחי)\s',
  );

  static final RegExp _between = RegExp(r'רעיון\s+(?:בין\s+)?(.+)$');

  /// Whether [text] reads as a request to open an idea, rather than a
  /// message to the other matchmaker.
  static bool looksLike(String text) {
    final String t = ' ${_clean(text)}';
    return t.contains('רעיון') && _verb.hasMatch(t);
  }

  /// Every way [text] can be split into two names — "יעל כהן לאורי לוי"
  /// is "יעל כהן" and "אורי לוי", but "שירה ללאה כהן" may be "לאה כהן".
  /// The caller keeps the split whose names both resolve.
  static List<NamePair> parse(String text) {
    final RegExpMatch? m = _between.firstMatch(_clean(text));
    if (m == null) return const <NamePair>[];
    final String rest = m.group(1)!.trim();
    final List<String> words = rest.split(RegExp(r'\s+'));
    final List<NamePair> out = <NamePair>[];
    void addPair(String a, String b) {
      final String x = _name(a);
      final String y = _name(b);
      if (x.isEmpty || y.isEmpty) return;
      final NamePair pair = (x, y);
      if (!out.contains(pair)) out.add(pair);
    }

    for (int i = 1; i < words.length; i++) {
      final String head = words.sublist(0, i).join(' ');
      final String w = words[i];
      final String tail = words.sublist(i + 1).join(' ');
      if (w == 'עם' || w == 'ל' || w == 'ו' || w == 'לבין' || w == 'ובין') {
        addPair(head, tail);
        continue;
      }
      for (final String prefix in <String>['ול', 'ל', 'ו']) {
        if (w.length > prefix.length + 1 && w.startsWith(prefix)) {
          final String second = <String>[
            w.substring(prefix.length).replaceFirst(RegExp('^[־-]'), ''),
            if (tail.isNotEmpty) tail,
          ].join(' ');
          addPair(head, second);
        }
      }
    }
    return out;
  }

  /// The people in [people] whose name answers [query] — the full name
  /// first, then a first name alone.
  static List<Person> resolve(String query, Iterable<Person> people) {
    final String q = _name(query);
    if (q.isEmpty) return const <Person>[];
    final List<Person> exact = <Person>[
      for (final Person p in people)
        if (_name(p.fullName) == q) p,
    ];
    if (exact.isNotEmpty) return exact;
    final List<Person> starts = <Person>[
      for (final Person p in people)
        if (_name(p.fullName).startsWith('$q ') || _name(p.firstName) == q) p,
    ];
    return starts;
  }

  static String _clean(String text) => text
      .replaceAll(RegExp('[״"\'׳.!?,:]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _name(String text) => _clean(text);
}
