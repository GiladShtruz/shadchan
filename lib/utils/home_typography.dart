import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The home screen's whole type scale: three sizes, and nothing between them.
///
/// **Why it is a theme override and not a rule everybody has to remember.** The
/// landing page is drawn by a dozen widgets in five files, and between them
/// they were reaching for ten of Material's roles — `headlineSmall`,
/// `titleLarge`, `titleMedium`, `titleSmall`, `bodyLarge`, `bodyMedium`,
/// `bodySmall`, `labelLarge`, `labelMedium`, `labelSmall`. Each choice was
/// defensible on its own card and the page as a whole had no scale at all: two
/// blocks sitting side by side would head themselves at 14 and 16, and a line
/// of explanation under one was larger than the heading of the next. Asking
/// every block to agree by hand is a rule that lasts until the next block.
///
/// So the roles are *folded* instead, once, at the top of the page: whatever a
/// widget asks for, it gets one of three sizes.
///
/// - **[lead]** — the greeting, and the name of a block that opens a whole
///   screen of its own. Two or three lines on the page wear it.
/// - **[title]** — every heading inside a block, and every control's label.
/// - **[note]** — everything that explains, dates, counts or qualifies.
///
/// **Colour is folded the same way, and for the same reason.** The page had
/// drifted into a near-black warm body colour, a warm taupe for secondary
/// lines, and a different accent per block for anything that wanted to look
/// like a heading. Now the three sizes carry two inks: everything that titles,
/// names or counts is [AppColors.headingInk], and everything that explains,
/// dates or qualifies is [AppColors.mutedInk]. A block that means something
/// specific by a colour — a status, a gender, a warning — still sets it, and
/// an explicit colour always wins over the fold.
///
/// Weight is left alone: it is how a card distinguishes its heading from its
/// body *within* one size, and folding that too would flatten the page rather
/// than order it.
///
/// The smaller sizes also buy the other half of the problem: a heading at 16
/// wrapped onto a second line on a 360px phone where the same words at 15 do
/// not, and a page of two-line headings reads as crowded however calm each
/// card is.
abstract final class HomeTypography {
  /// The greeting and the two banners that open a screen.
  static const double lead = 20;

  /// Every block heading and every button label.
  static const double title = 15;

  /// Every explanatory line, count and date.
  static const double note = 13;

  /// [base] with all ten roles the home page uses folded onto the three sizes
  /// and the two inks.
  ///
  /// `displayLarge` down to `headlineMedium` are deliberately untouched:
  /// nothing on this page draws them, and a screen pushed from here should
  /// keep Material's own scale for anything the home page has no opinion
  /// about.
  static TextTheme scale(TextTheme base, {required bool dark}) {
    final Color heading = AppColors.heading(dark: dark);
    final Color muted = AppColors.muted(dark: dark);

    TextStyle? at(TextStyle? style, double size, Color color) =>
        style?.copyWith(fontSize: size, color: color);

    return base.copyWith(
      headlineSmall: at(base.headlineSmall, lead, heading),
      titleLarge: at(base.titleLarge, lead, heading),
      titleMedium: at(base.titleMedium, title, heading),
      titleSmall: at(base.titleSmall, title, heading),
      bodyLarge: at(base.bodyLarge, title, heading),
      labelLarge: at(base.labelLarge, title, heading),
      bodyMedium: at(base.bodyMedium, note, muted),
      bodySmall: at(base.bodySmall, note, muted),
      labelMedium: at(base.labelMedium, note, muted),
      labelSmall: at(base.labelSmall, note, muted),
    );
  }
}
