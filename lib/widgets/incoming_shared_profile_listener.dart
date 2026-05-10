import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:shadchan/services/incoming_shared_profile_service.dart';
import 'package:shadchan/utils/app_router.dart';

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

  Future<void> _processQueue() async {
    if (_isProcessing || !mounted || _pendingDrafts.isEmpty) {
      return;
    }

    _isProcessing = true;

    while (mounted && _pendingDrafts.isNotEmpty) {
      final IncomingSharedProfileDraft draft = _pendingDrafts.removeFirst();
      await AppRouter.router.push<void>('/people/shared-import', extra: draft);
    }

    _isProcessing = false;
  }
}
