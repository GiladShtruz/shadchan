import 'package:flutter/material.dart';
import 'package:shadchan/providers/match_repository.dart'
    show MatchOutcomeParty;
import 'package:shadchan/utils/enums.dart';

/// Asks why a proposal ended, so closing it can be written to both candidates'
/// history properly.
///
/// Two shapes, because the two closings are different questions. A proposal
/// that never got off the ground is asked **why it did not progress**, in the
/// matchmaker's own words — "פחות התאים לו" is what actually happened, and it
/// is more useful six months from now than a name with a verdict attached. A
/// couple who dated and stopped is asked who ended it, which is the fact that
/// matters there.
///
/// The note is the point of the whole screen: it is the one place a matchmaker
/// records what they learned, and it lands on both candidates' histories.
class MatchOutcomeDialog extends StatefulWidget {
  const MatchOutcomeDialog({super.key, required this.status});

  final MatchStatus status;

  /// Returns the chosen party and note, or null when it was cancelled.
  static Future<({MatchOutcomeParty party, String note})?> show(
    BuildContext context,
    MatchStatus status,
  ) {
    return showDialog<({MatchOutcomeParty party, String note})>(
      context: context,
      builder: (BuildContext context) => MatchOutcomeDialog(status: status),
    );
  }

  @override
  State<MatchOutcomeDialog> createState() => _MatchOutcomeDialogState();
}

/// One answer, and which side it puts the decision on.
class _Reason {
  const _Reason(this.label, this.party);

  final String label;
  final MatchOutcomeParty party;
}

class _MatchOutcomeDialogState extends State<MatchOutcomeDialog> {
  final TextEditingController _noteController = TextEditingController();

  /// Nothing is chosen at first: a pre-ticked answer is one the matchmaker
  /// never actually gave, and it would end up in two people's histories.
  MatchOutcomeParty? _party;

  bool get _dated => widget.status == MatchStatus.dated;

  List<_Reason> get _reasons => _dated
      ? const <_Reason>[
          _Reason('הוא', MatchOutcomeParty.him),
          _Reason('היא', MatchOutcomeParty.her),
          _Reason('הדדי', MatchOutcomeParty.mutual),
          _Reason('לא ידוע', MatchOutcomeParty.unknown),
        ]
      : const <_Reason>[
          _Reason('פחות התאים לו', MatchOutcomeParty.him),
          _Reason('פחות התאים לה', MatchOutcomeParty.her),
          _Reason('מהבירור עלה שזה פחות מתאים', MatchOutcomeParty.mutual),
          _Reason('סיבה אחרת', MatchOutcomeParty.unknown),
        ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        _dated ? 'מי סיים?' : 'מה הייתה הסיבה שהרעיון לא התקדם?',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final _Reason reason in _reasons) _option(reason),
            const SizedBox(height: 12),
            // Said before the field rather than under it: it is an invitation
            // to write, and an invitation after the fact is a caption.
            Text(
              'כדאי לתעד כאן כל פרט שיכול לעזור בהמשך. ההערה תישמר בהיסטוריה '
              'של שני המועמדים ותעזור לך לדייק רעיונות עתידיים.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'הערה',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: _party == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop((party: _party!, note: _noteController.text.trim())),
          child: const Text('שמירה'),
        ),
      ],
    );
  }

  Widget _option(_Reason reason) {
    final bool selected = _party == reason.party;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(reason.label),
      onTap: () => setState(() => _party = reason.party),
    );
  }
}
