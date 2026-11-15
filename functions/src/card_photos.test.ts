import { test } from 'node:test';
import assert from 'node:assert/strict';
import { databaseUidOf, mayReadCardPhoto, validPhotoPath } from './card_photos';

const owner = 'owner1';
const path = `personalCards/${owner}/a.jpg`;
const card = { deleted: false, photoPaths: [path, `personalCards/${owner}/b.jpg`] };
const solo = {
  status: 'approved',
  cardGranted: true,
  matchmakerUid: 'm1',
  granteeUids: ['m1'],
};

test('an approved matchmaker receives a photo that is on the card', () => {
  assert.equal(
    mayReadCardPhoto({ uid: 'm1', ownerUid: owner, path, card, membership: undefined, grant: solo }),
    true,
  );
  // A grant from before granteeUids existed.
  assert.equal(
    mayReadCardPhoto({
      uid: 'm1', ownerUid: owner, path, card, membership: undefined,
      grant: { status: 'approved', matchmakerUid: 'm1' },
    }),
    true,
  );
});

test('pending, declined, revoked, card-not-granted and somebody else are refused', () => {
  for (const grant of [
    { ...solo, status: 'pending' },
    { ...solo, status: 'declined' },
    { ...solo, status: 'revoked' },
    { ...solo, cardGranted: false },
    { ...solo, matchmakerUid: 'other' },
    { ...solo, granteeUids: ['m1', 'm2'] },
    undefined,
  ]) {
    assert.equal(
      mayReadCardPhoto({ uid: 'm1', ownerUid: owner, path, card, membership: undefined, grant }),
      false,
    );
  }
});

test('a deleted card, or a photo no longer on it, serves nothing', () => {
  assert.equal(
    mayReadCardPhoto({
      uid: 'm1', ownerUid: owner, path, membership: undefined, grant: solo,
      card: { ...card, deleted: true },
    }),
    false,
  );
  assert.equal(
    mayReadCardPhoto({
      uid: 'm1', ownerUid: owner, path: `personalCards/${owner}/removed.jpg`,
      card, membership: undefined, grant: solo,
    }),
    false,
  );
  assert.equal(
    mayReadCardPhoto({ uid: 'm1', ownerUid: owner, path, card: undefined, membership: undefined, grant: solo }),
    false,
  );
});

test('a couple reads through the shared database grant naming both', () => {
  const membership = { databaseUid: 'db1', members: ['m1', 'm2'], state: 'active' };
  assert.equal(databaseUidOf('m1', membership), 'db1');
  assert.equal(databaseUidOf('m1', undefined), 'm1');
  const grant = { status: 'approved', matchmakerUid: 'db1', granteeUids: ['m2', 'm1'] };
  assert.equal(
    mayReadCardPhoto({ uid: 'm1', ownerUid: owner, path, card, membership, grant }),
    true,
  );
  assert.equal(
    mayReadCardPhoto({
      uid: 'm1', ownerUid: owner, path, card, membership,
      grant: { ...grant, granteeUids: ['m1'] },
    }),
    false,
  );
  assert.equal(
    mayReadCardPhoto({
      uid: 'm1', ownerUid: owner, path, card,
      membership: { ...membership, state: 'closed' }, grant,
    }),
    false,
  );
});

test('only a path straight under the owner folder is accepted', () => {
  assert.equal(validPhotoPath(owner, path), true);
  assert.equal(validPhotoPath(owner, `personalCards/other/a.jpg`), false);
  assert.equal(validPhotoPath(owner, `personalCards/${owner}/x/a.jpg`), false);
  assert.equal(validPhotoPath(owner, `personalCards/${owner}/..`), false);
  assert.equal(validPhotoPath(owner, `users/${owner}/photos/a.jpg`), false);
  assert.equal(validPhotoPath(owner, 42), false);
  // The owner always reads their own.
  assert.equal(
    mayReadCardPhoto({ uid: owner, ownerUid: owner, path, card: undefined, membership: undefined, grant: undefined }),
    true,
  );
});
