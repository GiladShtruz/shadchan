import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/screens/friends_with_cards_screen.dart';
import 'package:shadchan/widgets/private_looking.dart';

/// A grant/invitation can arrive before the local copy. Wait for an authorized
/// copy rather than redirecting the notification to a different screen.
class CardFriendScreen extends StatefulWidget {
  const CardFriendScreen({
    super.key,
    required this.ownerUid,
    this.phoneHash,
    this.focus = 'card',
  });
  final String ownerUid, focus;
  final String? phoneHash;
  @override
  State<CardFriendScreen> createState() => _CardFriendScreenState();
}

class _CardFriendScreenState extends State<CardFriendScreen> {
  Timer? _slow;
  bool _waiting = true;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    _slow = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _waiting = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!await context.read<CardAccessProvider>().ensureConnected() &&
          mounted) {
        setState(() => _waiting = false);
      }
    });
  }

  @override
  void dispose() {
    _slow?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<CardAccessProvider>();
    final people = context.watch<PersonRepository>();
    final grant = access.accessTo(widget.ownerUid);
    if (access.matchmakerAccessVerified &&
        (grant?.canReadCard == true || grant?.canReadLooking == true)) {
      final person = grant!.canReadCard
          ? people.findByCardOwner(widget.ownerUid)
          : widget.phoneHash == null
          ? null
          : people.findByPhoneHash(widget.phoneHash!);
      if (person != null && !_opening) {
        _opening = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go(
              '/people/${person.id}?focus=${Uri.encodeComponent(widget.focus)}',
            );
          }
        });
      }
      if (!grant.canReadCard && person == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('מידע לשדכנים')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [PrivateLookingBlock(ownerUid: widget.ownerUid)],
          ),
        );
      }
    }
    final denied =
        access.matchmakerAccessVerified &&
        grant?.canReadCard != true &&
        grant?.canReadLooking != true;
    // A new-card notice for a friend whose card this matchmaker cannot read:
    // straight to asking for it — the request is what the notice offers.
    // Likewise when access came and the card waits on the friend already
    // kept by hand: the sync question, on the same screen.
    if (widget.focus == 'request' &&
        !_opening &&
        (denied ||
            (grant?.canReadCard == true &&
                access.awaitingLinkFor(widget.ownerUid) != null))) {
      _opening = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(
            FriendsWithCardsScreen.requestRoute(
              widget.ownerUid,
              phoneHash: widget.phoneHash,
            ),
          );
        }
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('הכרטיס של החבר')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!denied && access.isConnected && _waiting)
                const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                denied
                    ? 'הגישה לכרטיס אינה זמינה. אפשר לצפות בו רק כל עוד יש אישור מבעל הכרטיס.'
                    : 'הכרטיס ייפתח לאחר קבלת הפרטים ואימות ההרשאה מול השרת.',
              ),
              if (!denied && !_waiting)
                TextButton(
                  onPressed: () => access.resync(widget.ownerUid),
                  child: const Text('ניסיון נוסף'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
