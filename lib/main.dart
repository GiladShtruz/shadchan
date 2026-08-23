import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/app.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/services/diagnostics_log.dart';
import 'package:shadchan/services/notification_service.dart';
import 'package:shadchan/utils/app_router.dart';
import 'package:shadchan/services/match_migrations.dart';
import 'package:shadchan/services/person_migrations.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/community_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/providers/support_inbox_provider.dart';
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';

Future<void> main() async {
  // A crash during startup used to leave a silent black screen (main threw
  // before runApp was ever called). Now any startup failure is caught and shown
  // on screen so it can be read and reported instead of just going black.
  //
  // What that could never catch is a failure *below* Dart — a plugin
  // registering, a channel, the engine itself — which is what an iPhone showing
  // the splash and then dying actually looks like. `DiagnosticsLog` is the
  // answer to those: every startup step writes itself to a file as it finishes,
  // and the next launch reads back how far the last one got.
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await _startDiagnostics();

      // Anything the framework catches during a build, layout or paint. It
      // shows its own error box either way; this is what makes the details
      // readable afterwards, from the phone it happened on.
      final FlutterExceptionHandler? previousOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        DiagnosticsLog.error(
          details.exception,
          details.stack,
          context: 'שגיאת ממשק',
        );
        previousOnError?.call(details);
      };
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        DiagnosticsLog.error(error, stack, context: 'שגיאה לא מטופלת');
        return true;
      };

      try {
        await _bootstrap();
        runApp(_buildApp());
        // The line whose *absence* is the crash signal, so it is written from
        // the first frame that actually reached the screen rather than from
        // here — `runApp` returning only means the tree was scheduled.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          DiagnosticsLog.markFirstFrame();
          // Everything that does not have to happen before the app appears,
          // and must not be allowed to stop it appearing. See
          // `_startNotifications`.
          unawaited(_startNotifications());
        });
      } catch (error, stackTrace) {
        DiagnosticsLog.error(error, stackTrace, context: 'כשל בהפעלה');
        runApp(_StartupErrorApp(error: error, stackTrace: stackTrace));
      }
    },
    (Object error, StackTrace stackTrace) {
      DiagnosticsLog.error(error, stackTrace, context: 'שגיאה מחוץ למסלול');
      debugPrint('Uncaught zone error: $error\n$stackTrace');
    },
  );
}

/// Opens the flight recorder before anything else has a chance to fail.
///
/// This must not call a plugin before the recorder itself is open. Device and
/// build facts are collected by the diagnostics screen after the app is
/// visible; asking `device_info_plus` and `package_info_plus` here used to put
/// three method-channel round trips in front of both the log and the first
/// frame. If one of them stalled on iOS, the launch could die without leaving
/// a Dart breadcrumb at all. The native log already carries iOS/app versions.
Future<void> _startDiagnostics() async {
  try {
    await DiagnosticsLog.start();
  } on Object catch (error) {
    debugPrint('diagnostics unavailable: $error');
  }
}

/// Opens storage and runs one-time startup work.
///
/// **Storage, and then as little as possible.** Everything on this path delays
/// the first frame, and on iOS a launch that takes too long is not slow — it is
/// killed. Notifications used to be awaited here and are not any more (see
/// `_startNotifications`); what is left is the boxes, which the app cannot draw
/// without, and the one-time migrations, which have to have run before anything
/// reads a record.
///
/// The migrations are wrapped anyway, so a failure in one is recorded, named
/// and stepped over rather than becoming a launch that never happens. Storage
/// is not, because an app with no boxes has nothing to show.
Future<void> _bootstrap() async {
  // Firebase is deliberately absent from startup. It is only needed by the AI
  // import, and `FirebaseBootstrap.ensureReady()` brings it up when one of
  // those screens is opened — awaiting it here opened the app to a white
  // screen when a step hung, and even unawaited it competed with the first
  // frame.
  final Stopwatch watch = Stopwatch()..start();
  void mark(String step) {
    DiagnosticsLog.mark('$step (${watch.elapsedMilliseconds}ms)');
  }

  /// A startup step that must never be the reason the app does not open: what
  /// goes wrong is written down and named, and the launch carries on.
  Future<void> optional(String step, Future<void> Function() work) async {
    try {
      await work();
      mark(step);
    } on Object catch (error, stackTrace) {
      DiagnosticsLog.error(error, stackTrace, context: 'שלב $step נכשל');
    }
  }

  await Hive.initFlutter();
  _registerAdapters();
  mark('hive_init');

  await Hive.openBox<Person>('people');
  await Hive.openBox<PersonNote>('person_notes');
  await Hive.openBox<PersonEvent>('person_events');
  await Hive.openBox<MatchIdea>('matches');
  await Hive.openBox<MatchNote>('match_notes');
  await Hive.openBox<MatchStatusEvent>('match_status_events');
  await Hive.openBox<dynamic>('settings');
  mark('boxes_open');

  await optional('migrations', () async {
    await PersonMigrations.convertBirthDatesToAges(
      people: Hive.box<Person>('people'),
      settings: Hive.box<dynamic>('settings'),
    );
    await MatchMigrations.reconcileStatusesWithAvailability(
      matches: Hive.box<MatchIdea>('matches'),
      people: Hive.box<Person>('people'),
      settings: Hive.box<dynamic>('settings'),
    );
  });

  mark('bootstrap_done');
}

/// Notifications, started once the app is already on screen.
///
/// **This is deliberately not part of `_bootstrap`, and that is the fix for a
/// launch that died on an iPhone.** `flutter_local_notifications` was being
/// initialised with `requestAlertPermission: true` from before `runApp`, and on
/// iOS that raises the system permission alert and waits for an answer. With
/// nothing drawn yet, what the phone shows during that wait is the launch
/// image — and iOS ends a process that has not finished launching after about
/// twenty seconds. Splash screen, then gone, and a report that says "hang"
/// rather than anything with a stack in it.
///
/// So nothing here blocks the first frame: the plugin comes up after it, and
/// [NotificationService.requestPermissions] asks with the app visible behind
/// the alert, which is where iOS expects such a question to be asked from.
Future<void> _startNotifications() async {
  try {
    // Set before `initialize`, which delivers a tap that launched the app the
    // moment it is ready — wiring this afterwards would drop exactly the tap
    // that matters most.
    //
    // `go` rather than `push`: the notification is the start of a journey, and
    // there may be no stack behind it on a cold start.
    NotificationService.onOpenMatch = (String matchId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppRouter.router.go('/matches/$matchId');
      });
    };
    // A tapped support alert lands on the notifications page rather than on
    // one thread: a single alert can stand for several reports, and they are
    // all listed there anyway.
    NotificationService.onOpenSupport = () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppRouter.router.go('/reminders');
      });
    };
    await NotificationService.initialize();
    DiagnosticsLog.mark('notifications_ready');

    await NotificationService.requestPermissions();
    DiagnosticsLog.mark('notifications_permission');

    // Pushed a week out on every launch, so it can only ever reach someone who
    // has not opened the app in that time.
    await NotificationService.scheduleReturnInvitation();
    await NotificationService.cancelBirthdayNotifications();
    DiagnosticsLog.mark('notifications_scheduled');
  } on Object catch (error, stackTrace) {
    DiagnosticsLog.error(error, stackTrace, context: 'שלב notifications נכשל');
  }
}

Widget _buildApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PersonRepository>(
        create: (_) => PersonRepository(
          Hive.box<Person>('people'),
          Hive.box<PersonNote>('person_notes'),
          Hive.box<PersonEvent>('person_events'),
        ),
      ),
      ChangeNotifierProvider<MatchRepository>(
        create: (BuildContext context) {
          final MatchRepository matchRepository = MatchRepository(
            Hive.box<MatchIdea>('matches'),
            Hive.box<MatchNote>('match_notes'),
            Hive.box<MatchStatusEvent>('match_status_events'),
          );
          final PersonRepository personRepository = context
              .read<PersonRepository>();
          // Availability flows both ways: a person going busy / on a break
          // moves their open proposals to "בהמתנה" and back to "רעיון" once
          // both sides are free, while a couple that starts dating is marked
          // "תפוס" on both cards.
          personRepository.onPersonStatusChanged =
              matchRepository.syncMatchesForPerson;
          matchRepository
            ..resolvePerson = personRepository.getById
            ..markPersonBusy = ((String personId, String matchId) =>
                personRepository.updateProfileStatus(
                  personId,
                  ProfileStatus.busy,
                  causedByMatchId: matchId,
                ))
            ..markPersonMazelTov = ((String personId, String matchId) =>
                personRepository.updateProfileStatus(
                  personId,
                  ProfileStatus.mazelTov,
                  causedByMatchId: matchId,
                ))
            ..restorePersonStatus =
                ((String personId, ProfileStatus status, String matchId) =>
                    personRepository.updateProfileStatus(
                      personId,
                      status,
                      causedByMatchId: matchId,
                    ))
            ..logPersonEvent = personRepository.logEvent;
          return matchRepository;
        },
      ),
      ChangeNotifierProvider<ThemeModeProvider>(
        create: (_) => ThemeModeProvider(Hive.box<dynamic>('settings')),
      ),
      ChangeNotifierProvider<ReligiousLevelsProvider>(
        create: (_) => ReligiousLevelsProvider(Hive.box<dynamic>('settings')),
      ),
      ChangeNotifierProvider<UserProfileProvider>(
        create: (_) => UserProfileProvider(Hive.box<dynamic>('settings')),
      ),
      // Lazy on purpose: constructing this is what starts Firebase, and
      // nothing outside Settings watches it, so the first frame never pays for
      // it. See the note in `_bootstrap` about keeping Firebase off startup.
      ChangeNotifierProvider<AccountProvider>(create: (_) => AccountProvider()),
      // Not lazy: `CloudSyncScheduler` reads it from the app's own builder, on
      // the frame after startup, to run the opening backup.
      ChangeNotifierProvider<SyncProvider>(
        lazy: false,
        create: (_) => SyncProvider(Hive.box<dynamic>('settings')),
      ),
      // The home screen watches this on the first frame, which is exactly why
      // its constructor only reads the local cache — see the note there.
      ChangeNotifierProvider<TipsProvider>(
        lazy: false,
        create: (_) => TipsProvider(Hive.box<dynamic>('settings')),
      ),
      // Not lazy for the same reason as `SyncProvider`: `CloudSyncScheduler`
      // refreshes it on the frame after startup. Its constructor touches
      // nothing but the local settings box — the counts are derived from Hive
      // and the publish only happens once Firebase is already up.
      ChangeNotifierProvider<CommunityProvider>(
        lazy: false,
        create: (_) => CommunityProvider(),
      ),
      // Reports that arrived and answers that came back. Lazy: it holds only
      // local timestamps until `CloudSyncScheduler` refreshes it a frame after
      // startup, which is where its one network call belongs.
      ChangeNotifierProvider<SupportInboxProvider>(
        create: (_) => SupportInboxProvider(Hive.box<dynamic>('settings')),
      ),
    ],
    child: const _DismissKeyboardOnTap(child: App()),
  );
}

/// Shown when startup fails, instead of a black screen. Keeps the error visible
/// so it can be screenshotted and reported.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'אירעה תקלה בהפעלת האפליקציה',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        '$error\n\n$stackTrace',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissKeyboardOnTap extends StatelessWidget {
  const _DismissKeyboardOnTap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: FocusManager.instance.primaryFocus?.unfocus,
      child: child,
    );
  }
}

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(PersonAdapter());
  }
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(MatchIdeaAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(MatchNoteAdapter());
  }
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter(GenderAdapter());
  }
  if (!Hive.isAdapterRegistered(4)) {
    Hive.registerAdapter(ReligiousLevelAdapter());
  }
  if (!Hive.isAdapterRegistered(5)) {
    Hive.registerAdapter(MatchStatusAdapter());
  }
  if (!Hive.isAdapterRegistered(6)) {
    Hive.registerAdapter(CurrentHandlerAdapter());
  }
  if (!Hive.isAdapterRegistered(7)) {
    Hive.registerAdapter(ProfileStatusAdapter());
  }
  if (!Hive.isAdapterRegistered(8)) {
    Hive.registerAdapter(PersonNoteAdapter());
  }
  if (!Hive.isAdapterRegistered(9)) {
    Hive.registerAdapter(MaritalStatusAdapter());
  }
  if (!Hive.isAdapterRegistered(10)) {
    Hive.registerAdapter(MatchProgressAdapter());
  }
  if (!Hive.isAdapterRegistered(12)) {
    Hive.registerAdapter(PersonEventAdapter());
    Hive.registerAdapter(MatchStatusEventAdapter());
  }
  if (!Hive.isAdapterRegistered(13)) {
    Hive.registerAdapter(PersonEventTypeAdapter());
  }
  if (!Hive.isAdapterRegistered(11)) {
    Hive.registerAdapter(MatchContactAdapter());
  }
  if (!Hive.isAdapterRegistered(14)) {
    Hive.registerAdapter(RegionAdapter());
  }
}
