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
  static int _latestScheduleRequestId = 0;

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

    final int requestId = ++_latestScheduleRequestId;
    final List<MatchIdea> matchesSnapshot = List<MatchIdea>.from(matches);

    _scheduleQueue = _scheduleQueue
        .then((_) async {
          if (requestId != _latestScheduleRequestId) {
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
        if (requestId != _latestScheduleRequestId) {
          return;
        }

        final DateTime? reminderDate = match.reminderDate;
        if (reminderDate != null && reminderDate.isAfter(DateTime.now())) {
          final tz.TZDateTime scheduledTime = tz.TZDateTime.from(
            reminderDate,
            tz.local,
          );

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
}
