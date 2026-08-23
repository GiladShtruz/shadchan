import 'package:flutter/material.dart';
import 'package:shadchan/services/diagnostics_log.dart';
import 'package:shadchan/utils/app_router.dart';

/// Says so, once, when the previous launch died before the app appeared.
///
/// **The person holding the phone is the only witness.** A startup crash leaves
/// nothing on screen to screenshot and nothing in the store console that could
/// be read, so the only way the details ever reach anybody is if the app asks
/// for them the next time it manages to open. It asks exactly once per launch,
/// it asks quietly, and "לא עכשיו" is a real answer — the log is still sitting
/// in "יומן תקלות" under עזרה afterwards.
///
/// The rule behind it is [DiagnosticsLog.previousRunCrashed]: the last run
/// never wrote `first_frame`. Closing the app normally, force-quitting it, even
/// being killed in the background hours later all leave that line behind, so
/// none of them look like this.
class StartupCrashNotice extends StatefulWidget {
  const StartupCrashNotice({super.key, required this.child});

  final Widget child;

  @override
  State<StartupCrashNotice> createState() => _StartupCrashNoticeState();
}

class _StartupCrashNoticeState extends State<StartupCrashNotice> {
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    if (DiagnosticsLog.previousRunCrashed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
    }
  }

  Future<void> _ask() async {
    if (_asked || !mounted) {
      return;
    }
    _asked = true;

    final String step = DiagnosticsLog.previousRunLastStep;
    final bool? open = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('האפליקציה נסגרה בפעם הקודמת'),
        content: Text(
          step.isEmpty
              ? 'בהפעלה הקודמת האפליקציה נסגרה לפני שהספיקה להיפתח. '
                    'שמרנו יומן קצר של מה שקרה — אפשר להעתיק אותו ולשלוח לנו, '
                    'וזה בדיוק מה שיעזור לתקן.'
              : 'בהפעלה הקודמת האפליקציה נסגרה לפני שהספיקה להיפתח, '
                    'אחרי השלב "$step". שמרנו יומן קצר של מה שקרה — אפשר '
                    'להעתיק אותו ולשלוח לנו, וזה בדיוק מה שיעזור לתקן.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('לא עכשיו'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('הצגת היומן'),
          ),
        ],
      ),
    );
    if (open == true) {
      AppRouter.router.push('/support/diagnostics');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
