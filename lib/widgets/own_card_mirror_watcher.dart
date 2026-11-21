import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/own_card_mirror.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/self_identity.dart';
import 'package:shadchan/services/workspace_store.dart';

/// Keeps the app's idea of who the user is ([SelfIdentity]) current — once
/// after the first frame, and again a moment after every change of the card
/// or of "המספר שלי" — so the user never appears in their own database.
///
/// It used to mirror the personal card into the database ([OwnCardMirror]);
/// that is retired: the user is never one of their own friends.
class OwnCardMirrorWatcher extends StatefulWidget {
  const OwnCardMirrorWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<OwnCardMirrorWatcher> createState() => _OwnCardMirrorWatcherState();
}

class _OwnCardMirrorWatcherState extends State<OwnCardMirrorWatcher> {
  static const Duration _settleAfter = Duration(milliseconds: 400);

  PersonalCardProvider? _card;
  UserProfileProvider? _profile;
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final PersonalCardProvider card;
    final UserProfileProvider profile;
    try {
      card = context.read<PersonalCardProvider>();
      profile = context.read<UserProfileProvider>();
    } on ProviderNotFoundException {
      return;
    }
    if (identical(card, _card) && identical(profile, _profile)) {
      return;
    }
    _card?.removeListener(_onChanged);
    _profile?.removeListener(_onChanged);
    _card = card..addListener(_onChanged);
    _profile = profile..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    FirebaseBootstrap.readyListenable.removeListener(_onFirebaseReady);
    _debounce?.cancel();
    _card?.removeListener(_onChanged);
    _profile?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(_settleAfter, _sync);
  }

  /// Keeps [SelfIdentity] in step with who the user is — their own number
  /// and their account — and retires the old own-card mirror: the user is
  /// never one of their own friends (2026-11-21).
  Future<void> _sync() async {
    if (!mounted) return;
    SelfIdentity.update(phone: _profile?.myPhone ?? '');
    if (WorkspaceStore.matchmakerEnabled) {
      try {
        await Zone.root.run(() async => OwnCardMirror.retire());
      } catch (error) {
        debugPrint('OwnCardMirrorWatcher: $error');
      }
    }
    if (FirebaseBootstrap.isReady) {
      final String? uid = await PersonalCardService.durableUid();
      if (mounted) SelfIdentity.update(uid: uid);
    } else if (!_waitingForFirebase) {
      _waitingForFirebase = true;
      FirebaseBootstrap.readyListenable.addListener(_onFirebaseReady);
    }
  }

  bool _waitingForFirebase = false;

  void _onFirebaseReady() {
    if (!FirebaseBootstrap.isReady) return;
    FirebaseBootstrap.readyListenable.removeListener(_onFirebaseReady);
    _waitingForFirebase = false;
    unawaited(_sync());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
