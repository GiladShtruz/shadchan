import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/push_service.dart';

void main() {
  test('a friend\'s new card opens their profile at the access request', () {
    expect(
      PushService.routeOf(<String, dynamic>{
        'kind': 'cardCreated',
        'route': '/reminders',
        'ownerUid': 'u1',
        'ownerPhoneHash': 'abc',
      }),
      '/card-friend/u1?h=abc&focus=request',
    );
  });

  test('an approval opens the card itself', () {
    expect(
      PushService.routeOf(<String, dynamic>{
        'kind': 'accessApproved',
        'route': '/card-friend/u1',
        'ownerUid': 'u1',
        'ownerPhoneHash': '',
      }),
      '/card-friend/u1?focus=card',
    );
  });

  test('anything else follows the route the server attached', () {
    expect(
      PushService.routeOf(<String, dynamic>{
        'kind': 'accessRequest',
        'route': '/me?section=requests',
      }),
      '/me?section=requests',
    );
    expect(PushService.routeOf(<String, dynamic>{'kind': 'x'}), isNull);
  });
}
