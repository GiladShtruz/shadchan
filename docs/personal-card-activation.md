# Personal card: activation and photo limit (phase 1)

A card is **active** only when the owner has not deleted it and it has at least one photo reference, or 30+ Unicode characters in the *description*. The name, status, and empty structured fields do not count. An inactive card remains an editable private draft.

The phone directory's `hasCard` follows this rule, while Firestore security rules independently prevent any matchmaker from reading an inactive card or requesting access to it. Storage rules also reject inactive card photos. The Cloud Function announcing card creation ignores drafts and announces when a draft first becomes active. Previously notified matchmakers are not notified twice.

The personal-card picker now accepts at most 4 photos; replacing the primary picture does not add a fifth, and extras selected in the gallery are removed from app storage. Matchmakers' ordinary friend cards retain their previous photo behavior. The server also caps `personalCards.photoPaths` at 4. Older local cards with more than 4 photos retain their local originals, but only the first four are published, to prevent hidden accidental data loss.

## Release checklist

1. Run `flutter analyze`, `flutter test test/core/personal_card_test.dart`, and `cd functions && npm run build && npm run test:rules`.
2. Deploy Firestore rules, Storage rules, and Cloud Functions before releasing the updated Flutter client; old clients may still publish a card with 5+ images and hit a denied write until updated.
3. Test name-only draft, 29/30-character description boundaries, photo add/replace/remove, pending requests, approval, deletion and restoration on two devices.
4. Confirm the corresponding backend Firebase projects match the Flutter build. Do not infer production deployment from merging the repository changes.

## Not in this phase

The separate private “מה אני מחפש/ת” data, independent grants, recording import/share, personal-home redesign, and married-couple shared databases are separate work. This document does not claim those features are present.
