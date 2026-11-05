import 'package:flutter/material.dart';
import 'package:shadchan/services/auto_match_rules.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_tags_editor.dart';

/// "סינון אוטומטי בהתאמות" — the criteria התאמות opens on for every friend who
/// has no filter of their own ([AutoMatchRules]).
///
/// Two things, each said the way a matchmaker would say it: how far apart in
/// age a pair may be, in the three age bands the rule has always had, and which
/// religious styles are offered to each style. Every change is saved at once
/// and used the next time a list of matches is opened; "חזרה לברירת המחדל"
/// puts back the rules the app came with.
class SettingsAutoMatchScreen extends StatefulWidget {
  const SettingsAutoMatchScreen({super.key});

  @override
  State<SettingsAutoMatchScreen> createState() =>
      _SettingsAutoMatchScreenState();
}

class _SettingsAutoMatchScreenState extends State<SettingsAutoMatchScreen> {
  AutoMatchRules _rules = AutoMatchRules.current;

  void _update(AutoMatchRules rules) {
    setState(() => _rules = rules);
    AutoMatchRules.save(rules);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('סינון אוטומטי בהתאמות')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            Text(
              'כך נבחרות ההתאמות לחבר שלא הגדרת לו סינון משלו. '
              'כשרווק מנהל את הכרטיס שלו ובחר "מה אני מחפש/ת", הבחירה שלו קודמת.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            HomePaperCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text('הפרש גילים', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'לפי הגיל של הבחור. בחורה רואה את הבחורים שהכלל הזה '
                      'מתאים לה.',
                      style: theme.textTheme.bodySmall,
                    ),
                    for (final AgeBandKind kind in AgeBandKind.values)
                      _AgeBandEditor(
                        kind: kind,
                        band: _rules.band(kind),
                        onChanged: (AgeBand band) =>
                            _update(_rules.withBand(kind, band)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            HomePaperCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text('סגנון דתי', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'לכל סגנון — אילו סגנונות יוצעו לו. הסגנון עצמו תמיד '
                      'כלול.',
                      style: theme.textTheme.bodySmall,
                    ),
                    for (final ReligiousLevel level in ReligiousLevels.global)
                      _StyleEditor(
                        level: level,
                        chosen: _rules.stylesFor(level)!,
                        onChanged: (List<ReligiousLevel> styles) =>
                            _update(_rules.withStyles(level, styles)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton.icon(
                onPressed: _rules.isDefault
                    ? null
                    : () => _update(AutoMatchRules.defaults),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('חזרה לברירת המחדל'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgeBandEditor extends StatelessWidget {
  const _AgeBandEditor({
    required this.kind,
    required this.band,
    required this.onChanged,
  });

  final AgeBandKind kind;
  final AgeBand band;
  final ValueChanged<AgeBand> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'בחור ${kind.label}',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          _YearsStepper(
            label: 'בחורה צעירה ממנו עד',
            value: band.younger,
            onChanged: (int v) => onChanged(band.copyWith(younger: v)),
          ),
          _YearsStepper(
            label: 'בחורה מבוגרת ממנו עד',
            value: band.older,
            onChanged: (int v) => onChanged(band.copyWith(older: v)),
          ),
        ],
      ),
    );
  }
}

class _YearsStepper extends StatelessWidget {
  const _YearsStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String years = value == 1 ? 'שנה' : '$value שנים';
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        IconButton(
          tooltip: '$label — פחות',
          visualDensity: VisualDensity.compact,
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 62,
          child: Text(
            value == 0 ? 'בלי' : years,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          tooltip: '$label — יותר',
          visualDensity: VisualDensity.compact,
          onPressed: value < AutoMatchRules.maxYears
              ? () => onChanged(value + 1)
              : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _StyleEditor extends StatelessWidget {
  const _StyleEditor({
    required this.level,
    required this.chosen,
    required this.onChanged,
  });

  final ReligiousLevel level;
  final List<ReligiousLevel> chosen;
  final ValueChanged<List<ReligiousLevel>> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            level.displayName,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final ReligiousLevel other in ReligiousLevels.global)
                TagChip(
                  label: other.displayName,
                  selected: chosen.contains(other),
                  // The style itself is always offered to itself.
                  onTap: other == level
                      ? () {}
                      : () => onChanged(
                          chosen.contains(other)
                              ? (chosen.toList()..remove(other))
                              : <ReligiousLevel>[...chosen, other],
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
