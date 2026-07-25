import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// A soft pastel circle holding the initials of a contact's first and last
/// name. The shade is derived from the name itself, so a contact keeps the same
/// colour wherever they appear.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.diameter = 36});

  final String name;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ({Color surface, Color ink}) pastel = AppColors.initialsPastel(name);

    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Dark mode can't use the pastel as a fill without lighting up the
        // whole row, so it becomes a faint wash with the pastel itself as ink.
        color: dark ? pastel.surface.withValues(alpha: 0.22) : pastel.surface,
        shape: BoxShape.circle,
      ),
      child: Text(
        initialsOf(name),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: dark ? pastel.surface : pastel.ink,
          fontWeight: FontWeight.w700,
          fontSize: diameter * 0.36,
          height: 1.1,
        ),
      ),
    );
  }

  /// First letter of the first name plus first letter of the family name.
  static String initialsOf(String name) {
    // Anything that isn't a letter or a digit (punctuation, emoji, the bidi
    // control marks contact names often carry) becomes a separator.
    final List<String> words = name
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return '?';
    }
    if (words.length == 1) {
      return words.first.characters.first;
    }
    return '${words.first.characters.first}${words[1].characters.first}';
  }
}
