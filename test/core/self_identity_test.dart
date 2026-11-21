import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/self_identity.dart';
import 'package:shadchan/utils/enums.dart';

Person _p(String id, {String? phone, String? owner}) {
  final DateTime now = DateTime(2026, 11, 1);
  return Person(
    id: id,
    firstName: id,
    lastName: '',
    gender: Gender.male,
    phone: phone,
    createdAt: now,
    updatedAt: now,
  )..cardOwnerUid = owner;
}

void main() {
  tearDown(SelfIdentity.reset);

  test(
    'the user is recognised by number, by their own card and by the old mirror',
    () {
      SelfIdentity.update(phone: '050-123-4567', uid: 'me');
      expect(SelfIdentity.isSelf(_p('a', phone: '+972501234567')), isTrue);
      expect(SelfIdentity.isSelf(_p('b', owner: 'me')), isTrue);
      expect(SelfIdentity.isSelf(_p('own-personal-card')), isTrue);
      expect(SelfIdentity.isSelf(_p('friend', phone: '0529999999')), isFalse);
      expect(SelfIdentity.isSelf(_p('other', owner: 'someone')), isFalse);
      expect(SelfIdentity.isOwnPhone('0501234567'), isTrue);
    },
  );

  test(
    'without a number of their own, nobody is taken for the user by phone',
    () {
      SelfIdentity.update(phone: '');
      expect(SelfIdentity.isSelf(_p('a', phone: '0501234567')), isFalse);
      expect(SelfIdentity.isOwnPhone('0501234567'), isFalse);
    },
  );

  test('signing out forgets who the user was', () {
    SelfIdentity.update(phone: '0501234567', uid: 'me');
    SelfIdentity.clear();
    expect(SelfIdentity.isSelf(_p('a', phone: '0501234567')), isFalse);
    expect(SelfIdentity.isSelf(_p('b', owner: 'me')), isFalse);
  });
}
