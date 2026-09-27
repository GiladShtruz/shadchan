import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/card_updates_seen.dart';
import 'package:shadchan/utils/date_utils.dart';

/// Every change a friend made to their own card, newest first — the
/// meaningful ones and the small ones alike. The profile's card tile shows
/// only what is new and worth a look; this is the whole record behind it.
///
/// Opening it is what marks the new updates as seen.
class CardHistoryScreen extends StatefulWidget {
  const CardHistoryScreen({super.key, required this.personId});

  final String personId;

  static Future<void> open(BuildContext context, String personId) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CardHistoryScreen(personId: personId),
      ),
    );
  }

  @override
  State<CardHistoryScreen> createState() => _CardHistoryScreenState();
}

class _CardHistoryScreenState extends State<CardHistoryScreen> {
  @override
  void initState() {
    super.initState();
    CardUpdatesSeen.markSeen(widget.personId);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository people = context.watch<PersonRepository>();
    final Person? person = people.getById(widget.personId);
    final List<PersonEvent> events = people.getCardHistoryForPerson(
      widget.personId,
    );
    final String name = person?.firstName.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          name.isEmpty ? 'היסטוריית שינויים' : 'השינויים בכרטיס של $name',
        ),
      ),
      body: events.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'עוד לא היו שינויים בכרטיס',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.mutedInk,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: events.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final PersonEvent event = events[index];
                final bool minor =
                    event.type == PersonEventType.cardSyncedMinor;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          event.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: minor
                                ? FontWeight.w400
                                : FontWeight.w700,
                            color: minor ? AppColors.mutedInk : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        AppDateUtils.formatDateShort(event.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedInk,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
