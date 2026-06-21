import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/match_suggestion_flow.dart';
import 'package:shadchan/dialogs/quick_update_dialog.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_list_card.dart';

class PendingPeopleScreen extends StatelessWidget {
  const PendingPeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository repository = context.watch<PersonRepository>();
    final List<Person> pendingPeople = repository.getPending();

    return Scaffold(
      appBar: AppBar(
        title: const Text('בהמתנה לעדכון'),
        centerTitle: true,
      ),
      body: pendingPeople.isEmpty
          ? const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'אין אנשים להצגה כרגע',
              subtitle:
                  'אנשים שמיובאים מאנשי הקשר יופיעו כאן עד שתוסיפו להם פרטים',
            )
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'נותרו ${pendingPeople.length} בהמתנה לעדכון',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: pendingPeople.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Person person = pendingPeople[index];
                      return PersonListCard(
                        person: person,
                        onTap: () => QuickUpdateDialog.show(context, person),
                        onLongPress: () => _confirmAndDelete(context, person),
                        onOpenMatches: () =>
                            _openMatchSuggestions(context, person),
                        onOpenWhatsApp: () => _openWhatsApp(context, person),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, Person person) async {
    final PersonRepository repository = context.read<PersonRepository>();
    final String name = person.fullName.trim();
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'למחוק את האדם?',
      message: name.isEmpty
          ? 'האם למחוק את איש הקשר הזה? (נוסף בטעות)'
          : 'האם למחוק את $name? (נוסף בטעות)',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }

    await repository.delete(person.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('איש הקשר נמחק')));
    }
  }

  Future<void> _openMatchSuggestions(
    BuildContext context,
    Person person,
  ) async {
    await MatchSuggestionFlow.open(context, sourcePerson: person);
  }

  Future<void> _openWhatsApp(BuildContext context, Person person) async {
    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('לא הצלחנו לפתוח את וואטסאפ')),
        );
    }
  }
}
