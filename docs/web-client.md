# The web client — decisions, contract and first phase

Written before any web code exists, so that the session that writes it does not
have to re-derive any of this. Read it end to end before starting.

## What was decided, and why

**A separate web application in Next.js + React + TypeScript, talking to the same
Firestore and the same Firebase Auth.** Not Flutter Web.

The alternative — adding the `web/` platform to this Flutter project — was
considered first and rejected. It wins on effort and loses on the only thing that
matters here: the browser target is a *desktop tool*, keyboard and mouse on a full
screen, and that is a different product from the phone app rather than a wider
version of it. Three panes at once, a candidate list beside a card beside its
proposals; a command palette; a wide sortable table over hundreds of records;
multi-select for batch work. Flutter Web under CanvasKit also gives up text
selection, the browser's own find, and a real document — on a screen whose whole
job is reading and comparing people, that is the wrong trade.

**The cost this buys, stated plainly:** the domain now lives in two languages.
A field added to `Person` has to be added in Dart and in TypeScript, and a
matching rule implemented twice can silently give two answers for the same pair.
Two things contain it:

1. **Shared domain logic belongs in Cloud Functions**, not in either client —
   match suggestions, status derivation, validation. Each client owns only its
   own presentation. Do this the moment the second implementation of any rule is
   about to be written.
2. **Phase 1 is read-only** (below), so the divergence cannot corrupt anything
   while the sync story is still one-directional.

## The data contract

`lib/services/cloud_sync_service.dart` already mirrors every record as its own
document — this is not a single backup blob, which is what makes a second client
viable at all.

```
users/{uid}/people/{id}
users/{uid}/personNotes/{id}
users/{uid}/matches/{id}
users/{uid}/matchNotes/{id}
users/{uid}/personEvents/{id}
users/{uid}/matchStatusEvents/{id}
```

- `firestore.rules` gates all six behind `isOwner()` — a signed-in user reads and
  writes only their own subtree. **Phase 1 needs no rules change at all.**
- **Each document body is exactly the backup JSON of the model**: the maps built
  by `BackupService.personToJson`, `matchToJson`, etc. Enums are serialized as
  their Dart `.name` string (`gender: "female"`, `religiousLevel: "datiLeumi"`,
  `status: "checking"`); dates are ISO-8601 strings, **not** Firestore
  `Timestamp`s. Mirror the enum spellings from `lib/utils/enums.dart` exactly —
  those strings are the wire format and renaming a Dart enum value breaks stored
  data on both clients.
- Photos live in Cloud Storage at `users/{uid}/photos/{basename}`, and the
  documents carry **basenames only**. The phone rebuilds them into local file
  paths; the web client must resolve them against Storage instead.
- The whole set is the *product* of the local Hive database, not a contract the
  phone honours in reverse. Which leads to:

## Phase 1: read-only

Sign in (Google / Apple, the same accounts), then read. No writes from the
browser at all in this phase.

The reason is not caution for its own sake. Hive is the source of truth on the
phone, `CloudSyncService` pushes a diff on open and on close, and a restore
overwrites the local database wholesale. A second writer changes what those
mechanics mean, and there is currently no answer for two sides editing the same
person between two syncs. Opening writes before that answer exists risks the
matchmaker's actual data.

So: phase 1 proves the read path and the UI. Writes are phase 2, and phase 2
starts with deciding conflict resolution — most likely a per-record
`updatedAt` comparison plus a server-side merge — not with a form.

## The design

Four desktop screens at 1440×900, RTL, drawn against this app's real palette
(`lib/utils/app_colors.dart`), type scale (`lib/utils/home_typography.dart`),
statuses and fields:

- Main — three panes: filtered list · candidate card · proposals and suggestions
- Matches — the six `MatchProposalTab` tabs, both sides on one row
- Command palette — ⌘K over the main screen, results grouped people / matches / actions
- Table — multi-facet filter rail, twelve columns, compare drawer for the checked rows

Sources are committed in `design/web/` as `.dc.html` artboards; the published
canvas is at
<https://claude.ai/code/artifact/c386145a-2465-4032-bc73-5b78f9296124>.

Two substitutions in the mockups, both deliberate: statuses render as a colour dot
plus a word rather than the app's emoji (🟢 💡 💍), which read as toys in a dense
table; and `Google Sans` — a local `.ttf` in `assets/fonts/` with no web licence —
is stood in for by Assistant. Settle the font question before building the real
thing.

## What has to happen outside the code

These need the Firebase console and cannot be done from a repository:

1. **Register a web app** in the `shadchan-gilad` project and run
   `flutterfire configure` again so `lib/firebase_options.dart` gains a web
   entry (today it carries android and ios only). The web client itself needs
   the same config as a plain JS object.
2. **App Check for web** is reCAPTCHA v3 or Enterprise — a different provider
   from the Play Integrity / DeviceCheck pair the app uses. Register a site key
   and enforce it, or the web client is refused by the same App Check gate that
   protects the phone.
3. **Authorized domains** for Auth must include whatever host serves the web app,
   or Google sign-in fails with `auth/unauthorized-domain`.
4. **Apple sign-in on web** goes through Apple's OAuth web flow — a Services ID
   plus a return URL — not the native sheet `sign_in_with_apple` uses. Budget
   for it or ship Google-only in phase 1.

## Repository layout and hosting

Put the web client in a top-level `web-app/` directory with its own
`package.json`, deliberately **not** `web/` — that name is what
`flutter create --platforms=web` claims, and leaving it free keeps the door open.

`firebase.json` currently serves the static marketing site from `site/` at the
root. Give hosting two targets rather than replacing it: the existing site, and
the app build. Serving the app from its own subdomain is cleaner than a `/app`
path, because a SPA rewrite at the root would swallow `privacy.html` and
`delete-account.html` — both of which are linked from the app stores and must
keep resolving.

## Rules to keep

- All user-facing text is Hebrew; the whole interface is RTL. (`AGENTS.md`)
- Do not change the six collection names or the enum wire strings without
  changing `CloudSyncService`, the Hive models and the web client together.
- `firestore.rules` and `storage.rules` are shared by both clients. A rule
  relaxed for the browser is relaxed for the phone too.
- The phone must keep working with no network at all. Nothing done for the web
  may make a local-only session worse.

## Open questions for the user

- Which font replaces `Google Sans` on the web.
- Whether the emoji statuses should come back in the desktop UI.
- Whether the web client ever needs the community, tips and support-admin
  surfaces, or only the matchmaker's own records.
