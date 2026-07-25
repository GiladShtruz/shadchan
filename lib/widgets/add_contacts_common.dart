import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The white, softly shadowed card the add-contacts screens are built from.
/// Light mode gets a barely-there drop shadow over the cream background; dark
/// mode drops it and leans on a hairline outline instead.
BoxDecoration softCardDecoration(
  BuildContext context, {
  double radius = 18,
  Color? color,
  Color? borderColor,
}) {
  final ThemeData theme = Theme.of(context);
  final bool dark = theme.brightness == Brightness.dark;

  return BoxDecoration(
    color: color ?? theme.colorScheme.surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color:
          borderColor ??
          (dark
              ? theme.colorScheme.outline.withValues(alpha: 0.6)
              : AppColors.outline.withValues(alpha: 0.5)),
    ),
    boxShadow: dark
        ? null
        : <BoxShadow>[
            BoxShadow(
              color: AppColors.onSurface.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
  );
}

/// The small progress block at the top of both add-contacts views: how many
/// friends are already in the database and — in the swipe view — how many
/// contacts are still waiting to be reviewed.
class AddContactsProgressHeader extends StatelessWidget {
  const AddContactsProgressHeader({
    super.key,
    required this.addedToDatabase,
    this.remaining,
    this.total,
  });

  /// People currently in the matchmaker's database.
  final int addedToDatabase;

  /// Contacts left in the swipe deck, or null in the list view.
  final int? remaining;

  /// Size of the deck the [remaining] count is measured against.
  final int? total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? remaining = this.remaining;
    final int? total = this.total;
    final bool showRemaining =
        remaining != null && total != null && total > 0 && remaining > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: softCardDecoration(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.favorite,
                size: 18,
                color: theme.brightness == Brightness.dark
                    ? AppColors.femaleAccentDm
                    : AppColors.femaleAccent,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'כבר הוספת $addedToDatabase חברים למאגר',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (showRemaining) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'נשארו עוד $remaining אנשי קשר',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: ((total - remaining) / total).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.outlineVariant,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.brightness == Brightness.dark
                                ? theme.colorScheme.primary
                                : AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One number plus its label inside [AddContactsStatsRow].
class AddContactsStat {
  const AddContactsStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
}

/// The compact "added / skipped / not relevant" tally under the swipe header.
class AddContactsStatsRow extends StatelessWidget {
  const AddContactsStatsRow({super.key, required this.stats});

  final List<AddContactsStat> stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: softCardDecoration(context, radius: 16),
      child: Row(
        children: <Widget>[
          for (final AddContactsStat stat in stats)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(stat.icon, size: 15, color: stat.color),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '${stat.label} ${stat.value}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
