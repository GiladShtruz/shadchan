import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';

/// The kinds of notification a user can switch off, one switch each.
///
/// **Every kind the app or the server sends belongs to exactly one of these.**
/// A server notice is mapped by its `kind` ([NotificationPreferences.categoryOf]);
/// a reminder or a friend's status change that moved ideas is [ideas]; a
/// support answer is [support]. A kind nobody has mapped yet lands in
/// [system], so a new notice never escapes the switches.
enum NotificationCategory {
  ideas(
    'רעיונות ותזכורות',
    'תזכורות לרעיונות ולחברים, ועדכונים שמשפיעים על רעיונות פתוחים',
  ),
  cardFriends(
    'חבר שהוסיף כרטיס אישי',
    'חבר מהמאגר שלך פתח כרטיס אישי או עדכן אותו',
  ),
  newMatchmakers('שדכן חדש מאנשי הקשר', 'מישהו מאנשי הקשר שלך הצטרף לשדכן'),
  access(
    'בקשות ואישורי גישה',
    'בקשות גישה לכרטיס, אישורים ובקשות חיבור בין שדכנים',
  ),
  celebrations(
    'שמחות וימי הולדת',
    'מזל טוב וימי הולדת עבריים של חברים שנתנו לך גישה',
  ),
  network(
    'רעיונות משדכנים מחוברים',
    'שדכן/ית שמחובר/ת אליך מציע/ה רעיון, או אישר/ה רעיון שהצעת',
  ),
  chats('הודעות בצ\'אט', 'הודעה חדשה משדכן/ית בצ\'אט'),
  system('עדכוני מערכת', 'חדשות מצוות שדכן ועדכונים כלליים'),
  support('תשובות לפניות שלך', 'כשצוות שדכן עונה על פנייה ששלחת');

  const NotificationCategory(this.label, this.description);

  final String label;
  final String description;

  static NotificationCategory? byName(String name) {
    for (final NotificationCategory c in NotificationCategory.values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// Which kinds of notification this user wants — every kind on by default.
///
/// Stored as the list of kinds switched **off** (`notifications.muted`), a
/// synced setting, so the choice follows the account to every phone. The
/// same list is published on the account's push document (see
/// `PersonalCardService.saveNotificationMutes`) so the server does not push
/// what was switched off; the app hides those rows from the notifications
/// page and the bell, and schedules no local reminder when [ideas] is off.
class NotificationPreferences extends ChangeNotifier {
  NotificationPreferences._();

  static final NotificationPreferences instance = NotificationPreferences._();

  static const String key = 'notifications.muted';

  /// Called with the new list whenever it changes — set by the app to publish
  /// it for the server and to reschedule the local reminders.
  static void Function(List<String> muted)? onChanged;

  Set<NotificationCategory>? _cache;

  Set<NotificationCategory> get muted {
    final Set<NotificationCategory>? cached = _cache;
    if (cached != null) return cached;
    final Set<NotificationCategory> out = <NotificationCategory>{};
    final Object? raw = Hive.isBoxOpen('settings')
        ? Hive.box<dynamic>('settings').get(key)
        : null;
    if (raw is String) {
      for (final String name in raw.split(',')) {
        final NotificationCategory? c = NotificationCategory.byName(
          name.trim(),
        );
        if (c != null) out.add(c);
      }
    }
    return _cache = out;
  }

  /// The muted kinds by name, as they travel to the server.
  List<String> get mutedNames =>
      <String>[for (final NotificationCategory c in muted) c.name]..sort();

  bool wants(NotificationCategory category) => !muted.contains(category);

  void set(NotificationCategory category, {required bool enabled}) {
    final Set<NotificationCategory> next = <NotificationCategory>{...muted};
    final bool changed = enabled ? next.remove(category) : next.add(category);
    if (!changed) return;
    _cache = next;
    persistHomeSetting(key, mutedNames.join(','));
    notifyListeners();
    onChanged?.call(mutedNames);
  }

  /// The account changed the settings box: read it again.
  void forgetCache() {
    _cache = null;
    notifyListeners();
  }

  /// The kind a server notice belongs to.
  static NotificationCategory categoryOf(String kind) => switch (kind) {
    'reminder' || 'idea' || 'friend' => NotificationCategory.ideas,
    'cardCreated' || 'cardUpdated' => NotificationCategory.cardFriends,
    'matchmakerJoined' || 'friendJoined' => NotificationCategory.newMatchmakers,
    'accessRequest' ||
    'accessApproved' ||
    'accessDeclined' ||
    'connectionRequest' ||
    'connectionApproved' ||
    'shareOnwardRequest' ||
    'statusReport' => NotificationCategory.access,
    'ideaProposal' ||
    'ideaProposalApproved' ||
    'ideaProposalDeclined' => NotificationCategory.network,
    'chatMessage' => NotificationCategory.chats,
    'birthday' || 'mazelTov' => NotificationCategory.celebrations,
    'support' => NotificationCategory.support,
    _ => NotificationCategory.system,
  };

  /// Whether a server notice of [kind] is wanted.
  bool wantsKind(String kind) => wants(categoryOf(kind));
}
