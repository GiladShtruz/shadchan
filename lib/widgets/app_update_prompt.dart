import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_router.dart';
import 'package:upgrader/upgrader.dart';

/// Asks the store whether a newer version of the app exists, and offers it.
///
/// The check runs when the app opens and again every time it returns from the
/// background (`checkOnResume`, on by default), so an update published while a
/// phone sat in a pocket is offered the next time the app is opened rather than
/// on some later launch. The lookup is the store's own listing — Play Store on
/// Android, the App Store on iOS — which means it needs no version number kept
/// anywhere in this repository or in Firebase: the released version *is* the
/// answer, and nothing has to be remembered to bump alongside `pubspec.yaml`.
///
/// The prompt is a suggestion, never a wall. `showIgnore` is off because
/// "never ask again about this version" is a decision nobody makes knowingly
/// from a dialog they did not open; "אחר כך" is the honest second button, and
/// the package will not ask again for three days — unless a *newer* version
/// than the one already declined appears, which starts the clock over.
///
/// Nothing here can keep the app from starting: a store lookup that fails,
/// times out or answers with an unparseable version simply leaves the version
/// info null and no dialog is ever built.
class AppUpdatePrompt extends StatefulWidget {
  const AppUpdatePrompt({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// The same seam `SyncProvider`, `AccountProvider` and `TipsProvider` carry,
  /// for the same reason. This widget sits in the app's own builder, so every
  /// widget test that pumps `App` would otherwise reach `SharedPreferences` and
  /// an http client through `Upgrader.initialize()` — both of which are plugin
  /// channels that do not exist under `flutter test`. Disabled, this widget is
  /// its child and nothing else.
  final bool enabled;

  @override
  State<AppUpdatePrompt> createState() => _AppUpdatePromptState();
}

class _AppUpdatePromptState extends State<AppUpdatePrompt> {
  Upgrader? _upgrader;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _upgrader = Upgrader(
        messages: HebrewUpgraderMessages(),
        debugLogging: kDebugMode,
      );
    }
  }

  @override
  void dispose() {
    // Drops the lifecycle observer the upgrader registers during initialize().
    _upgrader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Upgrader? upgrader = _upgrader;
    if (upgrader == null) {
      return widget.child;
    }

    return UpgradeAlert(
      upgrader: upgrader,
      // This widget lives above the app's `Navigator`, in the builder of
      // `MaterialApp.router`, so the dialog has to be pushed onto go_router's
      // navigator explicitly. That navigator is also below the app's
      // `Directionality`, which is what keeps the dialog RTL.
      navigatorKey: AppRouter.router.routerDelegate.navigatorKey,
      showIgnore: false,
      child: widget.child,
    );
  }
}

/// The update dialog in Hebrew.
///
/// `upgrader` does ship Hebrew, but it is translated from English and reads
/// like it ("לעדכן יישומון?"), and the body is built around `{{appName}}`,
/// which resolves to the platform's bundle label. The app is named שדכן in
/// both manifests, so it is written out here instead — one string that cannot
/// come back in Latin letters from a build setting nobody was thinking about.
class HebrewUpgraderMessages extends UpgraderMessages {
  HebrewUpgraderMessages() : super(code: 'he');

  @override
  String get title => 'יש גרסה חדשה של שדכן';

  /// `{{currentAppStoreVersion}}` and `{{currentInstalledVersion}}` are filled
  /// in by `Upgrader.body`.
  @override
  String get body =>
      'יצאה גרסה חדשה בחנות. כדאי לעדכן כדי לקבל את השיפורים והתיקונים האחרונים.'
      '\n\nהגרסה בחנות: {{currentAppStoreVersion}}'
      '\nהגרסה שלך: {{currentInstalledVersion}}';

  @override
  String get prompt => 'לעדכן עכשיו?';

  @override
  String get buttonTitleUpdate => 'עדכון';

  @override
  String get buttonTitleLater => 'אחר כך';

  @override
  String get buttonTitleIgnore => 'לא להזכיר שוב';

  @override
  String get releaseNotes => 'מה חדש בגרסה';
}
