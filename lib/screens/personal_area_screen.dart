import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/services/personal_card_sync.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/card_access_sections.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/shadchan_app_bar.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';

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
  const PersonalAreaScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    WorkspaceStore.setLastArea(WorkArea.personal);
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
                // **The way to the matchmaker's side is a card of its own,
                // right under the greeting** — for somebody who is both, it is
                // the other half of the account, not a footnote under it.
                if (matchmaker) ...<Widget>[
                  const SizedBox(height: 14),
                  _SwitchAreaCard(onTap: _goToMatchmaker),
                ],
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
                    onEdit: () => context.push('/me/card'),
                  ),
                  const SizedBox(height: 14),
                  _MyStatusCard(
                    card: card,
                    saving: _savingStatus,
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
                const SizedBox(height: 6),
                // Status reports, requests, who can see the card, friends who
                // could, and anybody blocked — all decided on the server.
                if (!cards.isDeleted)
                  CardAccessSections(hasCard: cards.hasCard),
                // A secondary action, quiet and at the very end.
                if (cards.hasCard) ...<Widget>[
                  const SizedBox(height: 20),
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
                  'מעבר לאזור השדכן',
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

/// "הסטטוס שלי" — three answers, and only three: פנוי, תפוס, בהפסקה.
///
/// "מזל טוב" is not one of them. It is news a matchmaker marks on their own
/// side, and asking somebody to set it on their own card was a fourth button
/// for a question nobody reaches for.
class _MyStatusCard extends StatelessWidget {
  const _MyStatusCard({
    required this.card,
    required this.saving,
    required this.onSelected,
  });

  final Person card;
  final bool saving;
  final ValueChanged<ProfileStatus> onSelected;

  static const List<ProfileStatus> choices = <ProfileStatus>[
    ProfileStatus.available,
    ProfileStatus.busy,
    ProfileStatus.onBreak,
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return HomePaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'הסטטוס שלי',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              for (final ProfileStatus status in choices) ...<Widget>[
                Expanded(
                  child: _StatusOption(
                    status: status,
                    gender: card.gender,
                    selected: card.profileStatus == status,
                    onTap: saving ? null : () => onSelected(status),
                  ),
                ),
                if (status != choices.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.status,
    required this.gender,
    required this.selected,
    required this.onTap,
  });

  final ProfileStatus status;
  final Gender gender;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = AppColors.profileStatusDotColor(status);
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.7)
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  status.displayNameFor(gender),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
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

class _MyCardSummary extends StatelessWidget {
  const _MyCardSummary({required this.card, required this.onEdit});

  final Person card;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> facts = <String>[
      if (card.age != null) '${card.age}',
      if ((card.city ?? '').trim().isNotEmpty) card.city!.trim(),
      if (card.religiousLevelLabel.isNotEmpty) card.religiousLevelLabel,
    ];
    final String description = (card.description ?? '').trim();

    return HomePaperCard(
      stripe: AppColors.genderAccent(card.gender),
      onTap: onEdit,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              PersonAvatar(person: card, radius: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('הכרטיס שלי', style: theme.textTheme.labelMedium),
                    Text(
                      card.fullName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (facts.isNotEmpty)
                      Text(facts.join(' · '), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              ProfileStatusTag(
                status: card.profileStatus,
                gender: card.gender,
                compact: true,
              ),
            ],
          ),
          if (description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('עריכת הכרטיס'),
            ),
          ),
        ],
      ),
    );
  }
}
