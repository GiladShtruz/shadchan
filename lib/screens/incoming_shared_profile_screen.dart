import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/incoming_shared_profile_service.dart';
import 'package:shadchan/widgets/person_avatar.dart';

class IncomingSharedProfileScreen extends StatefulWidget {
  const IncomingSharedProfileScreen({required this.draft, super.key});

  final IncomingSharedProfileDraft draft;

  @override
  State<IncomingSharedProfileScreen> createState() =>
      _IncomingSharedProfileScreenState();
}

class _IncomingSharedProfileScreenState
    extends State<IncomingSharedProfileScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showExistingSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository repository = context.watch<PersonRepository>();
    final List<Person> people = _filteredPeople(repository.getAll());

    return Scaffold(
      appBar: AppBar(title: const Text('פרטים משותפים'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          _SharedPreview(draft: widget.draft),
          const SizedBox(height: 24),
          Text(
            'לאן להוסיף את הפרטים?',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openNewPersonForm,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('יצירת איש קשר חדש'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _showExistingSearch = true;
              });
            },
            icon: const Icon(Icons.search),
            label: const Text('הוספה לאיש קשר קיים'),
          ),
          if (_showExistingSearch) ...<Widget>[
            const SizedBox(height: 24),
            TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'חיפוש לפי שם או טלפון...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (people.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'לא נמצאו אנשי קשר מתאימים',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...people.map(
                (Person person) => Card(
                  child: ListTile(
                    leading: PersonAvatar(person: person, radius: 24),
                    title: Text(
                      person.fullName.isEmpty ? 'ללא שם' : person.fullName,
                    ),
                    subtitle: Text(_personSubtitle(person)),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => _openExistingPersonForm(person),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Person> _filteredPeople(List<Person> people) {
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return people.take(30).toList();
    }

    return people.where((Person person) {
      return person.fullName.toLowerCase().contains(query) ||
          (person.phone ?? '').toLowerCase().contains(query);
    }).toList();
  }

  String _personSubtitle(Person person) {
    final List<String> parts = <String>[
      if ((person.phone ?? '').trim().isNotEmpty) person.phone!.trim(),
      person.gender.displayName,
    ];
    return parts.join(' · ');
  }

  void _openNewPersonForm() {
    context.pushReplacement('/people/add', extra: widget.draft);
  }

  void _openExistingPersonForm(Person person) {
    context.pushReplacement(
      '/people/${person.id}/shared-edit',
      extra: widget.draft,
    );
  }
}

class _SharedPreview extends StatelessWidget {
  const _SharedPreview({required this.draft});

  final IncomingSharedProfileDraft draft;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? text = draft.text?.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.ios_share, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('התקבלו פרטים לשמירה', style: theme.textTheme.titleMedium),
              ],
            ),
            if (text != null && text.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                text,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (draft.filePaths.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: draft.filePaths.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final File file = File(draft.filePaths[index]);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: file.existsSync()
                          ? Image.file(
                              file,
                              width: 76,
                              height: 92,
                              cacheWidth: 152,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 76,
                              height: 92,
                              color: theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
