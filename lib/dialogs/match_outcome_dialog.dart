import 'package:flutter/material.dart';
import 'package:shadchan/providers/match_repository.dart'
    show MatchOutcomeParty;
import 'package:shadchan/utils/enums.dart';

/// Asks who ended a proposal and why, so closing it can be written to both
/// candidates' history properly.
///
/// Shared by the proposal screen's "סגירת ההצעה" flow and the status sheet's
/// "נדחתה" option — both close a proposal, so both have to collect the same
/// answers and go through `MatchRepository.recordOutcome`.
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

class _MatchOutcomeDialogState extends State<MatchOutcomeDialog> {
  final TextEditingController _noteController = TextEditingController();
  MatchOutcomeParty _party = MatchOutcomeParty.unknown;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.status == MatchStatus.dated
            ? 'יצאו ולא המשיכו'
            : 'ההצעה לא התקדמה',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('מי סיים?'),
            _option(MatchOutcomeParty.him, 'הוא'),
            _option(MatchOutcomeParty.her, 'היא'),
            _option(MatchOutcomeParty.mutual, 'הדדי'),
            _option(MatchOutcomeParty.unknown, 'לא ידוע'),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'סיבה או הערה (אופציונלי)',
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
          onPressed: () => Navigator.of(
            context,
          ).pop((party: _party, note: _noteController.text.trim())),
          child: const Text('שמירה'),
        ),
      ],
    );
  }

  Widget _option(MatchOutcomeParty value, String label) {
    final bool selected = _party == value;
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
      title: Text(label),
      onTap: () => setState(() => _party = value),
    );
  }
}
