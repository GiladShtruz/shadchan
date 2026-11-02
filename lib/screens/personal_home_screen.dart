import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/dialogs/person_card_viewer.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_area_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/my_matchmakers_screen.dart';
import 'package:shadchan/screens/personal_area_screen.dart';
import 'package:shadchan/services/personal_helpers_store.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/services/personal_card_sync.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_period.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/home_typography.dart';
import 'package:shadchan/utils/community_prompt_gate.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/card_status_timestamp.dart';
import 'package:shadchan/widgets/home_app_bar.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/profile_status_choices.dart';
import 'package:shadchan/widgets/reminders_bell_button.dart';
import 'package:shadchan/widgets/shadchan_app_bar.dart';

/// Three personal destinations, separate from the matchmaker database tabs.
class PersonalAreaScreen extends StatelessWidget {
  const PersonalAreaScreen({
    super.key,
    this.section,
    this.friendUid,
    this.createData = PersonalAreaProvider.new,
  });
  final PersonalAreaProvider Function() createData;
  final String? section, friendUid;
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => createData(),
    child: _PersonalShell(section: section, friendUid: friendUid),
  );
}

class _PersonalShell extends StatefulWidget {
  const _PersonalShell({this.section, this.friendUid});
  final String? section, friendUid;
  @override
  State<_PersonalShell> createState() => _PersonalShellState();
}

class _PersonalShellState extends State<_PersonalShell> {
  int _tab = 0;
  int _tabFor(String? section) => switch (section) {
    'profile' => 2,
    'helpers' || 'approved' || 'requests' => 1,
    _ => 0,
  };
  @override
  void initState() {
    super.initState();
    _tab = _tabFor(widget.section);
    WorkspaceStore.setLastArea(WorkArea.personal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CommunityPromptGate.maybeAskHomeAreaOnly(context);
    });
  }

  @override
  void didUpdateWidget(covariant _PersonalShell old) {
    super.didUpdateWidget(old);
    if (old.section != widget.section || old.friendUid != widget.friendUid) {
      _tab = _tabFor(widget.section);
    }
  }

  void _select(int index) {
    setState(() => _tab = index);
    final router = GoRouter.maybeOf(context);
    router?.go(
      index == 0
          ? '/me'
          : index == 1
          ? '/me?section=helpers'
          : '/me?section=profile',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget shell() => Theme(
      data: theme.copyWith(
        textTheme: HomeTypography.scale(
          theme.textTheme,
          dark: theme.brightness == Brightness.dark,
        ),
      ),
      child: Scaffold(
        appBar: ShadchanAppBar(
          title: ['האזור האישי', 'השדכנים שלי', 'פרופיל'][_tab],
          actions: const [RemindersBellButton(boxed: true)],
        ),
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: [
              TickerMode(
                enabled: _tab == 0,
                child: _PersonalHome(onProfile: () => _select(2)),
              ),
              TickerMode(
                enabled: _tab == 1,
                child: MyMatchmakersScreen(
                  approved: widget.section == 'approved',
                  friendUid: widget.friendUid,
                ),
              ),
              TickerMode(
                enabled: _tab == 2,
                child: const PersonalProfileScreen(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _tab,
          onTap: _select,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'בית',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.handshake_outlined),
              activeIcon: Icon(Icons.handshake_rounded),
              label: 'השדכנים שלי',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'פרופיל',
            ),
          ],
        ),
      ),
    );
    if (!Hive.isBoxOpen('settings')) return shell();
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box<dynamic>(
        'settings',
      ).listenable(keys: [PersonalHelperActions.hiddenKey]),
      builder: (_, _, _) => ListenableBuilder(
        listenable: PersonalHelpersStore.revision,
        builder: (_, _) => shell(),
      ),
    );
  }
}

class _PersonalHome extends StatelessWidget {
  const _PersonalHome({required this.onProfile});
  final VoidCallback onProfile;
  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserProfileProvider>();
    final cards = context.watch<PersonalCardProvider>();
    final access = context.watch<CardAccessProvider>();
    final data = context.watch<PersonalAreaProvider>();
    final approved = access.approved.where((a) => a.canReadCard).length;
    final helpers = access.helpers
        .where((h) => !PersonalHelperActions.hidden.contains(h.uid))
        .toList();
    final card = cards.card;
    final hour = DateTime.now().hour;
    final greeting = hour >= 5 && hour < 12
        ? 'בוקר טוב'
        : hour < 17 && hour >= 12
        ? 'צהריים טובים'
        : hour >= 17 && hour < 21
        ? 'ערב טוב'
        : 'לילה טוב';
    DateTime? lastReview = data.date('reviewedAt');
    DateTime? edited = card?.updatedAt;
    final remoteEdit = data.date('editedAt');
    if (remoteEdit != null && (edited == null || remoteEdit.isAfter(edited))) {
      edited = remoteEdit;
    }
    if (edited != null && (lastReview == null || edited.isAfter(lastReview))) {
      lastReview = edited;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        HomeGreeting(
          greeting: greeting,
          name: '${profile.firstName ?? 'שלום'}! 👋',
          line: '{תן|תני} לחברים שלך לחשוב {עליך|עלייך}'.forGender(
            profile.gender,
          ),
        ),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _PersonalStat(
                  value: access.isConnected ? '$approved' : '—',
                  label: 'שדכנים עם גישה לכרטיס שלי',
                  onTap: () => context.go('/me?section=approved'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PersonalStat(
                  value: access.helpersLoaded
                      ? '${access.mutualFriends.length}'
                      : '—',
                  label: 'חברים רווקים שהצטרפו לשדכן',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MutualSingleFriendsScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PersonalStat(
                  value: data.stats['singles'] is num
                      ? '${data.stats['singles']}'
                      : '—',
                  label: 'רווקים ורווקות בקהילה',
                  onTap: () => _inviteCommunity(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'יש לך חברים בשדכן שעוד לא נתת להם גישה!',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        if (helpers.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final helper in helpers.take(10))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: SizedBox(
                        width: 238,
                        child: PersonalHelperCard(
                          helper: helper,
                          compact: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          )
        else
          HomePaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'מי עוד מכיר אותך מספיק טוב כדי לחשוב {עליך|עלייך}?'
                      .forGender(profile.gender),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () => PersonalAreaService.invite(context),
                  child: const Text('מזמינים חבר לשדכן'),
                ),
                TextButton(
                  onPressed: () => PersonalHelperActions.contacts(context),
                  child: const Text('איתור חברים מאנשי הקשר'),
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: () => context.go('/me?section=helpers'),
          child: const Text('לכל החברים ובקשות הגישה'),
        ),
        if (cards.hasCard &&
            lastReview != null &&
            PersonalAreaProvider.reviewDue(lastReview)) ...[
          HomePaperCard(
            stripe: AppColors.secondary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'עברו שלושה חודשים מאז העדכון האחרון. הכול עדיין רלוונטי?',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        try {
                          await PersonalAreaService.call(
                            'confirmPersonalCardCurrent',
                          );
                        } catch (_) {
                          if (context.mounted) {
                            AppNotice.show(
                              context,
                              'האישור לא נשמר. כדאי לנסות שוב.',
                            );
                          }
                        }
                      },
                      child: const Text('הכול מעודכן ✓'),
                    ),
                    TextButton(
                      onPressed: () => PersonalAreaService.editCard(context),
                      child: const Text('אני רוצה לשנות משהו'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (card != null && !cards.isDeleted)
          _CompactPersonalCard(
            card: card,
            onView: () => PersonCardViewer.openOwnCard(context),
          )
        else
          HomePaperCard(
            child: Column(
              children: [
                Text(
                  cards.isDeleted ? 'הכרטיס שלך נמחק' : 'עוד אין לך כרטיס אישי',
                ),
                FilledButton(
                  onPressed: cards.isDeleted
                      ? onProfile
                      : () => PersonalAreaService.editCard(context),
                  child: Text(
                    cards.isDeleted ? 'שחזור הכרטיס שלי' : 'יצירת הכרטיס שלי',
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const PersonalCommunityNews(),
        const SizedBox(height: 16),
        HomePaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'עוד חברים יכולים לחשוב {עליך|עלייך}!'.forGender(
                  profile.gender,
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'מזמינים חברים שמכירים אותך, ונותנים להם הזדמנות לחשוב על רעיון מתאים.',
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => PersonalAreaService.invite(context),
                icon: const Icon(Icons.share_outlined),
                label: const Text('מזמינים חברים לשדכן'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _inviteCommunity(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'יש לך חברים שעוד לא הצטרפו לשדכן? משתפים אותם, כדי שגם החברים שלהם יוכלו להתחיל לחשוב בשבילם!',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.pop(sheet);
                PersonalAreaService.invite(context);
              },
              child: const Text('משתפים חברים בשדכן'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PersonalStat extends StatelessWidget {
  const _PersonalStat({
    required this.value,
    required this.label,
    required this.onTap,
  });
  final String value, label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => HomePaperCard(
    stripe: AppColors.secondary,
    onTap: onTap,
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _CompactPersonalCard extends StatefulWidget {
  const _CompactPersonalCard({required this.card, required this.onView});
  final Person card;
  final VoidCallback onView;
  @override
  State<_CompactPersonalCard> createState() => _CompactPersonalCardState();
}

class _CompactPersonalCardState extends State<_CompactPersonalCard> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return HomePaperCard(
      stripe: AppColors.genderAccent(
        card.gender,
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PersonAvatar(person: card, radius: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.fullName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      [
                        if (card.age != null) '${card.age}',
                        if ((card.city ?? '').isNotEmpty) card.city!,
                      ].join(' · '),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProfileStatusChoices(
            title: 'הסטטוס שלי',
            framed: false,
            status: card.profileStatus,
            gender: card.gender,
            enabled: !_saving,
            onSelected: (status) async {
              setState(() => _saving = true);
              try {
                final cards = context.read<PersonalCardProvider>();
                await cards.setStatus(status);
                if (cards.card != null && FirebaseBootstrap.isReady) {
                  await PersonalCardSync.publishNow(cards.card!);
                }
                if (context.mounted) {
                  await PersonalAreaService.offerUpdate(context);
                }
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
          ),
          CardStatusTimestamp(ownerUid: context.read<CardAccessProvider>().uid),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () => PersonalAreaService.editCard(context),
                child: const Text('עריכת הכרטיס'),
              ),
              TextButton(
                onPressed: widget.onView,
                child: const Text('צפייה בכרטיס'),
              ),
            ],
          ),
          if (card.photosPaths.length < 2)
            const Text(
              'כדאי להוסיף עוד תמונה כדי לעזור לחברים להציג אותך בצורה טובה יותר.',
            ),
          if ((card.description ?? '').trim().isEmpty)
            Text(
              'כמה מילים {עליך|עלייך} יעזרו לחברים להכיר ולהציג אותך.'
                  .forGender(card.gender),
            ),
        ],
      ),
    );
  }
}

class MutualSingleFriendsScreen extends StatelessWidget {
  const MutualSingleFriendsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final access = context.watch<CardAccessProvider>();
    final active =
        WorkspaceStore.matchmakerEnabled &&
        context.watch<PersonRepository>().databaseCount > 1;
    return Scaffold(
      appBar: AppBar(title: const Text('חברים שהצטרפו לשדכן')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HomePaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  (active
                          ? '{עבור|עברי} לאזור {השדכן|השדכנית} {ותתחיל|ותתחילי} לחשוב על החברים שלך!'
                          : 'גם החברים שלך מחכים שמישהו יחשוב עליהם! {הצטרף|הצטרפי} לשדכן {ותתחיל|ותתחילי} לחשוב גם {אתה|את} בשבילם ❤️')
                      .forGender(context.userGender),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => PersonalAreaService.openMatchmaking(context),
                  child: Text(
                    (active
                            ? 'מעבר לאזור {השדכן|השדכנית}'
                            : 'להצטרפות {כשדכן|כשדכנית}')
                        .forGender(context.userGender),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'מוצגים רק חברים ששמורים אצלך ושגם שמרו אותך באנשי הקשר שלהם. פרטי הכרטיסים שלהם אינם מוצגים כאן.',
          ),
          for (final friend in access.mutualFriends)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(access.nameInContacts(friend.uid, friend.name)),
            ),
        ],
      ),
    );
  }
}

class PersonalCommunityNews extends StatefulWidget {
  const PersonalCommunityNews({super.key});
  @override
  State<PersonalCommunityNews> createState() => _PersonalCommunityNewsState();
}

class _PersonalCommunityNewsState extends State<PersonalCommunityNews> {
  Timer? _timer;
  int _index = 0;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<PersonalAreaProvider>();
    final stats = data.stats;
    final items = <PersonalNews>[...data.news];
    if (stats['weekKey'] == CommunityPeriods.weekKey()) {
      for (final entry in <(String, String)>[
        ('newSinglesWeek', 'רווקים ורווקות הצטרפו השבוע'),
        ('newMatchmakersWeek', 'שדכנים חדשים הצטרפו השבוע'),
        ('activeMatchmakers', 'שדכנים פעילים בקהילה השבוע'),
        ('couplesWeek', 'זוגות התחילו לצאת השבוע'),
        ('engagementsWeek', 'אירוסים דווחו השבוע'),
      ]) {
        final value = stats[entry.$1];
        if (value is num && value > 0) {
          items.add(
            PersonalNews(
              id: entry.$1,
              title: 'הקהילה ממשיכה להתחבר ❤️',
              text: '$value ${entry.$2}',
            ),
          );
        }
      }
    }
    final animate =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    if (items.length > 1 && animate) {
      _timer ??= Timer.periodic(const Duration(seconds: 6), (_) {
        if (mounted) setState(() => _index++);
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
    if (items.isEmpty) return const SizedBox.shrink();
    final item = items[_index % items.length];
    return HomePaperCard(
      stripe: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'מה חדש בקהילת שדכן?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: Duration(milliseconds: animate ? 350 : 0),
            child: Column(
              key: ValueKey(item.id),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (item.imagePath != null)
                  PersonalNewsImage(
                    key: ValueKey(item.imagePath),
                    path: item.imagePath!,
                  ),
                Text(item.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(item.text, maxLines: 5, overflow: TextOverflow.ellipsis),
                if (data.news.any((n) => n.id == item.id))
                  TextButton(
                    onPressed: () => context.push('/me/news/${item.id}'),
                    child: const Text('לקריאת העדכון'),
                  ),
              ],
            ),
          ),
          if (items.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'העדכון הקודם',
                  onPressed: () =>
                      setState(() => _index = (_index - 1) % items.length),
                  icon: const Icon(Icons.chevron_right),
                ),
                Text(
                  '${_index % items.length + 1} / ${items.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  tooltip: 'העדכון הבא',
                  onPressed: () => setState(() => _index++),
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class PersonalNewsImage extends StatefulWidget {
  const PersonalNewsImage({super.key, required this.path});
  final String path;
  @override
  State<PersonalNewsImage> createState() => _PersonalNewsImageState();
}

class _PersonalNewsImageState extends State<PersonalNewsImage> {
  late final _bytes = FirebaseStorage.instance
      .ref(widget.path)
      .getData(12 * 1024 * 1024);
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _bytes,
    builder: (_, snap) => snap.hasData
        ? Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(snap.data!, height: 180, fit: BoxFit.contain),
            ),
          )
        : const SizedBox.shrink(),
  );
}

class PersonalNewsDetailScreen extends StatelessWidget {
  const PersonalNewsDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('מה חדש בקהילת שדכן')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseBootstrap.isReady
          ? FirebaseFirestore.instance.doc('personalNews/$id').snapshots()
          : null,
      builder: (context, snapshot) {
        if (snapshot.hasError || snapshot.data?.exists == false) {
          return const Center(child: Text('העדכון כבר אינו זמין'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final news = PersonalNews.fromMap(id, snapshot.data!.data()!);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (news.imagePath != null)
              PersonalNewsImage(
                key: ValueKey(news.imagePath),
                path: news.imagePath!,
              ),
            Text(news.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(news.text),
          ],
        );
      },
    ),
  );
}
