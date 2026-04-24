# AGENTS.md

Guidance for future agents working in this repository.

## Project Snapshot

- This is a Flutter app named `shadchan`, a Hebrew RTL shidduchim management app.
- The current Dart source layout is intentionally simple and flat:
  - `lib/models/` - Hive data models and generated adapters.
  - `lib/providers/` - `ChangeNotifier` repositories for people and matches.
  - `lib/screens/` - top-level app screens and flows.
  - `lib/services/` - backup/import, contacts import, incoming files, notifications.
  - `lib/utils/` - routing, theme, enums, formatting, phone/share/name helpers.
  - `lib/widgets/` - reusable UI widgets.
  - `lib/dialogs/` - reusable dialogs and sheets.
- App entry points are `lib/main.dart` and `lib/app.dart`.
- Navigation is centralized in `lib/utils/app_router.dart` using `go_router`.
- Tests live under `test/`, with service tests in `test/core/services/` and the app boot test in `test/widget_test.dart`.

## Product Rules

- All user-facing UI text must be Hebrew.
- Keep the app fully RTL. `lib/app.dart` wraps the app in `Directionality.rtl`; new screens and widgets should fit that assumption.
- Preserve local-first behavior. User data is stored locally with Hive, local files, and explicit import/export flows.
- Be careful with privacy-sensitive features: contacts, photos, sharing, backup JSON files, and notifications.
- If a task is unclear or has a meaningful product/technical choice, ask before proceeding.

## Platform Rules

- Keep the minimum platform intent aligned to Android 21 and iOS 14 unless the user explicitly approves a change.
- iOS deployment target is currently set to `14.0` in `ios/Runner.xcodeproj/project.pbxproj`.
- Android uses the Flutter Gradle values in `android/app/build.gradle.kts`; do not raise the effective min SDK casually.
- Android release builds use `android/app/proguard-rules.pro` and `android/app/src/main/res/raw/keep.xml` for notification/Gson/R8 safety.
- Native file-open backup import is wired through:
  - Android: `android/app/src/main/kotlin/com/gilad/shadchan/MainActivity.kt` and `AndroidManifest.xml`.
  - iOS: `ios/Runner/IncomingBackupFileBridge.swift`, `SceneDelegate.swift`, and `Info.plist`.

## Development Workflow

- Read this file before starting work and update it after meaningful project changes.
- Prefer the existing folder structure before adding new layers.
- Keep generated Hive files (`*.g.dart`) in sync when changing Hive models/enums:
  - `flutter packages pub run build_runner build --delete-conflicting-outputs`
- Run targeted checks first, then broader checks when the change touches shared behavior.
- Useful verification commands:
  - `flutter analyze`
  - `flutter test`
  - `flutter build apk --debug`
  - `flutter build apk --release` for release/platform-sensitive changes.
- iOS native compilation is not normally verifiable from this Windows environment; mention that when relevant.

## Current Capabilities To Preserve

- People management: list, search/filter/sort, add/edit/detail, favorites, gallery photos, sharing, delete warnings.
- Matches management: list, create, duplicate detection, detail, status/handler updates, notes timeline.
- Dashboard tab at `/dashboard`.
- Contacts import: explicit permission-on-entry flow, search by name/phone, multi-select import, duplicate blocking by normalized phone.
- Swipe import flow at `/people/swipe`.
- Local JSON backup/export/import from Settings.
- Open-with-app backup import for JSON backups.
- Birthday notifications using local timezone support.
- Hebrew privacy policy screen and Settings entry.

## Recent Notes

- 2026-04-24: Improved large contact-book import performance. `ContactsImportService` now precomputes normalized blocked-name keywords, processes contacts in small async batches with progress callbacks, and stores filtered import candidates in a local Hive cache (`contact_import_cache`) so repeat entries can render quickly while a refresh runs. List and swipe import screens now show Hebrew progress text/linear loading instead of appearing frozen. Privacy policy text was updated to mention the local import-candidate cache.
- 2026-04-24: Added stronger contact import narrowing for large address books. Candidate contacts now require Israeli mobile prefixes (`05` or `+9725`), existing people remain filtered out before display, names matching `lib/utils/names.dart` keywords are hidden by default in the list import screen but still searchable and can be shown with a Hebrew toggle, and the swipe import screen excludes those name-filtered candidates. Android swipe import now sorts candidates by recent call log order through a native `READ_CALL_LOG` method channel with graceful fallback. Privacy policy text was updated for call log usage. Verified with `flutter analyze`, `flutter test`, and `flutter build apk --debug`.
- 2026-04-24: Updated the contacts list import flow so existing contacts are filtered out before display, selected contacts import with `Gender.unknown` by default instead of asking for gender, and import candidate cards stay compact without expanding to a gender selector. Also removed two stale analyzer warnings in dashboard/person detail. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: Rewrote `AGENTS.md` to match the current flat Flutter structure (`models`, `providers`, `screens`, `services`, `utils`, `widgets`, `dialogs`) and removed the long outdated implementation history. Verified the current file layout, `pubspec.yaml`, router, app entry points, and iOS deployment target while updating these instructions.
