import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/app.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/services/notification_service.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  _registerAdapters();

  await Hive.openBox<Person>('people');
  await Hive.openBox<PersonNote>('person_notes');
  await Hive.openBox<MatchIdea>('matches');
  await Hive.openBox<MatchNote>('match_notes');
  await Hive.openBox<dynamic>('settings');
  await NotificationService.initialize();
  await NotificationService.scheduleBirthdayNotifications(
    Hive.box<Person>('people').values.toList(),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PersonRepository>(
          create: (_) => PersonRepository(
            Hive.box<Person>('people'),
            Hive.box<PersonNote>('person_notes'),
          ),
        ),
        ChangeNotifierProvider<MatchRepository>(
          create: (_) => MatchRepository(
            Hive.box<MatchIdea>('matches'),
            Hive.box<MatchNote>('match_notes'),
          ),
        ),
        ChangeNotifierProvider<ThemeModeProvider>(
          create: (_) => ThemeModeProvider(Hive.box<dynamic>('settings')),
        ),
      ],
      child: const _DismissKeyboardOnTap(child: App()),
    ),
  );
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
}
