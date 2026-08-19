import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/app.dart';
import 'package:shadchan/utils/enums.dart';
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
import 'package:shadchan/providers/sync_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';

Future<void> main() async {
  // A crash during startup used to leave a silent black screen (main threw
  // before runApp was ever called). Now any startup failure is caught and shown
  // on screen so it can be read and reported instead of just going black.
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      try {
        await _bootstrap();
        runApp(_buildApp());
      } catch (error, stackTrace) {
        runApp(_StartupErrorApp(error: error, stackTrace: stackTrace));
      }
    },
    (Object error, StackTrace stackTrace) {
      debugPrint('Uncaught zone error: $error\n$stackTrace');
    },
  );
}

/// Opens storage and runs one-time startup work. Notification and migration
/// failures are non-fatal — they must never keep the app from starting — so
/// they are handled inside their own services / swallowed here.
Future<void> _bootstrap() async {
  // Firebase is deliberately absent from startup. It is only needed by the AI
  // import, and `FirebaseBootstrap.ensureReady()` brings it up when one of
  // those screens is opened — awaiting it here opened the app to a white
  // screen when a step hung, and even unawaited it competed with the first
  // frame.
  final Stopwatch watch = Stopwatch()..start();
  void mark(String step) {
    debugPrint('STARTUP $step: ${watch.elapsedMilliseconds}ms');
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

  // Where a tapped "יש לך הודעות מזל טוב!" goes. Set before `initialize`,
  // which delivers a tap that launched the app the moment it is ready — wiring
  // this afterwards would drop exactly the tap that matters most.
  //
  // `go` rather than `push`: the notification is the start of a journey, and
  // there may be no stack behind it on a cold start.
  NotificationService.onOpenMatch = (String matchId) {
    // After a frame, never during one. A tap that launched the app is
    // delivered inside `initialize`, before `runApp` — navigating from there
    // would run the router's redirect against a widget tree that does not
    // exist yet. One frame later everything it reads is in place.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.router.go('/matches/$matchId');
    });
  };
  await NotificationService.initialize();
  // Pushed a week out on every launch, so it can only ever reach someone who
  // has not opened the app in that time.
  unawaited(NotificationService.scheduleReturnInvitation());
  mark('notifications');

  await PersonMigrations.convertBirthDatesToAges(
    people: Hive.box<Person>('people'),
    settings: Hive.box<dynamic>('settings'),
  );
  await MatchMigrations.reconcileStatusesWithAvailability(
    matches: Hive.box<MatchIdea>('matches'),
    people: Hive.box<Person>('people'),
    settings: Hive.box<dynamic>('settings'),
  );
  mark('migrations');

  await NotificationService.cancelBirthdayNotifications();
  mark('done');
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
