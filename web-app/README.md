# שדכן — אתר למחשב (`web-app/`)

The desktop web client for the Shadchan app: same account, same database,
synced with the phones. Next.js (App Router) + React + TypeScript + Tailwind,
Hebrew and RTL throughout. Not Flutter Web — see `docs/web-client.md` for why.

**Status: phase 1 — prototype with demo data.** Every screen works against an
in-memory, made-up database (`src/data/demo.ts`). Edits are visible across the
site and reset on refresh. Nothing talks to Firebase yet.

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
| `src/data/store.tsx` | The one read/write API the screens use. Phase 2 swaps what is behind it for Firestore. |
| `src/app/login` | Sign-in (Google / Apple / email are placeholders; "נתוני דוגמה" enters the demo). |
| `src/app/(app)/` | The matchmaker area (`/`, `/people`, `/ideas`, `/notifications`, `/community`, `/settings`) and the personal area (`/me`, `/me/card`, `/me/matchmakers`). |

## Phase 2 — real data (not done yet)

1. Register a web app in Firebase project `shadchan-gilad`; put its config in env vars.
2. App Check for web (reCAPTCHA Enterprise) — Firestore and Storage enforce App Check.
3. Add the Vercel domain to Firebase Auth → Authorized domains.
4. Replace the store's state with listeners on `users/{uid}/*`; drop `_deleted` tombstones; ignore `_`-prefixed fields.
5. Writes: always set `_w: serverTimestamp()` and `_d`, never hard-delete (write a tombstone) — that is what the phones' `AccountSyncEngine` listens for.
6. Photos from Storage `users/{uid}/photos/{basename}` (and the voice notes), via the SDK.
