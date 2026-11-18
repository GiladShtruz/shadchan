import 'package:flutter/material.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/services/tag_catalog.dart';
import 'package:shadchan/utils/person_tags.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// "תגיות" in the console: the shared list singles choose from and
/// matchmakers are offered — add, rename, delete, drag to reorder, then save
/// the whole list at once — with how each word is used beside it: by how many
/// matchmakers (in their databases) and on how many singles' cards.
class TagCatalogEditor extends StatefulWidget {
  const TagCatalogEditor({super.key});

  @override
  State<TagCatalogEditor> createState() => _TagCatalogEditorState();
}

class _TagCatalogEditorState extends State<TagCatalogEditor> {
  late List<String> _tags = List<String>.of(TagCatalog.current);
  bool _dirty = false;
  bool _saving = false;
  Map<String, TagUsage>? _usage;
  final TextEditingController _add = TextEditingController();

  @override
  void initState() {
    super.initState();
    TagCatalog.refresh().then((_) {
      if (mounted && !_dirty) {
        setState(() => _tags = List<String>.of(TagCatalog.current));
      }
    });
    _loadUsage();
  }

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _loadUsage() async {
    final Map<String, TagUsage> usage = await TagCatalog.usage();
    if (mounted) setState(() => _usage = usage);
  }

  void _addTag() {
    final String value = PersonTags.normalize(_add.text);
    if (value.isEmpty) return;
    if (_tags.any((String t) => PersonTags.sameTag(t, value))) {
      AppNotice.show(context, 'התגית כבר ברשימה');
      return;
    }
    setState(() {
      _tags = <String>[..._tags, value];
      _dirty = true;
    });
    _add.clear();
  }

  Future<void> _rename(int index) async {
    final TextEditingController field = TextEditingController(
      text: _tags[index],
    );
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('עריכת תגית'),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: PersonTags.maxLength,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: const Text('שמירה'),
          ),
        ],
      ),
    );
    field.dispose();
    final String cleaned = PersonTags.normalize(value ?? '');
    if (cleaned.isEmpty || !mounted) return;
    setState(() {
      _tags = <String>[..._tags]..[index] = cleaned;
      _dirty = true;
    });
  }

  Future<void> _delete(int index) async {
    final bool ok = await ConfirmDialog.show(
      context,
      title: 'למחוק את התגית "${_tags[index]}"?',
      message: 'היא לא תוצע יותר. מי שכבר בחר בה ישאיר אותה עד שישנה בעצמו.',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _tags = <String>[..._tags]..removeAt(index);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final OverlayState? notices = AppNotice.capture(context);
    setState(() => _saving = true);
    final bool ok = await TagCatalog.save(_tags);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _dirty = false;
        _tags = List<String>.of(TagCatalog.current);
      }
    });
    AppNotice.showOn(
      notices,
      ok ? 'רשימת התגיות נשמרה' : 'לא הצלחנו לשמור. כדאי לנסות שוב.',
      isError: !ok,
    );
  }

  String _usageOf(String tag) {
    final Map<String, TagUsage>? usage = _usage;
    if (usage == null) return '';
    final TagUsage? found = usage[_serverKey(tag)];
    if (found == null) return 'לא בשימוש';
    return '${found.matchmakers} שדכנים · ${found.cards} כרטיסים';
  }

  /// The document id the server counts a word under (`tagKey` in the
  /// Cloud Functions).
  static String _serverKey(String tag) {
    final String key = PersonTags.keyOf(tag);
    return key.length > 60 ? key.substring(0, 60) : key;
  }

  /// Words people use that are not on the list — candidates to add.
  List<TagUsage> _unlisted() {
    final Map<String, TagUsage>? usage = _usage;
    if (usage == null) return const <TagUsage>[];
    final Set<String> listed = _tags.map(_serverKey).toSet();
    return usage.entries
        .where((MapEntry<String, TagUsage> e) => !listed.contains(e.key))
        .map((MapEntry<String, TagUsage> e) => e.value)
        .toList()
      ..sort((TagUsage a, TagUsage b) => b.total.compareTo(a.total));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<TagUsage> unlisted = _unlisted();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _add,
                  maxLength: PersonTags.maxLength,
                  onSubmitted: (_) => _addTag(),
                  decoration: const InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: 'תגית חדשה',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'הוספה',
                onPressed: _addTag,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${_tags.length} תגיות · גרירה לשינוי הסדר',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              FilledButton(
                onPressed: _dirty && !_saving ? _save : null,
                child: Text(_saving ? 'שומרים…' : 'שמירת הרשימה'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            itemCount: _tags.length,
            onReorder: (int from, int to) => setState(() {
              final List<String> next = List<String>.of(_tags);
              final String moved = next.removeAt(from);
              next.insert(to > from ? to - 1 : to, moved);
              _tags = next;
              _dirty = true;
            }),
            footer: unlisted.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'תגיות בשימוש שאינן ברשימה',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        for (final TagUsage u in unlisted.take(40))
                          ListTile(
                            dense: true,
                            title: Text(u.label),
                            subtitle: Text(
                              '${u.matchmakers} שדכנים · ${u.cards} כרטיסים',
                            ),
                            trailing: IconButton(
                              tooltip: 'הוספה לרשימה',
                              icon: const Icon(Icons.playlist_add),
                              onPressed: () => setState(() {
                                _tags = <String>[
                                  ..._tags,
                                  PersonTags.normalize(u.label),
                                ];
                                _dirty = true;
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
            itemBuilder: (BuildContext context, int index) {
              final String tag = _tags[index];
              return ListTile(
                key: ValueKey<String>('tag:$tag:$index'),
                dense: true,
                title: Text(tag),
                subtitle: Text(_usageOf(tag)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'עריכה',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _rename(index),
                    ),
                    IconButton(
                      tooltip: 'מחיקה',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _delete(index),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
