/// The search on "צ'אטים": existing conversations first, then the people in
/// this phone's contacts who use שדכן — whether or not they ever wrote, gave
/// access to a card or share a database. **Nobody else**: there is no search
/// over every user of the app.
///
/// Pure, so the matching rules are tested.
library;

/// Somebody the search can offer a conversation with.
class ChatContact {
  const ChatContact({
    required this.uid,
    required this.name,
    this.phone,
    this.why = '',
  });

  final String uid;

  /// The name saved in this phone, else their own.
  final String name;

  /// The number saved in this phone — matched, never shown.
  final String? phone;

  /// What ties the two ("שדכן/ית מאנשי הקשר", "כרטיס אישי"…).
  final String why;
}

abstract final class ChatSearch {
  /// How long typing rests before the search runs.
  static const Duration debounce = Duration(milliseconds: 250);

  /// Folds what differs between two spellings of one name: case, niqqud,
  /// final letters, punctuation and spacing.
  static String fold(String s) {
    final StringBuffer out = StringBuffer();
    for (final int c in s.toLowerCase().runes) {
      // Hebrew points and cantillation.
      if (c >= 0x0591 && c <= 0x05C7) continue;
      final String ch = String.fromCharCode(c);
      out.write(switch (ch) {
        'ך' => 'כ',
        'ם' => 'מ',
        'ן' => 'נ',
        'ף' => 'פ',
        'ץ' => 'צ',
        '-' || '־' || '\'' || '"' || '״' || '׳' || '.' => ' ',
        _ => ch,
      });
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Whether [name] answers [query]: every word typed starts a word of the
  /// name (first name, surname or both, in any order), or the whole query
  /// is inside it.
  static bool nameMatches(String name, String query) {
    final String q = fold(query);
    if (q.isEmpty) return true;
    final String n = fold(name);
    if (n.contains(q)) return true;
    final List<String> words = n.split(' ');
    for (final String part in q.split(' ')) {
      if (!words.any((String w) => w.startsWith(part))) return false;
    }
    return true;
  }

  /// A number in its local form ("0501234567"), digits only.
  static String localDigits(String phone) {
    String d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00972')) d = '0${d.substring(5)}';
    if (d.startsWith('972')) d = '0${d.substring(3)}';
    return d;
  }

  /// Whether [phone] answers a query of digits (at least four of them).
  static bool phoneMatches(String? phone, String query) {
    if (phone == null) return false;
    final String q = localDigits(query);
    if (q.length < 4) return false;
    return localDigits(phone).contains(q.startsWith('0') ? q : q);
  }

  /// The contacts that answer [query], without those already in
  /// [withThreads], one per uid, by name.
  static List<ChatContact> contacts(
    Iterable<ChatContact> all,
    String query, {
    Set<String> withThreads = const <String>{},
    String? me,
  }) {
    if (fold(query).isEmpty) return const <ChatContact>[];
    final Map<String, ChatContact> out = <String, ChatContact>{};
    for (final ChatContact c in all) {
      if (c.uid.isEmpty || c.uid == me || withThreads.contains(c.uid)) {
        continue;
      }
      if (out.containsKey(c.uid)) continue;
      if (nameMatches(c.name, query) || phoneMatches(c.phone, query)) {
        out[c.uid] = c;
      }
    }
    final List<ChatContact> list = out.values.toList()
      ..sort((ChatContact a, ChatContact b) => a.name.compareTo(b.name));
    return list;
  }
}
