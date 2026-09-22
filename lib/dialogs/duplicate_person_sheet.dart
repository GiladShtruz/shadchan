import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// What the matchmaker decided about a card that looks like one already there.
class DuplicateChoice {
  const DuplicateChoice.merge(Person this.existing);

  const DuplicateChoice.createNew() : existing = null;

  /// The card to fold the new details into, or null for "a different person".
  final Person? existing;
}

/// "נראה שהחבר הזה כבר במאגר" — the new card beside the one it resembles.
///
/// **Shown before anything is merged, never after.** Two people can share a
/// name, so the app does not decide: it lays the two cards out side by side —
/// photo, name, age, city, phone, religious style, marital status — and the
/// matchmaker, who knows them, says whether it is the same friend. Merging only
/// fills gaps on the existing card; see `PersonMerge.fillGaps`.
class DuplicatePersonSheet extends StatelessWidget {
  const DuplicatePersonSheet({
    super.key,
    required this.draft,
    required this.candidates,
  });

  final Person draft;
  final List<Person> candidates;

  /// Null when the sheet was dismissed: nothing is saved either way.
  static Future<DuplicateChoice?> show(
    BuildContext context, {
    required Person draft,
    required List<Person> candidates,
  }) {
    return showModalBottomSheet<DuplicateChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) =>
          DuplicatePersonSheet(draft: draft, candidates: candidates),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color lead = dark ? theme.colorScheme.primary : AppColors.primaryDark;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              candidates.length == 1
                  ? 'נראה שהכרטיס הזה כבר במאגר'
                  : 'נראה שיש במאגר כרטיסים דומים',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'כדי לא ליצור כרטיס כפול אפשר לאחד את הפרטים החדשים לכרטיס '
              'הקיים. כדאי לבדוק קודם שמדובר באותו אדם.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            for (final Person existing in candidates) ...<Widget>[
              _Comparison(draft: draft, existing: existing),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(DuplicateChoice.merge(existing)),
                style: FilledButton.styleFrom(
                  backgroundColor: lead,
                  foregroundColor: theme.colorScheme.onPrimary,
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.merge_rounded, size: 20),
                label: Text(
                  candidates.length == 1
                      ? 'איחוד לכרטיס הקיים'
                      : 'איחוד לכרטיס של ${existing.fullName}',
                ),
              ),
              const SizedBox(height: 18),
            ],
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).pop(const DuplicateChoice.createNew()),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              child: const Text('זה אדם אחר — יצירת כרטיס חדש'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The two cards, column by column: the new one on the reading edge.
class _Comparison extends StatelessWidget {
  const _Comparison({required this.draft, required this.existing});

  final Person draft;
  final Person existing;

  static String _text(String? value) {
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? '—' : trimmed;
  }

  static String _religious(Person person) {
    final String other = (person.religiousLevelOther ?? '').trim();
    if (other.isNotEmpty) {
      return other;
    }
    return person.religiousLevel?.displayName ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final List<(String, String, String)> rows = <(String, String, String)>[
      ('גיל', _text(draft.age?.toString()), _text(existing.age?.toString())),
      ('עיר', _text(draft.city), _text(existing.city)),
      ('טלפון', _text(draft.phone), _text(existing.phone)),
      ('סגנון דתי', _religious(draft), _religious(existing)),
      (
        'מצב משפחתי',
        draft.maritalStatus?.displayNameFor(draft.gender) ?? '—',
        existing.maritalStatus?.displayNameFor(existing.gender) ?? '—',
      ),
    ];

    Widget header(String caption, Person person) {
      return Expanded(
        child: Column(
          children: <Widget>[
            Text(
              caption,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            PersonAvatar(person: person, radius: 26),
            const SizedBox(height: 6),
            Text(
              person.fullName,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              header('הכרטיס החדש', draft),
              const SizedBox(width: 8),
              header('הכרטיס שבמאגר', existing),
            ],
          ),
          const SizedBox(height: 8),
          for (final (String label, String left, String right) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                children: <Widget>[
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      for (final String value in <String>[
                        left,
                        right,
                      ]) ...<Widget>[
                        Expanded(
                          child: Text(
                            value,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              // A difference is what decides "same person?",
                              // so it is the thing drawn in ink.
                              fontWeight: left != right
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (value == left) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
