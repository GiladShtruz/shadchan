import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/community_tags_service.dart';
import 'package:shadchan/services/tag_library.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/person_tags.dart';

/// Tags on one friend: the matchmaker's own words for sorting a big database.
///
/// **Light and secondary, in a fixed order of priority:**
///
/// 1. "+ הוספת תגית חדשה" — the first thing, because the point is for each
///    matchmaker to build their own language;
/// 2. the tags this matchmaker already made, so reusing one is one tap;
/// 3. for somebody with none yet, a handful of starters — shown explicitly as
///    examples, not as "popular" and not as a list to follow;
/// 4. "השראה מהקהילה" — folded away, a small scrolling box of words other
///    matchmakers use, loaded only when opened.
///
/// One field does both jobs: it filters every chip below it, and when what is
/// typed is not a tag yet it offers to create it.
class PersonTagsEditor extends StatefulWidget {
  const PersonTagsEditor({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  State<PersonTagsEditor> createState() => _PersonTagsEditorState();
}

class _PersonTagsEditorState extends State<PersonTagsEditor> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _typing = false;
  bool _communityOpen = false;
  Future<List<String>>? _community;

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _has(String tag) =>
      widget.selected.any((String t) => PersonTags.sameTag(t, tag));

  void _toggle(String tag) {
    final String value = PersonTags.normalize(tag);
    final List<String> next = _has(value)
        ? widget.selected
              .where((String t) => !PersonTags.sameTag(t, value))
              .toList()
        : <String>[...widget.selected, value];
    if (!_has(value)) {
      // Chosen from a suggestion or the community: it is theirs from now on.
      TagLibrary.remember(value);
    }
    widget.onChanged(next);
    setState(() {});
  }

  void _create() {
    final String value = PersonTags.normalize(_query.text);
    if (value.isEmpty) {
      return;
    }
    final String clipped = value.length > PersonTags.maxLength
        ? value.substring(0, PersonTags.maxLength).trim()
        : value;
    TagLibrary.remember(clipped);
    if (!_has(clipped)) {
      widget.onChanged(<String>[...widget.selected, clipped]);
    }
    _query.clear();
    setState(() {});
  }

  bool _matches(String tag) {
    final String q = PersonTags.keyOf(_query.text);
    return q.isEmpty || PersonTags.keyOf(tag).contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Person> people = context.watch<PersonRepository>().getAll();
    // The friend's own tags lead, whatever the library says.
    final List<String> mine = <String>[
      ...widget.selected,
      ...TagLibrary.personal(people).where((String tag) => !_has(tag)),
    ];
    final String typed = PersonTags.normalize(_query.text);
    final bool canCreate =
        typed.isNotEmpty &&
        !mine.any((String tag) => PersonTags.sameTag(tag, typed));
    final List<String> shownMine = mine.where(_matches).toList();
    final bool starters = mine.isEmpty;
    final List<String> shownStarters = starters
        ? PersonTags.starters.where(_matches).toList()
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 1. A new tag — or a search, in the same field.
        if (!_typing)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () {
                setState(() => _typing = true);
                _focus.requestFocus();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('הוספת תגית חדשה'),
            ),
          )
        else
          TextField(
            controller: _query,
            focusNode: _focus,
            maxLength: PersonTags.maxLength,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _create(),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'תגית חדשה או חיפוש בתגיות',
              prefixIcon: const Icon(Icons.sell_outlined, size: 18),
              suffixIcon: IconButton(
                tooltip: 'סגירה',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _query.clear();
                  _focus.unfocus();
                  setState(() => _typing = false);
                },
              ),
            ),
          ),
        if (canCreate) ...<Widget>[
          const SizedBox(height: 6),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: Text('יצירת התגית "$typed"'),
            onPressed: _create,
            visualDensity: VisualDensity.compact,
          ),
        ],

        // 2. Mine.
        if (shownMine.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _TagWrap(tags: shownMine, isSelected: _has, onTap: _toggle),
        ],

        // 3. Examples, only until there is a tag of one's own.
        if (shownStarters.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            'הצעות להתחלה — דוגמאות בלבד, לבחור רק מה שמתאים לך',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          _TagWrap(tags: shownStarters, isSelected: _has, onTap: _toggle),
        ],

        // 4. The community, folded away.
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => setState(() {
              _communityOpen = !_communityOpen;
              _community ??= CommunityTagsService.inspiration();
            }),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
              textStyle: theme.textTheme.labelMedium,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('השראה מהקהילה'),
                Icon(
                  _communityOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (_communityOpen)
          FutureBuilder<List<String>>(
            future: _community,
            builder: (BuildContext context, AsyncSnapshot<List<String>> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              final List<String> words = (snap.data ?? const <String>[])
                  .where(
                    (String word) =>
                        !mine.any((String t) => PersonTags.sameTag(t, word)),
                  )
                  .where(_matches)
                  .toList();
              if (words.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    'עוד אין כאן תגיות מהקהילה',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Container(
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: _TagWrap(
                    tags: words,
                    isSelected: _has,
                    onTap: _toggle,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _TagWrap extends StatelessWidget {
  const _TagWrap({
    required this.tags,
    required this.isSelected,
    required this.onTap,
  });

  final List<String> tags;
  final bool Function(String tag) isSelected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final String tag in tags)
          TagChip(
            label: tag,
            selected: isSelected(tag),
            onTap: () => onTap(tag),
          ),
      ],
    );
  }
}

/// One small, clean tag chip: outlined at rest, filled lightly when on.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;

    return Material(
      color: selected ? ink.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? ink.withValues(alpha: 0.55)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected) ...<Widget>[
                Icon(Icons.check_rounded, size: 14, color: ink),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? ink : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
