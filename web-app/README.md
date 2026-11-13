# שדכן — אתר למחשב (`web-app/`)

The desktop web client for the Shadchan app: same account, same database,
synced with the phones. Next.js (App Router) + React + TypeScript + Tailwind,
Hebrew and RTL throughout. Not Flutter Web — see `docs/web-client.md` for why.

**Status: phase 2a — the real account, read-only.** Two modes behind one store
(`src/data/store.tsx`):

- **demo** — "כניסה עם נתוני דוגמה": a made-up database in memory, fully editable, reset on refresh.
- **live** — sign in with Google / email (Apple needs a Services ID first) and the
  account's database is read live from Firestore (`src/data/live.ts`): the
  `memberships/{uid}` lookup for couples, the six record collections under
  `users/{databaseUid}`, the account's `settings` (profile, personal card), its
  `inbox`, `cardAccess` as owner and `private/helpers`. Tombstones are dropped,
  `_` fields stripped, photos read from Storage by basename. **Every edit is
  refused with a notice** until writes are built. Auth persistence is per tab.

```
npm install
npm run dev        # http://localhost:3000
npm run build      # production build (also type-checks)
```

## Layout

| Path | What |
| --- | --- |
| `src/domain/enums.ts` | Enum **wire strings** (the Dart `.name`s) + Hebrew labels. Must match `lib/utils/enums.dart`. |
| `src/domain/types.ts` | Record shapes = the Firestore documents (`BackupService.*ToJson`). |
| `src/domain/logic.ts` | Rules ported from Dart (age, proposal tabs, basic match filter, stages). Each names its Dart source. |
| `src/data/demo.ts` | The demo database. Invented names only. |
| `src/data/store.tsx` | The one read/write API the screens use: demo state, or the live snapshot with every mutator refused. |
| `src/data/firebase.ts` / `live.ts` / `photos.ts` | Firebase init (App Check, emulators), sign-in helpers, the live Firestore reader, Storage photo URLs. |
| `src/app/login` | Sign-in: Google, Apple (needs a Services ID), email + password, password reset; "נתוני דוגמה" enters the demo. |
| `src/app/(app)/` | The matchmaker area (`/`, `/people`, `/ideas`, `/notifications`, `/community`, `/settings`) and the personal area (`/me`, `/me/card`, `/me/matchmakers`). |

Configuration is in `.env.example` (all public values). Without
`NEXT_PUBLIC_FIREBASE_API_KEY`/`APP_ID` the build is demo-only.

## Console setup the live mode needs

1. A **Web app** registered in `shadchan-gilad` → its `apiKey`/`appId` into Vercel env vars.
2. **App Check** for that web app (reCAPTCHA Enterprise or v3) → the site key into Vercel. Firestore and Storage enforce App Check; without it every read is refused and the site says so.
3. **Auth → Authorized domains**: `shadchan-web.vercel.app`.
4. Apple on the web: an Apple Services ID + return URL (later).

## Testing against the emulators

From the repo root: `env -u HTTPS_PROXY -u https_proxy JAVA_TOOL_OPTIONS="" functions/node_modules/.bin/firebase emulators:start --only auth,firestore,storage --project shadchan-gilad`, seed with firebase-admin, then build with `NEXT_PUBLIC_FIREBASE_API_KEY=x NEXT_PUBLIC_FIREBASE_APP_ID=x NEXT_PUBLIC_USE_EMULATORS=1`. The real `firestore.rules`/`storage.rules` apply.

## Next: writes

Always set `_w: serverTimestamp()` and `_d`, never hard-delete (write a tombstone), and for a couple add `_actorUid` — that is what the phones' `AccountSyncEngine` and the rules expect. Settings are `{k, v: JSON}`.
