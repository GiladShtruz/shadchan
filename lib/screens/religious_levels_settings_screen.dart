import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/religious_levels_provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/gender_text.dart';

/// Lets the matchmaker choose which religious styles the app offers, and add
/// their own labels under "אחר".
class ReligiousLevelsSettingsScreen extends StatelessWidget {
  const ReligiousLevelsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ReligiousLevelsProvider provider = context
        .watch<ReligiousLevelsProvider>();
    final List<String> customLabels = provider.customLabels;

    return Scaffold(
      appBar: AppBar(title: const Text('הגדרות דתיות'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Text(
              '{בחר|בחרי} אילו סגנונות דתיים יופיעו באפליקציה בעת עריכת כרטיס '
                      'וסינון המאגר.'
                  .forGender(context.userGender),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final ReligiousLevel level
                in ReligiousLevelsProvider.selectableLevels)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(level.displayName),
                value: provider.isEnabled(level),
                onChanged: (bool? value) =>
                    provider.setEnabled(level, value ?? false),
              ),
            const Divider(height: 32),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('אחר', style: theme.textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => _addCustomLabel(context, provider),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('הוספה'),
                ),
              ],
            ),
            Text(
              'הגדרה אישית משלך, שתופיע לצד שאר הסגנונות.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (customLabels.isEmpty)
              Text(
                'עוד לא הוספתם הגדרה אישית.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final String label in customLabels)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label),
                  trailing: IconButton(
                    tooltip: 'הסרה',
                    icon: const Icon(Icons.close),
                    onPressed: () => provider.removeCustomLabel(label),
                  ),
                ),
            const Divider(height: 32),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: provider.resetToDefaults,
                child: const Text('חזרה לברירת המחדל'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addCustomLabel(
    BuildContext context,
    ReligiousLevelsProvider provider,
  ) async {
    final TextEditingController controller = TextEditingController();
    final String? label = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('הגדרה אישית'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'שם הסגנון'),
            onSubmitted: (String value) =>
                Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('הוספה'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (label != null) {
      await provider.addCustomLabel(label);
    }
  }
}
