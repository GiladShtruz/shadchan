import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

class PendingPeopleScreen extends StatelessWidget {
  const PendingPeopleScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final List<Person> pending = personRepository.getPending();

    return Scaffold(
      appBar: AppBar(
        title: const Text('בהמתנה לעדכון'),
        centerTitle: true,
      ),
      body: pending.isEmpty
          ? const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'אין אנשים בהמתנה',
              subtitle:
                  'אנשים שמיובאים מאנשי הקשר יופיעו כאן עד שתוסיפו להם פרטים',
            )
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'מלאו פרטים כדי שהאיש יעבור לרשימה הראשית. ${pending.length} ממתינים.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: pending.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Person person = pending[index];
                      final bool hasPhone =
                          PhoneUtils.toWhatsAppNumber(person.phone) != null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsetsDirectional.only(
                              start: 16,
                              end: 4,
                              top: 8,
                              bottom: 8,
                            ),
                            leading: PersonAvatar(person: person, radius: 22),
                            title: Text(
                              person.fullName.trim().isEmpty
                                  ? 'ללא שם'
                                  : person.fullName.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              person.phone ?? 'בלי טלפון',
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: hasPhone
                                  ? 'וואטסאפ — בקשת פרטים'
                                  : 'אין מספר טלפון תקין',
                              icon: FaIcon(
                                FontAwesomeIcons.whatsapp,
                                color: hasPhone
                                    ? const Color(0xFF25D366)
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              onPressed: hasPhone
                                  ? () => _openWhatsApp(context, person)
                                  : null,
                            ),
                            onTap: () =>
                                context.push('/people/${person.id}/edit'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
