import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/art_tint.dart';
import 'package:shadchan/utils/enums.dart';

/// The row under "מה עושים עכשיו?": "הוספת חברים", the main "+" and
/// "הוספת רעיון", side by side on the bare page.
///
/// **No card around it.** The home screen is read as one continuous area from
/// the title down to the list of what to do next; a frame round the two
/// actions cut it into boxes again. The row is open, with two hairlines
/// either side of the plus to hold it together.
///
/// The plus still opens the same small sheet with the same two choices.
class HomeAddHub extends StatelessWidget {
  const HomeAddHub({
    super.key,
    required this.onAddPeople,
    required this.onAddIdea,
    this.gender,
    this.header,
  });

  /// The two standing actions' names — the same words on every phone.
  static const String addPeopleLabel = 'הוספת חברים';
  static const String addIdeaLabel = 'הוספת רעיון';

  final VoidCallback onAddPeople;
  final VoidCallback onAddIdea;
  final Gender? gender;

  /// Drawn above the row, when a caller has something to say there.
  final Widget? header;

  void _choose(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'מה נוסיף היום?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _action(
                  people: true,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onAddPeople();
                  },
                ),
                _action(
                  people: false,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onAddIdea();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action({required bool people, required VoidCallback onTap}) {
    return _AddAction(
      title: people ? addPeopleLabel : addIdeaLabel,
      people: people,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color rule = theme.colorScheme.outlineVariant;
    Widget hairline() => Container(width: 1, height: 48, color: rule);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (header != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: header!),
        Row(
          children: <Widget>[
            Expanded(child: _action(people: true, onTap: onAddPeople)),
            hairline(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _PulsingAddButton(onPressed: () => _choose(context)),
            ),
            hairline(),
            Expanded(child: _action(people: false, onTap: onAddIdea)),
          ],
        ),
      ],
    );
  }
}

class _AddAction extends StatelessWidget {
  const _AddAction({
    required this.title,
    required this.people,
    required this.onTap,
  });

  final String title;
  final bool people;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = people
        ? (dark ? AppColors.primaryDarkDm : AppColors.addPeopleAccent)
        : (dark ? AppColors.secondaryDarkDm : AppColors.addIdeaAccent);
    return Semantics(
      button: true,
      label: title,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ExcludeSemantics(
                child: ColorFiltered(
                  colorFilter: artTint(
                    accent,
                    people ? ArtTint.addFriends : ArtTint.addIdea,
                  ),
                  child: Image.asset(
                    people
                        ? 'assets/add_friends_art.png'
                        : 'assets/add_idea_art.png',
                    width: 38,
                    height: 38,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // **One line.** On a narrow phone, or with larger system text,
              // "הוסיפי חברים" is scaled down rather than broken in two.
              _OneLine(
                title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single line of text, centred, scaled down rather than wrapped.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}

class _PulsingAddButton extends StatefulWidget {
  const _PulsingAddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_PulsingAddButton> createState() => _PulsingAddButtonState();
}

class _PulsingAddButtonState extends State<_PulsingAddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: 1.06,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  /// A breath every so often after the arrival, so the plus keeps inviting
  /// without the page ever being in constant motion.
  static const Duration _restBetweenBreaths = Duration(seconds: 9);

  Timer? _rest;

  bool _animate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool animate =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate == _animate) {
      return;
    }
    _animate = animate;
    if (animate) {
      // Two slow breaths on arrival, then one now and then.
      _pulse.repeat(reverse: true, count: 4);
      _rest ??= Timer.periodic(_restBetweenBreaths, (_) {
        if (mounted && _animate && !_pulse.isAnimating) {
          _pulse.repeat(reverse: true, count: 2);
        }
      });
    } else {
      _rest?.cancel();
      _rest = null;
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _rest?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color copper = Theme.of(context).brightness == Brightness.dark
        ? AppColors.secondaryDarkDm
        : AppColors.secondary;
    // A soft copper halo breathes out with each pulse, so the plus reads as
    // something alive to be pressed rather than as a large static badge. It
    // follows the same controller, so it rests when the pulse rests.
    return SizedBox.square(
      dimension: 74,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? child) {
              final double t = _pulse.value;
              return Container(
                width: 62 + 10 * t,
                height: 62 + 10 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: copper.withValues(alpha: 0.16 * t),
                ),
              );
            },
          ),
          ScaleTransition(
            scale: _scale,
            child: SizedBox.square(
              dimension: 62,
              child: IconButton.filled(
                onPressed: widget.onPressed,
                tooltip: 'הוספת חברים או רעיון',
                iconSize: 36,
                style: IconButton.styleFrom(
                  backgroundColor: copper,
                  foregroundColor: AppColors.surface,
                  elevation: 3,
                  shadowColor: copper.withValues(alpha: 0.5),
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
