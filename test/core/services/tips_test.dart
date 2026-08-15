import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/services/tips_service.dart';

/// The community tips, minus Firebase.
///
/// What is worth pinning down here is not the network call — it is the two
/// things that decide whether the feature is safe and whether the home screen
/// draws at all: who the app treats as the administrator, and the promise that
/// `TipsProvider`'s constructor is pure local I/O. If that second one ever
/// stops being true, every widget test that pumps the app hangs on Firebase.
void main() {
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('shadchan_tips_test');
    Hive.init(p.join(temp.path, 'hive'));
    await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    await Hive.box<dynamic>('settings').clear();
  });

  group('the administrator', () {
    test('is exactly one address, however it is capitalised', () {
      expect(TipsService.isAdminEmail('YITZ292@GMAIL.COM'), isTrue);
      expect(TipsService.isAdminEmail('yitz292@gmail.com'), isTrue);
      expect(TipsService.isAdminEmail(' Yitz292@Gmail.com '), isTrue);
    });

    test('is nobody else, and never a missing address', () {
      expect(
        TipsService.isAdminEmail('yitz292@gmail.com.evil.example'),
        isFalse,
      );
      expect(TipsService.isAdminEmail('someone@gmail.com'), isFalse);
      expect(TipsService.isAdminEmail(null), isFalse);
      expect(TipsService.isAdminEmail(''), isFalse);
    });
  });

  group('the local cache', () {
    test('is what the home screen reads, with no network on the way', () {
      final Box<dynamic> settings = Hive.box<dynamic>('settings');
      settings.put(
        'tips.approvedCache',
        jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 't1',
            'text': 'תזמון הוא חלק מהשידוך.',
            'authorName': 'רבקה לוי',
            'authorUid': 'u1',
            'status': 'approved',
            'createdAt': 1,
          },
        ]),
      );

      final TipsProvider tips = TipsProvider(settings, enabled: false);
      expect(tips.approved, hasLength(1));
      expect(tips.approved.single.text, 'תזמון הוא חלק מהשידוך.');
      expect(tips.approved.single.authorName, 'רבקה לוי');
    });

    test('unreadable storage is an empty rotation, not a crash', () {
      final Box<dynamic> settings = Hive.box<dynamic>('settings');
      settings.put('tips.approvedCache', 'not json at all');
      expect(TipsProvider(settings, enabled: false).approved, isEmpty);
    });

    test('a disabled provider never leaves the device', () async {
      final TipsProvider tips = TipsProvider(
        Hive.box<dynamic>('settings'),
        enabled: false,
      );
      // Every one of these would reach Firebase if the seam were not honoured;
      // under `flutter test` that hangs the suite rather than failing it.
      await tips.refreshApproved();
      await tips.refreshMine();
      await tips.refreshPending();
      expect(await tips.submit(text: 'משהו', authorName: 'מישהי'), isFalse);
      expect(tips.mine, isEmpty);
      expect(tips.pending, isEmpty);
    });
  });

  group('a stored tip', () {
    test('survives a round trip through the cache', () {
      final CommunityTip tip = CommunityTip(
        id: 't',
        text: 'אנשים משתנים.',
        authorName: 'מרים',
        authorUid: 'u',
        status: TipStatus.approved,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1234),
      );
      final CommunityTip? back = CommunityTip.fromJson(tip.toJson());
      expect(back, isNotNull);
      expect(back!.text, tip.text);
      expect(back.authorName, tip.authorName);
      expect(back.status, TipStatus.approved);
      expect(back.createdAt, tip.createdAt);
    });

    test('an empty tip is dropped rather than shown blank', () {
      expect(
        CommunityTip.fromJson(<String, Object?>{'id': 't', 'text': '   '}),
        isNull,
      );
      expect(CommunityTip.fromJson('nonsense'), isNull);
    });

    test('an unknown status reads as pending, never as approved', () {
      expect(TipStatus.byName('published'), TipStatus.pending);
      expect(TipStatus.byName(null), TipStatus.pending);
      expect(TipStatus.byName('approved'), TipStatus.approved);
    });
  });
}
