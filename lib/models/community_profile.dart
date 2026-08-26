/// What one matchmaker chose to let other matchmakers see about them.
///
/// **Everything here is opt-in and everything here is public.** The
/// `communityMembers` collection is readable by every installed copy of the
/// app — that is what makes a leaderboard and a shared total possible at all —
/// so a field is only added to it when a matchmaker deliberately fills it in,
/// and every one of them is erased by the same write that erases the name when
/// somebody hides themselves. See `CommunityService.publish`.
///
/// **What is deliberately not here.** No age, and no activity: not how long
/// somebody has been at this, not how many couples they have made, not which
/// age range they work in, not how they prefer to be approached. A public page
/// about a person is not a performance review, and a figure like "37 זוגות"
/// beside somebody's face turns a room of colleagues into a ranking — which the
/// leaderboard already is, once, in the one place it belongs.
library;

/// One thing a matchmaker chose to say about themselves, and which question it
/// answers.
///
/// **Prompts, not fields.** The profile used to be a form — a box for the
/// region, a box for the population, a box for the role — and a form is a list
/// of questions everybody has to have an answer to. Most matchmakers have two
/// or three of these and nothing sensible to put in the others, so the form
/// came back either mostly empty or filled with filler. These are offered as a
/// menu instead: pick the ones that are true of you, leave the rest alone, and
/// what you picked is shown together as one paragraph rather than as a table
/// with blanks in it.
enum MatchmakerShareKind {
  origin('מאיפה אני בארץ', 'למשל: פתח תקווה'),
  region('שדכן/ית של אזור', 'למשל: השרון והמרכז'),
  population('שדכן/ית של אוכלוסייה', 'למשל: דתי־לאומי, בוגרי ישיבות הסדר'),
  role('תפקיד או פעילות חברתית', 'למשל: רכזת בוגרות במדרשה'),
  more('מידע נוסף שחשוב לי', 'כל דבר שירצו שדכנים אחרים לדעת');

  const MatchmakerShareKind(this.label, this.hint);

  /// The question this line answers, shown above it on the public profile.
  final String label;

  /// One example, so a blank box is never the whole of the instruction.
  final String hint;

  static MatchmakerShareKind? byName(String name) {
    for (final MatchmakerShareKind kind in MatchmakerShareKind.values) {
      if (kind.name == name) {
        return kind;
      }
    }
    return null;
  }
}

/// One filled-in prompt.
///
/// Stored and published as `kind|text` — a single string, because the local
/// store keeps lists of strings and the shared collection's security rules can
/// check a list of short strings without a schema. The separator is split on
/// the *first* `|` only, so a matchmaker who writes one in their answer keeps
/// it.
class MatchmakerShare {
  const MatchmakerShare({required this.kind, required this.text});

  final MatchmakerShareKind kind;
  final String text;

  /// How long one answer may be. Long enough for a sentence, short enough that
  /// nobody can paste an essay into a collection everybody downloads.
  static const int maxLength = 120;

  String encode() => '${kind.name}|$text';

  static MatchmakerShare? decode(Object? raw) {
    if (raw is! String) {
      return null;
    }
    final int cut = raw.indexOf('|');
    if (cut <= 0) {
      return null;
    }
    final MatchmakerShareKind? kind = MatchmakerShareKind.byName(
      raw.substring(0, cut),
    );
    final String text = raw.substring(cut + 1).trim();
    if (kind == null || text.isEmpty) {
      return null;
    }
    return MatchmakerShare(
      kind: kind,
      text: text.length <= maxLength ? text : text.substring(0, maxLength),
    );
  }

  /// Every valid share in [raw], in the enum's own order and at most one per
  /// prompt — a stored list from an older build, or a hand-edited document,
  /// cannot make the profile show the same question twice.
  static List<MatchmakerShare> decodeAll(Iterable<Object?> raw) {
    final Map<MatchmakerShareKind, MatchmakerShare> byKind =
        <MatchmakerShareKind, MatchmakerShare>{};
    for (final Object? value in raw) {
      final MatchmakerShare? share = decode(value);
      if (share != null) {
        byKind.putIfAbsent(share.kind, () => share);
      }
    }
    return <MatchmakerShare>[
      for (final MatchmakerShareKind kind in MatchmakerShareKind.values)
        if (byKind[kind] case final MatchmakerShare share) share,
    ];
  }
}

/// One matchmaker's public page, as another matchmaker reads it.
class CommunityProfile {
  const CommunityProfile({
    required this.uid,
    required this.name,
    this.photoUrl = '',
    this.about = '',
    this.shares = const <MatchmakerShare>[],
    this.benefit = '',
    this.contactPhone = '',
  });

  /// How long the free-text fields may be.
  static const int maxAboutLength = 200;
  static const int maxBenefitLength = 240;

  /// At most one answer per prompt, so this is the ceiling by construction.
  static int get maxShares => MatchmakerShareKind.values.length;

  final String uid;
  final String name;
  final String photoUrl;

  /// "משפט קצר עליי" — the same line the matchmaker's own profile shows.
  final String about;

  /// The answers to "מה תרצה ששדכנים אחרים ידעו עליך?", in prompt order.
  final List<MatchmakerShare> shares;

  /// "הטבה לקהילה" — something this matchmaker offers other matchmakers. Empty
  /// for the very many who offer nothing, and the profile simply has no such
  /// area.
  final String benefit;

  /// A number to reach them on, if they published one. Never inferred from
  /// anything: a matchmaker types it into their own profile or there is no
  /// WhatsApp button.
  final String contactPhone;

  /// Whether there is anything here beyond a name and a face.
  bool get hasDetails =>
      about.isNotEmpty ||
      shares.isNotEmpty ||
      benefit.isNotEmpty ||
      contactPhone.isNotEmpty;

  /// Reads one member document. Everything is optional and everything is
  /// bounded: this is data other clients wrote.
  static CommunityProfile fromDocument(String uid, Map<String, dynamic> data) {
    String text(String field, int limit) {
      final Object? raw = data[field];
      if (raw is! String) {
        return '';
      }
      final String value = raw.trim();
      return value.length <= limit ? value : value.substring(0, limit);
    }

    final Object? rawShares = data['shares'];
    return CommunityProfile(
      uid: uid,
      name: text('name', 80).isEmpty ? 'שדכן' : text('name', 80),
      photoUrl: text('photoUrl', 500),
      about: text('about', maxAboutLength),
      shares: rawShares is Iterable
          ? MatchmakerShare.decodeAll(rawShares)
          : const <MatchmakerShare>[],
      benefit: text('benefit', maxBenefitLength),
      contactPhone: text('contactPhone', 24),
    );
  }
}
