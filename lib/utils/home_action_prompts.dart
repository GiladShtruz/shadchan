import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';

/// What a prompt on "הפעולה הבאה שלך" leads to.
enum HomeActionPromptKind {
  /// Friends with a card who have not been asked for access yet.
  askCardFriends,

  /// Friends in the database without a personal card — invite them.
  inviteFriends,

  /// The matchmaker's own profile photo is missing.
  addPhoto,

  /// Matchmakers among the contacts to connect with.
  connectMatchmakers,

  /// "משפט קצר עליי" is empty.
  completeProfile,
}

/// One prompt: a row of the action list that is not about a person or an
/// idea, but about using the app more — a photo, invitations, connections.
class HomeActionPrompt {
  const HomeActionPrompt({
    required this.kind,
    required this.title,
    required this.subtitle,
  });

  final HomeActionPromptKind kind;
  final String title;

  /// One short line.
  final String subtitle;

  /// What "הסרה מהלוח שלי" is recorded under.
  String get key => 'prompt:${kind.name}';
}

/// Which prompts the action list carries, in the order they are mixed in.
/// Pure, so every wording is tested.
abstract final class HomeActionPrompts {
  /// Fewer connections than this, and connecting is worth suggesting.
  static const int fewConnections = 5;

  /// At most this many at once, so the list stays about the work.
  static const int maxShown = 3;

  static List<HomeActionPrompt> build({
    required bool hasPhoto,
    required bool hasAbout,
    required int friendsWithoutCard,
    required int cardFriendsToAsk,
    required int connectedMatchmakers,
    required bool hasFriends,
    Gender? gender,
  }) {
    String g(String template) => template.forGender(gender);
    return <HomeActionPrompt>[
      if (cardFriendsToAsk > 0)
        HomeActionPrompt(
          kind: HomeActionPromptKind.askCardFriends,
          title: cardFriendsToAsk == 1
              ? 'חבר אחד שלך מנהל כרטיס אישי'
              : '$cardFriendsToAsk חברים שלך מנהלים כרטיס אישי',
          subtitle: g('{בקש|בקשי} גישה לכרטיס'),
        ),
      if (!hasPhoto)
        HomeActionPrompt(
          kind: HomeActionPromptKind.addPhoto,
          title: 'עוד אין לך תמונת פרופיל',
          subtitle: g('{הוסף|הוסיפי} תמונה'),
        ),
      if (hasFriends && friendsWithoutCard > 0)
        HomeActionPrompt(
          kind: HomeActionPromptKind.inviteFriends,
          title: friendsWithoutCard == 1
              ? 'חבר אחד עדיין בלי כרטיס אישי'
              : '$friendsWithoutCard חברים עדיין בלי כרטיס אישי',
          subtitle: friendsWithoutCard == 1
              ? g('{שלח|שלחי} לו הזמנה')
              : g('{שלח|שלחי} להם הזמנה'),
        ),
      if (connectedMatchmakers < fewConnections)
        HomeActionPrompt(
          kind: HomeActionPromptKind.connectMatchmakers,
          title: 'שדכנים מאנשי הקשר שלך',
          subtitle: g('{התחבר|התחברי} אליהם'),
        ),
      if (!hasAbout)
        HomeActionPrompt(
          kind: HomeActionPromptKind.completeProfile,
          title: 'משפט קצר עליך',
          subtitle: g('{כתוב|כתבי} כמה מילים לפרופיל'),
        ),
    ];
  }

  /// Where the prompts go among [rows] other rows: the third place, then
  /// every third — close enough to be seen, never ahead of the first real
  /// work.
  static List<int> positions(int rows, int prompts) {
    final List<int> at = <int>[];
    int index = 2;
    for (int i = 0; i < prompts; i++) {
      // Each prompt placed pushes the rows after it one down.
      at.add(index > rows + i ? rows + i : index);
      index += 3;
    }
    return at;
  }
}
