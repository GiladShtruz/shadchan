import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/theme_mode_provider.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// "התאמה אישית" — the light/dark choice.
///
/// Light is the default for everybody; dark is one switch away and is saved
/// to the account, so it follows the matchmaker to every phone.
class SettingsAppearanceScreen extends StatelessWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ThemeModeProvider themeMode = context.watch<ThemeModeProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('התאמה אישית')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SettingsGroup(
              title: 'תצוגה',
              children: <Widget>[
                // One switch, because there are only two answers: the app is
                // light unless somebody asks for dark here. The device's own
                // setting is deliberately not consulted — see
                // [ThemeModeProvider].
                SwitchListTile(
                  secondary: Icon(
                    themeMode.isDark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('תצוגה כהה'),
                  subtitle: const Text(
                    'הבחירה נשמרת בחשבון שלך ותופיע בכל מכשיר שמחובר אליו',
                  ),
                  value: themeMode.isDark,
                  onChanged: (bool dark) => themeMode.setThemeMode(
                    dark ? ThemeMode.dark : ThemeMode.light,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
