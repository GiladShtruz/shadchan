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
- Unified add-contacts screen at `/people/import` with toggle between swipe (default) and list views; legacy `/people/swipe` redirects to it.
- Local JSON backup/export/import from Settings.
- Open-with-app backup import for JSON backups.
- Birthday notifications using local timezone support.
- Hebrew privacy policy screen and Settings entry.

## Recent Notes

- 2026-04-27: Added multi-photo gallery selection for person photos in both person detail and the legacy person form edit flow using `ImagePicker.pickMultiImage()`. Person photos now support choosing a primary photo by moving that path to the front of `Person.photosPaths`; existing preview/avatar/header behavior continues to read the first photo as primary. The detail photo strip, edit photo strip, and full-screen `PhotoViewer` expose Hebrew primary-photo controls, and the privacy policy now mentions selecting one or more photos. Verified with `flutter analyze` and `flutter test`.
- 2026-04-27: Improved people table view. `_PeopleTable` is now stateful, shows a short Hebrew loading spinner before rendering, and supports header-based table filters for gender, age range, religious level, and profile status. Gender/religious/status filters allow multi-select values; age uses a range selector. Removed the city column from the table and kept name cells as plain tappable text without edit clutter. Verified with `flutter analyze` and `flutter test`.
- 2026-04-27: Updated the matches list search row so the status filter button uses the same `Icons.tune` visual as the people screen while keeping the active-filter dot indicator on the left side of the RTL search row. Verified with `flutter analyze`.
- 2026-04-27: Reviewed `SwipeImportScreen` and fixed two edge cases. Undoing an accepted swipe before the async import finishes now marks the history entry as undone and deletes the imported person once the import completes, preventing stray pending people. Returning from device settings after granting contacts permission now reloads contacts instead of showing an empty state. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: Added Settings export to Excel. `ExcelExportService` uses the `excel` package to generate an `.xlsx`, then rewrites workbook XML through `archive` so Hebrew sheet names and `rightToLeft="1"` are applied, following the pattern from `pkl_guide`. The export includes sheets for `סיכום`, `אנשים`, `יומן אנשי קשר`, `הצעות`, and `יומן הצעות`, and is shared from Settings via `ייצוא לאקסל`. Added a service test that inspects the generated workbook XML. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: Contacts list import now returns directly to `/people` after selected contacts finish importing, without showing a completion dialog. The people list refreshes through the existing repository state after import. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: Person detail and edit now share a single screen. `PersonDetailScreen` can enter inline edit mode from the existing card or from `/people/:id/edit`; the old edit route now opens the detail screen with editing enabled instead of `PersonFormScreen`. Exiting inline edit with `צא` or the device back action saves changes automatically before returning to the read-only card. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: People list cards now show compact missing-info tags for important incomplete fields. `PeopleScreen` displays `חסר מגדר` when `Gender.unknown` is stored and `חסר גיל` when neither birth date nor manual age is available, while preserving the existing age/religious-level subtitle. Verified with `flutter analyze`.
- 2026-04-24: Added a WhatsApp contact button to person detail using `font_awesome_flutter` for the official WhatsApp icon. The button converts saved phone numbers to WhatsApp international format, opens `wa.me` externally with a prefilled Hebrew onboarding message, and shows a Hebrew error when no valid phone is stored. Added `PhoneUtils.toWhatsAppNumber` coverage. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: Dashboard proposal stats now split the old ideas count into `רעיונות פתוחים` and `רעיונות שנפסלו`. Open ideas count statuses `idea`, `checking`, and `unavailable`; rejected ideas count only `rejected`. Verified with `flutter analyze`.
- 2026-04-24: Match status `צד לא פנוי` (`MatchStatus.unavailable`) now remains in the active proposals list instead of moving to the archive. Only rejected, dated, and married proposal statuses are archived by `MatchStatus.isArchived`. Verified with `flutter analyze`.
- 2026-04-24: Improved the people search/filter button contrast. The filter button in `PeopleScreen` now uses the primary color with `onPrimary` icon color instead of the pale primary container, making the tune icon readable in light and dark themes. Verified with `flutter analyze`.
- 2026-04-24: Added a user-selectable app theme mode. `ThemeModeProvider` stores `system`/`light`/`dark` in the local Hive `settings` box, `App` applies the selected `ThemeMode`, and Settings now includes a Hebrew segmented control for `מערכת`/`בהיר`/`כהה`. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: Added a person-level notes timeline and quick profile status controls. `PersonNote` now stores contact-card notes in a dedicated Hive box (`person_notes`) with backup/export/import support, while legacy `Person.notes` remains readable in the timeline for older data. Person detail now exposes profile status chips near the top and records status changes as automatic person notes. The old private-notes row was removed from person detail and the notes text field was removed from person edit. Generated `person_note.g.dart` with build_runner. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: Simplified birthday display and expanded Hebrew birthday support. Person detail now shows one birth-date row with automatic Hebrew/Gregorian conversion instead of separate duplicate rows, and the top quick-info chips were removed from person detail. Dashboard now includes a `ימי הולדת החודש העברי` section with tappable people for the current Hebrew month. Hebrew birthday notifications now fall back to converted Gregorian birth dates when stored Hebrew fields are missing and schedule upcoming Hebrew birthday reminders for multiple years. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: Polished person-card wording and edit flow. Gender display labels now use `זכר`/`נקבה`, the share action sends only the saved send-card description text without prepending the person's name, and the description UI is labeled `כרטיסייה לשליחה`. Person edit now includes a photo picker/thumbnail strip; newly picked photos are kept as unsaved form changes until the user saves, with abandoned copied photos cleaned up on discard. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: Improved large contact-book import performance. `ContactsImportService` now precomputes normalized blocked-name keywords, processes contacts in small async batches with progress callbacks, and stores filtered import candidates in a local Hive cache (`contact_import_cache`) so repeat entries can render quickly while a refresh runs. List and swipe import screens now show Hebrew progress text/linear loading instead of appearing frozen. Privacy policy text was updated to mention the local import-candidate cache.
- 2026-04-24: Added stronger contact import narrowing for large address books. Candidate contacts now require Israeli mobile prefixes (`05` or `+9725`), existing people remain filtered out before display, names matching `lib/utils/names.dart` keywords are hidden by default in the list import screen but still searchable and can be shown with a Hebrew toggle, and the swipe import screen excludes those name-filtered candidates. Android swipe import now sorts candidates by recent call log order through a native `READ_CALL_LOG` method channel with graceful fallback. Privacy policy text was updated for call log usage. Verified with `flutter analyze`, `flutter test`, and `flutter build apk --debug`.
- 2026-04-24: Updated the contacts list import flow so existing contacts are filtered out before display, selected contacts import with `Gender.unknown` by default instead of asking for gender, and import candidate cards stay compact without expanding to a gender selector. Also removed two stale analyzer warnings in dashboard/person detail. Verified with `flutter analyze` and `flutter test`.
- 2026-04-24: Rewrote `AGENTS.md` to match the current flat Flutter structure (`models`, `providers`, `screens`, `services`, `utils`, `widgets`, `dialogs`) and removed the long outdated implementation history. Verified the current file layout, `pubspec.yaml`, router, app entry points, and iOS deployment target while updating these instructions.
- 2026-04-26: Fixed three swipe import screen issues. (1) Corrected RTL icon positions so the heart (add) appears on the right and X (skip) on the left, matching swipe directions. (2) Skipped cards are now persisted in a Hive box (`swipe_skipped_phones`) so they do not reappear after app restart. (3) Added an undo button (center, between heart and X) using `CardSwiperController.undo()` with `onUndo` callback; undo reverts the counter state and, for accepted cards, deletes the imported person. The undo button is visually disabled when no history is available. Verified with `flutter analyze`.
- 2026-04-26: Added multi-select status filter to matches screen. A filter icon button in the AppBar opens a `showModalBottomSheet` with `FilterChip`s for each status relevant to the current view (active statuses: רעיון, בבדיקה, צד לא פנוי, יוצאים; archive statuses: נדחה, יצאו, חתונה). The filter dot badge on the icon shows when a filter is active. The filter resets when toggling between active/archive views. An empty filter set shows all matches. When filtered results are empty a dedicated Hebrew empty state with a clear-filter button is shown. Verified with `flutter analyze`.
- 2026-04-26: Redesigned dashboard stats layout. Changed "זוגות שיצאו" icon from `Icons.history` to `Icons.heart_broken`. Moved "חתונות" out of the grid into a separate full-width `_WideStatCard` banner below the 6-item 2×3 grid. Verified with `flutter analyze`.
- 2026-04-26: Reordered person detail screen sections: profile status → photos → כרטיסייה לשליחה (standalone) → action buttons → inline edit form → notes → related matches → details. Removed city (עיר) and source (מקור היכרות) fields from the UI only; Hive data is still loaded, saved, and exported. Verified with `flutter analyze`.
- 2026-04-26: WhatsApp button now conditionally sends the onboarding message. People with a filled description (כרטיסייה לשליחה) open a plain chat; people without a description get the prefilled onboarding message asking for details and photos. Verified with `flutter analyze`.
