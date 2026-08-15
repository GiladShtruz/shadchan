import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/screens/person_detail_screen.dart';
import 'package:shadchan/providers/add_contacts_session.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/add_contacts_common.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/initials_avatar.dart';

/// The swipe half of the add-friends screen.
///
/// It shows exactly the same contacts as the list view and counts exactly the
/// same progress — both read [AddContactsSession]. The only difference is that
/// here they arrive one card at a time.
class SwipeImportScreen extends StatefulWidget {
  const SwipeImportScreen({
    super.key,
    this.embedded = false,
    this.isActive = true,
  });

  final bool embedded;

  /// False while the list view is the one on screen. The deck is re-synced with
  /// the session when this turns true again, so contacts handled in the list
  /// never come back as cards.
  final bool isActive;

  @override
  State<SwipeImportScreen> createState() => _SwipeImportScreenState();
}

enum _SwipeAction { accept, reject, defer }

class _SwipeHistoryEntry {
  _SwipeHistoryEntry({
    required this.action,
    required this.candidate,
    this.importedCounted = false,
  });

  final _SwipeAction action;
  final ContactImportCandidate candidate;
  String? importedPersonId;
  bool importedCounted;
  bool wasUndone = false;
}

class _SwipeImportScreenState extends State<SwipeImportScreen> {
  /// Remembers that the swipe hint was already shown, so it only ever greets a
  /// first-time user.
  static const String _settingsBoxName = 'settings';
  static const String _hintSeenKey = 'swipeImportHintSeen';

  final CardSwiperController _controller = CardSwiperController();

  /// The cards currently in the stack. Taken from the session and refreshed
  /// whenever this view comes back to the front.
  List<ContactImportCandidate>? _deck;

  int _addedCount = 0;
  int _skippedCount = 0;
  bool _isFinished = false;
  bool _hintSeen = true;
  final List<_SwipeHistoryEntry> _history = <_SwipeHistoryEntry>[];

  /// Bumped whenever the deck contents change so the [CardSwiper] is rebuilt
  /// from scratch instead of reusing a stale index.
  int _deckGeneration = 0;

  /// Contacts the user chose to come back to later this session ("דילוג"). They
  /// are neither imported nor removed; once the main deck is done they can be
  /// reviewed again.
  final List<ContactImportCandidate> _deferredCandidates =
      <ContactImportCandidate>[];

  @override
  void initState() {
    super.initState();
    _loadHintSeen();
  }

  @override
  void didUpdateWidget(SwipeImportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      // Coming back from the list: whatever was added or removed there is
      // reflected here immediately rather than at the next visit.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() => _deck = null);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _loadHintSeen() {
    if (!Hive.isBoxOpen(_settingsBoxName)) {
      return;
    }
    _hintSeen = Hive.box<dynamic>(_settingsBoxName).get(_hintSeenKey) == true;
  }

  /// Called the first time the user acts on a card — by swipe or by button —
  /// after which the hint never comes back.
  void _markHintSeen() {
    if (_hintSeen) {
      return;
    }
    setState(() => _hintSeen = true);
    if (Hive.isBoxOpen(_settingsBoxName)) {
      unawaited(Hive.box<dynamic>(_settingsBoxName).put(_hintSeenKey, true));
    }
  }

  AddContactsSession get _session => context.read<AddContactsSession>();

  List<ContactImportCandidate> _buildDeck(AddContactsSession session) {
    final Set<String> deferred = _deferredCandidates
        .map((ContactImportCandidate c) => c.normalizedPhone)
        .toSet();
    return session.availableCandidates
        .where(
          (ContactImportCandidate candidate) =>
              !deferred.contains(candidate.normalizedPhone),
        )
        .toList();
  }

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    final List<ContactImportCandidate> deck =
        _deck ?? const <ContactImportCandidate>[];
    if (previousIndex >= deck.length) {
      return false;
    }
    final ContactImportCandidate candidate = deck[previousIndex];
    if (direction == CardSwiperDirection.right) {
      _handleAccept(candidate);
    } else if (direction == CardSwiperDirection.left) {
      _handleReject(candidate);
    } else if (direction == CardSwiperDirection.top) {
      _handleDefer(candidate);
    } else {
      return false;
    }
    _markHintSeen();
    return true;
  }

  bool _onUndo(
    int? previousIndex,
    int currentIndex,
    CardSwiperDirection direction,
  ) {
    if (_history.isEmpty) {
      return false;
    }

    final _SwipeHistoryEntry entry = _history.removeLast();
    switch (entry.action) {
      case _SwipeAction.accept:
        _undoAccept(entry);
      case _SwipeAction.reject:
        _undoReject(entry);
      case _SwipeAction.defer:
        _undoDefer(entry);
    }
    return true;
  }

  void _handleAccept(ContactImportCandidate candidate) {
    final PersonRepository repo = context.read<PersonRepository>();
    final _SwipeHistoryEntry entry = _SwipeHistoryEntry(
      action: _SwipeAction.accept,
      candidate: candidate,
      importedCounted: true,
    );
    _history.add(entry);
    unawaited(_importAcceptedCandidate(candidate, repo, entry));
    setState(() => _addedCount++);
  }

  Future<void> _importAcceptedCandidate(
    ContactImportCandidate candidate,
    PersonRepository repo,
    _SwipeHistoryEntry entry,
  ) async {
    final AddContactsSession session = _session;
    try {
      final StagedContact? staged =
          await ContactsImportService.stageSingleCandidate(candidate, repo);

      if (staged == null) {
        _revertPendingAddedCount(entry);
        return;
      }

      if (entry.wasUndone) {
        // The swipe was taken back before the details were even asked for.
        await ContactsImportService.discardStagedCandidate(staged, repo);
        return;
      }

      if (!mounted) {
        await ContactsImportService.discardStagedCandidate(staged, repo);
        return;
      }

      final QuickUpdateOutcome outcome = await QuickUpdateDialog.show(
        context,
        staged.person,
      );
      if (outcome.isAdded && !entry.wasUndone) {
        await repo.activatePendingContactDraft(staged.person);
        await session.clearRemoval(candidate);
        session.recordAdded();
        entry.importedPersonId = staged.person.id;
        if (outcome == QuickUpdateOutcome.openFullEditor && mounted) {
          // The full card ends on that person's profile, not back at the deck.
          await openExtendedPersonEditor(
            context,
            staged.person.id,
            isNewFriend: true,
          );
          if (mounted) {
            context.push('/people/${staged.person.id}');
          }
        }
        return;
      }

      // Cancelled: the draft is thrown away instead of being parked as a
      // contact waiting for details.
      await ContactsImportService.discardStagedCandidate(staged, repo);
      if (!mounted || entry.wasUndone) {
        return;
      }
      _revertPendingAddedCount(entry);

      // The card comes straight back, rather than being pushed to the
      // review-later pile at the end of the deck. "ביטול" here means "not that
      // — let me decide again", and answering it by making the person vanish
      // until the whole address book has been dealt with is the opposite of
      // what was asked for. The dialog is modal, so this swipe is still the
      // last one and undoing it restores exactly this candidate.
      if (_history.isNotEmpty && identical(_history.last, entry)) {
        _controller.undo();
      } else if (!_deferredCandidates.any(
        (ContactImportCandidate deferred) =>
            deferred.normalizedPhone == candidate.normalizedPhone,
      )) {
        setState(() => _deferredCandidates.add(candidate));
      }
    } catch (_) {
      _revertPendingAddedCount(entry);
    }
  }

  void _revertPendingAddedCount(_SwipeHistoryEntry entry) {
    if (entry.wasUndone || !entry.importedCounted || !mounted) {
      return;
    }

    setState(() {
      entry.importedCounted = false;
      _addedCount = (_addedCount - 1).clamp(0, 1 << 30);
    });
  }

  void _undoAccept(_SwipeHistoryEntry entry) {
    entry.wasUndone = true;
    final String? personId = entry.importedPersonId;
    if (personId != null) {
      final PersonRepository repo = context.read<PersonRepository>();
      unawaited(repo.delete(personId));
      _session.recordAddUndone();
    }
    setState(() {
      if (entry.importedCounted) {
        entry.importedCounted = false;
        _addedCount = (_addedCount - 1).clamp(0, 1 << 30);
      }
      _isFinished = false;
    });
  }

  void _handleDefer(ContactImportCandidate candidate) {
    // Not persisted anywhere: the candidate simply moves to a "review later"
    // pile that is offered again once the main deck is finished. They stay in
    // the list view the whole time.
    _deferredCandidates.add(candidate);
    _history.add(
      _SwipeHistoryEntry(action: _SwipeAction.defer, candidate: candidate),
    );
    setState(() {});
  }

  void _undoDefer(_SwipeHistoryEntry entry) {
    _deferredCandidates.removeWhere(
      (ContactImportCandidate c) =>
          c.normalizedPhone == entry.candidate.normalizedPhone,
    );
    setState(() => _isFinished = false);
  }

  /// Reloads the deck with the deferred contacts so the user can decide on them.
  void _reviewDeferred() {
    if (_deferredCandidates.isEmpty) {
      return;
    }
    setState(() {
      _deck = List<ContactImportCandidate>.from(_deferredCandidates);
      _deferredCandidates.clear();
      _history.clear();
      _isFinished = false;
      _deckGeneration++;
    });
  }

  void _handleReject(ContactImportCandidate candidate) {
    unawaited(_session.removeFromList(<ContactImportCandidate>[candidate]));
    _history.add(
      _SwipeHistoryEntry(action: _SwipeAction.reject, candidate: candidate),
    );
    setState(() => _skippedCount++);
  }

  void _undoReject(_SwipeHistoryEntry entry) {
    unawaited(_session.restoreToList(entry.candidate));
    setState(() {
      _skippedCount = (_skippedCount - 1).clamp(0, 1 << 30);
      _isFinished = false;
    });
  }

  void _onEnd() {
    setState(() => _isFinished = true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody(context);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('סריקת כרטיסים'), centerTitle: true),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final AddContactsSession session = context.watch<AddContactsSession>();
    // Watched so a friend added in the list view changes the numbers here too.
    context.watch<PersonRepository>();

    if (session.isLoading) {
      return _LoadingContactsView(
        message: session.loadingMessage,
        progress: session.loadingProgress,
      );
    }

    final ContactsPermissionState? permissionState = session.permissionState;
    if (permissionState == ContactsPermissionState.denied ||
        permissionState == ContactsPermissionState.permanentlyDenied) {
      final bool isPermanentlyDenied =
          permissionState == ContactsPermissionState.permanentlyDenied;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              EmptyState(
                icon: Icons.contact_phone_outlined,
                title: 'אין גישה לאנשי הקשר',
                subtitle: isPermanentlyDenied
                    ? 'כדי לייבא אנשי קשר צריך לאשר גישה בהגדרות המכשיר'
                    : 'כדי לייבא אנשי קשר צריך לאשר גישה לספר הטלפונים',
                buttonText: isPermanentlyDenied ? 'פתיחת הגדרות' : 'לנסות שוב',
                onButtonPressed: isPermanentlyDenied
                    ? session.openSettingsAndRecheck
                    : session.load,
              ),
              if (isPermanentlyDenied)
                TextButton(
                  onPressed: session.load,
                  child: const Text('בדיקה מחדש'),
                ),
            ],
          ),
        ),
      );
    }

    if (_deck == null) {
      // A new stack needs a new key, otherwise the swiper keeps the index it
      // had for the previous (differently sized) deck.
      _deck = _buildDeck(session);
      _deckGeneration++;
      _history.clear();
      _isFinished = false;
    }
    final List<ContactImportCandidate> deck = _deck!;

    if (deck.isEmpty && _deferredCandidates.isEmpty) {
      return EmptyState(
        icon: Icons.done_all,
        title: 'אין אנשי קשר חדשים לסקור',
        subtitle: 'כל אנשי הקשר שלך כבר במאגר או הוסרו מהרשימה',
        buttonText: 'חזרה',
        onButtonPressed: () => Navigator.of(context).maybePop(),
      );
    }

    if (_isFinished || deck.isEmpty) {
      return _buildSummary(context);
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AddContactsProgressHeader(
            addedToDatabase: session.databaseCount,
            remaining: session.remainingCount,
            total: session.progressTotal,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _buildStats(context),
        ),
        Expanded(child: _buildDeckView(context, deck)),
        if (!_hintSeen)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: _SwipeHint(),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: _buildActionButtons(context),
        ),
      ],
    );
  }

  Widget _buildStats(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AddContactsStatsRow(
      stats: <AddContactsStat>[
        AddContactsStat(
          icon: Icons.favorite,
          label: 'הוספתי',
          value: _addedCount,
          color: theme.brightness == Brightness.dark
              ? AppColors.femaleAccentDm
              : AppColors.femaleAccent,
        ),
        AddContactsStat(
          icon: Icons.schedule,
          label: 'דילגתי',
          value: _deferredCandidates.length,
          color: theme.colorScheme.secondary,
        ),
        AddContactsStat(
          icon: Icons.close,
          label: 'לא רלוונטיים',
          value: _skippedCount,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  /// The card stack, deliberately kept small so the screen doesn't turn into a
  /// large empty white rectangle.
  Widget _buildDeckView(
    BuildContext context,
    List<ContactImportCandidate> deck,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double deckWidth = math.min(constraints.maxWidth * 0.8, 300);
        // The swiper draws inside its own padding and lets the cards behind
        // peek out below, so the box it lives in is taller than the card.
        final double deckHeight = math.min(
          constraints.maxHeight,
          deckWidth * 1.15 + 54,
        );
        // Keep the circle proportional to whichever dimension is tighter, so a
        // short screen doesn't push the name off the card.
        final double avatarDiameter = math
            .min(deckWidth * 0.38, (deckHeight - 150) * 0.55)
            .clamp(56.0, 108.0);

        return Center(
          child: SizedBox(
            width: deckWidth,
            height: deckHeight,
            child: CardSwiper(
              key: ValueKey<int>(_deckGeneration),
              controller: _controller,
              cardsCount: deck.length,
              numberOfCardsDisplayed: deck.length >= 3 ? 3 : deck.length,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 30),
              scale: 0.94,
              backCardOffset: const Offset(0, 18),
              // Right = add, left = not relevant, up = review later ("דילוג").
              allowedSwipeDirection: const AllowedSwipeDirection.only(
                left: true,
                right: true,
                up: true,
              ),
              onSwipe: _onSwipe,
              onUndo: _onUndo,
              onEnd: _onEnd,
              cardBuilder:
                  (
                    BuildContext context,
                    int index,
                    int percentThresholdX,
                    int percentThresholdY,
                  ) {
                    return _NameCard(
                      candidate: deck[index],
                      avatarDiameter: avatarDiameter,
                    );
                  },
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        // The primary action: filled, largest, and first in reading order.
        _SwipeActionButton(
          icon: Icons.favorite,
          label: 'הוספה',
          diameter: 62,
          iconSize: 28,
          filled: true,
          color: dark ? theme.colorScheme.primary : AppColors.primaryDark,
          foregroundColor: dark ? AppColors.onSurface : AppColors.onPrimary,
          onPressed: () => _controller.swipe(CardSwiperDirection.right),
        ),
        // Come back to this contact once the deck is done.
        _SwipeActionButton(
          icon: Icons.schedule,
          label: 'דילוג',
          diameter: 48,
          iconSize: 21,
          color: theme.colorScheme.secondary,
          onPressed: () => _controller.swipe(CardSwiperDirection.top),
        ),
        // The quietest control — it only ever repairs a mistake.
        _SwipeActionButton(
          icon: Icons.replay,
          label: 'חזרה',
          diameter: 42,
          iconSize: 18,
          color: theme.colorScheme.onSurfaceVariant,
          onPressed: _history.isEmpty ? null : () => _controller.undo(),
        ),
        _SwipeActionButton(
          icon: Icons.close,
          label: 'לא רלוונטי',
          diameter: 58,
          iconSize: 26,
          color: theme.colorScheme.error,
          onPressed: () => _controller.swipe(CardSwiperDirection.left),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.check_circle,
              size: 72,
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.primary
                  : AppColors.primaryDark,
            ),
            const SizedBox(height: 16),
            Text('סיימנו!', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'הוספת $_addedCount חברים למאגר · $_skippedCount סומנו כלא רלוונטיים',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_deferredCandidates.isNotEmpty) ...<Widget>[
              FilledButton.icon(
                onPressed: _reviewDeferred,
                icon: const Icon(Icons.schedule),
                label: Text('חזרה לדילוגים (${_deferredCandidates.length})'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('חזרה'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingContactsView extends StatelessWidget {
  const _LoadingContactsView({required this.message, required this.progress});

  final String message;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: progress, minHeight: 6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown once, to a first-time user, so the buttons and the swipes are both
/// discoverable.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.swipe_outlined,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'החליקו או השתמשו בכפתורים למטה',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// A single deck card: a pastel initials circle with the contact's name below.
class _NameCard extends StatelessWidget {
  const _NameCard({required this.candidate, required this.avatarDiameter});

  final ContactImportCandidate candidate;
  final double avatarDiameter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: softCardDecoration(context, radius: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          InitialsAvatar(name: candidate.displayName, diameter: avatarDiameter),
          const SizedBox(height: 20),
          Flexible(
            child: Text(
              candidate.displayName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the four deck actions: a circular button with its name underneath, so
/// none of them relies on the icon alone.
class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    required this.diameter,
    required this.iconSize,
    this.filled = false,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final double diameter;
  final double iconSize;

  /// The primary action is a solid disc; the rest are soft tints of [color].
  final bool filled;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool disabled = onPressed == null;
    final Color background = filled
        ? (disabled ? color.withValues(alpha: 0.4) : color)
        : color.withValues(alpha: disabled ? 0.05 : 0.12);
    final Color foreground = filled
        ? (foregroundColor ?? theme.colorScheme.onPrimary)
        : (disabled ? color.withValues(alpha: 0.35) : color);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: background,
          shape: const CircleBorder(),
          elevation: filled && !disabled ? 2 : 0,
          shadowColor: AppColors.onSurface.withValues(alpha: 0.25),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: diameter,
              child: Icon(icon, color: foreground, size: iconSize),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: disabled
                ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
