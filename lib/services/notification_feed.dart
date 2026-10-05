import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/support_inbox_provider.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/reminder_log.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/enums.dart';

/// Where a notification came from.
enum NotificationSource { inbox, reminder, support }

/// One line on the notifications page, before any are merged.
///
/// Says the three things a glance needs — who, what happened, and when — and
/// carries whatever is needed to open the exact thing it is about.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.source,
    required this.time,
    required this.read,
    required this.groupKey,
    required this.title,
    this.subtitle,
    this.person,
    this.couple,
    this.inbox,
    this.report,
    this.reminder,
  });

  /// Unique across sources: `inbox:…`, `reminder:…`, `support:…`.
  final String id;
  final NotificationSource source;
  final DateTime time;
  final bool read;

  /// Lines about the same person (or idea, or conversation) close together
  /// in time are drawn as one — see [NotificationFeed.group].
  final String groupKey;

  /// The main line: what happened, or what the matchmaker wrote.
  final String title;

  /// A very short second line, when it adds anything.
  final String? subtitle;

  /// The face on the line: one friend…
  final Person? person;

  /// …or the two sides of an idea, boy first.
  final (Person?, Person?)? couple;

  final InboxItem? inbox;
  final SupportReport? report;
  final ReminderLogEntry? reminder;
}

/// Several lines about one subject, close in time, drawn as one row.
class NotificationGroup {
  NotificationGroup(this.items);

  /// Newest first.
  final List<AppNotification> items;

  AppNotification get latest => items.first;
  DateTime get time => latest.time;
  bool get read => items.every((AppNotification n) => n.read);
  int get count => items.length;
  String get id => latest.id;
}

/// The notifications page's list: card notices from the server, reminders
/// that came due, and support answers — one list, newest first.
abstract final class NotificationFeed {
  /// Lines about one subject this close together are one row.
  static const Duration groupWindow = Duration(hours: 6);

  /// Every reminder that is due right now, in the shape [ReminderLog.sync]
  /// takes. Due means from the start of its day, as everywhere in the app.
  static List<DueReminder> dueReminders({
    required Iterable<MatchIdea> matches,
    required Map<String, DateTime> personReminders,
    required String? Function(String personId) personNote,
    required bool Function(String personId) personExists,
    DateTime? now,
  }) {
    final DateTime today = now ?? DateTime.now();
    final DateTime endOfToday = DateTime(
      today.year,
      today.month,
      today.day,
      23,
      59,
      59,
    );
    bool due(DateTime date) => !date.isAfter(endOfToday);
    return <DueReminder>[
      for (final MatchIdea match in matches)
        if (match.reminderDate case final DateTime at when due(at))
          DueReminder(
            kind: HomeItemKind.idea,
            targetId: match.id,
            date: at,
            note: match.reminderNote == MatchRepository.defaultReminderNote
                ? null
                : match.reminderNote,
          ),
      for (final MapEntry<String, DateTime> entry in personReminders.entries)
        if (due(entry.value) && personExists(entry.key))
          DueReminder(
            kind: HomeItemKind.person,
            targetId: entry.key,
            date: entry.value,
            note: personNote(entry.key),
          ),
    ];
  }

  /// Builds every line, newest first.
  static List<AppNotification> build({
    required Iterable<InboxItem> inbox,
    required Iterable<SupportThread> support,
    required Iterable<ReminderLogEntry> reminders,
    required bool supportAdmin,
    required Person? Function(String id) personById,
    required MatchIdea? Function(String id) matchById,
    required Person? Function(InboxItem item) personOfNotice,
    DateTime? now,
  }) {
    final DateTime clock = now ?? DateTime.now();
    final List<AppNotification> out = <AppNotification>[];

    for (final InboxItem item in inbox) {
      final Person? person = personOfNotice(item);
      out.add(
        AppNotification(
          id: 'inbox:${item.id}',
          source: NotificationSource.inbox,
          time: item.createdAt ?? clock,
          read: item.read,
          groupKey:
              'who:${item.ownerUid ?? item.ownerPhoneHash ?? 'inbox:${item.id}'}',
          title: item.title.trim(),
          subtitle: item.body.trim().isEmpty ? null : item.body.trim(),
          person: person,
          inbox: item,
        ),
      );
    }

    for (final SupportThread thread in support) {
      final SupportReport report = thread.report;
      final String title;
      if (supportAdmin) {
        final String who = report.authorName.trim().isEmpty
            ? 'שולח לא מזוהה'
            : report.authorName.trim();
        title = report.hasConversation ? 'שיחה עם $who' : 'פנייה חדשה מ$who';
      } else {
        title = report.lastMessageFromAdmin
            ? 'תשובה מצוות שדכן'
            : 'הפנייה שלך — שיחה פתוחה';
      }
      out.add(
        AppNotification(
          id: 'support:${report.id}',
          source: NotificationSource.support,
          time: report.lastMessageAt ?? report.createdAt,
          read: !thread.unread,
          groupKey: 'support:${report.id}',
          title: title,
          subtitle: report.text.trim().isEmpty ? null : report.text.trim(),
          report: report,
        ),
      );
    }

    for (final ReminderLogEntry entry in reminders) {
      if (entry.removed) {
        continue;
      }
      final AppNotification? line = _reminderLine(
        entry,
        personById: personById,
        matchById: matchById,
        now: clock,
      );
      if (line != null) {
        out.add(line);
      }
    }

    out.sort(
      (AppNotification a, AppNotification b) => b.time.compareTo(a.time),
    );
    return out;
  }

  static AppNotification? _reminderLine(
    ReminderLogEntry entry, {
    required Person? Function(String id) personById,
    required MatchIdea? Function(String id) matchById,
    required DateTime now,
  }) {
    // A reminder that came due today before its hour is shown at "now", not
    // in the future.
    final DateTime time = entry.dueAt.isAfter(now) ? now : entry.dueAt;
    final String note = entry.note.trim();
    if (entry.kind == HomeItemKind.person) {
      final Person? person = personById(entry.targetId);
      if (person == null) {
        return null;
      }
      final String name = _name(person);
      return AppNotification(
        id: 'reminder:${entry.key}',
        source: NotificationSource.reminder,
        time: time,
        read: entry.read,
        groupKey: 'person:${person.id}',
        title: note.isNotEmpty ? note : 'לבדוק שוב עם $name',
        subtitle: note.isNotEmpty ? 'תזכורת · $name' : 'תזכורת',
        person: person,
        reminder: entry,
      );
    }
    final MatchIdea? match = matchById(entry.targetId);
    if (match == null) {
      return null;
    }
    final (Person?, Person?) couple = boyFirst(
      personById(match.personAId),
      personById(match.personBId),
    );
    final (Person? male, Person? female) = couple;
    final String pair = pairName(male, female);
    return AppNotification(
      id: 'reminder:${entry.key}',
      source: NotificationSource.reminder,
      time: time,
      read: entry.read,
      groupKey: 'idea:${match.id}',
      title: ideaReminderText(note, pair).$1,
      subtitle: ideaReminderText(note, pair).$2,
      couple: couple,
      reminder: entry,
    );
  }

  /// Merges lines about the same subject that arrived within [groupWindow]
  /// of each other into one row. [lines] newest first, as [build] returns.
  static List<NotificationGroup> group(List<AppNotification> lines) {
    final List<NotificationGroup> groups = <NotificationGroup>[];
    final Map<String, NotificationGroup> open = <String, NotificationGroup>{};
    for (final AppNotification line in lines) {
      final NotificationGroup? current = open[line.groupKey];
      if (current != null &&
          current.items.last.time.difference(line.time) <= groupWindow) {
        current.items.add(line);
        continue;
      }
      final NotificationGroup fresh = NotificationGroup(<AppNotification>[
        line,
      ]);
      groups.add(fresh);
      open[line.groupKey] = fresh;
    }
    return groups;
  }

  /// What the bell counts: rows not yet read, the same rows the page draws.
  static int unreadRows(List<NotificationGroup> groups) =>
      groups.where((NotificationGroup g) => !g.read).length;

  /// The couple with the boy first, as every row in the app draws them.
  static (Person?, Person?) boyFirst(Person? a, Person? b) {
    final bool swap = a?.gender == Gender.female || b?.gender == Gender.male;
    return swap ? (b, a) : (a, b);
  }

  /// "דוד ושרה" — first names, in the order given.
  static String pairName(Person? first, Person? second) =>
      '${_first(first)} ו${_first(second)}';

  /// An idea reminder's two lines: what the matchmaker wrote, or a short line
  /// naming the couple. Shared with the tray, so both say the same thing.
  static (String, String) ideaReminderText(String note, String pair) {
    final String text = note.trim();
    return text.isNotEmpty
        ? (text, 'תזכורת · $pair')
        : ('לבדוק מה קורה עם $pair', 'תזכורת לרעיון');
  }

  static String _name(Person person) {
    final String full = person.fullName.trim();
    return full.isNotEmpty ? full : person.firstName.trim();
  }

  static String _first(Person? person) {
    if (person == null) {
      return '—';
    }
    final String first = person.firstName.trim();
    return first.isNotEmpty ? first : person.fullName.trim();
  }
}
