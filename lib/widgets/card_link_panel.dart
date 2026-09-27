import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_invite.dart';
import 'package:shadchan/widgets/home_section.dart';

/// Warns before a matchmaker edits a card that follows its owner. Opening the
/// editor changes nothing; only a save that changes the card detaches it.
Future<bool> confirmEditSyncedCard(BuildContext context, Person person) async {
  if (!person.isCardSynced) {
    return true;
  }
  final String name = person.firstName.trim();
  final bool female = person.gender == Gender.female;
  final bool? go = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('כרטיס שמתעדכן אוטומטית'),
      content: Text(
        'הכרטיס הזה כרגע מתעדכן אוטומטית מ־$name. '
        '${'אם {תערוך|תערכי}'.forGender(dialogContext.userGender)} '
        '${female ? 'אותה' : 'אותו'} בעצמך, שינויים עתידיים ש$name '
        '${female ? 'תעשה' : 'יעשה'} בכרטיס לא יתעדכנו אצלך.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('להמשיך לערוך'),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// A matchmaker who marks a card owner "מזל טוב" is offered a WhatsApp nudge
/// asking the owner to update their own status — the owner is also asked to
/// confirm it in their personal area, automatically.
Future<void> offerMazelTovWhatsApp(BuildContext context, Person person) async {
  if (person.cardOwnerUid == null || PhoneIdentity.hash(person.phone) == null) {
    return;
  }
  final String name = person.firstName.trim();
  final bool female = person.gender == Gender.female;
  final bool? send = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('מזל טוב! 🎉'),
      content: Text(
        'לשלוח ל$name הודעת וואטסאפ ש${female ? 'תעדכן' : 'יעדכן'} את הסטטוס '
        'בכרטיס ${female ? 'שלה' : 'שלו'}? בנוסף תישלח ${female ? 'אליה' : 'אליו'} '
        'בקשת אימות באפליקציה.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('לא עכשיו'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('לשלוח'),
        ),
      ],
    ),
  );
  if (send != true) {
    return;
  }
  await WhatsAppUtils.openChatWithText(
    person.phone,
    'מזל טוב!! 🎉 ${female ? 'אשמח אם תעדכני' : 'אשמח אם תעדכן'} בכרטיס '
    '${female ? 'שלך' : 'שלך'} בשדכן את הסטטוס ל״מזל טוב״.',
  );
}

/// "הכרטיס האישי" on a friend's profile, for the matchmaker.
///
/// Says where this record's details come from, and offers the one next step:
/// ask for access, wait, try again, or invite the friend to write a card.
/// Drawn only while connected — every state here is the server's answer.
class CardLinkPanel extends StatefulWidget {
  const CardLinkPanel({super.key, required this.person});

  final Person person;

  @override
  State<CardLinkPanel> createState() => _CardLinkPanelState();
}

class _CardLinkPanelState extends State<CardLinkPanel> {
  String? _lookedUpHash;
  Map<String, dynamic>? _entry;
  bool _looking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lookUp();
  }

  @override
  void didUpdateWidget(CardLinkPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _lookUp();
  }

  Future<void> _lookUp() async {
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final String? hash = PhoneIdentity.hash(widget.person.phone);
    if (!access.isConnected ||
        hash == null ||
        hash == _lookedUpHash ||
        widget.person.cardOwnerUid != null) {
      return;
    }
    _lookedUpHash = hash;
    setState(() => _looking = true);
    final Map<String, dynamic>? entry = await access.lookup(hash);
    if (mounted) {
      setState(() {
        _entry = entry;
        _looking = false;
      });
    }
  }

  Future<void> _request(String ownerUid) async {
    await CardInviteFlow.requestAccess(
      context,
      widget.person,
      ownerUid: ownerUid,
      ownerPhoneHash: _lookedUpHash ?? '',
    );
  }

  Future<void> _resume(PersonRepository people) async {
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final String? owner = widget.person.cardOwnerUid;
    widget.person.cardSyncDetached = false;
    await people.saveSynced(widget.person);
    if (owner != null) {
      await access.resync(owner);
    }
    if (mounted) {
      AppNotice.show(context, 'הכרטיס יתעדכן שוב אוטומטית');
    }
  }

  @override
  Widget build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final PersonRepository people = context.watch<PersonRepository>();
    final ThemeData theme = Theme.of(context);
    final Person person = widget.person;
    final String name = person.firstName.trim();
    if (!access.isConnected) {
      return const SizedBox.shrink();
    }

    Widget body;
    if (person.cardOwnerUid != null) {
      final List<PersonEvent> updates = people
          .getEventsForPerson(person.id)
          .where((PersonEvent e) => e.type == PersonEventType.cardSynced)
          .take(3)
          .toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            person.cardSyncDetached
                ? 'ערכת את הכרטיס בעצמך, ולכן הפרטים כבר לא מתעדכנים מ־$name. '
                      'הסטטוס עדיין מתעדכן.'
                : 'הכרטיס מתעדכן אוטומטית מ־$name',
            style: theme.textTheme.bodyMedium,
          ),
          if (updates.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            for (final PersonEvent e in updates)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• ${e.text}', style: theme.textTheme.bodySmall),
              ),
          ],
          if (person.cardSyncDetached)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => _resume(people),
                child: const Text('חזרה לעדכון אוטומטי'),
              ),
            ),
        ],
      );
    } else if (_looking) {
      return const SizedBox.shrink();
    } else {
      final Object? ownerUid = _entry?['uid'];
      final bool hasCard = _entry?['hasCard'] == true && ownerUid is String;
      if (!hasCard) {
        // A friend with no card of their own is invited from the card section
        // under this panel, when the matchmaker has no card for them either.
        // Only a friend whose card was written here by hand is invited from
        // this panel — so the invitation is offered once, never twice.
        if (PhoneIdentity.hash(person.phone) == null ||
            (person.description ?? '').trim().isEmpty) {
          return const SizedBox.shrink();
        }
        // The card here was written by the matchmaker; the friend has not
        // taken it over. Say plainly what the link is for.
        final bool she = person.gender == Gender.female;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '{שלח|שלחי} הזמנה ל${she ? 'חברה' : 'חבר'} לערוך את הכרטיס '
                      '${she ? 'שלה' : 'שלו'} ולנהל את הפרטים '
                      '${she ? 'שלה בעצמה' : 'שלו בעצמו'}'
                  .forGender(context.userGender),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => CardInviteFlow.invite(context, person),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              icon: const FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 17,
                color: Color(0xFF25D366),
              ),
              label: Text(CardInviteFlow.inviteLabelFor(person)),
            ),
          ],
        );
      } else if ((person.description ?? '').trim().isEmpty) {
        // With no card text here, the card itself asks for access in its own
        // place (`FriendCardInvite`) — once, not twice.
        return const SizedBox.shrink();
      } else {
        final CardAccess? row = access.accessTo(ownerUid);
        final bool busy = access.isBusy('request:$ownerUid');
        switch (row?.status) {
          case CardAccessStatus.blocked:
            return const SizedBox.shrink();
          case CardAccessStatus.pending:
            body = Text(
              'ביקשת גישה לכרטיס של $name · ממתין לאישור',
              style: theme.textTheme.bodyMedium,
            );
          case CardAccessStatus.approved:
            body = Text(
              'מתחבר לכרטיס של $name…',
              style: theme.textTheme.bodyMedium,
            );
          case CardAccessStatus.declined:
          case CardAccessStatus.revoked:
          case null:
            body = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row?.status == CardAccessStatus.declined
                      ? 'הבקשה לא אושרה'
                      : person.gender == Gender.female
                      ? 'ל$name יש כרטיס אישי שהיא מנהלת בעצמה'
                      : 'ל$name יש כרטיס אישי שהוא מנהל בעצמו',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: row?.status == CardAccessStatus.declined
                        ? AppColors.mutedInk
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: () => _request(ownerUid),
                        icon: const Icon(Icons.lock_open_rounded, size: 18),
                        label: Text(
                          row?.status == CardAccessStatus.declined
                              ? 'לבקש שוב'
                              : CardInviteFlow.requestLabelFor(person),
                        ),
                      ),
              ],
            );
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: HomePaperCard(
        stripe: AppColors.secondary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.badge_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                  'הכרטיס האישי',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}
