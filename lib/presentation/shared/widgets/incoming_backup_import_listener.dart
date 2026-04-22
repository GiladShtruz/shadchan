import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/core/services/backup_service.dart';
import 'package:shadchan/core/services/incoming_backup_file_service.dart';
import 'package:shadchan/data/repositories/match_repository.dart';
import 'package:shadchan/data/repositories/person_repository.dart';
import 'package:shadchan/presentation/shared/backup_import_feedback.dart';

class IncomingBackupImportListener extends StatefulWidget {
  IncomingBackupImportListener({
    required this.child,
    IncomingBackupFilesSource? fileService,
    super.key,
  }) : fileService = fileService ?? IncomingBackupFileService.instance;

  final Widget child;
  final IncomingBackupFilesSource fileService;

  @override
  State<IncomingBackupImportListener> createState() =>
      _IncomingBackupImportListenerState();
}

class _IncomingBackupImportListenerState
    extends State<IncomingBackupImportListener> {
  final Queue<String> _pendingPaths = Queue<String>();

  StreamSubscription<String>? _incomingFilesSubscription;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _incomingFilesSubscription = widget.fileService.incomingFiles.listen(
      _enqueuePath,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPendingPaths());
    });
  }

  @override
  void dispose() {
    _incomingFilesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _loadPendingPaths() async {
    final List<String> pendingPaths = await widget.fileService
        .takePendingFilePaths();
    for (final String path in pendingPaths) {
      _enqueuePath(path);
    }
  }

  void _enqueuePath(String path) {
    if (path.isEmpty) {
      return;
    }

    _pendingPaths.add(path);
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    if (_isProcessing || !mounted || _pendingPaths.isEmpty) {
      return;
    }

    _isProcessing = true;
    final PersonRepository personRepo = context.read<PersonRepository>();
    final MatchRepository matchRepo = context.read<MatchRepository>();

    while (mounted && _pendingPaths.isNotEmpty) {
      final String path = _pendingPaths.removeFirst();

      try {
        final ImportResult result = await BackupService.importData(
          File(path),
          personRepo,
          matchRepo,
        );

        if (!mounted) {
          return;
        }

        await BackupImportFeedback.showResultDialog(context, result);
      } on FormatException catch (error) {
        if (!mounted) {
          return;
        }

        BackupImportFeedback.showImportError(context, error);
      } catch (error) {
        if (!mounted) {
          return;
        }

        BackupImportFeedback.showImportError(context, error);
      }
    }

    _isProcessing = false;
  }
}
