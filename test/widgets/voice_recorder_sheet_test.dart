import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/dialogs/voice_recorder_sheet.dart';

void main() {
  late Directory dir;
  final List<String> calls = <String>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rec');
    calls.clear();
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => dir.path,
    );
    String? path;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (MethodCall call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'hasPermission':
            return true;
          case 'start':
            path = (call.arguments as Map<Object?, Object?>)['path'] as String?;
            File(path!).writeAsBytesSync(<int>[0, 1, 2]);
            return null;
          case 'stop':
            return path;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on Object {
      // Already gone.
    }
  });

  testWidgets(
    'recording shows a microphone, never a stop square; then a take to review',
    (WidgetTester tester) async {
      VoiceRecording? result;
      // The recorder's state stream has no platform side in a test.
      final previous = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exception is MissingPluginException) return;
        previous?.call(details);
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () async =>
                    result = await VoiceRecorderSheet.record(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('go'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(VoiceRecorderSheet.recordingTitle), findsOneWidget);
      expect(find.text('מקליט…'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
      expect(find.byIcon(Icons.videocam_rounded), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey<String>('voice-finish')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // The take: listen, record again, delete or keep.
      expect(find.text(VoiceRecorderSheet.reviewTitle), findsOneWidget);
      expect(find.text(VoiceRecorderSheet.againLabel), findsOneWidget);
      expect(find.byTooltip('מחיקה'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(result, isNull);

      await tester.tap(find.byKey(const ValueKey<String>('voice-save')));
      await tester.pumpAndSettle();
      // The sheet was opened from real async (the recorder's channel), so its
      // answer lands there too.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(result, isNotNull);
      expect(
        calls,
        containsAllInOrder(<String>['hasPermission', 'start', 'stop']),
      );
      FlutterError.onError = previous;
    },
  );
}
