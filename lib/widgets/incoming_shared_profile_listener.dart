import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/services/incoming_shared_profile_service.dart';
import 'package:shadchan/utils/app_router.dart';
import 'package:shadchan/utils/import_file_kind.dart';

class IncomingSharedProfileListener extends StatefulWidget {
  IncomingSharedProfileListener({
    required this.child,
    IncomingSharedProfileSource? profileService,
    super.key,
  }) : profileService = profileService ?? IncomingSharedProfileService.instance;

  final Widget child;
  final IncomingSharedProfileSource profileService;

  @override
  State<IncomingSharedProfileListener> createState() =>
      _IncomingSharedProfileListenerState();
}

class _IncomingSharedProfileListenerState
    extends State<IncomingSharedProfileListener> {
  final Queue<IncomingSharedProfileDraft> _pendingDrafts =
      Queue<IncomingSharedProfileDraft>();

  StreamSubscription<IncomingSharedProfileDraft>? _incomingDraftsSubscription;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _incomingDraftsSubscription = widget.profileService.incomingDrafts.listen(
      _enqueueDraft,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPendingDrafts());
    });
  }

  @override
  void dispose() {
    _incomingDraftsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _loadPendingDrafts() async {
    final List<IncomingSharedProfileDraft> pendingDrafts = await widget
        .profileService
        .takePendingDrafts();
    for (final IncomingSharedProfileDraft draft in pendingDrafts) {
      _enqueueDraft(draft);
    }
  }

  void _enqueueDraft(IncomingSharedProfileDraft draft) {
    if (!draft.hasContent) {
      return;
    }

    _pendingDrafts.add(draft);
    unawaited(_processQueue());
  }

  /// Opens a screen for every share that has arrived.
  ///
  /// **Nothing here waits for the screen it opened to close.** It used to, and
  /// that is what made a second share do nothing at all: the intake screen
  /// leaves by `pushReplacement`, which drops the imperative route go_router
  /// was holding the completer for, so the future returned by `push` never
  /// completed. `_isProcessing` then stayed true for the rest of the launch,
  /// and every later share only brought the app forward onto whatever screen
  /// it had been left on. A share must always land in the intake flow, so the
  /// latch now only guards against two drafts racing onto the same frame, and
  /// it is released in a `finally` either way.
  Future<void> _processQueue() async {
    if (_isProcessing || !mounted || _pendingDrafts.isEmpty) {
      return;
    }

    _isProcessing = true;
    try {
      while (mounted && _pendingDrafts.isNotEmpty) {
        final IncomingSharedProfileDraft draft = _pendingDrafts.removeFirst();

        // A spreadsheet or a chat export is a batch of people, not one
        // profile, so it goes to the AI import instead of the single-contact
        // form. Checked before the profile route because such a file would
        // otherwise land there as an unreadable attachment.
        final String? importable = ImportFileKinds.firstSupported(
          draft.filePaths,
        );
        // A voice note is filed under a friend's notes, not made into a card.
        final bool voice =
            draft.filePaths.isNotEmpty &&
            draft.filePaths.any(VoiceNoteStore.isAudioPath);
        unawaited(
          importable != null
              ? AppRouter.router.push<void>('/people/ai', extra: importable)
              : voice
              ? AppRouter.router.push<void>(
                  '/people/shared-voice',
                  extra: draft,
                )
              : AppRouter.router.push<void>(
                  '/people/shared-import',
                  extra: draft,
                ),
        );

        // Let the push reach the navigator before the next draft is pushed
        // over it, so two shares arriving together still stack in order.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _isProcessing = false;
    }
  }
}
