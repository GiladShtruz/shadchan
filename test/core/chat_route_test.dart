import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/chat_service.dart';

void main() {
  test('one id per pair, whoever opens it', () {
    expect(ChatService.directId('b', 'a'), 'a_b');
    expect(ChatService.directId('a', 'b'), 'a_b');
  });

  test('the other side is read off the id — before the chat exists', () {
    expect(ChatService.otherOfId('a_b', 'a'), 'b');
    expect(ChatService.otherOfId('a_b', 'b'), 'a');
    expect(ChatService.otherOfId('broken', 'a'), '');
  });

  test('the route carries the name, and an idea as context — never a role', () {
    expect(
      ChatService.routeTo(me: 'b', otherUid: 'a', theirName: 'דנה כהן'),
      '/chats/a_b?name=${Uri.encodeQueryComponent('דנה כהן')}',
    );
    // Opened from a shared idea: the same conversation, with its context.
    expect(
      ChatService.routeTo(me: 'b', otherUid: 'a', ideaId: 'p1'),
      '/chats/a_b?idea=p1',
    );
  });

  test('one send writes the conversation as a merge the rules accept', () {
    final DateTime now = DateTime(2026, 11, 21);
    final Map<String, Object?> w = ChatService.chatWriteFor(
      me: 'b',
      other: 'a',
      lastText: 'שלום',
      type: ChatMessageType.text,
      myName: 'בני',
      now: now,
    );
    expect(w['members'], <String>['a', 'b']);
    expect(w['type'], 'direct');
    expect(w['lastFromUid'], 'b');
    expect(w['readAt'], <String, Object>{'b': now});
    // Zero for the sender, one more for the other side.
    expect(w['unread'], <String, Object>{'b': 0, 'a': 1});
    expect(w['names'], <String, String>{'b': 'בני'});
    expect(w.containsKey('photos'), isFalse);
  });

  test('a conversation counts and previews what is waiting', () {
    final ChatThread t = ChatThread(
      id: 'a_b',
      members: const <String>['a', 'b'],
      names: const <String, String>{'a': 'דנה', 'b': 'בני'},
      lastText: '',
      lastType: ChatMessageType.voice,
      lastFromUid: 'a',
      lastAt: DateTime(2026, 11, 21, 10),
      unread: const <String, int>{'b': 3},
    );
    expect(t.titleFor('b'), 'דנה');
    expect(t.isUnreadFor('b'), isTrue);
    expect(t.unreadCountFor('b'), 3);
    expect(t.isUnreadFor('a'), isFalse);
    expect(t.previewFor('b'), 'הודעה קולית');
    expect(t.previewFor('a'), 'אני: הודעה קולית');
  });

  test('a system line never makes a conversation unread', () {
    final ChatThread t = ChatThread(
      id: 'a_b',
      members: const <String>['a', 'b'],
      names: const <String, String>{},
      lastText: 'הרעיון אושר',
      lastType: ChatMessageType.system,
      lastFromUid: 'system',
      lastAt: DateTime(2026, 11, 21, 10),
    );
    expect(t.isUnreadFor('a'), isFalse);
  });

  test('read marks are derived from the other side\'s readAt', () {
    final DateTime at = DateTime(2026, 11, 21, 10);
    final ChatMessage m = ChatMessage(id: 'm', fromUid: 'b', text: 'x', at: at);
    final ChatThread t = ChatThread(
      id: 'a_b',
      members: const <String>['a', 'b'],
      names: const <String, String>{},
      readAt: <String, DateTime>{'a': at.add(const Duration(minutes: 1))},
    );
    expect(m.readBy(t, 'a'), isTrue);
    expect(m.readBy(null, 'a'), isFalse);
  });
}
