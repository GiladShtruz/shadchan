import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/bulk_details_request_sheet.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_invite.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// "להזמין חברים להוסיף כרטיס אישי" — the friends the matchmaker added to the
/// database by hand, to tick and invite in one go: each one gets the same
/// ready invitation to join שדכן and fill in a personal card of their own,
/// one WhatsApp chat after the other (WhatsApp offers no way to message
/// several chats at once).
///
/// Friends whose card already follows them here, or who are known to keep a
/// card, are not on the list; neither is anybody WhatsApp cannot reach.
abstract final class InviteCardFriendsSheet {
  /// Who can be invited: visible friends with a WhatsApp number, not linked
  /// to a card and not among [withCard] (phone identities of friends known to
  /// keep one). Alphabetical.
  static List<Person> candidates(
    Iterable<Person> people, {
    Set<String> withCard = const <String>{},
  }) {
    final List<Person> list =
        people
            .where(
              (Person p) =>
                  !p.hidden &&
                  p.cardOwnerUid == null &&
                  PhoneUtils.toWhatsAppNumber(p.phone) != null &&
                  !withCard.contains(PhoneIdentity.hash(p.phone)),
            )
            .toList()
          ..sort((Person a, Person b) => a.fullName.compareTo(b.fullName));
    return list;
  }

  static Future<void> show(BuildContext context) async {
    final PersonRepository people = context.read<PersonRepository>();
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final Set<String> withCard = <String>{
      for (final helper in access.mutualFriends) ?helper.phoneHash,
      for (final row in access.matchmakerRows.values) ?row.ownerPhoneHash,
    };
    final List<Person> list = candidates(people.getAll(), withCard: withCard);
    if (list.isEmpty) {
      AppNotice.show(context, 'אין חברים במאגר שאפשר להזמין כרגע');
      return;
    }
    final List<Person>? chosen = await showModalBottomSheet<List<Person>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      builder: (_) => _InvitePicker(people: list),
    );
    if (chosen == null || chosen.isEmpty || !context.mounted) {
      return;
    }
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final Uri link = CardInviteFlow.link(
      myUid: access.uid,
      myFirstName: profile.firstName ?? '',
    );
    await BulkDetailsRequestSheet.show(
      context,
      chosen,
      title: 'הזמנה להוסיף כרטיס אישי',
      send: (Person person) => WhatsAppUtils.openChatWithText(
        person.phone,
        CardInviteFlow.inviteMessage(
          friendFirstName: person.firstName.trim(),
          friendGender: person.gender,
          myGender: profile.gender,
          link: link,
        ),
      ),
    );
  }
}

class _InvitePicker extends StatefulWidget {
  const _InvitePicker({required this.people});
  final List<Person> people;

  @override
  State<_InvitePicker> createState() => _InvitePickerState();
}

class _InvitePickerState extends State<_InvitePicker> {
  final Set<String> _selected = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String q = _query.trim();
    final List<Person> shown = q.isEmpty
        ? widget.people
        : widget.people.where((Person p) => p.fullName.contains(q)).toList();
    final bool allShown =
        shown.isNotEmpty && shown.every((Person p) => _selected.contains(p.id));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'להזמין חברים להוסיף כרטיס אישי',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'כל חבר יקבל הודעה מוכנה להצטרף לשדכן ולמלא כרטיס אישי שרק הוא מנהל',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                hintText: 'חיפוש לפי שם',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (String value) => setState(() => _query = value),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: shown.isEmpty
                    ? null
                    : () => setState(() {
                        if (allShown) {
                          _selected.removeAll(shown.map((Person p) => p.id));
                        } else {
                          _selected.addAll(shown.map((Person p) => p.id));
                        }
                      }),
                child: Text(allShown ? 'ניקוי הבחירה' : 'בחירת כולם'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (BuildContext context, int index) {
                  final Person person = shown[index];
                  final bool on = _selected.contains(person.id);
                  return CheckboxListTile(
                    value: on,
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    secondary: PersonAvatar(person: person, radius: 20),
                    title: Text(
                      person.fullName.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (_) => setState(() {
                      if (on) {
                        _selected.remove(person.id);
                      } else {
                        _selected.add(person.id);
                      }
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(<Person>[
                      for (final Person p in widget.people)
                        if (_selected.contains(p.id)) p,
                    ]),
              icon: const Icon(Icons.send_rounded, size: 20),
              label: Text(
                _selected.isEmpty
                    ? 'בחירת חברים להזמנה'
                    : _selected.length == 1
                    ? 'שליחת הזמנה לחבר אחד'
                    : 'שליחת הזמנה ל־${_selected.length} חברים',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
