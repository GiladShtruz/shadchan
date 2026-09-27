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
/// **One fixed order, always the same three shelves:**
///
/// 1. the app's default tags ([PersonTags.starters]) — **always** drawn, picked
///    or not. They used to be offered only until the matchmaker had a tag of
///    their own, so the first tap on one made the whole row disappear;
/// 2. the tags this matchmaker made (or took from the community), recently
///    used first, with the ones on this friend leading;
/// 3. "השראה מהקהילה" — folded away, words other matchmakers use, **most used
///    first**, loaded only when opened.
///
/// Above them, "+ הוספת תגית חדשה" opens one field that does both jobs: it
/// filters every chip below it, and when what is typed is not a tag yet it
/// offers to create it.
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

    bool isDefault(String tag) =>
        PersonTags.starters.any((String s) => PersonTags.sameTag(s, tag));

    // 1. The defaults, in their own fixed order, whatever has been picked.
    final List<String> defaults = PersonTags.starters;

    // 2. The matchmaker's own — this friend's first, then the library.
    final List<String> personal = <String>[];
    for (final String tag in <String>[
      ...widget.selected,
      ...TagLibrary.personal(people),
    ]) {
      if (isDefault(tag) ||
          personal.any((String t) => PersonTags.sameTag(t, tag))) {
        continue;
      }
      personal.add(tag);
    }

    bool known(String tag) =>
        isDefault(tag) ||
        personal.any((String t) => PersonTags.sameTag(t, tag));

    final String typed = PersonTags.normalize(_query.text);
    final bool canCreate = typed.isNotEmpty && !known(typed);
    final List<String> shownDefaults = defaults.where(_matches).toList();
    final List<String> shownPersonal = personal.where(_matches).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // A new tag — or a search, in the same field.
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

        // 1. Defaults — always there.
        if (shownDefaults.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _ShelfLabel('תגיות מוכנות'),
          const SizedBox(height: 6),
          _TagWrap(tags: shownDefaults, isSelected: _has, onTap: _toggle),
        ],

        // 2. Mine.
        if (shownPersonal.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _ShelfLabel('התגיות שלי'),
          const SizedBox(height: 6),
          _TagWrap(tags: shownPersonal, isSelected: _has, onTap: _toggle),
        ],

        // 3. The community, folded away, most used first.
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
                  .where((String word) => !known(word))
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

/// The small grey heading over one shelf of tags.
class _ShelfLabel extends StatelessWidget {
  const _ShelfLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
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
