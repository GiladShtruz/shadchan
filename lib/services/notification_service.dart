import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shadchan/utils/hebrew_date_utils.dart';
import 'package:shadchan/models/person.dart' as model;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;
  static Future<void> _scheduleQueue = Future<void>.value();
  static int _latestScheduleRequestId = 0;

  static const AndroidNotificationDetails _androidBirthdayDetails =
      AndroidNotificationDetails(
        'birthday_reminders',
        'תזכורות ימי הולדת',
        channelDescription: 'התראות על ימי הולדת קרובים של אנשי קשר',
        importance: Importance.high,
        priority: Priority.high,
      );

  static const DarwinNotificationDetails _iosBirthdayDetails =
      DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

  static const NotificationDetails _birthdayNotificationDetails =
      NotificationDetails(
        android: _androidBirthdayDetails,
        iOS: _iosBirthdayDetails,
      );

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

  static Future<void> scheduleBirthdayNotifications(
    List<model.Person> people,
  ) async {
    if (!_isInitialized) {
      return;
    }

    final int requestId = ++_latestScheduleRequestId;
    final List<model.Person> peopleSnapshot = List<model.Person>.from(people);

    _scheduleQueue = _scheduleQueue
        .then((_) async {
          if (requestId != _latestScheduleRequestId) {
            return;
          }

          await _scheduleBirthdayNotificationsInternal(
            peopleSnapshot,
            requestId: requestId,
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint(
            'NotificationService.scheduleBirthdayNotifications failed: '
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

  static Future<void> _scheduleBirthdayNotificationsInternal(
    List<model.Person> people, {
    required int requestId,
  }) async {
    try {
      await _plugin.cancelAll();

      int notifId = 10000;

      for (final model.Person person in people) {
        if (requestId != _latestScheduleRequestId) {
          return;
        }

        final DateTime? birthDate = person.birthDate;
        if (birthDate != null) {
          final tz.TZDateTime birthdayMorning = _nextBirthdayOccurrence(
            birthDate: birthDate,
            hour: 9,
          );
          final tz.TZDateTime birthdayEve = _nextBirthdayOccurrence(
            birthDate: birthDate,
            hour: 20,
            daysOffset: -1,
          );

          await _plugin.zonedSchedule(
            notifId,
            'יום הולדת היום',
            '🎂 היום יום ההולדת של ${person.fullName.trim()}!',
            birthdayMorning,
            _birthdayNotificationDetails,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dateAndTime,
          );

          await _plugin.zonedSchedule(
            notifId + 1,
            'תזכורת ליום הולדת',
            '🎂 מחר יום ההולדת של ${person.fullName.trim()}',
            birthdayEve,
            _birthdayNotificationDetails,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dateAndTime,
          );

          notifId += 2;
        }

        final ({int year, int month, int day})? convertedHebrew =
            birthDate == null ? null : HebrewDateUtils.fromGregorian(birthDate);
        final int? hebrewMonth =
            person.hebrewBirthMonth ?? convertedHebrew?.month;
        final int? hebrewDay = person.hebrewBirthDay ?? convertedHebrew?.day;
        if (hebrewMonth != null && hebrewDay != null) {
          final List<DateTime> hebrewOccurrences =
              HebrewDateUtils.upcomingGregorianOccurrences(
                month: hebrewMonth,
                day: hebrewDay,
                count: 3,
              );
          for (final DateTime nextHebrew in hebrewOccurrences) {
            final tz.TZDateTime hebrewMorning = tz.TZDateTime(
              tz.local,
              nextHebrew.year,
              nextHebrew.month,
              nextHebrew.day,
              9,
            );
            final tz.TZDateTime hebrewEve = tz.TZDateTime(
              tz.local,
              nextHebrew.year,
              nextHebrew.month,
              nextHebrew.day,
              20,
            ).subtract(const Duration(days: 1));
            final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
            if (hebrewEve.isAfter(now)) {
              await _plugin.zonedSchedule(
                notifId,
                'תזכורת ליום הולדת עברי',
                '🎂 מחר יום ההולדת העברי של ${person.fullName.trim()}',
                hebrewEve,
                _birthdayNotificationDetails,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
                androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              );
              notifId += 1;
            }
            if (hebrewMorning.isAfter(tz.TZDateTime.now(tz.local))) {
              await _plugin.zonedSchedule(
                notifId,
                'יום הולדת עברי היום',
                '🎂 היום יום ההולדת העברי של ${person.fullName.trim()}!',
                hebrewMorning,
                _birthdayNotificationDetails,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
                androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              );
              notifId += 1;
            }

            if (notifId >= 20000) {
              break;
            }
          }
        }

        if (notifId >= 20000) {
          break;
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'NotificationService.scheduleBirthdayNotifications failed: '
        '$error\n$stackTrace',
      );
    }
  }

  static tz.TZDateTime _nextBirthdayOccurrence({
    required DateTime birthDate,
    required int hour,
    int minute = 0,
    int daysOffset = 0,
  }) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = _birthdayForYear(
      birthDate: birthDate,
      year: now.year,
      hour: hour,
      minute: minute,
      daysOffset: daysOffset,
    );

    if (!scheduledDate.isAfter(now)) {
      scheduledDate = _birthdayForYear(
        birthDate: birthDate,
        year: now.year + 1,
        hour: hour,
        minute: minute,
        daysOffset: daysOffset,
      );
    }

    return scheduledDate;
  }

  static tz.TZDateTime _birthdayForYear({
    required DateTime birthDate,
    required int year,
    required int hour,
    required int minute,
    required int daysOffset,
  }) {
    final int safeDay = _safeDay(year, birthDate.month, birthDate.day);
    final tz.TZDateTime birthday = tz.TZDateTime(
      tz.local,
      year,
      birthDate.month,
      safeDay,
      hour,
      minute,
    );

    return birthday.add(Duration(days: daysOffset));
  }

  static int _safeDay(int year, int month, int day) {
    final DateTime lastDayOfMonth = month == 12
        ? DateTime(year + 1, 1, 0)
        : DateTime(year, month + 1, 0);
    return day > lastDayOfMonth.day ? lastDayOfMonth.day : day;
  }
}
