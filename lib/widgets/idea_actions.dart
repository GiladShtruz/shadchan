import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_icons.dart';
import 'package:shadchan/widgets/app_glyphs.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// The answers a suggested match can be given, drawn in the app's own icon
/// language: a thin rounded glyph on a soft wash of a palette colour, with one
/// short word under it.
///
/// These replaced a set of hand-drawn marker pictures (an arrow, a heart and a
/// cross). The drawings were pleasant on their own but came from another
/// style — thick, uneven strokes next to an app that is otherwise thin lines
/// on cream paper — so a page of suggestions read like a second app. The
/// glyphs now come from the same places as the rest of the app: a new idea is
/// the bottom bar's own bulb ([IdeaBulbIcon]), the rest are Material's rounded
/// outlines — a question mark for an idea that already exists ("what is
/// happening with it?"), so a pair with an idea never wears the same sign as a
/// pair still waiting for one.
enum IdeaActionKind {
  /// "פתיחת רעיון" — the one answer that moves anything forward.
  openIdea,

  /// "לרעיון הקיים" — the pair already has an idea; this goes to it.
  existingIdea,

  /// "לא מתאים".
  notSuitable,

  /// "החזרה" — takes back an earlier "לא מתאים".
  restore,

  /// "השוואת כרטיסים" — the two cards side by side.
  compare,
}

/// One answer: the glyph on its wash, and the word under it, as one tap
/// target.
class IdeaAction extends StatelessWidget {
  const IdeaAction({
    super.key,
    required this.kind,
    required this.onTap,
    this.label,
    this.width,
  });

  final IdeaActionKind kind;
  final VoidCallback? onTap;

  /// Overrides the default word for [kind].
  final String? label;

  /// A fixed width keeps a column of rows aligned; null lets the action take
  /// whatever its parent gives it.
  final double? width;

  static String defaultLabel(IdeaActionKind kind) => switch (kind) {
    IdeaActionKind.openIdea => 'פתיחת רעיון',
    IdeaActionKind.existingIdea => 'לרעיון הקיים',
    IdeaActionKind.notSuitable => 'לא מתאים',
    IdeaActionKind.restore => 'החזרה',
    IdeaActionKind.compare => 'השוואת כרטיסים',
  };

  /// The palette colour each answer is said in: the idea in the rose the app
  /// uses for couples, an existing idea and the comparison in the blue, and
  /// the two "no"s in the copper — warm, never an alarm red.
  static Color colorOf(IdeaActionKind kind, {bool dark = false}) =>
      switch (kind) {
        IdeaActionKind.openIdea =>
          dark ? AppColors.femaleAccentDm : AppColors.femaleAccent,
        IdeaActionKind.existingIdea || IdeaActionKind.compare =>
          dark ? AppColors.primaryDarkDm : AppColors.primaryDark,
        IdeaActionKind.notSuitable || IdeaActionKind.restore =>
          dark ? AppColors.secondaryDarkDm : AppColors.secondary,
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color color = colorOf(kind, dark: dark);
    final String text = label ?? defaultLabel(kind);
    final bool enabled = onTap != null;
    // One size for every answer, small enough that "פתיחת רעיון" fits its
    // column unscaled, so two words side by side never come out in two sizes.
    final TextStyle? labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      color: color,
    );
    final double lineHeight = MediaQuery.textScalerOf(
      context,
    ).scale((labelStyle?.fontSize ?? 10.5) * 1.4);

    final Widget glyph = switch (kind) {
      IdeaActionKind.openIdea => IdeaBulbIcon(size: 19, color: color),
      IdeaActionKind.existingIdea => Icon(
        AppIcons.help,
        size: 19,
        color: color,
      ),
      IdeaActionKind.notSuitable => Icon(
        Icons.close_rounded,
        size: 18,
        color: color,
      ),
      IdeaActionKind.restore => Icon(
        Icons.undo_rounded,
        size: 18,
        color: color,
      ),
      IdeaActionKind.compare => Icon(
        Icons.compare_arrows_rounded,
        size: 19,
        color: color,
      ),
    };

    final Widget body = Semantics(
      button: true,
      enabled: enabled,
      label: text,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: dark ? 0.2 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: glyph,
                ),
                const SizedBox(height: 3),
                // A line of fixed height: a longer word is scaled down to
                // fit its width, and without this it would also come out
                // shorter, and the row carrying it with it.
                SizedBox(
                  height: lineHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(text, maxLines: 1, style: labelStyle),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return width == null ? body : SizedBox(width: width, child: body);
  }
}

/// Three answers across the foot of a suggested pair ("רעיונות שהמאגר מציע
/// לך"): compare the two cards, open the idea, or not suitable — read in RTL
/// from the comparison at the right to the "no" at the far end, with the idea
/// in the middle.
class IdeaActionBar extends StatelessWidget {
  const IdeaActionBar({
    super.key,
    required this.onCompare,
    required this.onOpenIdea,
    required this.onNotSuitable,
  });

  final VoidCallback onCompare;
  final VoidCallback onOpenIdea;
  final VoidCallback onNotSuitable;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: IdeaAction(kind: IdeaActionKind.compare, onTap: onCompare),
        ),
        Expanded(
          child: IdeaAction(kind: IdeaActionKind.openIdea, onTap: onOpenIdea),
        ),
        Expanded(
          child: IdeaAction(
            kind: IdeaActionKind.notSuitable,
            onTap: onNotSuitable,
          ),
        ),
      ],
    );
  }
}

/// One suggested match in "התאמות", on a single compact line.
///
/// **Every row has the same shape and height**, so the page is scanned rather
/// than read: the person at the start edge (photo, name, then age and
/// religious style), and at the other end, level with them, the two answers
/// and a small arrow into the full card. The arrow opens the card whether or
/// not there is one — a person with no card gets an empty card with a way to
/// ask for the details, never nothing.
class SuggestionRow extends StatelessWidget {
  const SuggestionRow({
    super.key,
    required this.person,
    required this.summary,
    required this.onTap,
    required this.onOpenIdea,
    required this.onNotSuitable,
    required this.onOpenCard,
    this.onAvatarTap,
    this.hasIdea = false,
    this.dismissed = false,
    this.tag,
    this.surfaceColor,
    this.nameColor,
    this.mutedColor,
    this.frameColor,
  });

  final Person person;

  /// "גיל 25 · דתי לאומי".
  final String summary;

  /// The row itself — the person's details.
  final VoidCallback onTap;
  final VoidCallback? onAvatarTap;
  final VoidCallback onOpenIdea;
  final VoidCallback onNotSuitable;
  final VoidCallback onOpenCard;

  /// The pair already has an idea: the first answer goes to it.
  final bool hasIdea;

  /// Marked "לא מתאים" already: the second answer takes it back.
  final bool dismissed;

  /// A small trailing word on the details line — the idea's status, or
  /// "כבר נצפתה".
  final Widget? tag;

  final Color? surfaceColor;
  final Color? nameColor;
  final Color? mutedColor;

  /// The colour of the frame when the pair already has a live idea — the very
  /// frame its card wears on "הרעיונות שלי" ([AppColors.ideaFrame]): blue
  /// open, orange waiting, rose out. Null draws the plain row.
  final Color? frameColor;

  /// The width of each answer, the same on every row so the columns line up.
  static const double actionWidth = 60;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = mutedColor ?? theme.colorScheme.onSurfaceVariant;
    final String name = person.fullName.trim();

    return SuggestionFrame(
      surfaceColor: surfaceColor,
      frameColor: frameColor,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 2, 7),
        child: Row(
          children: <Widget>[
            GestureDetector(
              onTap: onAvatarTap,
              child: PersonAvatar(person: person, radius: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          name.isEmpty ? 'ללא שם' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: nameColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (tag != null) ...<Widget>[
                        const SizedBox(width: 6),
                        // Beside the name, so the age and the religious
                        // style below always keep their whole line; held to a
                        // short width so the name keeps the rest.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 64),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: tag,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IdeaAction(
              kind: hasIdea
                  ? IdeaActionKind.existingIdea
                  : IdeaActionKind.openIdea,
              width: actionWidth,
              onTap: onOpenIdea,
            ),
            IdeaAction(
              kind: dismissed
                  ? IdeaActionKind.restore
                  : IdeaActionKind.notSuitable,
              width: actionWidth,
              onTap: onNotSuitable,
            ),
            // Material's chevrons follow the text direction: in this RTL
            // app `chevron_right` is the one drawn pointing left — forward.
            IconButton(
              tooltip: 'פתיחת הכרטיס',
              onPressed: onOpenCard,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 40),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.chevron_right_rounded, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The paper a suggestion sits on — a row in the list or a square in the grid.
///
/// Plain, it is the page's own surface. With a [frameColor] — the pair already
/// has a live idea — it wears exactly what that idea's card wears on
/// "הרעיונות שלי": the calm cream ground, a 1.6 border in the status colour and
/// a soft shadow of the same colour, so the status reads the same at a glance
/// on both pages.
class SuggestionFrame extends StatelessWidget {
  const SuggestionFrame({
    super.key,
    required this.child,
    required this.onTap,
    this.surfaceColor,
    this.frameColor,
  });

  final Widget child;
  final VoidCallback onTap;
  final Color? surfaceColor;
  final Color? frameColor;

  static const double radius = 16;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color paper = surfaceColor ?? theme.colorScheme.surface;
    final Color? frame = frameColor;
    final BorderRadius corners = BorderRadius.circular(radius);
    if (frame == null) {
      return Material(
        color: paper,
        borderRadius: corners,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: child),
      );
    }
    // The ground live idea cards share (`MatchIdeaCard`'s `_CardTone`).
    final Color ground = dark
        ? Color.alphaBlend(AppColors.onSurfaceDm.withValues(alpha: 0.03), paper)
        : Color.alphaBlend(AppColors.background.withValues(alpha: 0.55), paper);
    return Material(
      color: ground,
      elevation: 2,
      shadowColor: frame.withValues(alpha: 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: corners,
        side: BorderSide(color: frame.withValues(alpha: 0.6), width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

/// One suggested match as a square, for the grid view of "התאמות".
///
/// Everything the row carries, rearranged rather than trimmed: the photo, the
/// name, age and religious style, the idea's status (or "כבר נצפתה"), the two
/// answers, and the arrow into the full card — which sits in the square's top
/// corner so the foot holds only the two answers and nothing crowds them.
/// Framed by status exactly as a row is ([SuggestionFrame]).
class SuggestionTile extends StatelessWidget {
  const SuggestionTile({
    super.key,
    required this.person,
    required this.summary,
    required this.onTap,
    required this.onOpenIdea,
    required this.onNotSuitable,
    required this.onOpenCard,
    this.onAvatarTap,
    this.hasIdea = false,
    this.dismissed = false,
    this.tag,
    this.surfaceColor,
    this.nameColor,
    this.mutedColor,
    this.frameColor,
  });

  final Person person;
  final String summary;
  final VoidCallback onTap;
  final VoidCallback? onAvatarTap;
  final VoidCallback onOpenIdea;
  final VoidCallback onNotSuitable;
  final VoidCallback onOpenCard;
  final bool hasIdea;
  final bool dismissed;
  final Widget? tag;
  final Color? surfaceColor;
  final Color? nameColor;
  final Color? mutedColor;
  final Color? frameColor;

  static const double avatarRadius = 28;
  static const double _tagSlot = 18;

  /// The height every square in a grid is given: computed from the type the
  /// square draws, put through the reader's own text size, so a square never
  /// overflows at large text and every square in the grid is the same height.
  static double extentFor(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle? style, double fallback) =>
        scaler.scale((style?.fontSize ?? fallback) * 1.45);
    final double name = line(theme.textTheme.titleSmall, 14);
    final double summary = line(theme.textTheme.bodySmall, 12);
    final double tag = scaler.scale(_tagSlot);
    // The answer: its padding, the 32px disc, the gap, and its word.
    final double action = 6 + 32 + 3 + scaler.scale(10.5 * 1.4);
    return 10 + avatarRadius * 2 + 6 + name + summary + tag + 4 + action + 10;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = mutedColor ?? theme.colorScheme.onSurfaceVariant;
    final String name = person.fullName.trim();
    final double tagSlot = MediaQuery.textScalerOf(context).scale(_tagSlot);

    return SuggestionFrame(
      surfaceColor: surfaceColor,
      frameColor: frameColor,
      onTap: onTap,
      child: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
            child: Column(
              children: <Widget>[
                GestureDetector(
                  onTap: onAvatarTap,
                  child: PersonAvatar(person: person, radius: avatarRadius),
                ),
                const SizedBox(height: 6),
                Text(
                  name.isEmpty ? 'ללא שם' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: nameColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                // A slot of its own, held even when empty, so the answers sit
                // at the same height in every square.
                SizedBox(
                  height: tagSlot,
                  child: tag == null
                      ? null
                      : Center(
                          child: FittedBox(fit: BoxFit.scaleDown, child: tag),
                        ),
                ),
                const Spacer(),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: IdeaAction(
                        kind: hasIdea
                            ? IdeaActionKind.existingIdea
                            : IdeaActionKind.openIdea,
                        onTap: onOpenIdea,
                      ),
                    ),
                    Expanded(
                      child: IdeaAction(
                        kind: dismissed
                            ? IdeaActionKind.restore
                            : IdeaActionKind.notSuitable,
                        onTap: onNotSuitable,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Into the full card, in the square's far corner (where the arrow
          // points) — the same arrow and the same word as at the end of a row.
          PositionedDirectional(
            top: 2,
            end: 2,
            child: IconButton(
              tooltip: 'פתיחת הכרטיס',
              onPressed: onOpenCard,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.chevron_right_rounded, color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
