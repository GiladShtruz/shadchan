import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/personal_card_lifecycle.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/card_access_sections.dart';
import 'package:shadchan/widgets/photo_share_switch.dart';

/// "ניהול ופרטיות": who may ask, who sees what, who is hidden — and, at the
/// very foot, deleting the card. Deleting lives here and only here.
class PersonalPrivacyScreen extends StatefulWidget {
  const PersonalPrivacyScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const PersonalPrivacyScreen()),
  );

  @override
  State<PersonalPrivacyScreen> createState() => _PersonalPrivacyScreenState();
}

class _PersonalPrivacyScreenState extends State<PersonalPrivacyScreen> {
  bool _deleting = false;

  Future<void> _delete() async {
    setState(() => _deleting = true);
    await PersonalCardLifecycle.delete(context);
    if (mounted) setState(() => _deleting = false);
  }

  @override
  Widget build(BuildContext context) {
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('ניהול ופרטיות')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: <Widget>[
          CardAccessSections(hasCard: cards.hasCard, management: true),
          // Who sees the photos is decided above; whether they may leave the
          // app is decided here.
          if (cards.card != null && !cards.isDeleted) ...<Widget>[
            const SizedBox(height: 12),
            const PhotoShareSwitch(),
          ],
          if (cards.card != null && !cards.isDeleted) ...<Widget>[
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Center(
              child: _deleting
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.mutedInk,
                      ),
                      child: const Text('מחיקת הכרטיס שלי'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
