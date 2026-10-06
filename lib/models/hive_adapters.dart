import 'package:hive/hive.dart';
import 'package:shadchan/models/match_contact.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_note.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/models/person_note.dart';
import 'package:shadchan/utils/enums.dart';

/// Every Hive adapter the app's boxes need, registered once. Shared by the app
/// and by tests that open the real boxes.
void registerHiveAdapters() {
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
