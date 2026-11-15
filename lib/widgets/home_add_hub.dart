import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/art_tint.dart';
import 'package:shadchan/utils/enums.dart';

/// The two standing actions of the home page: "הוספת חברים" | "הוספת רעיון".
///
/// **Two buttons, nothing between them.** There used to be a "+" in the
/// middle that opened a sheet asking which of the same two was meant — one
/// more control saying what the buttons either side of it already said. Now
/// each action is a large button of its own, half the width each, in the
/// app's own colours: the friends blue and the idea copper, each on a light
/// wash of itself with its own hand-drawn mark, so the pair reads as the
/// page's main buttons at a glance.
///
/// The row is pinned under the search bar while the page scrolls, so it has
/// a height that is known before it is laid out — see [heightFor].
class HomeAddHub extends StatelessWidget {
  const HomeAddHub({
    super.key,
    required this.onAddPeople,
    required this.onAddIdea,
    this.gender,
  });

  /// The two standing actions' names — the same words on every phone.
  static const String addPeopleLabel = 'הוספת חברים';
  static const String addIdeaLabel = 'הוספת רעיון';

  final VoidCallback onAddPeople;
  final VoidCallback onAddIdea;
  final Gender? gender;

  /// The row's height for [scaler]: large enough to be the page's main
  /// buttons, growing with the reader's text size, and fixed for a frame so
  /// a pinned header can promise it in advance. The label is scaled down to
  /// fit rather than ever overflowing.
  static double heightFor(TextScaler scaler) {
    final double text = scaler.scale(16);
    return (text * 1.4 + 34).clamp(58.0, 80.0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: heightFor(MediaQuery.textScalerOf(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _AddButton(
              title: addPeopleLabel,
              people: true,
              onTap: onAddPeople,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _AddButton(
              title: addIdeaLabel,
              people: false,
              onTap: onAddIdea,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
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
    // The label in the deeper member of the same hue, so it reads on the wash.
    final Color ink = dark
        ? accent
        : (people ? AppColors.primaryInk : AppColors.secondaryInk);
    final Color fill = Color.alphaBlend(
      accent.withValues(alpha: dark ? 0.22 : 0.17),
      dark ? theme.colorScheme.surface : AppColors.page,
    );
    final BorderRadius radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: title,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: fill,
        elevation: 2,
        shadowColor: accent.withValues(alpha: 0.35),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: accent.withValues(alpha: 0.7), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: accent.withValues(alpha: 0.18),
          highlightColor: accent.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                      width: 34,
                      height: 34,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // **One line.** On a narrow phone, or with larger system
                // text, the label is scaled down rather than broken in two.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
