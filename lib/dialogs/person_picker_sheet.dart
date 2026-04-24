import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

class PersonPickerSheet extends StatefulWidget {
  const PersonPickerSheet({
    super.key,
    required this.title,
    this.filterGender,
    this.excludeIds = const <String>{},
  });

  final Gender? filterGender;
  final Set<String> excludeIds;
  final String title;

  static Future<Person?> show(
    BuildContext context, {
    required String title,
    Gender? filterGender,
    Set<String> excludeIds = const <String>{},
  }) {
    return showModalBottomSheet<Person>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: PersonPickerSheet(
            title: title,
            filterGender: filterGender,
            excludeIds: excludeIds,
          ),
        );
      },
    );
  }

  @override
  State<PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends State<PersonPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final String query = _searchController.text.trim().toLowerCase();

    final List<Person> people = personRepository.getAll().where((
      Person person,
    ) {
      if (widget.filterGender != null && person.gender != widget.filterGender) {
        return false;
      }

      if (widget.excludeIds.contains(person.id)) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      return person.firstName.toLowerCase().contains(query) ||
          person.lastName.toLowerCase().contains(query) ||
          person.fullName.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'חיפוש לפי שם...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _searchController.clear,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: people.isEmpty
                  ? const EmptyState(
                      icon: Icons.search,
                      title: 'לא נמצאו תוצאות',
                      subtitle: 'נסו לחפש בשם אחר',
                    )
                  : ListView.builder(
                      itemCount: people.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Person person = people[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: PersonAvatar(person: person, radius: 22),
                          title: Text(
                            person.fullName.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _personSubtitle(person),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).pop(person),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _personSubtitle(Person person) {
    final List<String> parts = <String>[
      if (person.age != null) person.age!.toString(),
      if (person.religiousLevel != null) person.religiousLevel!.displayName,
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ];

    return parts.join(' · ');
  }

  void _handleSearchChanged() {
    setState(() {});
  }
}
