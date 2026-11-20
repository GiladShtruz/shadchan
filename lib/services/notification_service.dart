import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:shadchan/utils/reminder_schedule_plan.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/services/notification_preferences.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;
  static Future<void> _scheduleQueue = Future<void>.value();

  // One counter per reminder kind: a queued match refresh must not be dropped
  // because a person reminder was saved after it (and the other way round).
  static int _latestMatchRequestId = 0;
  static int _latestPersonRequestId = 0;

  /// **What is on the device now, per notification id** — the line each
  /// reminder was last scheduled with. A refresh plans the whole list in Dart
  /// first and then talks to the plugin only about the ids whose line
  /// changed.
  ///
  /// This is the stutter fix of 2026-11-20. Every change to the database —
  /// and every batch the account sync brings down from the server — used to
  /// cancel *every* pending reminder and schedule every one again: up to 55
  /// round trips to the platform per change, and on Android each one makes
  /// the plugin re-serialise its whole saved list on the main thread, the
  /// same thread that delivers touches. Scrolling stuttered while the phone
  /// was busy rewriting reminders nobody had changed. Null until the first
  /// refresh of the launch, which still starts from a clean slate.
  static bool _birthdaysCleared = false;
  static Map<int, String>? _matchScheduled;
  static Map<int, String>? _personScheduled;

  /// A burst of changes (a sync batch, an import) is one refresh, a moment
  /// after the last of them.
  static const Duration _coalesce = Duration(milliseconds: 1500);
  static Timer? _matchTimer;
  static Timer? _personTimer;
  static List<Completer<void>> _matchWaiting = <Completer<void>>[];
  static List<Completer<void>> _personWaiting = <Completer<void>>[];

  /// The tint Android puts on `ic_notification` (a white-on-transparent mark:
  /// Android draws a notification icon from its alpha alone, which is why the
  /// full-bleed launcher icon used to show as a plain square). The same
  /// blue as `notification_color` in `res/values/colors.xml`, which covers the
  /// pushes the system draws itself.
  static const Color _notificationColor = Color(0xFF5F91A3);

  static const AndroidNotificationDetails _androidMatchDetails =
      AndroidNotificationDetails(
        'match_reminders',
        'תזכורות לרעיונות',
        channelDescription: 'התראות על רעיונות שידוך',
        importance: Importance.high,
        priority: Priority.high,
        color: _notificationColor,
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
        color: _notificationColor,
      );

  static const NotificationDetails _personNotificationDetails =
      NotificationDetails(
        android: _androidPersonDetails,
        iOS: _iosMatchDetails,
      );

  static const AndroidNotificationDetails _androidMazelTovDetails =
      AndroidNotificationDetails(
        'mazel_tov',
        'הודעות מזל טוב',
        channelDescription: 'ברכות משדכנים אחרים על חתונה',
        importance: Importance.high,
        priority: Priority.high,
        color: _notificationColor,
      );

  static const NotificationDetails _mazelTovNotificationDetails =
      NotificationDetails(
        android: _androidMazelTovDetails,
        iOS: _iosMatchDetails,
      );

  static const AndroidNotificationDetails _androidSupportDetails =
      AndroidNotificationDetails(
        'support_inbox',
        'פניות ותשובות',
        channelDescription: 'תקלות ורעיונות שנשלחו, ותשובות עליהם',
        importance: Importance.high,
        priority: Priority.high,
        color: _notificationColor,
      );

  static const NotificationDetails _supportNotificationDetails =
      NotificationDetails(
        android: _androidSupportDetails,
        iOS: _iosMatchDetails,
      );

  /// The personal card's news: an access request or answer, a friend's card,
  /// a wedding, a birthday. Created up front (see [initialize]) because a
  /// push that arrives while the app is closed is drawn by the system into
  /// whatever channel the server names, and a channel that does not exist yet
  /// silently becomes "Miscellaneous".
  static const String personalCardChannelId = 'personal_card';

  static const AndroidNotificationDetails _androidPersonalCardDetails =
      AndroidNotificationDetails(
        personalCardChannelId,
        'הכרטיס האישי',
        channelDescription: 'בקשות גישה, אישורים ועדכונים מחברים',
        importance: Importance.high,
        priority: Priority.high,
        color: _notificationColor,
      );

  static const NotificationDetails _personalCardNotificationDetails =
      NotificationDetails(
        android: _androidPersonalCardDetails,
        iOS: _iosMatchDetails,
      );

  static const String _routePayloadPrefix = 'route:';

  /// Ceilings on scheduled reminder notifications. iOS keeps only the 64
  /// soonest pending notifications per app and drops the rest without a word;
  /// these two plus the few others the app schedules stay under it, and the
  /// plan keeps the *nearest* reminders when it has to choose.
  static const int _maxMatchNotifications = 40;
  static const int _maxPersonNotifications = 15;

  /// What a tapped notification does: open [route]. [launch] is true when the
  /// tap is what started the app — Back from there should lead home, not out.
  static void Function(String route, bool launch)? onOpenRoute;

  /// A push that arrived while the app is open: shown inside the app rather
  /// than as a system notification. Set by the app, like [onOpenRoute].
  static void Function(String title, String body, String? route)?
  onForegroundNotice;

  /// Draws a push that arrived while the app was open — the system only draws
  /// them itself while it is in the background.
  static Future<void> showRemote({
    required int id,
    required String title,
    required String body,
    String? route,
  }) async {
    if (!_isInitialized ||
        title.trim().isEmpty ||
        !NotificationPreferences.instance.wants(NotificationCategory.support)) {
      return;
    }
    try {
      await _plugin.show(
        id,
        title,
        body,
        _personalCardNotificationDetails,
        payload: route == null ? null : '$_routePayloadPrefix$route',
      );
    } catch (error) {
      debugPrint('NotificationService.showRemote failed: $error');
    }
  }

  /// Hands a route from a tapped notification to the app.
  static void openRoute(String route, {bool launch = false}) {
    if (route.startsWith('/')) {
      onOpenRoute?.call(route, launch);
    }
  }

  /// Reminders are picked as a plain date, which would otherwise fire at
  /// midnight. They go out at this hour of the reminder day instead.
  static const int _reminderHour = 9;

  /// Brings the plugin up. **Asks for nothing.**
  ///
  /// This used to be awaited from `main`, before `runApp`, with
  /// `requestAlertPermission: true` — which on iOS means the system permission
  /// alert is raised and `initialize` does not return until the person answers
  /// it. Before the first frame there is nothing on screen but the launch
  /// image, so what that produced was a splash screen sitting there while iOS
  /// counted; past about twenty seconds the watchdog kills the process, and the
  /// report it leaves behind is an "app hang", not a crash with a stack.
  ///
  /// So: no prompt in here, and the whole call moved off the launch path (see
  /// `main`). Asking is [requestPermissions], which runs with the app already
  /// drawn — which is also where an iOS permission alert is supposed to appear.
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
        AndroidInitializationSettings('@drawable/ic_notification');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) =>
            _handleTap(response.payload),
      );
      _isInitialized = true;
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              personalCardChannelId,
              'הכרטיס האישי',
              description: 'בקשות גישה, אישורים ועדכונים מחברים',
              importance: Importance.high,
            ),
          );
      // A tap that *launched* the app is not delivered to the callback above —
      // the plugin was not listening yet when it happened. It is waiting here
      // instead, and without this the one notification in the app that has
      // somewhere to go would do nothing on a cold start, which is the most
      // likely way it is ever tapped.
      await _handleLaunchTap();
    } catch (error, stackTrace) {
      _isInitialized = false;
      debugPrint('NotificationService.initialize failed: $error\n$stackTrace');
    }
  }

  /// Asks for permission to post notifications, on whichever platform this is.
  ///
  /// Called once the app is on screen, never during startup: on iOS this raises
  /// the system alert and waits for an answer, and a launch that waits for a
  /// person is a launch the watchdog ends. Never throws — a matchmaker who says
  /// no to notifications still gets the whole app, and the reminders simply
  /// live on the home board instead of in the tray.
  static Future<void> requestPermissions() async {
    if (!_isInitialized) {
      return;
    }
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (error, stackTrace) {
      debugPrint('NotificationService.requestPermissions: $error');
      debugPrint('$stackTrace');
    }
  }

  /// Birth dates were removed from the app, so no birthday notifications are
  /// scheduled any more. This clears the ones older versions already put on the
  /// device (ids 10000-19999) so users stop receiving them.
  static Future<void> cancelBirthdayNotifications() async {
    // Once a launch is enough: nothing schedules them any more, and listing
    // every pending notification on each edit was a platform round trip per
    // keystroke-save.
    if (!_isInitialized || _birthdaysCleared) {
      return;
    }
    _birthdaysCleared = true;

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

  /// [describe] gives a reminder its words — the line the matchmaker wrote,
  /// or a short one naming the couple — exactly as the notifications page
  /// draws the same reminder.
  static Future<void> scheduleMatchReminders(
    List<MatchIdea> matches, {
    MatchReminderText Function(MatchIdea match)? describe,
  }) async {
    if (!_isInitialized) {
      return;
    }

    final List<MatchIdea> matchesSnapshot = List<MatchIdea>.from(matches);
    final Completer<void> done = Completer<void>();
    _matchWaiting.add(done);
    _matchTimer?.cancel();
    _matchTimer = Timer(_coalesce, () {
      final List<Completer<void>> waiting = _matchWaiting;
      _matchWaiting = <Completer<void>>[];
      final int requestId = ++_latestMatchRequestId;
      _scheduleQueue = _scheduleQueue
          .then((_) async {
            if (requestId != _latestMatchRequestId) {
              return;
            }
            await _scheduleMatchRemindersInternal(
              matchesSnapshot,
              describe: describe,
              requestId: requestId,
            );
          })
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint(
              'NotificationService.scheduleMatchReminders failed: '
              '$error\n$stackTrace',
            );
          });
      unawaited(
        _scheduleQueue.whenComplete(() {
          for (final Completer<void> c in waiting) {
            if (!c.isCompleted) c.complete();
          }
        }),
      );
    });
    await done.future;
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

    final List<PersonReminderNotification> snapshot =
        List<PersonReminderNotification>.from(reminders);
    final Completer<void> done = Completer<void>();
    _personWaiting.add(done);
    _personTimer?.cancel();
    _personTimer = Timer(_coalesce, () {
      final List<Completer<void>> waiting = _personWaiting;
      _personWaiting = <Completer<void>>[];
      final int requestId = ++_latestPersonRequestId;
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
      unawaited(
        _scheduleQueue.whenComplete(() {
          for (final Completer<void> c in waiting) {
            if (!c.isCompleted) c.complete();
          }
        }),
      );
    });
    await done.future;
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
      if (!NotificationPreferences.instance.wants(
        NotificationCategory.system,
      )) {
        return;
      }
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

  // --- "יש לך הודעות מזל טוב!" ----------------------------------------------

  /// Where a tapped notification should take the reader, as a payload string.
  ///
  /// A prefix and an id rather than a route, so the routing decision stays in
  /// one place ([_handleTap]) and a payload written by an older version of the
  /// app can be recognised or ignored by a newer one.
  static const String _matchPayloadPrefix = 'match:';

  /// Ids 50000-59999 belong to this. Kept out of the reminder ranges, which are
  /// cancelled wholesale on every reschedule — a congratulation is not a
  /// reminder and must not be swept away with them.
  static const int _mazelTovIdBase = 50000;

  /// "יש לך הודעות מזל טוב!" — one per wedding, however many arrived.
  ///
  /// Shown immediately rather than scheduled: the messages are already in the
  /// journal by the time this is called, so the notification is a pointer at
  /// something that has happened, not a plan to say something later. The caller
  /// ([MazelTovInbox]) owns the "once per proposal" rule.
  static Future<void> showMazelTov(String matchId) async {
    if (!_isInitialized ||
        matchId.isEmpty ||
        !NotificationPreferences.instance.wants(
          NotificationCategory.celebrations,
        )) {
      return;
    }
    try {
      await _plugin.show(
        _mazelTovIdBase + (matchId.hashCode.abs() % 10000),
        'יש לך הודעות מזל טוב!',
        'שדכנים מהקהילה שלחו לך ברכה על הזוג שהתחתן',
        _mazelTovNotificationDetails,
        payload: '$_matchPayloadPrefix$matchId',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'NotificationService.showMazelTov failed: $error\n$stackTrace',
      );
    }
  }

  // --- פניות ותשובות ---------------------------------------------------------

  /// Where a tapped support notification goes. The notifications page, not a
  /// thread: a single alert can stand for several reports, and the page is
  /// where they are all listed anyway.
  static const String _supportPayload = 'support';

  /// Ids 60000-60009 belong to this. One id, reused: the alert says "there is
  /// something in the support inbox", and a second copy of that sentence in the
  /// tray helps nobody.
  static const int _supportId = 60000;

  /// "הגיעה פנייה חדשה" for an administrator, "יש לך תשובה" for everybody else.
  ///
  /// Shown immediately: by the time this is called the thing it is about has
  /// already happened and is already on the notifications page. The caller
  /// ([SupportInboxProvider]) owns the "only when something changed" rule, so
  /// this never fires twice for the same news.
  static Future<void> showSupportAlert({
    required String title,
    required String body,
  }) async {
    if (!_isInitialized ||
        title.trim().isEmpty ||
        !NotificationPreferences.instance.wants(NotificationCategory.support)) {
      return;
    }
    try {
      final String trimmed = body.trim().split(RegExp(r'\s+')).join(' ');
      await _plugin.show(
        _supportId,
        title,
        trimmed.length > 120 ? '${trimmed.substring(0, 120)}…' : trimmed,
        _supportNotificationDetails,
        payload: _supportPayload,
      );
    } catch (error, stackTrace) {
      debugPrint('NotificationService.showSupportAlert failed: $error');
      debugPrint('$stackTrace');
    }
  }

  static Future<void> _handleLaunchTap() async {
    try {
      final NotificationAppLaunchDetails? details = await _plugin
          .getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        _handleTap(details?.notificationResponse?.payload, launch: true);
      }
    } catch (_) {
      // Nothing to open. Never worth an error on startup.
    }
  }

  static void _handleTap(String? payload, {bool launch = false}) {
    if (payload == null) {
      return;
    }
    if (payload == _supportPayload) {
      // The notifications page: a single alert can stand for several
      // reports, and they are all listed there.
      openRoute('/reminders', launch: launch);
      return;
    }
    if (payload.startsWith(_routePayloadPrefix)) {
      openRoute(payload.substring(_routePayloadPrefix.length), launch: launch);
      return;
    }
    if (!payload.startsWith(_matchPayloadPrefix)) {
      return;
    }
    final String matchId = payload.substring(_matchPayloadPrefix.length);
    if (matchId.isNotEmpty) {
      openRoute('/matches/$matchId', launch: launch);
    }
  }

  static tz.TZDateTime _atHour(tz.TZDateTime day, int hour) {
    return tz.TZDateTime(tz.local, day.year, day.month, day.day, hour);
  }

  static Future<void> cancelAll() async {
    if (!_isInitialized) {
      return;
    }

    _matchScheduled = null;
    _personScheduled = null;
    try {
      await _plugin.cancelAll();
    } catch (error, stackTrace) {
      debugPrint('NotificationService.cancelAll failed: $error\n$stackTrace');
    }
  }

  /// The server pushes this account's reminders (`sendReminders` in
  /// functions/), once per account rather than once per phone — so this
  /// phone schedules none of its own and only clears what it scheduled before.
  /// Set by `CloudSyncScheduler` when this device has a push token and the
  /// server has run; off otherwise, so a phone without push keeps reminding.
  static bool serverDelivers = false;

  /// "רעיונות ותזכורות" switched off in the notification settings: no local
  /// reminder is scheduled (and the ones already scheduled are cleared).
  static bool get _wantsReminders =>
      NotificationPreferences.instance.wants(NotificationCategory.ideas);

  static Future<void> _scheduleMatchRemindersInternal(
    List<MatchIdea> matches, {
    MatchReminderText Function(MatchIdea match)? describe,
    required int requestId,
  }) async {
    try {
      final List<_PlannedNotification> planned = <_PlannedNotification>[];
      if (!serverDelivers && _wantsReminders) {
        final List<PlannedReminder<MatchIdea>> due =
            <PlannedReminder<MatchIdea>>[];
        for (final MatchIdea match in matches) {
          final tz.TZDateTime? scheduledTime = _notificationTime(
            match.reminderDate,
          );
          if (scheduledTime != null) {
            due.add(PlannedReminder<MatchIdea>(at: scheduledTime, item: match));
          }
        }
        final ReminderSchedulePlan<MatchIdea> plan = ReminderSchedulePlan.build(
          due,
          maxNotifications: _maxMatchNotifications,
        );
        int notifId = 20000;
        for (final PlannedReminder<MatchIdea> p in plan.single) {
          final MatchIdea match = p.item;
          final MatchReminderText text =
              describe?.call(match) ??
              MatchReminderText(
                title: match.reminderNote ?? 'תזכורת לרעיון',
                body: 'תזכורת לרעיון',
              );
          planned.add(
            _PlannedNotification(
              id: notifId++,
              title: text.title,
              body: text.body,
              at: tz.TZDateTime.from(p.at, tz.local),
              payload: '$_routePayloadPrefix/matches/${match.id}',
            ),
          );
        }
        // Every one of them is still a row on the notifications page; this
        // one push is only the knock on the door.
        for (final ReminderBundle<MatchIdea> bundle in plan.bundles) {
          planned.add(
            _PlannedNotification(
              id: notifId++,
              title: 'יש לך ${bundle.count} רעיונות שכדאי לחזור אליהם',
              body: 'התזכורות מחכות בעמוד ההתראות',
              at: tz.TZDateTime.from(bundle.at, tz.local),
              payload: '$_routePayloadPrefix/reminders',
            ),
          );
        }
      }
      _matchScheduled = await _apply(
        planned,
        previous: _matchScheduled,
        range: (20000, 30000),
        details: _matchNotificationDetails,
        stillCurrent: () => requestId == _latestMatchRequestId,
      );
    } catch (error, stackTrace) {
      // Unknown state on the device: the next refresh starts clean.
      _matchScheduled = null;
      debugPrint(
        'NotificationService.scheduleMatchReminders failed: '
        '$error\n$stackTrace',
      );
    }
  }

  /// Brings the device's pending notifications in [range] to [planned],
  /// touching only the ids whose line changed. Returns what is now scheduled,
  /// or null when the work was abandoned half-way (a newer refresh took
  /// over), so the next one starts clean.
  static Future<Map<int, String>?> _apply(
    List<_PlannedNotification> planned, {
    required Map<int, String>? previous,
    required (int, int) range,
    required NotificationDetails details,
    required bool Function() stillCurrent,
  }) async {
    final Map<int, String> next = <int, String>{
      for (final _PlannedNotification p in planned) p.id: p.signature,
    };
    if (previous != null && mapEquals(previous, next)) {
      // Nothing a reminder says or when it fires has changed: nothing to do.
      return previous;
    }
    if (previous == null) {
      // First refresh of the launch: whatever an earlier run left behind goes.
      final List<PendingNotificationRequest> pending = await _plugin
          .pendingNotificationRequests();
      for (final PendingNotificationRequest req in pending) {
        if (req.id >= range.$1 &&
            req.id < range.$2 &&
            !next.containsKey(req.id)) {
          await _plugin.cancel(req.id);
        }
      }
    } else {
      for (final int id in previous.keys) {
        if (!next.containsKey(id)) await _plugin.cancel(id);
      }
    }
    for (final _PlannedNotification p in planned) {
      if (!stillCurrent()) return null;
      if (previous != null && previous[p.id] == p.signature) continue;
      // Scheduling an id that is already pending replaces it.
      await _plugin.zonedSchedule(
        p.id,
        p.title,
        p.body,
        p.at,
        details,
        payload: p.payload,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
    return next;
  }

  static Future<void> _schedulePersonRemindersInternal(
    List<PersonReminderNotification> reminders, {
    required int requestId,
  }) async {
    try {
      final List<_PlannedNotification> planned = <_PlannedNotification>[];
      if (!serverDelivers && _wantsReminders) {
        final List<PlannedReminder<PersonReminderNotification>> due =
            <PlannedReminder<PersonReminderNotification>>[];
        for (final PersonReminderNotification reminder in reminders) {
          final tz.TZDateTime? scheduledTime = _notificationTime(reminder.date);
          if (scheduledTime != null) {
            due.add(
              PlannedReminder<PersonReminderNotification>(
                at: scheduledTime,
                item: reminder,
              ),
            );
          }
        }
        final ReminderSchedulePlan<PersonReminderNotification> plan =
            ReminderSchedulePlan.build(
              due,
              maxNotifications: _maxPersonNotifications,
            );
        int notifId = 30000;
        for (final PlannedReminder<PersonReminderNotification> p
            in plan.single) {
          final PersonReminderNotification reminder = p.item;
          final String note = (reminder.note ?? '').trim();
          planned.add(
            _PlannedNotification(
              id: notifId++,
              title: note.isNotEmpty ? note : 'לבדוק שוב עם ${reminder.name}',
              body: note.isNotEmpty ? 'תזכורת · ${reminder.name}' : 'תזכורת',
              at: tz.TZDateTime.from(p.at, tz.local),
              payload: reminder.personId.isEmpty
                  ? null
                  : '$_routePayloadPrefix/people/${reminder.personId}',
            ),
          );
        }
        for (final ReminderBundle<PersonReminderNotification> bundle
            in plan.bundles) {
          planned.add(
            _PlannedNotification(
              id: notifId++,
              title: 'יש לך ${bundle.count} חברים לבדוק שוב איתם',
              body: 'התזכורות מחכות בעמוד ההתראות',
              at: tz.TZDateTime.from(bundle.at, tz.local),
              payload: '$_routePayloadPrefix/reminders',
            ),
          );
        }
      }
      _personScheduled = await _apply(
        planned,
        previous: _personScheduled,
        range: (30000, 40000),
        details: _personNotificationDetails,
        stillCurrent: () => requestId == _latestPersonRequestId,
      );
    } catch (error, stackTrace) {
      _personScheduled = null;
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
  const PersonReminderNotification({
    required this.name,
    required this.date,
    this.personId = '',
    this.note,
  });

  final String name;
  final DateTime date;

  /// Where a tap on it goes: this friend's profile.
  final String personId;

  /// What the matchmaker wrote on the reminder, when they wrote anything.
  final String? note;
}

/// The two lines of an idea's reminder in the tray.
class MatchReminderText {
  const MatchReminderText({required this.title, required this.body});

  final String title;
  final String body;
}

/// One reminder notification as planned, before the plugin is asked.
class _PlannedNotification {
  const _PlannedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    this.payload,
  });

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime at;
  final String? payload;

  /// Everything the device shows or acts on — equal lines need no call.
  String get signature =>
      '${at.millisecondsSinceEpoch}|$title|$body|${payload ?? ''}';
}
