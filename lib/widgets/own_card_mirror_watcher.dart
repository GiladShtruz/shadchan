import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/own_card_mirror.dart';
import 'package:shadchan/services/workspace_store.dart';

/// Keeps the matchmaker's own personal card in their database
/// ([OwnCardMirror]): once after the first frame, and again a moment after
/// every save of the card (or of "המספר שלי", which becomes its phone).
///
/// Above the router, like `AchievementWatcher`: the card is saved from the
/// personal area, and the database it lands in belongs to the other area.
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
  bool _running = false;
  bool _again = false;

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
    _debounce?.cancel();
    _card?.removeListener(_onChanged);
    _profile?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(_settleAfter, _sync);
  }

  Future<void> _sync() async {
    final PersonalCardProvider? card = _card;
    if (!mounted || card == null || !card.hasCard) {
      return;
    }
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    final PersonRepository people = context.read<PersonRepository>();
    try {
      // Plain background I/O, like `persistHomeSetting`: the writes must not
      // belong to whichever zone the card happened to be saved from.
      await Zone.root.run(
        () => OwnCardMirror.sync(
          card: card.card,
          cardIsLive: card.hasCard,
          matchmakerEnabled: WorkspaceStore.matchmakerEnabled,
          people: people,
          myPhone: _profile?.myPhone,
        ),
      );
    } catch (error) {
      debugPrint('OwnCardMirrorWatcher: $error');
    } finally {
      _running = false;
    }
    if (_again && mounted) {
      _again = false;
      unawaited(_sync());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
