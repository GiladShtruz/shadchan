import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/art_tint.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The two ways to earn points, gathered around the home's main add button.
class HomeAddHub extends StatelessWidget {
  const HomeAddHub({
    super.key,
    required this.onAddPeople,
    required this.onAddIdea,
    this.gender,
  });

  final VoidCallback onAddPeople;
  final VoidCallback onAddIdea;
  final Gender? gender;

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
    return _EarnAction(
      title: (people ? '{הוסף|הוסיפי} חברים' : '{הוסף|הוסיפי} רעיון').forGender(
        gender,
      ),
      subtitle: '{וצבור|וצברי} נקודות'.forGender(gender),
      people: people,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return HomePaperCard(
      stripe: dark ? AppColors.secondaryDarkDm : AppColors.secondary,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
      elevation: 4,
      child: Row(
        children: <Widget>[
          Expanded(child: _action(people: true, onTap: onAddPeople)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _PulsingAddButton(onPressed: () => _choose(context)),
          ),
          Expanded(child: _action(people: false, onTap: onAddIdea)),
        ],
      ),
    );
  }
}

class _EarnAction extends StatelessWidget {
  const _EarnAction({
    required this.title,
    required this.subtitle,
    required this.people,
    required this.onTap,
  });

  final String title;
  final String subtitle;
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
      label: '$title $subtitle',
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
                    width: 44,
                    height: 44,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // **Each line stays one line.** On a narrow phone, or with
              // larger system text, "הוסיפי חברים" used to break in two and
              // push the caption under it onto a third and fourth line; a line
              // that does not fit is now scaled down instead.
              _OneLine(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 2),
              _OneLine(subtitle, style: theme.textTheme.bodySmall),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool animate =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate) {
      if (!_pulse.isAnimating) {
        // Two slow breaths on arrival, then rest so the page stays calm.
        _pulse.repeat(reverse: true, count: 4);
      }
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
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
      dimension: 88,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? child) {
              final double t = _pulse.value;
              return Container(
                width: 76 + 12 * t,
                height: 76 + 12 * t,
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
              dimension: 76,
              child: IconButton.filled(
                onPressed: widget.onPressed,
                tooltip: 'הוספה וצבירת נקודות',
                iconSize: 44,
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
