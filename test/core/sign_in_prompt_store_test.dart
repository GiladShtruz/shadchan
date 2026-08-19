import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';

/// When the app may mention signing in again, to somebody who already said no.
///
/// The pacing is the whole feature. One reminder, at the point the database is
/// worth something, and then silence until it has grown a great deal — because
/// the alternative is an app that asks for an account every time it is opened,
/// which is how a matchmaker learns to dismiss whatever it says.
void main() {
  late Directory directory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('shadchan_signin_store_');
    Hive.init(directory.path);
    await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    await Hive.box<dynamic>('settings').clear();
    SignInPromptStore.resetForTest();
  });

  tearDownAll(() async {
    await Hive.close();
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  test('a fresh install has not answered, and one answer is enough', () {
    expect(SignInPromptStore.hasAnswered, isFalse);
    SignInPromptStore.markAnswered();
    expect(SignInPromptStore.hasAnswered, isTrue);
  });

  test('a small database is never used as a reason to ask', () {
    // Four friends is somebody who arrived this afternoon. "כבר בנית מאגר
    // משמעותי" would not be true, and saying it anyway is how a prompt stops
    // being believed.
    expect(SignInPromptStore.shouldRemind(0), isFalse);
    expect(SignInPromptStore.shouldRemind(4), isFalse);
    expect(
      SignInPromptStore.shouldRemind(SignInPromptStore.remindFromFriends - 1),
      isFalse,
    );
  });

  test('a database worth losing earns exactly one reminder', () {
    expect(
      SignInPromptStore.shouldRemind(SignInPromptStore.remindFromFriends),
      isTrue,
    );

    SignInPromptStore.markReminded(SignInPromptStore.remindFromFriends);
    expect(
      SignInPromptStore.shouldRemind(SignInPromptStore.remindFromFriends),
      isFalse,
    );
    // Two more friends is not a new reason to be asked again.
    expect(
      SignInPromptStore.shouldRemind(SignInPromptStore.remindFromFriends + 2),
      isFalse,
    );
  });

  test('it comes back only when the database has really grown', () {
    const int first = SignInPromptStore.remindFromFriends;
    SignInPromptStore.markReminded(first);

    final int justShort = first + SignInPromptStore.remindAgainAfterFriends - 1;
    expect(SignInPromptStore.shouldRemind(justShort), isFalse);
    expect(
      SignInPromptStore.shouldRemind(
        first + SignInPromptStore.remindAgainAfterFriends,
      ),
      isTrue,
    );
  });

  test('the pacing survives being reloaded from the box', () async {
    SignInPromptStore.markReminded(40);
    // The write is scheduled on the root zone rather than awaited — see
    // `persistHomeSetting` — so the box catches up a microtask later.
    await Future<void>.delayed(Duration.zero);
    SignInPromptStore.resetForTest();

    // Read back through Hive rather than through the cache: the reminder must
    // not come back a second time simply because the app was restarted.
    expect(SignInPromptStore.remindedAtFriends, 40);
    expect(SignInPromptStore.shouldRemind(45), isFalse);
  });
}
