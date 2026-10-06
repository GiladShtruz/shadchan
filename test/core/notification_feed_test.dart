import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/notification_feed.dart';
import 'package:shadchan/services/reminder_log.dart';
import 'package:shadchan/utils/enums.dart';

void main() {
  final DateTime now = DateTime(2026, 10, 5, 15);

  Person person(String id, String first, Gender gender) => Person(
    id: id,
    firstName: first,
    lastName: 'כהן',
    gender: gender,
    createdAt: now,
    updatedAt: now,
  );

  final Person david = person('m', 'דוד', Gender.male);
  final Person sara = person('f', 'שרה', Gender.female);
  final MatchIdea idea = MatchIdea(
    id: 'idea',
    personAId: 'f',
    personBId: 'm',
    status: MatchStatus.idea,
    currentHandler: CurrentHandler.me,
    createdAt: now,
    updatedAt: now,
  );

  InboxItem notice(
    String id,
    String kind,
    Duration ago, {
    String owner = 'owner-1',
    bool read = false,
  }) => InboxItem(
    id: id,
    kind: kind,
    title: 'יעל ברק $kind',
    body: '',
    route: '/reminders',
    read: read,
    ownerUid: owner,
    createdAt: now.subtract(ago),
  );

  List<AppNotification> build({
    List<InboxItem> inbox = const <InboxItem>[],
    List<ReminderLogEntry> reminders = const <ReminderLogEntry>[],
  }) => NotificationFeed.build(
    inbox: inbox,
    support: const [],
    reminders: reminders,
    supportAdmin: false,
    personById: (String id) => <String, Person>{'m': david, 'f': sara}[id],
    matchById: (String id) => id == idea.id ? idea : null,
    personOfNotice: (_) => null,
    now: now,
  );

  group('NotificationFeed', () {
    test('one list, newest first, across sources', () {
      final List<AppNotification> lines = build(
        inbox: <InboxItem>[notice('a', 'cardCreated', const Duration(days: 2))],
        reminders: <ReminderLogEntry>[
          ReminderLogEntry(
            kind: HomeItemKind.idea,
            targetId: 'idea',
            dueAt: now.subtract(const Duration(hours: 3)),
            note: '',
          ),
        ],
      );
      expect(
        lines.map((AppNotification n) => n.source).toList(),
        <NotificationSource>[
          NotificationSource.reminder,
          NotificationSource.inbox,
        ],
      );
      // No text written on the reminder: a short line of its own, boy first.
      expect(lines.first.title, 'לבדוק מה קורה עם דוד ושרה');
    });

    test('a reminder\'s own text is the main line', () {
      final List<AppNotification> lines = build(
        reminders: <ReminderLogEntry>[
          ReminderLogEntry(
            kind: HomeItemKind.person,
            targetId: 'f',
            dueAt: now.subtract(const Duration(hours: 1)),
            note: 'לשאול אם חזרה מחו״ל',
          ),
        ],
      );
      expect(lines.single.title, 'לשאול אם חזרה מחו״ל');
      expect(lines.single.subtitle, 'תזכורת · שרה כהן');
    });

    test('several notices about one person close together are one row', () {
      final List<NotificationGroup> groups = NotificationFeed.group(
        build(
          inbox: <InboxItem>[
            notice('a', 'cardCreated', const Duration(hours: 2)),
            notice('b', 'accessApproved', const Duration(hours: 1)),
            notice('c', 'cardCreated', const Duration(days: 3)),
            notice('d', 'birthday', const Duration(hours: 1), owner: 'other'),
          ],
        ),
      );
      expect(groups, hasLength(3));
      expect(groups.first.count, 2);
      expect(groups.first.latest.inbox!.id, 'b');
      expect(NotificationFeed.unreadRows(groups), 3);
    });

    test('a reminder due later today shows as now, not in the future', () {
      final List<AppNotification> lines = build(
        reminders: <ReminderLogEntry>[
          ReminderLogEntry(
            kind: HomeItemKind.person,
            targetId: 'm',
            dueAt: now.add(const Duration(hours: 2)),
            note: '',
          ),
        ],
      );
      expect(lines.single.time, now);
    });

    test('the default monthly note is not "what the matchmaker wrote"', () {
      final MatchIdea withDefault =
          MatchIdea(
              id: 'x',
              personAId: 'm',
              personBId: 'f',
              status: MatchStatus.idea,
              currentHandler: CurrentHandler.me,
              createdAt: now,
              updatedAt: now,
            )
            ..reminderDate = DateTime(2026, 10, 5)
            ..reminderNote = MatchRepository.defaultReminderNote;
      final List<DueReminder> due = NotificationFeed.dueReminders(
        matches: <MatchIdea>[withDefault],
        personReminders: <String, DateTime>{'m': DateTime(2026, 10, 6)},
        personNote: (_) => null,
        personExists: (_) => true,
        now: now,
      );
      expect(due, hasLength(1));
      expect(due.single.note, isNull);
    });
  });

  group('ReminderLog', () {
    late Directory directory;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('reminder_log_');
      Hive.init(directory.path);
      await Hive.openBox<dynamic>('settings');
    });

    tearDownAll(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    setUp(() => ReminderLog.instance.resetForTest());

    test('logs once, keeps it after the reminder moves, and forgets nothing '
        'by age', () {
      final ReminderLog log = ReminderLog.instance..reset();
      final DueReminder first = DueReminder(
        kind: HomeItemKind.person,
        targetId: 'm',
        date: DateTime(2026, 9, 1),
      );
      log
        ..sync(<DueReminder>[first])
        ..sync(<DueReminder>[first]);
      expect(log.visible, hasLength(1));
      expect(log.visible.single.dueAt, DateTime(2026, 9, 1, 9));

      // Set again for another day: a second notification, the first stays.
      log.sync(<DueReminder>[
        DueReminder(
          kind: HomeItemKind.person,
          targetId: 'm',
          date: DateTime(2026, 10, 5),
        ),
      ]);
      expect(log.visible, hasLength(2));
    });

    test('read and removed are remembered; removed is never re-logged', () {
      final ReminderLog log = ReminderLog.instance..reset();
      final DueReminder due = DueReminder(
        kind: HomeItemKind.idea,
        targetId: 'idea',
        date: DateTime(2026, 10, 1),
      );
      log.sync(<DueReminder>[due]);
      final String key = log.visible.single.key;
      log.markAllRead();
      expect(
        log.isRead(HomeItemKind.idea, 'idea', DateTime(2026, 10, 1)),
        isTrue,
      );
      log.remove(<String>[key]);
      log.sync(<DueReminder>[due]);
      expect(log.visible, isEmpty);
      log.restore(<String>[key]);
      expect(log.visible, hasLength(1));
    });
  });
}
