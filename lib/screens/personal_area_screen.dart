import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/widgets/private_looking.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/widgets/card_status_timestamp.dart';
import 'dart:io';
import 'package:shadchan/dialogs/person_card_viewer.dart';

import 'package:flutter/material.dart';
import 'package:shadchan/utils/personal_nav.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/dialogs/personal_card_lifecycle.dart';
import 'package:shadchan/screens/personal_privacy_screen.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/person_photo_carousel.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';
import 'package:shadchan/widgets/profile_status_choices.dart';

/// The personal card's part of the one profile: the card in full, its
/// status, "מה אני מחפש/ת" and the recording, and the ways to manage who sees
/// it. Drawn inside [ProfileScreen] for somebody who keeps a card — there is
/// no separate personal profile any more.
///
/// Card content and private wishes remain separate; permission management is
/// a secondary route and never an authorization shortcut.
class PersonalCardProfileSection extends StatefulWidget {
  const PersonalCardProfileSection({super.key});

  @override
  State<PersonalCardProfileSection> createState() =>
      _PersonalCardProfileSectionState();
}

class _PersonalCardProfileSectionState
    extends State<PersonalCardProfileSection> {
  bool _savingStatus = false;
  bool _restoring = false;

  /// Brings the card back as "פנוי", then asks about the old grants.
  Future<void> _restoreCard() async {
    setState(() => _restoring = true);
    await PersonalCardLifecycle.restore(context);
    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _setStatus(Person card, ProfileStatus status) async {
    if (_savingStatus || card.profileStatus == status) {
      return;
    }
    if (status == ProfileStatus.mazelTov) {
      final bool? sure = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('מזל טוב! 🎉'),
          content: const Text(
            'לסמן את הסטטוס שלך כ"מזל טוב"? השדכנים שיש להם גישה לכרטיס '
            'שלך יראו את העדכון.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('כן, לעדכן'),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) {
        return;
      }
    }
    setState(() => _savingStatus = true);
    try {
      await PersonalAreaService.updateStatus(context, status);
    } finally {
      if (mounted) {
        setState(() => _savingStatus = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    final Person? card = cards.card;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (cards.isDeleted)
          _RestoreCardPrompt(busy: _restoring, onRestore: _restoreCard)
        else if (card == null)
          _CreateCardPrompt(
            gender: context.watch<UserProfileProvider>().gender,
            onCreate: () => PersonalAreaService.editCard(context),
          )
        else ...<Widget>[
          _MyCardSummary(
            card: card,
            onEdit: () => PersonalAreaService.editCard(context),
          ),
          if (card.photosPaths.length < 2)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'כדאי להוסיף עוד תמונה כדי לעזור לחברים להציג אותך בצורה טובה יותר.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 14),
          if (!cards.hasCard)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(PersonalCardCodec.draftHint(card) ?? ''),
            ),
          ProfileStatusChoices(
            title: 'הסטטוס שלי',
            status: card.profileStatus,
            gender: card.gender,
            enabled: !_savingStatus,
            onSelected: (ProfileStatus status) => _setStatus(card, status),
          ),
        ],
        CardStatusTimestamp(ownerUid: context.read<CardAccessProvider>().uid),
        if (!cards.isDeleted)
          PrivateLookingBlock(
            onSaved: () => PersonalAreaService.offerUpdate(context),
          ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          children: <Widget>[
            TextButton.icon(
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('מי רואה אותי'),
              onPressed: () =>
                  PersonalNav.openMatchmakers(context, section: 'approved'),
            ),
            TextButton.icon(
              icon: const Icon(Icons.lock_outline),
              label: const Text('ניהול שיתוף ופרטיות'),
              onPressed: () => PersonalPrivacyScreen.open(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _RestoreCardPrompt extends StatelessWidget {
  const _RestoreCardPrompt({required this.busy, required this.onRestore});

  final bool busy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return HomePaperCard(
      stripe: AppColors.secondary,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'הכרטיס שלך נמחק',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'הוא שמור, ואפשר להחזיר אותו בכל עת. הוא יחזור בסטטוס "פנוי".',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          busy
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('שחזור הכרטיס שלי'),
                ),
        ],
      ),
    );
  }
}

class _CreateCardPrompt extends StatelessWidget {
  const _CreateCardPrompt({required this.gender, required this.onCreate});

  final Gender? gender;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return HomePaperCard(
      stripe: AppColors.secondary,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'עוד אין לך כרטיס',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'כרטיס אחד, שאת הפרטים בו רק {אתה מעדכן|את מעדכנת} — והחברים '
                    'שמשדכים רואים תמיד את הגרסה העדכנית.'
                .forGender(gender),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('יצירת הכרטיס שלי'),
          ),
        ],
      ),
    );
  }
}

/// The owner's card **as it is**: every photo, the whole text and the facts
/// a matchmaker reads first — the card in full, the moment the area opens —
/// with editing and sharing right under it.
///
/// It used to be a three-line summary behind a tap, which meant somebody who
/// came to see their own card had to open the editor to see it.
class _MyCardSummary extends StatelessWidget {
  const _MyCardSummary({required this.card, required this.onEdit});

  final Person card;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = AppColors.genderAccent(card.gender, dark: dark);
    final List<String> facts = <String>[
      if (card.age != null)
        '${card.gender == Gender.female ? 'בת' : 'בן'} ${card.age}',
      if (card.heightCm != null) '${card.heightCm} ס״מ',
      if (card.maritalStatus != null)
        card.maritalStatus!.displayNameFor(card.gender),
      if (card.religiousLevelLabel.isNotEmpty) card.religiousLevelLabel,
      if ((card.city ?? '').trim().isNotEmpty) card.city!.trim(),
    ];
    final String description = (card.description ?? '').trim();
    final List<String> photos = card.photosPaths
        .where((String path) => File(path).existsSync())
        .toList();
    final bool shareable = WhatsAppUtils.hasSendableCard(card);

    return HomePaperCard(
      stripe: accent,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                // The way into the card is here, on the profile — no longer a
                // shortcut on בית — so its heading reads as one.
                child: Text(
                  'הכרטיס שלי',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ),
              ProfileStatusTag(
                status: card.profileStatus,
                gender: card.gender,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            card.fullName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: accent,
              height: 1.15,
            ),
          ),
          if (facts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(facts.join(' · '), style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          if (photos.isNotEmpty)
            PersonPhotoCarousel(
              photosPaths: photos,
              height: 300,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(16),
              backgroundColor: dark
                  ? theme.colorScheme.surfaceContainerHighest
                  : AppColors.cardCream,
            )
          else
            Center(child: PersonAvatar(person: card, radius: 44)),
          const SizedBox(height: 12),
          Text(
            description.isEmpty
                ? 'עוד אין טקסט בכרטיס. כמה שורות {עליך|עלייך} עוזרות לשדכנים להכיר.'
                      .forGender(card.gender)
                : description,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.55,
              color: description.isEmpty
                  ? theme.colorScheme.onSurfaceVariant
                  : (dark ? theme.colorScheme.onSurface : AppColors.onSurface),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('עריכת הכרטיס'),
                ),
              ),
              if (shareable) ...<Widget>[
                const SizedBox(width: 10),
                Builder(
                  builder: (BuildContext anchor) => OutlinedButton.icon(
                    onPressed: () => ShareUtils.sharePerson(
                      card,
                      origin: ShareUtils.originOf(anchor),
                    ),
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('שיתוף'),
                  ),
                ),
              ],
            ],
          ),
          TextButton(
            onPressed: () => PersonCardViewer.openOwnCard(context),
            child: const Text('תצוגת הכרטיס לשדכנים'),
          ),
        ],
      ),
    );
  }
}
