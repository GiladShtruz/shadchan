import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/analytics_service.dart';
import 'package:shadchan/services/telemetry.dart';
import 'package:shadchan/utils/app_router.dart';

/// The monitoring's one way in: a small taxonomy, codes only, never blocking.
void main() {
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];

  setUp(() {
    Telemetry.resetForTest();
    events.clear();
    Telemetry.debugSink = events.add;
  });

  tearDown(Telemetry.resetForTest);

  test('four generic event types, with the feature and action as fields', () {
    Telemetry.opened(AppFeature.matches);
    Telemetry.started(AppFeature.add_contacts, 'pick');
    Telemetry.completed(AppFeature.idea_open, 'create');
    Telemetry.failed(AppFeature.whatsapp_share, 'card', TimeoutException('x'));
    expect(events.map((Map<String, Object?> e) => e['t']), <String>[
      'open',
      'start',
      'done',
      'fail',
    ]);
    expect(events[1]['f'], 'add_contacts');
    expect(events[1]['a'], 'pick');
    expect(events[3]['e'], 'timeout');
  });

  test('every event has its own id, the time and the session', () {
    Telemetry.opened(AppFeature.home);
    Telemetry.opened(AppFeature.home);
    expect(events[0]['id'], isNot(events[1]['id']));
    expect(events[0]['s'], events[1]['s']);
    expect(events[0]['ts'], isA<int>());
  });

  test('errors and actions are reduced to short codes — never a message', () {
    expect(
      Telemetry.code(FirebaseException(plugin: 'x', code: 'permission-denied')),
      'permission_denied',
    );
    expect(
      Telemetry.code(const SocketException('a phone 0521234567')),
      'network',
    );
    expect(Telemetry.code(StateError('יוסי כהן')), 'stateerror');
    expect(Telemetry.code('Save Card!'), 'save_card_');
  });

  test('track records start, then done or fail, with the duration', () async {
    await Telemetry.track(AppFeature.chats, 'send', () async => 1);
    await expectLater(
      Telemetry.track(
        AppFeature.chats,
        'send',
        () async => throw StateError('x'),
      ),
      throwsStateError,
    );
    expect(events.map((Map<String, Object?> e) => e['t']), <String>[
      'start',
      'done',
      'start',
      'fail',
    ]);
    expect(events[1]['ms'], isA<int>());
  });

  test('an AI call carries metadata only', () {
    Telemetry.aiCall(
      feature: AppFeature.ai_import,
      model: 'gemini-4-hydrogen',
      inputTokens: 1200,
      outputTokens: 300,
      latencyMs: 2400,
      ok: true,
      tries: 2,
    );
    final Map<String, Object?> e = events.single;
    expect(e['t'], 'ai');
    expect(e['f'], 'ai_import');
    expect(e['ms'], 2400);
    expect(e['x'], <String, Object?>{
      'model': 'gemini_4_hydrogen',
      'in': 1200,
      'out': 300,
      'ok': true,
      'tries': 2,
    });
  });

  test('a step completed elsewhere is matched once, within five minutes', () {
    Telemetry.expect('idea', AppFeature.matches, 'idea');
    Telemetry.fulfil('idea');
    Telemetry.fulfil('idea');
    expect(
      events.where((Map<String, Object?> e) => e['a'] == 'idea'),
      hasLength(1),
    );
  });

  group('with the usage opt-out on', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('telemetry');
      Hive.init(dir.path);
      final Box<dynamic> settings = await Hive.openBox<dynamic>('settings');
      await settings.put(Analytics.optOutKey, 'true');
    });
    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('usage stops; AI cost records are still kept', () {
      Telemetry.opened(AppFeature.home);
      Telemetry.completed(AppFeature.idea_open, 'create');
      Telemetry.aiCall(
        feature: AppFeature.ai_card,
        model: 'm',
        inputTokens: 1,
        outputTokens: 1,
        latencyMs: 1,
        ok: true,
      );
      expect(events.map((Map<String, Object?> e) => e['t']), <String>['ai']);
    });
  });

  test('every page has a fixed feature id', () {
    expect(AppRouter.featureOf('/home'), AppFeature.home);
    expect(AppRouter.featureOf('/people'), AppFeature.people);
    expect(AppRouter.featureOf('/people/3f2a-9c'), AppFeature.card_open);
    expect(AppRouter.featureOf('/people/import'), AppFeature.add_contacts);
    expect(AppRouter.featureOf('/people/add'), AppFeature.add_manual);
    expect(AppRouter.featureOf('/people/ai'), AppFeature.ai);
    expect(AppRouter.featureOf('/matches'), AppFeature.ideas);
    expect(AppRouter.featureOf('/chats/a_b'), AppFeature.chats);
    expect(
      AppRouter.featureOf('/network/sharing'),
      AppFeature.database_sharing,
    );
    expect(
      AppRouter.featureOf('/known-matchmakers/x'),
      AppFeature.partner_matchmakers,
    );
    expect(AppRouter.featureOf('/me/matchmakers'), AppFeature.my_matchmakers);
    expect(AppRouter.featureOf('/reminders'), AppFeature.notifications);
    expect(AppRouter.featureOf('/something-new'), AppFeature.other);
  });
}
