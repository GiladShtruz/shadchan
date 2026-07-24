import 'dart:math';

/// Short pieces of encouragement shown at the bottom of the home screen. A
/// different one greets the matchmaker on every visit.
abstract final class MatchmakerTips {
  static const List<String> tips = <String>[
    'אל תמהר לשדך.\nתן לכל רעיון זמן להיקלט ולבשל.',
    'רעיון שנדחה היום יכול להתאים בעוד שנה.\nשווה לשמור אותו.',
    'שיחה קצרה עם ההורים חוסכת לפעמים שלושה סבבי בירורים.',
    'עדכון קטן בכרטיס היום שווה חיפוש ארוך בעוד חודש.',
    'כדאי לחזור לחברים שלא דיברת איתם מזמן — הרבה השתנה אצלם.',
    'לא כל התאמה על הנייר מרגישה נכון בפגישה, וזה בסדר גמור.',
    'זוג שיוצא צריך מישהו שיאמין בו גם כשקצת קשה.',
    'לפני שמציעים — כדאי לשאול את עצמכם מה השאלה הראשונה שכל צד ישאל.',
    'שדכן טוב מקשיב יותר משהוא מדבר.',
    'תיעוד של סירוב חשוב לא פחות מתיעוד של הצלחה.',
  ];

  static final Random _random = Random();

  /// A random tip, never the one currently on screen (unless there is only one).
  static String next({String? previous}) {
    if (tips.length == 1) {
      return tips.first;
    }
    String candidate = tips[_random.nextInt(tips.length)];
    while (candidate == previous) {
      candidate = tips[_random.nextInt(tips.length)];
    }
    return candidate;
  }
}
