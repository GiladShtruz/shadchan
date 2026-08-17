import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:shadchan/models/match_idea.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;
  static Future<void> _scheduleQueue = Future<void>.value();

  // One counter per reminder kind: a queued match refresh must not be dropped
  // because a person reminder was saved after it (and the other way round).
  static int _latestMatchRequestId = 0;
  static int _latestPersonRequestId = 0;

  static const AndroidNotificationDetails _androidMatchDetails =
      AndroidNotificationDetails(
        'match_reminders',
        'תזכורות להצעות',
        channelDescription: 'התראות על הצעות שידוך',
        importance: Importance.high,
        priority: Priority.high,
      );

  static const DarwinNotificationDetails _iosMatchDetails =
      DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

  static const NotificationDetails _matchNotificationDetails =
      NotificationDetails(android: _androidMatchDetails, iOS: _iosMatchDetails);

  static const AndroidNotificationDetails _androidPersonDetails =
      AndroidNotificationDetails(
        'person_reminders',
        'תזכורות לחברים',
        channelDescription: 'התראות לבדוק שוב עם חברים במאגר',
        importance: Importance.high,
        priority: Priority.high,
      );

  static const NotificationDetails _personNotificationDetails =
      NotificationDetails(
        android: _androidPersonDetails,
        iOS: _iosMatchDetails,
      );

  /// Reminders are picked as a plain date, which would otherwise fire at
  /// midnight. They go out at this hour of the reminder day instead.
  static const int _reminderHour = 9;

  static Future<void> initialize() async {
    tz_data.initializeTimeZones();

    try {
      final TimezoneInfo localTimezone =
          await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      _isInitialized = true;
    } catch (error, stackTrace) {
      _isInitialized = false;
      debugPrint('NotificationService.initialize failed: $error\n$stackTrace');
    }
  }

  /// Birth dates were removed from the app, so no birthday notifications are
  /// scheduled any more. This clears the ones older versions already put on the
  /// device (ids 10000-19999) so users stop receiving them.
  static Future<void> cancelBirthdayNotifications() async {
    if (!_isInitialized) {
      return;
    }

    _scheduleQueue = _scheduleQueue
        .then((_) async {
          final List<PendingNotificationRequest> pending = await _plugin
              .pendingNotificationRequests();
          for (final PendingNotificationRequest request in pending) {
            if (request.id >= 10000 && request.id < 20000) {
              await _plugin.cancel(request.id);
            }
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint(
            'NotificationService.cancelBirthdayNotifications failed: '
            '$error\n$stackTrace',
          );
        });

    await _scheduleQueue;
  }

  static Future<void> scheduleMatchReminders(List<MatchIdea> matches) async {
    if (!_isInitialized) {
      return;
    }

    final int requestId = ++_latestMatchRequestId;
    final List<MatchIdea> matchesSnapshot = List<MatchIdea>.from(matches);

    _scheduleQueue = _scheduleQueue
        .then((_) async {
          if (requestId != _latestMatchRequestId) {
            return;
          }

          await _scheduleMatchRemindersInternal(
            matchesSnapshot,
            requestId: requestId,
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint(
            'NotificationService.scheduleMatchReminders failed: '
            '$error\n$stackTrace',
          );
        });

    await _scheduleQueue;
  }

  /// Schedules the per-person "check on them again" reminders — the ones set
  /// when someone goes busy or on a break. Same contract as
  /// [scheduleMatchReminders]: the full list is passed in every time and
  /// replaces whatever was pending, so clearing a reminder cancels its
  /// notification.
  static Future<void> schedulePersonReminders(
    List<PersonReminderNotification> reminders,
  ) async {
    if (!_isInitialized) {
      return;
    }

    final int requestId = ++_latestPersonRequestId;
    final List<PersonReminderNotification> snapshot =
        List<PersonReminderNotification>.from(reminders);

    _scheduleQueue = _scheduleQueue
        .then((_) async {
          if (requestId != _latestPersonRequestId) {
            return;
          }

          await _schedulePersonRemindersInternal(
            snapshot,
            requestId: requestId,
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint(
            'NotificationService.schedulePersonReminders failed: '
            '$error\n$stackTrace',
          );
        });

    await _scheduleQueue;
  }

  /// The one notification the app sends that the matchmaker did not ask for.
  ///
  /// Re-armed for a week ahead on every launch, so it only ever fires for
  /// someone who has genuinely not opened the app in that time. It is an
  /// invitation, not a scoreboard: there is no count of what is "waiting" and
  /// nothing in it implies that anything was neglected. Everything else the app
  /// sends is a reminder the matchmaker set themselves.
  static Future<void> scheduleReturnInvitation() async {
    if (!_isInitialized) {
      return;
    }

    try {
      await _plugin.cancel(_returnInvitationId);
      final tz.TZDateTime when = tz.TZDateTime.from(
        DateTime.now().add(const Duration(days: 7)),
        tz.local,
      );
      await _plugin.zonedSchedule(
        _returnInvitationId,
        'החברים שלך כאן',
        'אולי דווקא עכשיו יעלה הרעיון הנכון לאחד מהם',
        _atHour(when, _reminderHour),
        _personNotificationDetails,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'NotificationService.scheduleReturnInvitation failed: '
        '$error\n$stackTrace',
      );
    }
  }

  static const int _returnInvitationId = 40001;

  static tz.TZDateTime _atHour(tz.TZDateTime day, int hour) {
    return tz.TZDateTime(tz.local, day.year, day.month, day.day, hour);
  }

  static Future<void> cancelAll() async {
    if (!_isInitialized) {
      return;
    }

    try {
      await _plugin.cancelAll();
    } catch (error, stackTrace) {
      debugPrint('NotificationService.cancelAll failed: $error\n$stackTrace');
    }
  }

  static Future<void> _scheduleMatchRemindersInternal(
    List<MatchIdea> matches, {
    required int requestId,
  }) async {
    try {
      final List<PendingNotificationRequest> pending = await _plugin
          .pendingNotificationRequests();
      for (final PendingNotificationRequest req in pending) {
        if (req.id >= 20000 && req.id < 30000) {
          await _plugin.cancel(req.id);
        }
      }

      int notifId = 20000;

      for (final MatchIdea match in matches) {
        if (requestId != _latestMatchRequestId) {
          return;
        }

        final DateTime? reminderDate = match.reminderDate;
        final tz.TZDateTime? scheduledTime = _notificationTime(reminderDate);
        if (scheduledTime != null) {
          await _plugin.zonedSchedule(
            notifId,
            'תזכורת להצעה',
            match.reminderNote ?? 'יש לך תזכורת להצעת שידוך',
            scheduledTime,
            _matchNotificationDetails,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
          notifId++;
        }

        if (notifId >= 30000) {
          break;
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'NotificationService.scheduleMatchReminders failed: '
        '$error\n$stackTrace',
      );
    }
  }

  static Future<void> _schedulePersonRemindersInternal(
    List<PersonReminderNotification> reminders, {
    required int requestId,
  }) async {
    try {
      final List<PendingNotificationRequest> pending = await _plugin
          .pendingNotificationRequests();
      for (final PendingNotificationRequest req in pending) {
        if (req.id >= 30000 && req.id < 40000) {
          await _plugin.cancel(req.id);
        }
      }

      int notifId = 30000;

      for (final PersonReminderNotification reminder in reminders) {
        if (requestId != _latestPersonRequestId) {
          return;
        }

        final tz.TZDateTime? scheduledTime = _notificationTime(reminder.date);
        if (scheduledTime != null) {
          await _plugin.zonedSchedule(
            notifId,
            'תזכורת לבדוק שוב',
            'הגיע הזמן לבדוק שוב עם ${reminder.name}',
            scheduledTime,
            _personNotificationDetails,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
          notifId++;
        }

        if (notifId >= 40000) {
          break;
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'NotificationService.schedulePersonReminders failed: '
        '$error\n$stackTrace',
      );
    }
  }

  /// When to actually fire a reminder that was picked as a bare date: at
  /// [_reminderHour] on that day rather than at midnight. Returns null when the
  /// moment has already passed, or when there is no reminder at all.
  static tz.TZDateTime? _notificationTime(DateTime? date) {
    if (date == null) {
      return null;
    }

    final DateTime target = date.hour == 0 && date.minute == 0
        ? DateTime(date.year, date.month, date.day, _reminderHour)
        : date;
    final tz.TZDateTime scheduled = tz.TZDateTime.from(target, tz.local);
    return scheduled.isAfter(tz.TZDateTime.now(tz.local)) ? scheduled : null;
  }
}

/// One per-person reminder ready to be scheduled: who it is about and when.
class PersonReminderNotification {
  const PersonReminderNotification({required this.name, required this.date});

  final String name;
  final DateTime date;
}
