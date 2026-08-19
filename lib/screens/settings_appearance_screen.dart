import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "תצוגה וערכת נושא" — the light/dark choice, and the way to the religious
/// styles.
///
/// Small enough that it looks like it did not need a screen, and that is the
/// point: three segments and a row do not belong at the head of the settings
/// where they were, above everything a matchmaker actually goes there to do.
class SettingsAppearanceScreen extends StatelessWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ThemeModeProvider themeMode = context.watch<ThemeModeProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('התאמה אישית'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SettingsGroup(
              title: 'תצוגה',
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            'ערכת נושא',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          // The mode icons ride along with the title instead of
                          // inside the segments, which had no room for them;
                          // the active one lights up so the row still says
                          // which mode is on.
                          for (final (ThemeMode mode, IconData icon) entry
                              in <(ThemeMode, IconData)>[
                                (
                                  ThemeMode.system,
                                  Icons.brightness_auto_outlined,
                                ),
                                (ThemeMode.light, Icons.light_mode_outlined),
                                (ThemeMode.dark, Icons.dark_mode_outlined),
                              ])
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 10,
                              ),
                              child: Icon(
                                entry.$2,
                                size: 20,
                                color: themeMode.themeMode == entry.$1
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.45),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<ThemeMode>(
                        // A third of the card is not enough for an icon, a
                        // checkmark and 'אוטומטי' side by side — that is what
                        // pushed the last letter onto a second line. Labels
                        // only, and a scale-down guard so a large system font
                        // shrinks the text instead of wrapping or clipping it.
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        segments: const <ButtonSegment<ThemeMode>>[
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.system,
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'אוטומטי',
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.light,
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('בהיר', maxLines: 1, softWrap: false),
                            ),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.dark,
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('כהה', maxLines: 1, softWrap: false),
                            ),
                          ),
                        ],
                        selected: <ThemeMode>{themeMode.themeMode},
                        onSelectionChanged: (Set<ThemeMode> selection) {
                          themeMode.setThemeMode(selection.first);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: 'המאגר',
              children: <Widget>[
                SettingsRow(
                  icon: Icons.style_outlined,
                  title: 'סגנונות דתיים',
                  subtitle: 'אילו סגנונות יופיעו באפליקציה',
                  onTap: () => context.push('/profile/religious-levels'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
