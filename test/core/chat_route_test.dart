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

  test('the route carries the name and the kind for the first message', () {
    expect(
      ChatService.routeTo(me: 'b', otherUid: 'a', theirName: 'דנה כהן'),
      '/chats/a_b?name=${Uri.encodeQueryComponent('דנה כהן')}',
    );
    expect(
      ChatService.routeTo(me: 'b', otherUid: 'a', kind: 'single'),
      '/chats/a_b?kind=single',
    );
  });
}
