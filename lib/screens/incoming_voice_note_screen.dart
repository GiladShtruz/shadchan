import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/incoming_shared_profile_service.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// A voice note shared in from WhatsApp: which friend is it about?
///
/// A recording is not a card and cannot start one, so there is no "new
/// friend" here — only the database, searchable by name or number. Choosing
/// a friend files every shared recording as a voice note in their notes and
/// opens their profile, where it plays.
class IncomingVoiceNoteScreen extends StatefulWidget {
  const IncomingVoiceNoteScreen({required this.draft, super.key});

  final IncomingSharedProfileDraft draft;

  @override
  State<IncomingVoiceNoteScreen> createState() =>
      _IncomingVoiceNoteScreenState();
}

class _IncomingVoiceNoteScreenState extends State<IncomingVoiceNoteScreen> {
  final TextEditingController _search = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _recordings =>
      widget.draft.filePaths.where(VoiceNoteStore.isAudioPath).toList();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository repository = context.watch<PersonRepository>();
    final String query = _search.text.trim().toLowerCase();
    final List<Person> people = repository
        .getAll()
        .where(
          (Person person) =>
              query.isEmpty ||
              person.fullName.toLowerCase().contains(query) ||
              (person.phone ?? '').contains(query),
        )
        .take(query.isEmpty ? 40 : 200)
        .toList();
    final int count = _recordings.length;

    return Scaffold(
      appBar: AppBar(title: const Text('הקלטה קולית'), centerTitle: true),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.mic_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    count > 1
                        ? 'התקבלו $count הקלטות. לאיזה חבר לשייך אותן?'
                        : 'התקבלה הקלטה. לאיזה חבר לשייך אותה?',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'חיפוש לפי שם או טלפון...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: people.isEmpty
                ? Center(
                    child: Text(
                      'לא נמצאו חברים מתאימים',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    itemCount: people.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Person person = people[index];
                      return ListTile(
                        enabled: !_saving,
                        leading: PersonAvatar(person: person, radius: 22),
                        title: Text(
                          person.fullName.isEmpty ? 'ללא שם' : person.fullName,
                        ),
                        onTap: () => _fileUnder(person),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _fileUnder(Person person) async {
    setState(() => _saving = true);
    final PersonRepository repository = context.read<PersonRepository>();
    final OverlayState? notices = AppNotice.capture(context);
    int saved = 0;
    for (final String path in _recordings) {
      final String? name = await VoiceNoteStore.importFile(path);
      if (name == null) {
        continue;
      }
      await repository.addVoiceNote(person.id, fileName: name);
      saved++;
    }
    if (!mounted) {
      return;
    }
    if (saved == 0) {
      setState(() => _saving = false);
      AppNotice.showOn(notices, 'לא הצלחנו לקרוא את ההקלטה', isError: true);
      return;
    }
    AppNotice.showOn(
      notices,
      saved > 1
          ? 'ההקלטות נשמרו בהערות של ${person.firstName.trim()}'
          : 'ההקלטה נשמרה בהערות של ${person.firstName.trim()}',
    );
    context.pushReplacement('/people/${person.id}');
  }
}
