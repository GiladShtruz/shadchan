import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/intro_screens.dart';
import 'package:shadchan/utils/enums.dart';

/// The matchmaker's own name is now two fields, and one of them is what the
/// home screen greets by. The part worth pinning down is the *fallback*: every
/// install from before the split has one joined string in the box, and none of
/// them should have to be re-onboarded to be greeted properly.
void main() {
  late Directory directory;
  late Box<dynamic> box;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shadchan_profile_name_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('profile_name_test');
  });

  tearDown(() async {
    await Hive.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  UserProfileProvider provider() => UserProfileProvider(box);

  test('registration stores the two names apart and joined', () async {
    final UserProfileProvider profile = provider();
    await profile.saveProfile(
      name: 'רבקה',
      lastName: 'כהן־שטרן',
      gender: Gender.female,
      isSingle: false,
    );

    expect(profile.firstName, 'רבקה');
    expect(profile.lastName, 'כהן־שטרן');
    // The joined name stays, because the profile header, the tip signature and
    // the cloud backup all read it.
    expect(profile.name, 'רבקה כהן־שטרן');
  });

  test('a profile saved before the split still answers both halves', () async {
    // Exactly what an older install has in the box: one key, one string.
    await box.put('userName', 'רבקה כהן־שטרן');

    final UserProfileProvider profile = provider();
    expect(profile.firstName, 'רבקה');
    expect(profile.lastName, 'כהן־שטרן');
    expect(profile.name, 'רבקה כהן־שטרן');
  });

  test('a one-word older name is a first name, not a surname', () async {
    await box.put('userName', 'רבקה');

    final UserProfileProvider profile = provider();
    expect(profile.firstName, 'רבקה');
    expect(profile.lastName, isNull);
  });

  test('a surname with several words survives the round trip', () async {
    final UserProfileProvider profile = provider();
    await profile.saveProfile(
      name: 'יהונתן',
      lastName: 'בן דוד הלוי',
      gender: Gender.male,
      isSingle: true,
    );

    expect(profile.firstName, 'יהונתן');
    expect(profile.lastName, 'בן דוד הלוי');
  });

  test('an empty surname is stored as no surname at all', () async {
    final UserProfileProvider profile = provider();
    await profile.saveProfile(
      name: 'שרה',
      lastName: '   ',
      gender: Gender.female,
      isSingle: false,
    );

    expect(profile.firstName, 'שרה');
    expect(profile.lastName, isNull);
    expect(profile.name, 'שרה');
  });

  test('nothing saved means nothing to greet by', () {
    final UserProfileProvider profile = provider();
    expect(profile.firstName, isNull);
    expect(profile.lastName, isNull);
  });

  // --- the welcome --------------------------------------------------------

  test('the welcome addresses one person throughout', () {
    // This is the one screen shown *before* anybody has said whether they are a
    // man or a woman, so it has to work for both — and it is the screen that
    // promises the database is private, which it cannot do while being vague
    // about whose database it is.
    for (final IntroPage page in IntroScreens.pages) {
      for (final String plural in <String>[
        'שלכם',
        'לכם',
        'אתם',
        'שאתם',
        'תוסיפו',
        'שתוסיפו',
      ]) {
        expect(
          page.body.contains(plural),
          isFalse,
          reason: '${page.title}: "$plural"',
        );
        expect(page.title.contains(plural), isFalse, reason: page.title);
      }
    }
  });

  test('the welcome says what the app is, without overselling it', () {
    final IntroPage first = IntroScreens.pages.first;
    expect(first.body, 'לשדכנים, ולכל מי שחושב על החברים שלו.');

    final IntroPage second = IntroScreens.pages[1];
    // A journal, not a database: what it holds is a train of thought about
    // people over time.
    expect(second.title, contains('יומן השידוכים'));
    expect(second.title, isNot(contains('מאגר השידוכים')));
    expect(
      second.body,
      'החברים שחושבים עליהם, הרעיונות שעולים בראש ומה קרה עם כל אחד מהם – '
      'הכל נשמר לך במקום אחד.',
    );

    expect(IntroScreens.pages[2].body, contains('את המאגר שלך'));
  });
}
