import 'package:flutter/material.dart';
import 'package:shadchan/services/mazel_tov_service.dart';
import 'package:shadchan/widgets/community_widgets.dart';

/// "שלחו מזל טוב" — the whole of sending one.
///
/// **Four taps' worth of thought, and none of them required.** A ready-made
/// bracha sends on one tap; anybody who wants to write their own has a field
/// under them. There is no subject, no recipient picker and no thread, because
/// there is exactly one person this can go to and exactly one thing it can be
/// about.
///
/// It never reveals who it is going to. The announcement it answers says "a
/// couple got married"; the sender learns nothing more by congratulating, and
/// the recipient's name is not in this sheet even when the app happens to know
/// it — what would be gained is a name, and what would be risked is turning a
/// bracha into an introduction.
class MazelTovSheet extends StatefulWidget {
  const MazelTovSheet({super.key});

  /// Returns the chosen text, or null when the sheet was dismissed.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => const MazelTovSheet(),
    );
  }

  @override
  State<MazelTovSheet> createState() => _MazelTovSheetState();
}

class _MazelTovSheetState extends State<MazelTovSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(String text) {
    final String message = text.trim();
    if (message.isEmpty) {
      return;
    }
    Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lead = communityLead(theme);
    final String typed = _controller.text.trim();

    return Padding(
      // Above the keyboard, which is open the moment somebody starts writing
      // their own line.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'שליחת מזל טוב',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'הברכה תגיע לשדכן, אל ההיסטוריה של אותה הצעה. '
                'שום פרט על הזוג לא נחשף לך ולא נשלח.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              for (final String suggestion in MazelTovService.suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _send(suggestion),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: lead.withValues(alpha: 0.09),
                        border: Border.all(color: lead.withValues(alpha: 0.22)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              suggestion,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.send_rounded, size: 16, color: lead),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                maxLength: MazelTovService.maxLength,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'או כתיבת ברכה משלך',
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: typed.isEmpty ? null : () => _send(typed),
                icon: const Icon(Icons.favorite_rounded, size: 18),
                label: const Text('שליחה'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
