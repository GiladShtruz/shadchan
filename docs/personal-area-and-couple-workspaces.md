# Personal cards, private wishes and couple workspaces

## Personal area

The section-by-section product requirement map and remaining device/deployment
checks are in [personal-area-requirements.md](personal-area-requirements.md).

The owner's sendable card is still a `Person` kept outside the matchmaker's
people box. It is active only with at least one photograph or 30 trimmed Unicode
characters in its sendable text. Seeded names/statuses do not activate a draft.
Owner galleries, the editor, uploads and server rules cap it at four photographs.
Announcements and request rules use the same activation criterion.

`privateLooking/{ownerUid}` is a separate server document: free text and at most
one audio object. It is never a `Person` field, a matchmaker note, an export, or
an account-sync setting. `privateLookingPresence` reveals only whether content
exists to someone already approved for the card. The callable checks the actual
media using ffprobe, rejects video and audio over 600 seconds, and converts
WhatsApp Opus/Ogg/AMR to AAC when needed for iOS playback. Storage objects are
immutable and have no persistent download token after verification. Upload
retries reuse the already uploaded immutable file.

`cardAccess` has independent `cardGranted` and `lookingGranted` flags. Legacy
approved rows retain card access only; they never imply private access.
`lookingRequested` adds a private request without disturbing a card grant, and
`cardRequested` lets a private-only grantee ask for the card without losing the
private grant. Declining either additional request preserves existing access.
The first private save offers all existing card grantees, manual selection or
skip; later edits remain live for the already authorized recipients.

Matchmakers read private content through authenticated live snapshots and
protected temporary playback files. Neither the owner’s nor the matchmaker’s
private-audio player exposes an external share/export action.
Revocation disposes playback and removes the private block. Their own notes,
ideas, statuses and local edits never flow back to the card owner. Private
wishes always require a separate explicit grant, including after invitations.

The personal area has exactly three persistent tabs at `/me`: בית,
השדכנים שלי and פרופיל. Home leads with the gendered invitation to let friends
think about the owner, three clickable counters, one-tap card grants, a compact
card/status control, community news and personal invitations. Full card content,
private wishes, account/privacy controls and deletion/restoration live in the
profile tab. Permission management separates available/approved friends; hiding
is reversible synced presentation state, independent from blocking and grants.

Automatic discovery and join notices require reciprocal uploaded contact hashes
and matching directory ownership. The server writes only a name/presence row for
single friends, never candidate details/photos. A targeted personal invitation is
separate: `createPersonalInvite` binds a random token to the recipient's verified
email. `redeemPersonalInvite` atomically claims it once and grants card access to
that account, never private wishes or an unapproved spouse. Forwarded, expired,
wrong-account and unverified claims fail. A consumed token cannot restore revoked
access. Owners can cancel pending invitations; links expire after 30 days and
are purged. The generated join page preserves the token through Android's install
referrer; on iOS the recipient reopens the link after installing. Matchmakers'
legacy invitations to create a card still require explicit owner permission.

`matchmakerActivity/{uid}` records the current database size and an actual
foreground/interaction/exit timestamp. It is writable by its account only and
readable by approved card owners, not as a public roster. These values are shown
as metadata, not ratings; unavailable information is labelled as unavailable.
`publicStats/personalArea` contains server-computed anonymous counts; weekly
figures use Israel's Sunday-based week and never expose a candidate list.

Status synchronization is quiet, including legacy wedding statuses. The server
owns `personalCards.statusUpdatedAt` independently from ordinary edits; clients
show that one date below the status and do not append status-history lines.
`users/{uid}/private/cardActivity` keeps `editedAt`, `reviewedAt` and `nudgedAt`.
Card/private-wishes saves reset the review clock. The quarterly reminder uses
three calendar months (clamped at month ends); “הכול מעודכן” changes only the review
time. A no-op autosave does not move the card's edit time. Explicit update prompts
call `remindMyMatchmakers`, whose transaction enforces one reminder per rolling
30 days; an outbox delivers generic notices only to current card grantees. Nothing
in the notice reveals the changed field or status. Inbox notices are independent
from FCM/device-notification consent.

`personalNews` holds administrator-authored text/optional-image posts and optional
inbox announcements. Verified support admins alone can create/edit/publish/delete
them and upload `personalNews/{id}/{file}` images. Published posts rotate with real
community figures; notification copies are edited/removed with the source,
retain read state and use deterministic IDs to prevent duplicate alerts. Delivery
reads current source state and retries safely. Drafts/images are unavailable to
ordinary readers. `inbox.newsId` has a collection-group index for updates/deletion.

Personal-card copies stay out of database lists, search and direct lookups until
a current server grant **and card** have been validated. Revocation immediately
closes server reads; the client removes access, imported photos, remote baselines
and owner-authored automatic history while preserving the matchmaker's own data.
A grant/invitation link waits for the authorized local card instead of bouncing
to the notification list before sync finishes. An editor already open on a
linked card also closes its stale fields when access ends, even after the
pre-card database record is restored. Own-card preview reuses the same read-only
viewer as the matchmaker’s card and never adds an owner record to the database.

## Couple data and identity

Two durable personal Auth accounts explicitly confirm that they are married.
A random invitation code expires after seven days and can be accepted once.
A transaction locks both memberships; a person cannot join two workspaces.

- `memberships/{uid}` is server-owned and identifies the sole matchmaking
  database (`databaseUid`, the initiating account) and immutable workspace
  operation ID. The six record collections remain under `users/{databaseUid}`.
- Profile settings, the owner's personal card, contacts hashes, device tokens,
  authentication, support and reminders remain under each individual's account.
- Shared board/tag settings and notices live under `coupleData/{operation}`.
  Shared media lives under `coupleFiles/{operation}`. Every pairing has a new
  operation ID, so a later spouse cannot read an earlier pairing's data.
- `_sources` records person provenance, `_authorUid` note authorship and
  `_actorUid` the last actor. Source filters compose with the existing filters.
- Idea reminder values are overlaid from each account's own settings, including
  updates from another device signed into that same individual account.
- The joint database publishes one community score under both names. Ordinary
  record edits synchronize quietly. Shared notices are handled once for both.

Individual card consent never silently widens to a spouse. Pair requests include
both grantees and their combined name. Firestore and Storage check the exact
current membership against that approved list. Old individual grants are
requested again as a named pair; a blocked recipient remains blocked.

## Migration and split

Merge/split writes are frozen by membership state. Each operation keeps immutable
source snapshots before writing destination records. Bulk writes flush before
awaiting their results. Processing leases prevent concurrent retries, and either
spouse can resume an interrupted merge.

Phone normalization merges equal Israeli local/international numbers. Both
sources, photographs, tags and conflicting text are preserved. Other conflicting
field values are retained in `_mergeConflicts` and source archives. Names without
phones are never merged automatically. Idea, note and history references are
remapped; a phone index and aliases reconcile later simultaneous phone duplicates
and late-arriving notes.

Split previews each side's people/idea counts and requires explicit confirmation.
Each side receives their contributed people and relevant notes/history. A cross-
source idea retains both participants and its complete journal on both sides;
unrelated people are not copied. Each person's reminder ownership is retained.
Joint card grants are revoked, and there are no parallel active databases.
Unsynced device edits are kept separately for explicit recovery/export instead of
silently copying the entire joint database. Recovery archives and closed
workspace files expire after 30 days. Account deletion requires splitting first.

## Verification and rollout

Run from `functions/`:

```
npm test
npm run test:rules
FUNCTIONS_DISCOVERY_TIMEOUT=60 npm run test:personal
FUNCTIONS_DISCOVERY_TIMEOUT=60 npm run test:workspaces
```

The last command starts Auth, Firestore, Functions and Storage emulators and
covers real callable authentication, merge/split, retries, same-phone duplicates,
private audio validation, Opus conversion and video rejection. Emulator project
IDs are always `demo-shadchan`.

Deploy Firestore rules **and indexes**, Storage rules, Cloud Functions and
hosting (the join page and regenerated policies) before distributing the app.
Wait for the new `personalNews`/`inbox.newsId` indexes to become ready. The new
personal functions include invitation creation/redemption/revocation, review
confirmation, explicit reminders, news delivery and invitation expiry cleanup.
There is no Hive/Person/backup-enum migration. Existing active cards without a
known join date are included in the total, not guessed into the week's new count.

The new client requires the new callable endpoints and field permissions. Native
Android/iOS builds and physical WhatsApp share sheets require device validation.
The separate desktop web client must resolve `memberships` before reading a
couple database; its record/enum JSON contract is unchanged by this change.

The existing full Flutter suite has two baseline failures in the unrelated
WhatsApp AI import plan/options tests. They were reproduced on the unchanged
base commit in a separate worktree. Targeted card checks and the remaining
Flutter tests pass; static analysis has no errors or warnings, with existing
SDK/lint information described in the PR.
