import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/private_looking_service.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// What the owner chose to let one matchmaker see.
typedef AccessChoice = ({bool card, bool looking});

/// Every way the owner changes who sees what — giving access, answering a
/// request, changing one permission, withdrawing access — in one place, so
/// the home page, "השדכנים שלי" and "ניהול גישה" can never disagree.
///
/// **"מה אני מחפש/ת" is offered only when there is something in it.** While it
/// is empty the choice has one answer, so giving access stays one tap; once
/// it has content, "לתת הרשאה" asks with a checkbox for each.
abstract final class PersonalAccessFlow {
  /// Whether the owner's "מה אני מחפש/ת" has a text or a recording. A read
  /// that cannot be made answers no, which can only ever offer *less*.
  static Future<bool> hasLooking(String? uid) async {
    if (uid == null || !FirebaseBootstrap.isReady) return false;
    try {
      final Map<String, dynamic>? data = (await PrivateLookingService.doc(
        uid,
      ).get(const GetOptions(source: Source.server))).data();
      return (data?['text'] as String? ?? '').trim().isNotEmpty ||
          data?['audioPath'] != null;
    } catch (_) {
      return false;
    }
  }

  /// "לתת הרשאה": a checkbox for the card and, when [askLooking], one for
  /// "מה אני מחפש/ת". Null when the owner cancelled.
  static Future<AccessChoice?> choose(
    BuildContext context, {
    required String name,
    required bool askLooking,
    bool card = true,
    bool looking = false,
    bool couple = false,
  }) {
    return showDialog<AccessChoice>(
      context: context,
      builder: (BuildContext dialogContext) {
        bool cardValue = card;
        bool lookingValue = looking;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => AlertDialog(
            title: const Text('לתת הרשאה'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(name, style: Theme.of(context).textTheme.titleSmall),
                if (couple)
                  const Text('האישור ניתן לשני בני הזוג במאגר המשותף'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('גישה לכרטיס'),
                  value: cardValue,
                  onChanged: (bool? v) => setState(() => cardValue = v!),
                ),
                if (askLooking)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('גישה ל״מה אני מחפש/ת״'),
                    subtitle: const Text('לעיני השדכן בלבד'),
                    value: lookingValue,
                    onChanged: (bool? v) => setState(() => lookingValue = v!),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ביטול'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, (
                  card: cardValue,
                  looking: askLooking && lookingValue,
                )),
                child: const Text('שמירה'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The owner's number, asked once if missing: every grant carries it, so the
  /// matchmaker's copy finds the friend already in their database.
  static Future<bool> _ensurePhone(BuildContext context) async {
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    if (profile.myPhone != null) return true;
    final String? phone = await MyPhoneDialog.show(context);
    if (phone == null || !context.mounted) return false;
    await profile.setMyPhone(phone);
    return true;
  }

  /// Gives [friend] access, or answers their request — with the checkboxes
  /// when there is a choice to make.
  static Future<void> grant(
    BuildContext context,
    MatchmakerFriend friend,
  ) async {
    if (!OfflineGuard.allow(context)) {
      return;
    }
    final PersonalCardProvider cards = context.read<PersonalCardProvider>();
    if (!cards.hasCard) {
      AppNotice.show(context, 'יש להשלים כרטיס פעיל לפני מתן גישה');
      return;
    }
    final CardAccessProvider access = context.read<CardAccessProvider>();
    if (!await _ensurePhone(context) || !context.mounted) return;
    final bool askLooking =
        friend.asksForLooking ||
        friend.canReadLooking ||
        await hasLooking(access.uid);
    if (!context.mounted) return;
    final CardAccess? row = friend.row;
    final bool couple =
        (row?.granteeUids.length ?? friend.helper?.granteeUids.length ?? 0) ==
        2;
    AccessChoice choice = (
      card: true,
      looking: friend.canReadLooking || friend.asksForLooking,
    );
    if (askLooking) {
      final AccessChoice? picked = await choose(
        context,
        name: friend.name,
        askLooking: true,
        card: true,
        looking: choice.looking,
        couple: couple,
      );
      if (picked == null || !context.mounted) return;
      choice = picked;
    }
    if (!choice.card && !choice.looking) return;
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final bool ok;
    if (row != null) {
      ok = await access.setStatus(
        row,
        CardAccessStatus.approved,
        cardGranted: choice.card,
        lookingGranted: choice.looking,
        ownerName: profile.fullName,
        ownerPhoneHash: PhoneIdentity.hash(profile.myPhone),
        ownerPhone: profile.myPhone,
      );
    } else {
      final CardHelper helper = friend.helper!;
      ok = await access.grant(
        helper,
        ownerName: profile.fullName ?? '',
        ownerPhoneHash: PhoneIdentity.hash(profile.myPhone),
        ownerPhone: profile.myPhone,
        cardGranted: choice.card,
        lookingGranted: choice.looking,
        expectedRecipient: <String, dynamic>{
          'uid': helper.recipientUid ?? helper.uid,
          'members': helper.granteeUids.isEmpty
              ? <String>[helper.uid]
              : helper.granteeUids,
        },
      );
    }
    if (context.mounted) {
      AppNotice.show(
        context,
        ok
            ? 'הגישה ניתנה ל${friend.name} ❤️'
            : 'הגישה לא נשמרה. כדאי לרענן ולנסות שוב.',
      );
    }
  }

  /// "לא עכשיו" on a request: the request goes, nothing is granted, and the
  /// friend stays on the list to be given access later.
  static Future<void> decline(BuildContext context, CardAccess row) async {
    if (!OfflineGuard.allow(context)) {
      return;
    }
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final bool ok = row.status == CardAccessStatus.approved
        ? await access.setPermissions(
            row,
            card: row.canReadCard,
            looking: row.canReadLooking,
          )
        : await access.setStatus(row, CardAccessStatus.declined);
    if (!ok && context.mounted) {
      AppNotice.show(context, 'לא הצלחנו לעדכן כרגע. אפשר לנסות שוב.');
    }
  }

  /// Changes the two permissions one by one. Unticking both withdraws access.
  static Future<void> edit(
    BuildContext context,
    MatchmakerFriend friend,
  ) async {
    if (!OfflineGuard.allow(context)) {
      return;
    }
    final CardAccess? row = friend.row;
    if (row == null) return;
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final bool askLooking =
        row.canReadLooking ||
        row.lookingRequested ||
        await hasLooking(access.uid);
    if (!context.mounted) return;
    final AccessChoice? choice = await choose(
      context,
      name: friend.name,
      askLooking: askLooking,
      card: row.canReadCard,
      looking: row.canReadLooking,
      couple: row.granteeUids.length == 2,
    );
    if (choice == null || !context.mounted) return;
    final bool ok = await access.setPermissions(
      row,
      card: choice.card,
      looking: choice.looking,
    );
    if (!ok && context.mounted) {
      AppNotice.show(context, 'לא הצלחנו לעדכן כרגע. אפשר לנסות שוב.');
    }
  }

  /// Withdraws every permission at once.
  static Future<void> revoke(BuildContext context, CardAccess row) async {
    if (!OfflineGuard.allow(context)) {
      return;
    }
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final bool ok = await access.setStatus(row, CardAccessStatus.revoked);
    if (context.mounted) {
      AppNotice.show(
        context,
        ok
            ? 'הגישה לכרטיס ול״מה אני מחפש/ת״ בוטלה'
            : 'ביטול הגישה לא נשמר. יש לנסות שוב.',
      );
    }
  }
}
