import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/incoming_backup_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel methodChannel = MethodChannel(
    'shadchan/incoming_backup_files/methods',
  );
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final IncomingBackupFileService service = IncomingBackupFileService.instance;

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test(
    'takePendingFilePaths returns incoming file paths from the platform',
    () async {
      messenger.setMockMethodCallHandler(methodChannel, (
        MethodCall call,
      ) async {
        if (call.method == 'takePendingFilePaths') {
          return <String>[
            'C:\\temp\\backup_a.json',
            '',
            'C:\\temp\\backup_b.json',
          ];
        }

        return null;
      });

      final List<String> paths = await service.takePendingFilePaths();

      expect(paths, <String>[
        'C:\\temp\\backup_a.json',
        'C:\\temp\\backup_b.json',
      ]);
    },
  );

  test(
    'takePendingFilePaths returns an empty list when the platform is unavailable',
    () async {
      messenger.setMockMethodCallHandler(methodChannel, null);

      final List<String> paths = await service.takePendingFilePaths();

      expect(paths, isEmpty);
    },
  );
}
