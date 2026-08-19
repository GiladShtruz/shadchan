import 'package:flutter/material.dart';
import 'package:shadchan/utils/app_colors.dart';

/// "נוספו X אנשים למאגר" — the moment an import finishes.
///
/// **The largest thing this app ever does, acknowledged in the middle of the
/// screen.** It used to be a toast along the bottom edge: a strip of text that
/// faded in three seconds, after a flow that can take several minutes and adds
/// hundreds of people. The number deserves to be looked at, and the person who
/// waited for it deserves to see it land.
///
/// It closes itself after a few seconds, and a tap closes it sooner. There is
/// no button: what happens next — landing on the people who were just added —
/// happens either way, so a button would only be a thing to press before being
/// allowed to continue.
class ImportedBanner extends StatefulWidget {
  const ImportedBanner({super.key, required this.added});

  /// How long it stays if nobody touches it.
  static const Duration visibleFor = Duration(milliseconds: 2200);

  final int added;

  /// Shows the banner and returns when it has gone.
  static Future<void> show(BuildContext context, {required int added}) {
    if (added <= 0) {
      return Future<void>.value();
    }
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (BuildContext context) => ImportedBanner(added: added),
    );
  }

  @override
  State<ImportedBanner> createState() => _ImportedBannerState();
}

class _ImportedBannerState extends State<ImportedBanner> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(ImportedBanner.visibleFor, () {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color tone = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: theme.colorScheme.surface,
            border: Border.all(color: tone.withValues(alpha: 0.28), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: dark ? 0.22 : 0.14),
                ),
                child: Icon(Icons.groups_rounded, size: 38, color: tone),
              ),
              const SizedBox(height: 20),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'נוספו ${widget.added} אנשים למאגר',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'עכשיו נראה אותם ברשימה נפרדת, כדי שיהיה קל לעבור עליהם '
                'ולהשלים פרטים.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
