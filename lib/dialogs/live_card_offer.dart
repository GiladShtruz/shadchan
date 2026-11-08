import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/services/connectivity_status.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_invite.dart';

/// What the matchmaker chose for a contact who already keeps a personal card.
enum LiveCardChoice {
  /// Fill the card in by hand, as with anybody else.
  manual,

  /// An access request went out instead — no hand-made copy is added; the
  /// card itself arrives in the database once the friend approves.
  requested,

  /// Neither, for now.
  skip,
}

/// Adding a contact who already manages their own personal card in שדכן.
///
/// Typing their details in by hand makes a second, stale copy of a card that
/// keeps itself up to date — and when the friend later approves access the
/// two have to be told apart. So before the details dialog, the app asks the
/// directory once (cached for the session) and, when the friend's card is
/// there and open to requests, offers "בקשת גישה" first: once approved, the
/// card, its photos and every later change land in the database by themselves.
abstract final class LiveCardOffer {
  /// How long the directory gets before the ordinary flow carries on.
  static const Duration lookupTimeout = Duration(seconds: 4);

  /// The friends with a live card that the server already knows about —
  /// mutual contacts, by phone hash. Drawn as a tag in the contacts list;
  /// costs no read.
  static Set<String> knownCardHashes(BuildContext context) {
    try {
      final CardAccessProvider access = Provider.of<CardAccessProvider>(
        context,
      );
      return <String>{
        for (final CardHelper friend in access.mutualFriends)
          if (friend.phoneHash case final String hash) hash,
      };
    } on ProviderNotFoundException {
      return const <String>{};
    }
  }

  /// Asks, when [draft]'s number belongs to a live, requestable card.
  /// Anything that cannot be decided quickly (offline, no account, a slow
  /// directory) is [LiveCardChoice.manual] — the flow as it always was.
  static Future<LiveCardChoice> ask(BuildContext context, Person draft) async {
    final CardAccessProvider? access = _access(context);
    final String? hash = PhoneIdentity.hash(draft.phone);
    if (access == null || hash == null || ConnectivityStatus.isOffline) {
      return LiveCardChoice.manual;
    }
    final CardInviteState state;
    try {
      state = await CardInviteFlow.stateFor(
        access,
        draft,
      ).timeout(lookupTimeout);
    } catch (_) {
      return LiveCardChoice.manual;
    }
    if (state != CardInviteState.requestable || !context.mounted) {
      return LiveCardChoice.manual;
    }
    final Object? ownerUid = (await access.lookup(hash))?['uid'];
    if (ownerUid is! String || !context.mounted) {
      return LiveCardChoice.manual;
    }

    final LiveCardChoice? choice = await showDialog<LiveCardChoice>(
      context: context,
      builder: (BuildContext context) => _LiveCardDialog(person: draft),
    );
    if (choice != LiveCardChoice.requested || !context.mounted) {
      return choice ?? LiveCardChoice.skip;
    }
    final CardRequestOutcome? outcome = await CardInviteFlow.requestAccess(
      context,
      draft,
      ownerUid: ownerUid,
      ownerPhoneHash: hash,
    );
    if (outcome == CardRequestOutcome.sent) {
      return LiveCardChoice.requested;
    }
    // The request could not go out: the ordinary way is still open.
    if (context.mounted && outcome != null) {
      AppNotice.show(context, 'אפשר להוסיף ידנית בינתיים');
    }
    return LiveCardChoice.manual;
  }

  static CardAccessProvider? _access(BuildContext context) {
    try {
      return Provider.of<CardAccessProvider>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }
}

class _LiveCardDialog extends StatelessWidget {
  const _LiveCardDialog({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final String first = person.firstName.trim().isNotEmpty
        ? person.firstName.trim()
        : person.fullName.trim();
    final Gender gender = person.gender;
    return AlertDialog(
      scrollable: true,
      title: Text(
        '$first {מנהל|מנהלת} כרטיס אישי בשדכן'.forGender(gender),
        textAlign: TextAlign.center,
      ),
      content: Text(
        'במקום למלא את הפרטים ידנית, אפשר לבקש גישה לכרטיס. '
                'אחרי {שיאשר|שתאשר}, הכרטיס והתמונות יגיעו למאגר שלך '
                'ויתעדכנו מעצמם.'
            .forGender(gender),
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowDirection: VerticalDirection.down,
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(LiveCardChoice.requested),
          child: const Text('בקשת גישה לכרטיס'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(LiveCardChoice.manual),
          child: const Text('הוספה ידנית'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(LiveCardChoice.skip),
          child: const Text('דילוג'),
        ),
      ],
    );
  }
}
