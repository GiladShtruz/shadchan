import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/support_chat_sheet.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/support_inbox_provider.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/notification_feed.dart';
import 'package:shadchan/services/reminder_log.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/app_navigation.dart';
import 'package:shadchan/utils/person_reminders.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';

T? _maybe<T>(BuildContext context, {required bool listen}) {
  try {
    return Provider.of<T>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

/// The one place the notifications are put together — for the page, the bell,
/// the app icon's badge and "הלוח שלי" alike, so they can never disagree
/// about what is unread.
abstract final class NotificationCenter {
  static const String _hiddenSupportKey = 'notifications.hiddenSupport';
  static Map<String, int>? _hiddenSupportCache;

  /// Support conversations taken off the page, with the moment of the last
  /// message they had then.
  static Map<String, int> get _hiddenSupport {
    final Map<String, int>? cached = _hiddenSupportCache;
    if (cached != null) {
      return cached;
    }
    final Map<String, int> map = <String, int>{};
    final Object? raw = Hive.isBoxOpen('settings')
        ? Hive.box<dynamic>('settings').get(_hiddenSupportKey)
        : null;
    if (raw is String && raw.isNotEmpty) {
      for (final String pair in raw.split('|')) {
        final int at = pair.lastIndexOf('=');
        final int? millis = at < 0
            ? null
            : int.tryParse(pair.substring(at + 1));
        if (millis != null) {
          map[pair.substring(0, at)] = millis;
        }
      }
    }
    return _hiddenSupportCache = map;
  }

  /// Forgets the support threads taken off the page, for a sign-out.
  static void reset() {
    _hiddenSupportCache = <String, int>{};
    persistHomeSetting(_hiddenSupportKey, '');
  }

  /// The friend a server notice is about, when they are in the database.
  static Person? personOfNotice(PersonRepository people, InboxItem item) {
    final String? owner = item.ownerUid;
    final String? hash = item.ownerPhoneHash;
    return (owner == null ? null : people.findByCardOwner(owner)) ??
        (hash == null || hash.isEmpty ? null : people.findByPhoneHash(hash));
  }

  /// Every row, newest first. [listen] makes the caller rebuild when any
  /// source moves (reminders, notices, support, the log itself).
  static List<NotificationGroup> groups(
    BuildContext context, {
    bool listen = true,
  }) {
    final PersonRepository people = Provider.of<PersonRepository>(
      context,
      listen: listen,
    );
    final MatchRepository matches = Provider.of<MatchRepository>(
      context,
      listen: listen,
    );
    final InboxProvider? inbox = _maybe<InboxProvider>(context, listen: listen);
    final SupportInboxProvider? support = _maybe<SupportInboxProvider>(
      context,
      listen: listen,
    );
    final bool admin =
        _maybe<AccountProvider>(context, listen: listen)?.isSupportAdmin ??
        false;

    final ReminderLog log = ReminderLog.instance;
    log.sync(
      NotificationFeed.dueReminders(
        matches: matches.getAll(),
        personReminders: PersonReminders.all(),
        personNote: PersonReminders.noteFor,
        personExists: (String id) => people.getById(id) != null,
      ),
    );

    final Map<String, int> hiddenSupport = _hiddenSupport;
    return NotificationFeed.group(
      NotificationFeed.build(
        inbox: inbox?.items ?? const <InboxItem>[],
        support: <SupportThread>[
          for (final SupportThread t
              in support?.threads ?? const <SupportThread>[])
            if ((hiddenSupport[t.report.id] ?? -1) <
                (t.report.lastMessageAt ?? t.report.createdAt)
                    .millisecondsSinceEpoch)
              t,
        ],
        reminders: log.visible,
        supportAdmin: admin,
        personById: people.getById,
        matchById: matches.getById,
        personOfNotice: (InboxItem item) => personOfNotice(people, item),
      ),
    );
  }

  static int unreadCount(BuildContext context, {bool listen = true}) =>
      NotificationFeed.unreadRows(groups(context, listen: listen));

  /// "סמן הכל כנקרא" — and what opening the page does by itself.
  static Future<void> markAllRead(BuildContext context) async {
    ReminderLog.instance.markAllRead();
    final InboxProvider? inbox = _maybe<InboxProvider>(context, listen: false);
    final SupportInboxProvider? support = _maybe<SupportInboxProvider>(
      context,
      listen: false,
    );
    await Future.wait(<Future<void>>[
      if (inbox != null) inbox.markAllRead(),
      if (support != null && support.unreadCount > 0) support.markAllSeen(),
    ]);
  }

  /// Marks one row read — opening it from "הלוח שלי" is reading it.
  static void markRead(BuildContext context, NotificationGroup group) {
    final InboxProvider? inbox = _maybe<InboxProvider>(context, listen: false);
    ReminderLog.instance.markRead(<String>[
      for (final AppNotification n in group.items)
        if (n.reminder case final ReminderLogEntry e) e.key,
    ]);
    for (final AppNotification n in group.items) {
      if (n.inbox case final InboxItem item when inbox != null) {
        inbox.markRead(item);
      }
    }
  }

  /// Takes a row off the page. Reminders can be put back from the notice;
  /// a server notice is deleted at once, like a message in a chat.
  static void remove(BuildContext context, NotificationGroup group) {
    final InboxProvider? inbox = _maybe<InboxProvider>(context, listen: false);
    final List<String> reminderKeys = <String>[
      for (final AppNotification n in group.items)
        if (n.reminder case final ReminderLogEntry e) e.key,
    ];
    ReminderLog.instance.remove(reminderKeys);
    for (final AppNotification n in group.items) {
      if (n.inbox case final InboxItem item when inbox != null) {
        inbox.remove(item);
      }
    }
    // A support conversation is not deleted from here — it is a thread with
    // a person. Its row leaves the page until somebody writes in it again.
    final List<SupportReport> reports = <SupportReport>[
      for (final AppNotification n in group.items)
        if (n.report case final SupportReport r) r,
    ];
    if (reports.isNotEmpty) {
      final Map<String, int> hidden = _hiddenSupport;
      for (final SupportReport r in reports) {
        hidden[r.id] = (r.lastMessageAt ?? r.createdAt).millisecondsSinceEpoch;
      }
      persistHomeSetting(
        _hiddenSupportKey,
        hidden.entries
            .map((MapEntry<String, int> e) => '${e.key}=${e.value}')
            .join('|'),
      );
      ReminderLog.instance.touch();
    }
    if (reminderKeys.isNotEmpty &&
        group.items.every((AppNotification n) => n.reminder != null)) {
      AppNotice.show(
        context,
        'ההתראה הוסרה',
        actionLabel: 'ביטול',
        onAction: () => ReminderLog.instance.restore(reminderKeys),
      );
    }
  }

  /// Where a row goes: exactly the thing it is about.
  static String? routeFor(BuildContext context, AppNotification line) {
    final ReminderLogEntry? reminder = line.reminder;
    if (reminder != null) {
      return reminder.kind == HomeItemKind.idea
          ? '/matches/${reminder.targetId}'
          : '/people/${reminder.targetId}';
    }
    final InboxItem? item = line.inbox;
    if (item == null) {
      return null;
    }
    final Person? person = line.person;
    switch (item.kind) {
      case 'cardCreated':
        // Straight to where access is asked for.
        return person == null ? null : '/people/${person.id}?focus=request';
      case 'accessApproved':
        // Straight to the card itself, whole and up to date.
        if (person != null) {
          return '/people/${person.id}?focus=card';
        }
        return item.route.startsWith('/') ? item.route : null;
      default:
        if (person != null) {
          return '/people/${person.id}';
        }
        return item.route.startsWith('/') && item.route != '/reminders'
            ? item.route
            : null;
    }
  }

  /// Opens a row and marks it read.
  static Future<void> open(
    BuildContext context,
    NotificationGroup group,
  ) async {
    final AppNotification line = group.latest;
    markRead(context, group);
    final SupportReport? report = line.report;
    if (report != null) {
      final bool admin =
          _maybe<AccountProvider>(context, listen: false)?.isSupportAdmin ??
          false;
      await SupportChatSheet.show(context, report, asAdmin: admin);
      return;
    }
    final InboxItem? item = line.inbox;
    if (item != null && item.kind == 'cardCreated') {
      final String? hash = item.ownerPhoneHash;
      if (hash != null && hash.isNotEmpty) {
        // The directory said "no card" a minute ago; this notice says
        // otherwise.
        _maybe<CardAccessProvider>(context, listen: false)?.forgetLookup(hash);
      }
    }
    final String? route = routeFor(context, line);
    if (route == null) {
      if (item != null && item.kind == 'cardCreated') {
        AppNotice.show(context, 'החבר הזה עוד לא במאגר שלך');
      }
      return;
    }
    AppNavigation.open(context, route);
  }

  /// Opens one server notice from outside the page — "הלוח שלי".
  static Future<void> openNotice(BuildContext context, InboxItem item) {
    final Person? person = personOfNotice(
      context.read<PersonRepository>(),
      item,
    );
    return open(
      context,
      NotificationGroup(<AppNotification>[
        AppNotification(
          id: 'inbox:${item.id}',
          source: NotificationSource.inbox,
          time: item.createdAt ?? DateTime.now(),
          read: item.read,
          groupKey: 'inbox:${item.id}',
          title: item.title,
          person: person,
          inbox: item,
        ),
      ]),
    );
  }

  /// The greeting a mazel-tov or birthday notice offers.
  static Future<void> sendGreeting(BuildContext context, InboxItem item) async {
    final Person? person = personOfNotice(
      context.read<PersonRepository>(),
      item,
    );
    if (person == null) {
      AppNotice.show(context, 'החבר הזה לא נמצא במאגר שלך');
      return;
    }
    final String name = person.firstName.trim();
    final bool opened = await WhatsAppUtils.openChatWithText(
      person.phone,
      item.kind == 'birthday'
          ? 'מזל טוב ליום ההולדת, $name! 🎂'
          : 'מזל טוב, $name!!! 🎉',
    );
    if (!opened && context.mounted) {
      AppNotice.show(context, 'אין מספר וואטסאפ תקין לחבר הזה');
    }
  }

  /// The match a reminder row is about, for its faces.
  static MatchIdea? matchOf(BuildContext context, AppNotification line) {
    final ReminderLogEntry? entry = line.reminder;
    if (entry == null || entry.kind != HomeItemKind.idea) {
      return null;
    }
    return context.read<MatchRepository>().getById(entry.targetId);
  }
}
