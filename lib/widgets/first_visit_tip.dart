import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/app_colors.dart';

/// The screens that explain themselves once, on the first visit.
///
/// A topic is only a *key* — what it is shown as is the screen's own choice.
/// [friendProfile] draws the inline [FirstVisitTip] below; [addFriends] opens
/// `AddContactsIntroDialog`, because what it has to say is the reason to use
/// the screen at all rather than a hint about its controls.
enum FirstVisitTopic {
  /// "הוספת אנשי קשר": why a bigger database is a better one.
  addFriends('firstVisit.addFriends'),

  /// A friend's profile: the photo and the words are already in WhatsApp.
  friendProfile('firstVisit.friendProfile');

  const FirstVisitTopic(this.key);

  final String key;
}

/// Whether a screen has been visited before.
///
/// **Taken, not peeked.** [takeFirstVisit] answers and records in one call, so
/// the tip belongs to the first visit whether or not it was closed by hand — a
/// hint that returned until somebody found its close button would be a nag.
/// Writes go through [persistHomeSetting] for the reason documented there, and
/// `_pending` covers the moment between the answer and the box having it.
abstract final class FirstVisitTips {
  static final Map<String, bool> _pending = <String, bool>{};

  static bool takeFirstVisit(FirstVisitTopic topic) {
    final Object? stored = Hive.isBoxOpen('settings')
        ? Hive.box<dynamic>('settings').get(topic.key)
        : null;
    if (_pending[topic.key] == true || stored == true || stored == 'true') {
      return false;
    }
    _pending[topic.key] = true;
    persistHomeSetting(topic.key, 'true');
    return true;
  }

  @visibleForTesting
  static void resetForTest() => _pending.clear();
}

/// A short explanation at the top of a screen, shown on the first visit only.
///
/// Inline, and so never between the matchmaker and the screen it describes: a
/// back press over one of these still means "leave". That is the right shape
/// for a hint about a screen somebody is already using — see [FirstVisitTopic]
/// for the case that is not.
class FirstVisitTip extends StatelessWidget {
  const FirstVisitTip({
    super.key,
    required this.icon,
    required this.headline,
    this.lines = const <String>[],
    this.action,
    required this.onDismiss,
  });

  final IconData icon;
  final String headline;
  final List<String> lines;

  /// One optional button under the text — the thing the tip is pointing at.
  final Widget? action;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 4, 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          lead.withValues(alpha: dark ? 0.18 : 0.08),
          theme.colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: lead.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lead.withValues(alpha: dark ? 0.24 : 0.12),
            ),
            child: Icon(icon, size: 18, color: lead),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    headline,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
                for (final String line in lines) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    line,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
                if (action != null) ...<Widget>[
                  const SizedBox(height: 4),
                  action!,
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'סגירה',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
