import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  validSharedPhotoPath,
  mayReadSharedPhoto,
  proposalNotice,
  proposalEvents,
  chatPreview,
  communityExposed,
  directChatId,
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

test('photos go to the owner and to the readers the card names only', () => {
  const path = 'sharedCards/a/p1/x.jpg';
  const base = { ownerUid: 'a', path, inProposal: false };
  assert.equal(mayReadSharedPhoto({ ...base, uid: 'a', card: undefined }), true);
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'b', card: { ownerUid: 'a', readers: ['b', 'c'] } }),
    true,
  );
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'd', card: { ownerUid: 'a', readers: ['b', 'c'] } }),
    false,
  );
  // A card row of somebody else never opens this owner's photos.
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'b', card: { ownerUid: 'x', readers: ['b'] } }),
    false,
  );
  assert.equal(mayReadSharedPhoto({ ...base, uid: 'b', card: undefined }), false);
  // An idea between the two keeps its photos after the share stops.
  assert.equal(mayReadSharedPhoto({ ...base, uid: 'b', card: undefined, inProposal: true }), true);
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
    'הרעיון נועה ודוד אושר',
  ]);
  assert.deepEqual(proposalEvents('approved', 'opened', {}, {}, names, 'נועה ודוד'), [
    'הרעיון נועה ודוד נפתח',
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
  const base = { ownerUid: 'a', path: 'partnerCards/a/p1/x.jpg', inProposal: false, card: undefined };
  assert.equal(validSharedPhotoPath('a', 'partnerCards/a/p1/x.jpg'), true);
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'b', partnership: { status: 'active', uids: ['a', 'b'] } }),
    true,
  );
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'b', partnership: { status: 'ended', uids: ['a', 'b'] } }),
    false,
  );
  // A share between matchmakers never opens a partner's database.
  assert.equal(
    mayReadSharedPhoto({ ...base, uid: 'c', card: { ownerUid: 'a', readers: ['c'] } }),
    false,
  );
});

test('approving opens the idea at once, said in one line', () => {
  assert.deepEqual(proposalEvents('pending', 'opened', {}, {}, {}, 'נועה ודוד'), [
    'הרעיון נועה ודוד אושר ונפתח',
  ]);
});

test('a push of a message without words says what it is', () => {
  assert.equal(chatPreview('voice', ''), 'הודעה קולית');
  assert.equal(chatPreview('image', '  '), 'תמונה');
  assert.equal(chatPreview('ideaOffer', ''), 'יש לי רעיון בשבילך');
  assert.equal(chatPreview('text', 'שלום'), 'שלום');
});

test('a conversation from the community: one id per pair, only somebody shown', () => {
  assert.equal(directChatId('bbb', 'aaa'), 'aaa_bbb');
  assert.equal(directChatId('aaa', 'bbb'), 'aaa_bbb');
  assert.equal(communityExposed(undefined), false);
  assert.equal(communityExposed({ hidden: true }), false);
  assert.equal(communityExposed({ hidden: false, name: 'x' }), true);
});
