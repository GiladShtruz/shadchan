import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/utils/chat_search.dart';

void main() {
  test('a name answers by first name, surname, both, any order', () {
    expect(ChatSearch.nameMatches('יונתן כהן', 'יונ'), isTrue);
    expect(ChatSearch.nameMatches('יונתן כהן', 'כהן'), isTrue);
    expect(ChatSearch.nameMatches('יונתן כהן', 'כהן יונתן'), isTrue);
    expect(ChatSearch.nameMatches('יונתן כהן', 'לוי'), isFalse);
    // Final letters, niqqud and hyphens do not stand in the way.
    expect(ChatSearch.nameMatches('אברהם בן־דוד', 'אברהמ'), isTrue);
    expect(ChatSearch.nameMatches('אברהם בן־דוד', 'דוד'), isTrue);
    expect(ChatSearch.nameMatches('שָׂרָה', 'שרה'), isTrue);
  });

  test('a phone answers only from four digits, in any spelling', () {
    expect(ChatSearch.phoneMatches('+972 54-123-4567', '0541234'), isTrue);
    expect(ChatSearch.phoneMatches('054-1234567', '4567'), isTrue);
    expect(ChatSearch.phoneMatches('054-1234567', '45'), isFalse);
    expect(ChatSearch.phoneMatches(null, '0541234'), isFalse);
  });

  test('contacts: only the contacts given, no one twice, not those with a '
      'conversation, not me', () {
    const List<ChatContact> all = <ChatContact>[
      ChatContact(uid: 'a', name: 'יונתן כהן'),
      ChatContact(uid: 'a', name: 'יונתן כהן (כפול)'),
      ChatContact(uid: 'b', name: 'יונה לוי'),
      ChatContact(uid: 'c', name: 'יוסי', phone: '0541112222'),
      ChatContact(uid: 'me', name: 'יואב'),
    ];
    final List<String> found = ChatSearch.contacts(
      all,
      'יו',
      withThreads: <String>{'b'},
      me: 'me',
    ).map((ChatContact c) => c.uid).toList();
    expect(found.toSet(), <String>{'a', 'c'});
    expect(ChatSearch.contacts(all, '  '), isEmpty);
    expect(
      ChatSearch.contacts(all, '1112').map((ChatContact c) => c.uid),
      <String>['c'],
    );
  });

  group('outbox', () {
    tearDown(ChatOutbox.clear);

    ChatOutboxItem item(String id, {bool sending = false}) => ChatOutboxItem(
      localId: id,
      chatId: 'a_b',
      type: ChatMessageType.text,
      text: 'שלום',
      at: DateTime(2026),
      sending: sending,
    );

    test('a failed line stays until retried or deleted, never twice', () {
      ChatOutbox.fail(item('m1', sending: true));
      ChatOutbox.fail(item('m1'));
      expect(ChatOutbox.of('a_b'), hasLength(1));
      expect(ChatOutbox.of('a_b').single.sending, isFalse);
      ChatOutbox.markSending('m1');
      expect(ChatOutbox.of('a_b').single.sending, isTrue);
      ChatOutbox.remove('m1');
      expect(ChatOutbox.of('a_b'), isEmpty);
      expect(ChatOutbox.of('other'), isEmpty);
    });
  });

  test('a blocked conversation is read off the document', () {
    final ChatThread? t = ChatThread.fromMap('a_b', <String, dynamic>{
      'members': <String>['a', 'b'],
      'blockedBy': <String>['a'],
    });
    expect(t!.isBlocked, isTrue);
    expect(t.blockedByMe('a'), isTrue);
    expect(t.blockedByMe('b'), isFalse);
  });
}
