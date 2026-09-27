import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/personal_card_sync.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// Where a friend stands with their own personal card, from the matchmaker's
/// side.
enum CardInviteState {
  /// Their card already follows them here.
  synced,

  /// Nothing known in the system — they have no card, or the app cannot
  /// tell. Offer the invitation.
  noCard,

  /// They keep a card; this matchmaker has no access yet. Offer to ask.
  requestable,

  /// A request is waiting on them.
  pending,

  /// Access was given; the card is on its way.
  approved,

  /// Nothing to offer at all.
  blocked,
}

/// **One rule for the personal card, everywhere the app offers it** — a
/// friend's profile, the comparison of two cards, the list of matches:
///
/// - no card in the system → "שליחת קישור להצטרפות", the invitation to write one;
/// - a card, but no access → "בקשת גישה לכרטיס", and straight after the request
///   an offer to tell the friend in WhatsApp, with the link that opens their
///   personal area where the request waits.
///
/// Before this the profile offered a WhatsApp "send me your details" message,
/// the card panel offered an invitation, and a friend who had long since
/// written a card of their own was invited to write one again.
abstract final class CardInviteFlow {
  /// The link every invitation and every access request carries. Opened on a
  /// phone without the app it leads to the store with the inviter kept; with
  /// the app installed it opens the personal area.
  static Uri link({required String? myUid, required String myFirstName}) {
    return Uri.https('shadchan-gilad.web.app', '/join', <String, String>{
      'from': ?myUid,
      if (myFirstName.isNotEmpty) 'name': myFirstName,
    });
  }

  /// "היי יוסי! אני משתמש ב״שדכן״…" — in the matchmaker's grammatical gender
  /// and addressed in the friend's.
  static String inviteMessage({
    required String friendFirstName,
    required Gender friendGender,
    required Gender? myGender,
    required Uri link,
  }) {
    final bool she = friendGender == Gender.female;
    final String hello = friendFirstName.isEmpty
        ? 'היי!'
        : 'היי $friendFirstName!';
    return '$hello ${'אני {משתמש|משתמשת}'.forGender(myGender)} ב״שדכן״, '
        'יומן אישי לניהול שידוכים לחברים.\n'
        'אפשר למלא בו כרטיס אישי ש${she ? 'רק את מנהלת ומעדכנת' : 'רק אתה מנהל ומעדכן'}, '
        'ולתת גישה רק לחברים ש${she ? 'את בוחרת' : 'אתה בוחר'}:\n'
        '$link\n'
        'יכול לעניין אותך?';
  }

  /// The message that follows an access request.
  static String requestMessage({required Uri link}) {
    return 'היי, שלחתי לך בקשה באפליקציית שדכן לגישה לכרטיס שלך. '
        'אפשר להיכנס מכאן ולאשר לי את הגישה: $link';
  }

  /// Works out where [person] stands. Cheap after the first call per number:
  /// the directory lookup is cached by [CardAccessProvider].
  static Future<CardInviteState> stateFor(
    CardAccessProvider access,
    Person person,
  ) async {
    if (person.cardOwnerUid != null) {
      return CardInviteState.synced;
    }
    final String? hash = PhoneIdentity.hash(person.phone);
    if (hash == null || !await access.ensureConnected()) {
      return CardInviteState.noCard;
    }
    final Map<String, dynamic>? entry = await access.lookup(hash);
    final Object? ownerUid = entry?['uid'];
    if (entry?['hasCard'] != true || ownerUid is! String) {
      return CardInviteState.noCard;
    }
    switch (access.accessTo(ownerUid)?.status) {
      case CardAccessStatus.pending:
        return CardInviteState.pending;
      case CardAccessStatus.approved:
        return CardInviteState.approved;
      case CardAccessStatus.blocked:
        return CardInviteState.blocked;
      case CardAccessStatus.declined:
      case CardAccessStatus.revoked:
      case null:
        return CardInviteState.requestable;
    }
  }

  /// The invitation: a join link, sent in WhatsApp — which is what the button
  /// says, next to the WhatsApp mark.
  static const String inviteLabel = 'שליחת קישור להצטרפות';

  /// The same invitation where the matchmaker is asking about a *candidate*
  /// (the matches list) — there it is a request for details.
  static const String detailsRequestLabel = 'לבקשת פרטים בוואטסאפ';

  /// The invitation named for the friend it goes to: "לשליחת קישור לדוד".
  /// Falls back to [inviteLabel] when there is no name to put in it.
  static String inviteLabelFor(Person? person) {
    final String first = (person?.firstName ?? '').trim();
    final String name = first.isNotEmpty
        ? first
        : (person?.fullName ?? '').trim();
    return name.isEmpty ? inviteLabel : 'לשליחת קישור ל$name';
  }

  /// The access request named for the friend: "בקשת גישה לכרטיס של דוד".
  static String requestLabelFor(Person person) {
    final String first = person.firstName.trim();
    final String name = first.isNotEmpty ? first : person.fullName.trim();
    return name.isEmpty ? 'בקשת גישה לכרטיס' : 'בקשת גישה לכרטיס של $name';
  }

  /// The label for [state], or null when there is nothing to offer. With
  /// [person], the invitation carries their name — see [inviteLabelFor].
  static String? labelFor(CardInviteState state, {Person? person}) {
    switch (state) {
      case CardInviteState.noCard:
        return person == null ? inviteLabel : inviteLabelFor(person);
      case CardInviteState.requestable:
        return person == null ? 'בקשת גישה לכרטיס' : requestLabelFor(person);
      case CardInviteState.pending:
        return 'ממתין לאישור גישה';
      case CardInviteState.synced:
      case CardInviteState.approved:
      case CardInviteState.blocked:
        return null;
    }
  }

  /// Does the right thing for [person] now: invites, or asks for access.
  static Future<void> run(BuildContext context, Person person) async {
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final CardInviteState state = await stateFor(access, person);
    if (!context.mounted) {
      return;
    }
    switch (state) {
      case CardInviteState.noCard:
        await invite(context, person);
      case CardInviteState.requestable:
        final String hash = PhoneIdentity.hash(person.phone)!;
        final Object? ownerUid = (await access.lookup(hash))?['uid'];
        if (ownerUid is String && context.mounted) {
          await requestAccess(
            context,
            person,
            ownerUid: ownerUid,
            ownerPhoneHash: hash,
          );
        }
      case CardInviteState.pending:
        AppNotice.show(context, 'הבקשה כבר נשלחה וממתינה לאישור');
      case CardInviteState.synced:
      case CardInviteState.approved:
      case CardInviteState.blocked:
        break;
    }
  }

  /// Sends the invitation to write a card — in WhatsApp when the friend has a
  /// number, through the share sheet when not.
  static Future<void> invite(BuildContext context, Person person) async {
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final Uri joinLink = link(
      myUid: access.uid,
      myFirstName: profile.firstName ?? '',
    );
    final String message = inviteMessage(
      friendFirstName: person.firstName.trim(),
      friendGender: person.gender,
      myGender: profile.gender,
      link: joinLink,
    );
    await _deliver(context, person, message);
  }

  /// Asks for access to [person]'s card, then offers to tell them.
  static Future<CardRequestOutcome?> requestAccess(
    BuildContext context,
    Person person, {
    required String ownerUid,
    required String ownerPhoneHash,
  }) async {
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    if (profile.myPhone == null) {
      final String? phone = await MyPhoneDialog.show(
        context,
        purpose: MyPhonePurpose.matchmakerRequest,
      );
      if (phone == null || !context.mounted) {
        return null;
      }
      await profile.setMyPhone(phone);
    }
    if (!context.mounted) {
      return null;
    }
    // The request is checked against the number this account published; make
    // sure it has been published before asking.
    await PersonalCardSync.run(
      cards: context.read<PersonalCardProvider>(),
      profile: profile,
    );
    final CardRequestOutcome outcome = await access.request(
      ownerUid: ownerUid,
      ownerName: person.fullName,
      ownerPhoneHash: ownerPhoneHash,
      matchmakerName: profile.fullName ?? '',
    );
    if (!context.mounted) {
      return outcome;
    }
    switch (outcome) {
      case CardRequestOutcome.sent:
        await _offerRequestMessage(context, person);
      case CardRequestOutcome.notAllowed:
        final bool female = person.gender == Gender.female;
        AppNotice.show(
          context,
          'אפשר לבקש גישה רק אם ${person.firstName.trim()} '
          '${female ? 'שמרה' : 'שמר'} את המספר שלך באנשי הקשר',
          duration: const Duration(seconds: 4),
        );
      case CardRequestOutcome.failed:
        AppNotice.show(context, 'לא הצלחנו לשלוח את הבקשה. אפשר לנסות שוב.');
    }
    return outcome;
  }

  static Future<void> _offerRequestMessage(
    BuildContext context,
    Person person,
  ) async {
    final String name = person.firstName.trim();
    final bool female = person.gender == Gender.female;
    final bool? send = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('הבקשה נשלחה'),
        content: Text(
          'לשלוח ל${name.isEmpty ? (female ? 'חברה' : 'חבר') : name} הודעת '
          'וואטסאפ עם קישור ישיר לאישור הגישה?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('לא עכשיו'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
            label: const Text('לשלוח'),
          ),
        ],
      ),
    );
    if (send != true || !context.mounted) {
      return;
    }
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final String message = requestMessage(
      link: link(myUid: access.uid, myFirstName: profile.firstName ?? ''),
    );
    await _deliver(context, person, message);
  }

  static Future<void> _deliver(
    BuildContext context,
    Person person,
    String message,
  ) async {
    if (PhoneUtils.toWhatsAppNumber(person.phone) != null) {
      final bool opened = await WhatsAppUtils.openChatWithText(
        person.phone,
        message,
      );
      if (opened || !context.mounted) {
        return;
      }
    }
    if (!context.mounted) {
      return;
    }
    await Share.share(
      message,
      sharePositionOrigin: ShareUtils.originOf(context),
    );
  }
}

/// The one button the unified rule draws: "שליחת קישור להצטרפות" or "בקשת גישה
/// לכרטיס", worked out for [person] — and nothing at all where there is
/// nothing to offer.
class CardInviteButton extends StatefulWidget {
  const CardInviteButton({
    super.key,
    required this.person,
    this.onlyInvite = false,
    this.dense = false,
  });

  final Person person;

  /// Draws only the invitation, leaving every access state to a panel that
  /// already shows it — the friend's profile, where `CardLinkPanel` does.
  final bool onlyInvite;

  /// A small text link rather than an outlined button.
  final bool dense;

  @override
  State<CardInviteButton> createState() => _CardInviteButtonState();
}

class _CardInviteButtonState extends State<CardInviteButton> {
  CardInviteState? _state;
  String? _resolvedFor;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CardInviteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  Future<void> _resolve({bool force = false}) async {
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final String key =
        '${widget.person.id}|${widget.person.phone}|'
        '${widget.person.cardOwnerUid}|${access.isConnected}';
    if (!force && key == _resolvedFor) {
      return;
    }
    _resolvedFor = key;
    final CardInviteState state = await CardInviteFlow.stateFor(
      access,
      widget.person,
    );
    if (mounted) {
      setState(() => _state = state);
    }
  }

  Future<void> _tap() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await CardInviteFlow.run(context, widget.person);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _resolve(force: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when access rows change, so "בקשת גישה" turns into "ממתין".
    context.watch<CardAccessProvider>();
    final CardInviteState? state = _state;
    if (state == null) {
      return const SizedBox.shrink();
    }
    if (widget.onlyInvite && state != CardInviteState.noCard) {
      return const SizedBox.shrink();
    }
    final String? label = CardInviteFlow.labelFor(state, person: widget.person);
    if (label == null) {
      return const SizedBox.shrink();
    }
    final bool actionable = state != CardInviteState.pending;
    final Widget icon = state == CardInviteState.noCard
        ? const FaIcon(
            FontAwesomeIcons.whatsapp,
            size: 17,
            color: Color(0xFF25D366),
          )
        : const Icon(Icons.lock_open_rounded, size: 18);

    if (widget.dense) {
      return TextButton.icon(
        onPressed: actionable && !_busy ? _tap : null,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        icon: icon,
        label: Text(label),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: actionable && !_busy ? _tap : null,
        icon: icon,
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// The foot of a friend's card while the matchmaker has no card text for
/// them — worked out from where the friend stands, so it never contradicts
/// the server:
///
/// - no card of their own → the invitation to write one, in WhatsApp;
/// - a card of their own → "בקשת גישה לכרטיס של X", never the invitation:
///   inviting somebody to write a card they already keep is the one message
///   this must not send;
/// - a request waiting, or access just given → says so.
///
/// Beside each, "הזנה ידנית של כרטיס", so there are always two plain choices.
/// Only that one is drawn until the answer is known, so a friend with a card
/// is never shown the invitation for a moment first.
class FriendCardInvite extends StatefulWidget {
  const FriendCardInvite({
    super.key,
    required this.person,
    this.textStyle,
    this.onManualEntry,
  });

  final Person person;

  /// "הזנה ידנית של כרטיס" — the other way to fill an empty card, offered
  /// beside the invitation or the access request so there are always two
  /// plain choices.
  final VoidCallback? onManualEntry;

  /// The quiet explanatory line's style, from the card it sits in.
  final TextStyle? textStyle;

  @override
  State<FriendCardInvite> createState() => _FriendCardInviteState();
}

class _FriendCardInviteState extends State<FriendCardInvite> {
  CardInviteState? _state;
  String? _resolvedFor;
  String? _ownerUid;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant FriendCardInvite oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  Future<void> _resolve({bool force = false}) async {
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final Person person = widget.person;
    final String key =
        '${person.id}|${person.phone}|${person.cardOwnerUid}|'
        '${access.isConnected}|'
        '${access.accessTo(_ownerUid ?? '')?.status}';
    if (!force && key == _resolvedFor) {
      return;
    }
    _resolvedFor = key;
    final CardInviteState state = await CardInviteFlow.stateFor(access, person);
    final String? hash = PhoneIdentity.hash(person.phone);
    if (hash != null && state != CardInviteState.noCard) {
      final Object? uid = (await access.lookup(hash))?['uid'];
      _ownerUid = uid is String ? uid : null;
    }
    if (mounted) {
      setState(() => _state = state);
    }
  }

  Future<void> _tap() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await CardInviteFlow.run(context, widget.person);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _resolve(force: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Access rows moving turn "בקשת גישה" into "ממתין" and on.
    context.watch<CardAccessProvider>();
    final CardInviteState? state = _state;
    final Person person = widget.person;
    final bool she = person.gender == Gender.female;
    final String name = person.firstName.trim().isNotEmpty
        ? person.firstName.trim()
        : person.fullName.trim();
    final TextStyle? style =
        widget.textStyle ?? Theme.of(context).textTheme.bodyMedium;

    Widget line(String text) => Text(text, style: style);
    Widget busyOr(Widget button) => _busy
        ? const Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : button;
    final Widget? manual = widget.onManualEntry == null
        ? null
        : OutlinedButton.icon(
            onPressed: widget.onManualEntry,
            icon: const Icon(Icons.edit_note_rounded, size: 20),
            label: const Text('הזנה ידנית של כרטיס'),
          );
    Widget options(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );

    switch (state) {
      case CardInviteState.synced:
        return const SizedBox.shrink();
      case null:
        // Still asking the server: typing a card in by hand never has to wait.
        return manual ?? const SizedBox.shrink();
      case CardInviteState.noCard:
        return options(<Widget>[
          line(
            she
                ? 'עוד אין כאן כרטיס. הזמנה אישית קצרה בוואטסאפ, והיא '
                      'ממלאת כרטיס בעצמה — מדויק, עם תמונות, ומתעדכן אצלך.'
                : 'עוד אין כאן כרטיס. הזמנה אישית קצרה בוואטסאפ, והוא '
                      'ממלא כרטיס בעצמו — מדויק, עם תמונות, ומתעדכן אצלך.',
          ),
          busyOr(
            OutlinedButton.icon(
              onPressed: _tap,
              icon: const FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 17,
                color: Color(0xFF25D366),
              ),
              label: Text(
                CardInviteFlow.inviteLabelFor(person),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ?manual,
        ]);
      case CardInviteState.requestable:
        // Two plain choices, nothing to read: ask for the card the friend
        // wrote, or type one in by hand.
        final bool declined =
            _ownerUid != null &&
            context.read<CardAccessProvider>().accessTo(_ownerUid!)?.status ==
                CardAccessStatus.declined;
        return options(<Widget>[
          busyOr(
            FilledButton.tonalIcon(
              onPressed: _tap,
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(
                declined
                    ? 'לבקש שוב גישה לכרטיס של $name'
                    : CardInviteFlow.requestLabelFor(person),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ?manual,
        ]);
      case CardInviteState.pending:
        return options(<Widget>[
          line('ביקשת גישה לכרטיס של $name · ממתין לאישור'),
          ?manual,
        ]);
      case CardInviteState.approved:
        return line('מתחבר לכרטיס של $name…');
      case CardInviteState.blocked:
        return manual ?? const SizedBox.shrink();
    }
  }
}
