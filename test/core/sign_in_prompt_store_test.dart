import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';

/// The flag the router reads on the first frame to decide whether this launch
/// opens on the sign-in screen.
///
/// It has to survive a restart and it has to be readable *before* Firebase
/// exists — see the note on the store itself for why the honest question
/// ("is somebody signed in?") cannot be asked there.
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

  test('a fresh install has no account, and signing in gives it one', () {
    expect(SignInPromptStore.hasAccount, isFalse);
    SignInPromptStore.markSignedIn();
    expect(SignInPromptStore.hasAccount, isTrue);
  });

  test('signing out takes the account back off the device', () {
    // The flag is what the router reads on the first frame, so this is the
    // whole of "the next launch asks again" — and of "this launch does too".
    SignInPromptStore.markSignedIn();
    SignInPromptStore.markSignedOut();
    expect(SignInPromptStore.hasAccount, isFalse);
  });
}
