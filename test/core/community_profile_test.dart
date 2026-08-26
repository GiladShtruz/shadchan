import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/community_profile.dart';

/// The matchmaker's public page: what survives a round trip through the shared
/// collection, and what a badly written document cannot do to the screen that
/// reads it.
///
/// Everything here is data written by *another client*. It goes into a
/// collection every installed copy of the app can read and write its own row
/// in, so the decoder's job is not to be clever — it is to be impossible to
/// break.
void main() {
  group('MatchmakerShare', () {
    test('survives a round trip, separator in the answer included', () {
      const MatchmakerShare share = MatchmakerShare(
        kind: MatchmakerShareKind.region,
        // The encoding splits on the first `|` only, so one inside the answer
        // is part of the answer.
        text: 'השרון | המרכז',
      );

      final MatchmakerShare? back = MatchmakerShare.decode(share.encode());

      expect(back?.kind, MatchmakerShareKind.region);
      expect(back?.text, 'השרון | המרכז');
    });

    test('refuses everything that is not a filled-in prompt', () {
      expect(MatchmakerShare.decode(null), isNull);
      expect(MatchmakerShare.decode(42), isNull);
      expect(MatchmakerShare.decode(''), isNull);
      // No separator at all.
      expect(MatchmakerShare.decode('region'), isNull);
      // A prompt this build has never heard of.
      expect(MatchmakerShare.decode('astrology|מזל דגים'), isNull);
      // A separator with nothing after it is an empty answer, which is the
      // same as not having answered.
      expect(MatchmakerShare.decode('region|   '), isNull);
      // And an empty prompt name is not a prompt.
      expect(MatchmakerShare.decode('|השרון'), isNull);
    });

    test('an over-long answer is cut, not dropped', () {
      final String long = 'א' * (MatchmakerShare.maxLength + 40);

      final MatchmakerShare? share = MatchmakerShare.decode('role|$long');

      expect(share, isNotNull);
      expect(share!.text.length, MatchmakerShare.maxLength);
    });

    test('answers come back in prompt order, one per prompt', () {
      // Written out of order, and with the same prompt twice — which is what a
      // stored list from an older build, or a hand-edited document, can look
      // like. The first answer for a prompt wins and the rest are dropped: a
      // profile that showed "שדכן/ית של אזור" twice would read as a bug.
      final List<MatchmakerShare> shares = MatchmakerShare.decodeAll(<Object?>[
        'more|אשמח להכיר',
        'origin|פתח תקווה',
        'origin|ירושלים',
        'nonsense',
      ]);

      expect(
        shares.map((MatchmakerShare share) => share.kind),
        <MatchmakerShareKind>[
          MatchmakerShareKind.origin,
          MatchmakerShareKind.more,
        ],
      );
      expect(shares.first.text, 'פתח תקווה');
    });
  });

  group('CommunityProfile.fromDocument', () {
    test('reads a full page', () {
      final CommunityProfile profile = CommunityProfile.fromDocument(
        'uid-1',
        <String, dynamic>{
          'name': ' רבקה כהן ',
          'photoUrl': 'https://example.test/a.jpg',
          'about': 'אוהבת לחבר בין אנשים',
          'shares': <String>['origin|פתח תקווה', 'role|רכזת בוגרות'],
          'benefit': 'שיחת ייעוץ ללא תשלום',
          'contactPhone': '0501234567',
        },
      );

      expect(profile.uid, 'uid-1');
      expect(profile.name, 'רבקה כהן');
      expect(profile.about, 'אוהבת לחבר בין אנשים');
      expect(profile.shares, hasLength(2));
      expect(profile.benefit, 'שיחת ייעוץ ללא תשלום');
      expect(profile.contactPhone, '0501234567');
      expect(profile.hasDetails, isTrue);
    });

    test('a row with nothing on it is a name and no details', () {
      final CommunityProfile profile = CommunityProfile.fromDocument(
        'uid-2',
        <String, dynamic>{'name': '', 'weekActions': 12},
      );

      // The board's own fallback, so a member whose name was never stored is
      // still a person rather than a blank line.
      expect(profile.name, 'שדכן');
      expect(profile.hasDetails, isFalse);
      expect(profile.shares, isEmpty);
    });

    test('fields of the wrong type are ignored rather than thrown on', () {
      final CommunityProfile profile = CommunityProfile.fromDocument(
        'uid-3',
        <String, dynamic>{
          'name': 'דוד',
          'about': 17,
          'shares': 'not-a-list',
          'benefit': <String>['no'],
          'contactPhone': null,
        },
      );

      expect(profile.about, isEmpty);
      expect(profile.shares, isEmpty);
      expect(profile.benefit, isEmpty);
      expect(profile.contactPhone, isEmpty);
      expect(profile.hasDetails, isFalse);
    });

    test('an over-long field is cut to the length the rules allow', () {
      final CommunityProfile profile =
          CommunityProfile.fromDocument('uid-4', <String, dynamic>{
            'name': 'שרה',
            'about': 'א' * (CommunityProfile.maxAboutLength + 100),
            'benefit': 'ב' * (CommunityProfile.maxBenefitLength + 100),
          });

      expect(profile.about.length, CommunityProfile.maxAboutLength);
      expect(profile.benefit.length, CommunityProfile.maxBenefitLength);
    });
  });
}
