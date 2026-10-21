import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/widgets/home_community_link.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/services/personal_card_sync.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/community_prompt_gate.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/person_photo_carousel.dart';
import 'package:shadchan/widgets/card_access_sections.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/shadchan_app_bar.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';
import 'package:shadchan/widgets/profile_status_choices.dart';

/// The card owner's own area: their card, their status, and who may see it.
///
/// **No bottom bar, on purpose.** This is not a fourth tab of the matchmaker's
/// app; it is the other half of the account, and somebody who only came to
/// manage their card should never be shown a database or a list of ideas.
/// A user who is both reaches the matchmaker's tabs through one clear button.
///
/// Opening this page is what makes it the page the app opens on next time —
/// see [WorkspaceStore.lastArea].
class PersonalAreaScreen extends StatefulWidget {
  const PersonalAreaScreen({super.key, this.section});

  /// A part of the page to open on — `requests`, from a notice about an
  /// access request, lands on the requests themselves rather than on the
  /// greeting.
  final String? section;

  @override
  State<PersonalAreaScreen> createState() => _PersonalAreaScreenState();
}

class _PersonalAreaScreenState extends State<PersonalAreaScreen> {
  bool _savingStatus = false;
  bool _deleting = false;
  bool _restoring = false;

  /// Deletes the card — the card only, never the account or the matchmaker's
  /// side of it. Every matchmaker stops seeing it at once; it stays restorable
  /// indefinitely.
  Future<void> _deleteCard() async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('למחוק את הכרטיס שלך?'),
        content: const Text(
          'השדכנים שקיבלו גישה יפסיקו לראות אותו מיד. החשבון שלך נשאר, '
          'ואפשר לשחזר את הכרטיס בכל עת.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('מחיקה'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) {
      return;
    }
    setState(() => _deleting = true);
    final bool ok = await PersonalCardSync.deleteNow();
    if (!mounted) {
      return;
    }
    if (ok) {
      await context.read<PersonalCardProvider>().markDeleted();
    } else {
      AppNotice.show(context, 'לא הצלחנו למחוק כרגע. אפשר לנסות שוב.');
    }
    if (mounted) {
      setState(() => _deleting = false);
    }
  }

  /// Brings the card back as "פנוי", then asks about the old grants.
  Future<void> _restoreCard() async {
    final PersonalCardProvider cards = context.read<PersonalCardProvider>();
    final CardAccessProvider access = context.read<CardAccessProvider>();
    setState(() => _restoring = true);
    final Person? restored = await cards.restore();
    final bool ok =
        restored != null && await PersonalCardSync.publishNow(restored);
    if (!mounted) {
      return;
    }
    if (!ok) {
      await cards.markDeleted();
      if (mounted) {
        setState(() => _restoring = false);
        AppNotice.show(context, 'לא הצלחנו לשחזר כרגע. אפשר לנסות שוב.');
      }
      return;
    }
    setState(() => _restoring = false);
    if (access.approved.isEmpty) {
      AppNotice.show(context, 'הכרטיס שוחזר');
      return;
    }
    final bool? keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('הכרטיס שוחזר'),
        content: Text(
          '{האם תרצה|האם תרצי} לשחזר גם את אישורי הגישה לשדכנים?'.forGender(
            dialogContext.userGender,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('לא'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('כן, לשחזר'),
          ),
        ],
      ),
    );
    final bool done = keep == true
        ? await access.reawakenApproved()
        : await access.revokeAllApproved();
    if (!done && mounted) {
      AppNotice.show(
        context,
        'לא הצלחנו לעדכן את אישורי הגישה. אפשר לנסות שוב.',
      );
    }
  }

  final GlobalKey _requestsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WorkspaceStore.setLastArea(WorkArea.personal);
    _scrollToSection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        CommunityPromptGate.maybeAskHomeAreaOnly(context);
      }
    });
  }

  @override
  void didUpdateWidget(PersonalAreaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.section != oldWidget.section) {
      _scrollToSection();
    }
  }

  /// Brings the asked-for section into view — once on the first frame, and
  /// once more a moment later, when the requests have arrived from the server
  /// and the sections above them have taken their real height.
  void _scrollToSection() {
    if (widget.section != 'requests') {
      return;
    }
    void reveal() {
      final BuildContext? target = _requestsKey.currentContext;
      if (!mounted || target == null) {
        return;
      }
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.05,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      reveal();
      Future<void>.delayed(const Duration(milliseconds: 700), reveal);
    });
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
      await context.read<PersonalCardProvider>().setStatus(status);
    } finally {
      if (mounted) {
        setState(() => _savingStatus = false);
      }
    }
  }

  void _goToMatchmaker() {
    WorkspaceStore.setLastArea(WorkArea.matchmaker);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final Person? card = cards.card;
    final bool matchmaker = WorkspaceStore.matchmakerEnabled;
    final String firstName = profile.firstName ?? '';

    // **The personal area speaks the home page's language**: the same paper
    // cards, the same three type sizes and two inks, the same greeting — so
    // moving between the two halves of the account never feels like moving
    // between two apps.
    return Theme(
      data: theme.copyWith(
        textTheme: HomeTypography.scale(theme.textTheme, dark: dark),
      ),
      child: Builder(
        builder: (BuildContext context) => Scaffold(
          appBar: ShadchanAppBar(
            title: 'האזור האישי',
            actions: <Widget>[
              HomeBarButton(
                tooltip: 'הפרופיל שלי',
                icon: const Icon(Icons.person_outline_rounded),
                onPressed: () => context.go('/profile'),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: <Widget>[
                HomeGreeting(
                  greeting: _greetingFor(TimeOfDay.now()),
                  name: firstName.isEmpty ? 'שלום' : firstName,
                  line: 'כאן {אתה מנהל|את מנהלת} את הכרטיס האישי שלך'.forGender(
                    profile.gender,
                  ),
                ),
                const SizedBox(height: 14),
                if (cards.isDeleted)
                  _RestoreCardPrompt(busy: _restoring, onRestore: _restoreCard)
                else if (card == null)
                  _CreateCardPrompt(
                    gender: profile.gender,
                    onCreate: () => context.push('/me/card'),
                  )
                else ...<Widget>[
                  _MyCardSummary(
                    card: card,
                    active: cards.hasCard,
                    onEdit: () => context.push('/me/card'),
                  ),
                  if (!cards.hasCard) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      'הכרטיס עדיין טיוטה. הוספת תמונה אחת או 30 תווים '
                      'בתיאור תאפשר לשדכנים לבקש גישה.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  ProfileStatusChoices(
                    title: 'הסטטוס שלי',
                    status: card.profileStatus,
                    gender: card.gender,
                    enabled: !_savingStatus,
                    onSelected: (ProfileStatus status) =>
                        _setStatus(card, status),
                  ),
                ],
                // Without the user's own number nobody can find the card, so
                // the question stays here until it is answered.
                if (profile.myPhone == null) ...<Widget>[
                  const SizedBox(height: 14),
                  HomePaperCard(
                    stripe: dark
                        ? AppColors.secondaryDarkDm
                        : AppColors.secondary,
                    onTap: () async {
                      final String? phone = await MyPhoneDialog.show(context);
                      if (phone != null) {
                        await profile.setMyPhone(phone);
                      }
                    },
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.phone_outlined, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'הוספת המספר שלי',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'בלעדיו חברים שמשדכים לא יוכלו למצוא את '
                                'הכרטיס שלך',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // Keep the home page a summary, not an endless list of
                // permission switches and matchmakers. Full controls live in
                // /me/privacy and retain their server-enforced behavior.
                if (!cards.isDeleted)
                  _PersonalAccessOverview(
                    requestsKey: _requestsKey,
                    hasCard: cards.hasCard,
                  ),
                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => context.push('/me/privacy'),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('ניהול ופרטיות'),
                  ),
                ),
                if (matchmaker) ...<Widget>[
                  const SizedBox(height: 8),
                  _SwitchAreaCard(onTap: _goToMatchmaker),
                ],
                const SizedBox(height: 20),
                _ShareAppLink(gender: profile.gender),
                // Deleting the card is a secondary action: under a rule, quiet,
                // and the very last thing on the page.
                if (cards.hasCard) ...<Widget>[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Center(
                    child: _deleting
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _deleteCard,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.mutedInk,
                            ),
                            child: const Text('מחיקת הכרטיס שלי'),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _greetingFor(TimeOfDay now) {
    final int hour = now.hour;
    if (hour >= 5 && hour < 12) {
      return 'בוקר טוב';
    }
    if (hour >= 12 && hour < 17) {
      return 'צהריים טובים';
    }
    if (hour >= 17 && hour < 21) {
      return 'ערב טוב';
    }
    return 'לילה טוב';
  }
}

/// "שיתוף האפליקציה" — a small link at the foot of the page, drawn like the
/// share line at the bottom of the matchmakers' home page: it opens the
/// phone's share sheet with a ready message and the join link.
class _ShareAppLink extends StatelessWidget {
  const _ShareAppLink({required this.gender});

  final Gender? gender;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Builder(
        builder: (BuildContext anchor) => FooterLink(
          icon: Icon(
            Icons.share_outlined,
            size: 17,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          label: 'שיתוף האפליקציה עם חברים',
          theme: theme,
          onTap: () async {
            try {
              await Share.share(
                CommunityLinks.singleShareMessage(gender),
                sharePositionOrigin: ShareUtils.originOf(anchor),
              );
            } on Object {
              // Nothing to share to is not worth a message.
            }
          },
        ),
      ),
    );
  }
}

/// "לעבור לאזור השדכן" — a whole card, near the top, for somebody who is also a
/// matchmaker.
class _SwitchAreaCard extends StatelessWidget {
  const _SwitchAreaCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;

    return HomePaperCard(
      stripe: ink,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.swap_horiz_rounded, color: ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'מעבר לאזור {השדכן|השדכנית}'.forGender(context.userGender),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'המאגר, הרעיונות והלוח שלך',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: ink),
        ],
      ),
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
  const _MyCardSummary({
    required this.card,
    required this.active,
    required this.onEdit,
  });

  final Person card;
  final bool active;
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
    final bool shareable = active && WhatsAppUtils.hasSendableCard(card);

    return HomePaperCard(
      stripe: accent,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('הכרטיס שלי', style: theme.textTheme.labelMedium),
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
                  : AppColors.secondaryLight,
            )
          else
            Center(child: PersonAvatar(person: card, radius: 44)),
          const SizedBox(height: 12),
          Text(
            description.isEmpty
                ? 'עוד אין טקסט בכרטיס. כמה שורות עליך עוזרות לשדכנים להכיר.'
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
        ],
      ),
    );
  }
}

/// A quiet overview. Names and counts come exclusively from the access
/// provider's live Firestore snapshot; no view counts or invented activity.
class _PersonalAccessOverview extends StatelessWidget {
  const _PersonalAccessOverview({
    required this.requestsKey,
    required this.hasCard,
  });

  final Key requestsKey;
  final bool hasCard;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final approved = access.approved;
    final pending = access.pendingRequests;
    final helpers = access.helpers;
    final int reports = access.statusReports.length;
    final String approvedPreview = approved
        .take(3)
        .map((row) =>
            access.nameInContacts(row.matchmakerUid, row.matchmakerName))
        .where((name) => name.trim().isNotEmpty)
        .join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HomePaperCard(
          onTap: () => context.push('/me/privacy'),
          child: Row(
            children: <Widget>[
              const Icon(Icons.visibility_outlined, size: 25),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('מי רואה את הכרטיס שלי',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      hasCard
                          ? '${approved.length} שדכנים קיבלו גישה לכרטיס'
                          : 'הכרטיס עדיין לא פעיל',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (approvedPreview.isNotEmpty)
                      Text(
                        approvedPreview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
        if (pending.isNotEmpty || reports > 0) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            key: requestsKey,
            child: HomePaperCard(
              onTap: () => context.push('/me/privacy'),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.mark_email_unread_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('מחכה לטיפול שלך',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        if (pending.isNotEmpty)
                          Text('${pending.length} בקשות גישה חדשות'),
                        if (reports > 0)
                          Text('$reports עדכוני סטטוס לאישור'),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded),
                ],
              ),
            ),
          ),
        ],
        if (hasCard && helpers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          HomePaperCard(
            onTap: () => context.push('/me/privacy'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('החברים שלי שמשדכים בשדכן',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final helper in helpers.take(3))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      access.nameInContacts(helper.uid, helper.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    helpers.length > 3 ? 'הצגת כל החברים' : 'לתת הרשאה לחבר',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Lists, privacy toggles and grants are one level below the personal home.
/// The old CardAccessSections logic remains intact; its request and helper
/// actions continue using the same rules and confirmation dialogs.
class PersonalPrivacyScreen extends StatelessWidget {
  const PersonalPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final PersonalCardProvider cards = context.watch<PersonalCardProvider>();
    return Scaffold(
      appBar: ShadchanAppBar(
        title: 'ניהול ופרטיות',
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            Text(
              'הכרטיס שייך לך. מכאן אפשר לנהל מי מקבל גישה אליו.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            CardAccessSections(hasCard: cards.hasCard),
          ],
        ),
      ),
    );
  }
}
