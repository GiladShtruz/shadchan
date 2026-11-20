import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  validSharedPhotoPath,
  mayReadSharedPhoto,
  proposalNotice,
  proposalEvents,
  sideEvent,
  allowsOnward,
  granteesOf,
} from './network';
import { categoryOf } from './notices';

const row = (data: Record<string, unknown>) => ({ get: (f: string) => data[f] });

test('a shared photo path is exactly sharedCards/{owner}/{person}/{file}', () => {
  assert.equal(validSharedPhotoPath('a', 'sharedCards/a/p1/x.jpg'), true);
  assert.equal(validSharedPhotoPath('a', 'sharedCards/b/p1/x.jpg'), false);
  assert.equal(validSharedPhotoPath('a', 'sharedCards/a/../x.jpg'), false);
  assert.equal(validSharedPhotoPath('a', 'personalCards/a/x.jpg'), false);
  assert.equal(validSharedPhotoPath('a', 'sharedCards/a/p1/x/y.jpg'), false);
});

test('photos go to the owner and to an approved connection only', () => {
  const path = 'sharedCards/a/p1/x.jpg';
  const base = { ownerUid: 'a', path, inProposal: false };
  assert.equal(mayReadSharedPhoto({ ...base, uid: 'a', connection: undefined }), true);
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'b', connection: { status: 'approved', uids: ['a', 'b'] } }),
    true,
  );
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'b', connection: { status: 'pending', uids: ['a', 'b'] } }),
    false,
  );
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'c', connection: { status: 'approved', uids: ['a', 'b'] } }),
    false,
  );
  assert.equal(mayReadSharedPhoto({ ...base, uid: 'b', connection: undefined }), false);
  // An idea between the two keeps its photos after a disconnect.
  assert.equal(mayReadSharedPhoto({ ...base, uid: 'b', connection: undefined, inProposal: true }), true);
});

test('an idea proposal tells the side asked, and the asker of a yes', () => {
  const doc = {
    fromName: 'יונתן',
    toName: 'שרה',
    candidate: { firstName: 'נועה' },
    target: { firstName: 'דוד' },
    id: 'x',
  };
  const asked = proposalNotice(null, 'pending', doc)!;
  assert.equal(asked.to, 'to');
  assert.equal(asked.kind, 'ideaProposal');
  assert.match(asked.body, /נועה ודוד/);
  const yes = proposalNotice('pending', 'approved', doc)!;
  assert.equal(yes.to, 'from');
  // Network activity is never pushed — it waits in the chat and the inbox.
  assert.equal(asked.push, false);
  assert.equal(yes.push, false);
  const no = proposalNotice('pending', 'declined', doc)!;
  assert.equal(no.push, false);
  assert.equal(proposalNotice('approved', 'approved', doc), null);
});

test('a proposal writes small system lines into the pair\'s chat', () => {
  const names = { a: 'יונתן כהן', b: 'שרה לוי' };
  assert.deepEqual(proposalEvents('pending', 'approved', {}, {}, names, 'נועה ודוד'), [
    'הרעיון נועה ודוד אושר ונפתח',
  ]);
  assert.deepEqual(
    proposalEvents('approved', 'approved', { a: { status: 'idea' } }, { a: { status: 'unavailable' } }, names, 'נועה ודוד'),
    ['נועה ודוד: עבר להמתנה (אצל יונתן)'],
  );
  assert.deepEqual(
    proposalEvents('approved', 'approved', {}, { b: { status: 'idea' } }, names, 'נועה ודוד'),
    [],
  );
  assert.equal(sideEvent('dating', 'dated'), 'הרעיון נסגר');
  assert.equal(sideEvent('unavailable', 'idea'), 'הרעיון חזר להיות פתוח');
});

test('consent to show a card onward needs an approved grant with shareOnward', () => {
  assert.equal(allowsOnward(row({ status: 'approved', shareOnward: true })), true);
  assert.equal(allowsOnward(row({ status: 'approved' })), false);
  assert.equal(allowsOnward(row({ status: 'revoked', shareOnward: true })), false);
  assert.equal(allowsOnward(undefined), false);
  assert.deepEqual(granteesOf(row({ matchmakerUid: 'm', granteeUids: ['x', 'y'] })), ['x', 'y', 'm']);
});

test('network notices sit under their own switches', () => {
  assert.equal(categoryOf('ideaProposal'), 'network');
  assert.equal(categoryOf('ideaProposalApproved'), 'network');
  assert.equal(categoryOf('chatMessage'), 'chats');
  assert.equal(categoryOf('shareOnwardRequest'), 'access');
});

test('a partner photo reaches the partner only while the couple space is active', () => {
  const base = { ownerUid: 'a', path: 'partnerCards/a/p1/x.jpg', inProposal: false, connection: undefined };
  assert.equal(validSharedPhotoPath('a', 'partnerCards/a/p1/x.jpg'), true);
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'b', partnership: { status: 'active', uids: ['a', 'b'] } }),
    true,
  );
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'b', partnership: { status: 'ended', uids: ['a', 'b'] } }),
    false,
  );
  // A connection between matchmakers never opens a partner's database.
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'c', connection: { status: 'approved', uids: ['a', 'c'] } }),
    false,
  );
});
