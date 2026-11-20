import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/shared_card.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/screens/chats_screen.dart';
import 'package:shadchan/screens/couple_workspace_screen.dart';
import 'package:shadchan/screens/network_screen.dart';
import 'package:shadchan/screens/profile_screen.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/services/couple_workspace_service.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/services/partner_space.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/known_matchmakers.dart';
import 'package:shadchan/utils/person_navigation.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';

/// "המרחב הזוגי שלנו" — opening it, the partner's yes, and once it is open:
/// both faces, the partner's database, the chat and the ideas the two share.
///
/// See [PartnerSpace] for what it is — and is not.
class PartnerSpaceScreen extends StatelessWidget {
  const PartnerSpaceScreen({super.key});

  static const String route = '/partner';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('המרחב הזוגי')),
      body: ValueListenableBuilder<Partnership?>(
        valueListenable: PartnerSpace.current,
        builder: (BuildContext context, Partnership? p, _) {
          final String me = PartnerSpace.uid ?? '';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              if (CoupleWorkspaceService.isCouple) const _OldCoupleNote(),
              if (p == null)
                const _OpenSpace()
              else if (p.isActive)
                _ActiveSpace(partnership: p, me: me)
              else if (p.fromUid == me)
                _Outgoing(partnership: p, me: me)
              else
                _Incoming(partnership: p, me: me),
            ],
          );
        },
      ),
    );
  }
}

/// The few sentences that say what a couple space is, everywhere it is
/// offered or answered.
class _Explanation extends StatelessWidget {
  const _Explanation();

  static const List<String> points = <String>[
    'כל אחד ממשיך עם החשבון והמאגר האישי שלו, ועם אנשי הקשר של הטלפון שלו בלבד.',
    'כל אחד רואה את כל המאגר של השני — צפייה בלבד: פרטי הכרטיס, תמונות, תגיות ו"מה מחפש".',
    'ההערות האישיות, ההיסטוריה, התזכורות ומספרי הטלפון נשארים פרטיים.',
    'אפשר לפתוח רעיון בין חבר שלך לחבר של בן/בת הזוג בלי לבקש אישור — הרעיון משותף לשניכם.',
    'צ\'אט זוגי אחד, קבוע.',
    'אפשר לבטל בכל רגע: הגישה ההדדית נעלמת מיד, ושום חבר לא נמחק או עובר בין המאגרים.',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final String line in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(line, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

class _OldCoupleNote extends StatelessWidget {
  const _OldCoupleNote();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: HomePaperCard(
        stripe: AppColors.secondary,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'אתם עדיין במאגר זוגי משותף מהגרסה הקודמת',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'המרחב הזוגי החדש שומר לכל אחד את המאגר שלו. אפשר להפריד את '
              'המאגר המשותף — כל אחד מקבל בחזרה את החברים שהוסיף — ואז לפתוח '
              'מרחב זוגי.',
              style: theme.textTheme.bodySmall,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CoupleWorkspaceScreen(),
                  ),
                ),
                child: const Text('להפרדת המאגר המשותף'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No tie yet: what it is, and "הזמנת בן/בת הזוג".
class _OpenSpace extends StatelessWidget {
  const _OpenSpace();

  Future<void> _invite(BuildContext context) async {
    if (!OfflineGuard.allow(context)) return;
    final KnownMatchmaker? chosen = await _PartnerPicker.show(context);
    if (chosen == null || !context.mounted) return;
    final String myName = context.read<UserProfileProvider>().fullName ?? '';
    final bool ok = await PartnerSpace.invite(
      otherUid: chosen.uid,
      myName: myName,
      theirName: chosen.name,
    );
    if (!context.mounted) return;
    AppNotice.show(
      context,
      ok
          ? 'ההזמנה נשלחה ל${chosen.name}. המרחב ייפתח לאחר האישור.'
          : 'ההזמנה לא נשלחה. אפשר לנסות שוב.',
      isError: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Icon(
          Icons.favorite_border_rounded,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 8),
        Text(
          'פתיחת מרחב זוגי',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'לחשוב יחד על שידוכים בין החברים של שניכם — בלי לאחד מאגרים.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        const _Explanation(),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _invite(context),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('הזמנת בן/בת הזוג'),
        ),
        const SizedBox(height: 8),
        Text(
          'בן/בת הזוג צריכים להשתמש בשדכן ולהיות שמורים באנשי הקשר שלך. '
          'ההזמנה תגיע אליהם, והמרחב ייפתח רק לאחר אישור שלהם.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The matchmakers this phone knows — connected first — to invite one.
abstract final class _PartnerPicker {
  static Future<KnownMatchmaker?> show(BuildContext context) {
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final KnownMatchmakerGroups groups = KnownMatchmakers.build(
      me: MatchmakerShares.uid ?? access.uid,
      helpers: access.knownHelpers,
      shares: MatchmakerShares.rows.value,
      nameOf: (CardHelper h) => ContactHashUpload.nameFor(h.phoneHash),
    );
    final List<KnownMatchmaker> all = <KnownMatchmaker>[
      ...groups.connected,
      ...groups.others,
    ];
    return showModalBottomSheet<KnownMatchmaker>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'את מי להזמין למרחב הזוגי?',
                  style: Theme.of(sheet).textTheme.titleMedium,
                ),
              ),
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'לא מצאנו עדיין שדכנים מאנשי הקשר שלך. כשבן/בת הזוג '
                    'יירשמו לשדכן ויישמרו אצלך באנשי הקשר, הם יופיעו כאן.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: all.length,
                    itemBuilder: (BuildContext context, int i) => ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          all[i].name.trim().isEmpty
                              ? '?'
                              : all[i].name.trim().characters.first,
                        ),
                      ),
                      title: Text(all[i].name),
                      onTap: () => Navigator.of(sheet).pop(all[i]),
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

class _Outgoing extends StatelessWidget {
  const _Outgoing({required this.partnership, required this.me});
  final Partnership partnership;
  final String me;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = partnership.nameOf(partnership.otherOf(me));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'ההזמנה נשלחה ל$name',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'המרחב הזוגי ייפתח ברגע שיאשרו בטלפון שלהם.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const _Explanation(),
        TextButton(
          onPressed: () => PartnerSpace.end(partnership),
          child: const Text('ביטול ההזמנה'),
        ),
      ],
    );
  }
}

class _Incoming extends StatelessWidget {
  const _Incoming({required this.partnership, required this.me});
  final Partnership partnership;
  final String me;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = partnership.nameOf(partnership.otherOf(me));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '$name מזמין/ה אותך למרחב זוגי',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        const _Explanation(),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            if (!OfflineGuard.allow(context)) return;
            final bool ok = await PartnerSpace.accept(partnership);
            if (!ok && context.mounted) {
              AppNotice.show(
                context,
                'האישור לא נשמר. אפשר לנסות שוב.',
                isError: true,
              );
            }
          },
          child: const Text('אישור ופתיחת המרחב הזוגי'),
        ),
        TextButton(
          onPressed: () => PartnerSpace.end(partnership),
          child: const Text('לא עכשיו'),
        ),
      ],
    );
  }
}

/// "המרחב הזוגי שלנו": both faces and names, and the three ways in.
class _ActiveSpace extends StatelessWidget {
  const _ActiveSpace({required this.partnership, required this.me});
  final Partnership partnership;
  final String me;

  Future<void> _end(BuildContext context) async {
    final String first = PartnerSpace.partnerFirstName;
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: const Text('לבטל את המרחב הזוגי?'),
        content: Text(
          'הגישה ההדדית למאגרים תיעלם מיד. כל אחד נשאר עם החשבון והמאגר '
          'שלו בדיוק כפי שהיה — שום חבר לא נמחק ולא עובר. רעיונות שכבר '
          'נפתחו עם $first נשמרים אצל שניכם.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('לבטל את המרחב'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    if (!OfflineGuard.allow(context)) return;
    await PartnerSpace.end(partnership);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String partner = partnership.otherOf(me);
    final String partnerName = partnership.nameOf(partner);
    final String myName = partnership.nameOf(me);
    final List<SharedIdeaLink> shared = SharedIdeas.links.values
        .where((SharedIdeaLink l) => l.partnerUid == partner)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HomePaperCard(
          stripe: AppColors.femaleAccent,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Builder(
                    builder: (BuildContext context) {
                      final UserProfileProvider profile = context
                          .watch<UserProfileProvider>();
                      return UserProfileAvatar(
                        photoPath: profile.photoPath,
                        gender: profile.gender,
                        name: profile.fullName,
                        radius: 30,
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.favorite_rounded, color: AppColors.femaleAccent),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 30,
                    child: Text(
                      partnerName.isEmpty ? '?' : partnerName.characters.first,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'המרחב הזוגי שלנו',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '$myName · $partnerName',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SpaceTile(
          icon: Icons.groups_2_outlined,
          title: 'המאגר של ${PartnerSpace.partnerFirstName}',
          subtitle: 'צפייה, חיפוש וסינון — ופתיחת רעיון עם חבר שלך',
          onTap: () => context.push(PartnerDatabaseScreen.route),
        ),
        _SpaceTile(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'הצ\'אט הזוגי',
          subtitle: 'אפשר לכתוב גם "פתח רעיון בין יוסי לנועה"',
          onTap: () => ChatLauncher.open(
            context,
            otherUid: partner,
            otherName: partnerName,
            kind: 'partners',
          ),
        ),
        _SpaceTile(
          icon: Icons.lightbulb_outline_rounded,
          title: 'הרעיונות המשותפים',
          subtitle: shared.isEmpty
              ? 'עוד לא נפתחו רעיונות משותפים'
              : shared.length == 1
              ? 'רעיון משותף אחד'
              : '${shared.length} רעיונות משותפים',
          onTap: () => _SharedIdeasSheet.show(context, shared),
        ),
        const SizedBox(height: 18),
        TextButton(
          onPressed: () => _end(context),
          child: Text(
            'ביטול המרחב הזוגי',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

abstract final class _SharedIdeasSheet {
  static Future<void> show(BuildContext context, List<SharedIdeaLink> links) {
    final MatchRepository matches = context.read<MatchRepository>();
    final PersonRepository people = context.read<PersonRepository>();
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: links.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'רעיון שנפתח בין חבר שלך לחבר של בן/בת הזוג יופיע כאן — '
                  'ובהרעיונות שלי של שניכם.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final SharedIdeaLink l in links)
                    if (matches.getById(l.matchId) case final idea?)
                      ListTile(
                        title: Text(
                          '${people.getById(idea.personAId)?.fullName ?? ''}'
                          ' ו${people.getById(idea.personBId)?.fullName ?? ''}',
                        ),
                        subtitle: Text(idea.status.stateLabel),
                        onTap: () {
                          Navigator.of(sheet).pop();
                          context.push('/matches/${idea.id}');
                        },
                      ),
                ],
              ),
      ),
    );
  }
}

// --- The partner's database ------------------------------------------------

enum _Scope { partner, both }

/// "המאגר של X" — the partner's whole database, view only, with search and
/// the same filter as המאגר שלי; or both databases together, where a friend
/// known to both appears once, marked "מוכר לשניכם".
class PartnerDatabaseScreen extends StatefulWidget {
  const PartnerDatabaseScreen({super.key});

  static const String route = '/partner/database';

  @override
  State<PartnerDatabaseScreen> createState() => _PartnerDatabaseScreenState();
}

/// One row of the list: a friend of the partner, one of mine, or one both
/// know.
class _Row {
  const _Row({this.card, this.mine, this.both = false});
  final SharedCard? card;
  final Person? mine;
  final bool both;

  Person get person => mine ?? card!.person;
}

class _PartnerDatabaseScreenState extends State<PartnerDatabaseScreen> {
  _Scope _scope = _Scope.partner;
  String _query = '';
  PeopleFilterState? _filter;

  List<_Row> _rows(List<SharedCard> cards, List<Person> mine) {
    final Map<String, Person> mineByIdentity = <String, Person>{
      for (final Person p in mine)
        if (PhoneIdentity.hash(p.phone) case final String h) h: p,
    };
    final Set<String> mineByCardOwner = <String>{
      for (final Person p in mine)
        if ((p.cardOwnerUid ?? '').isNotEmpty) p.cardOwnerUid!,
    };
    bool knownToMe(SharedCard c) =>
        (c.identity != null && mineByIdentity.containsKey(c.identity)) ||
        (c.cardOwnerUid != null && mineByCardOwner.contains(c.cardOwnerUid));
    final List<_Row> rows = <_Row>[];
    if (_scope == _Scope.partner) {
      for (final SharedCard c in cards) {
        rows.add(_Row(card: c, both: knownToMe(c)));
      }
    } else {
      final Set<String> sharedIdentities = <String>{};
      final Set<String> sharedOwners = <String>{};
      for (final SharedCard c in cards) {
        if (knownToMe(c)) {
          if (c.identity != null) sharedIdentities.add(c.identity!);
          if (c.cardOwnerUid != null) sharedOwners.add(c.cardOwnerUid!);
        } else {
          rows.add(_Row(card: c));
        }
      }
      for (final Person p in mine) {
        final String? h = PhoneIdentity.hash(p.phone);
        final bool both =
            (h != null && sharedIdentities.contains(h)) ||
            ((p.cardOwnerUid ?? '').isNotEmpty &&
                sharedOwners.contains(p.cardOwnerUid));
        rows.add(_Row(mine: p, both: both));
      }
    }
    final String q = _query.trim().toLowerCase();
    return rows
        .where(
          (_Row r) =>
              (q.isEmpty || r.person.fullName.toLowerCase().contains(q)) &&
              (_filter == null || _filter!.matches(r.person)),
        )
        .toList()
      ..sort(
        (_Row a, _Row b) => a.person.fullName.compareTo(b.person.fullName),
      );
  }

  @override
  Widget build(BuildContext context) {
    final PersonRepository people = context.watch<PersonRepository>();
    final String first = PartnerSpace.partnerFirstName;
    return Scaffold(
      appBar: AppBar(title: Text('המאגר של $first')),
      body: ValueListenableBuilder<List<SharedCard>>(
        valueListenable: PartnerSpace.partnerCards,
        builder: (BuildContext context, List<SharedCard> cards, _) {
          if (!PartnerSpace.isActive) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'המרחב הזוגי לא פתוח — אין גישה למאגר.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final List<Person> mine = <Person>[
            for (final Person p in people.getAll())
              if (!p.hidden && !p.needsReview) p,
          ];
          final List<_Row> rows = _rows(cards, mine);
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: SegmentedButton<Object>(
                  segments: <ButtonSegment<Object>>[
                    const ButtonSegment<Object>(
                      value: 'mine',
                      label: Text('המאגר שלי'),
                    ),
                    ButtonSegment<Object>(
                      value: _Scope.partner,
                      label: Text('המאגר של $first'),
                    ),
                    const ButtonSegment<Object>(
                      value: _Scope.both,
                      label: Text('שניהם'),
                    ),
                  ],
                  selected: <Object>{_scope},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<Object> s) {
                    final Object v = s.first;
                    if (v == 'mine') {
                      context.go('/people');
                      return;
                    }
                    setState(() => _scope = v as _Scope);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        onChanged: (String v) => setState(() => _query = v),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: _scope == _Scope.both
                              ? 'חיפוש בשני המאגרים'
                              : 'חיפוש במאגר של $first',
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'סינון',
                      icon: Badge(
                        isLabelVisible: _filter != null && !_filter!.isEmpty,
                        child: const Icon(Icons.tune_rounded),
                      ),
                      onPressed: () async {
                        final PeopleFilterState? f =
                            await showPeopleFiltersSheet(
                              context,
                              repository: people,
                              initial: _filter,
                            );
                        if (f != null && mounted) setState(() => _filter = f);
                      },
                    ),
                  ],
                ),
              ),
              if (!PartnerSpace.partnerCardsLoaded.value && cards.isEmpty)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (rows.isEmpty)
                const Expanded(child: Center(child: Text('לא נמצאו חברים.')))
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: rows.length,
                    itemBuilder: (BuildContext context, int i) => _PartnerRow(
                      key: ValueKey<String>(rows[i].person.id),
                      row: rows[i],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PartnerRow extends StatelessWidget {
  const _PartnerRow({super.key, required this.row});
  final _Row row;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Person person = row.person;
    final SharedCard? card = row.card;
    final Person? mine = row.mine;
    final Widget avatar = mine != null
        ? PersonAvatar(person: mine, radius: 22)
        : SharedPhoto(
            ownerUid: card!.ownerUid,
            path: card.photoPaths.isEmpty ? null : card.photoPaths.first,
            person: card.person,
            radius: 22,
          );
    final String owner = mine != null
        ? 'מהמאגר שלי'
        : 'מהמאגר של ${PartnerSpace.partnerFirstName}';
    return ListTile(
      leading: avatar,
      title: Text(
        person.fullName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        <String>[
          sharedSummaryOf(person),
          if (row.both) 'מוכר לשניכם' else owner,
        ].where((String s) => s.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: row.both
          ? Icon(Icons.people_alt_rounded, color: theme.colorScheme.primary)
          : null,
      onTap: () {
        if (mine != null) {
          openPersonProfile(context, mine.id);
        } else {
          PartnerCardSheet.show(context, card!);
        }
      },
    );
  }
}

/// One friend of the partner: the card, view only — photos, details, the
/// card text, tags and "מה מחפש/ת" — and "פתיחת רעיון" with a friend of
/// mine.
abstract final class PartnerCardSheet {
  static Future<void> show(BuildContext context, SharedCard card) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (BuildContext _, ScrollController scroll) =>
            _PartnerCardBody(card: card, scroll: scroll, outer: context),
      ),
    );
  }

  /// Picks a friend of mine for [card] and opens the idea — at once, for
  /// both partners.
  static Future<void> openIdea(BuildContext context, SharedCard card) async {
    if (!OfflineGuard.allow(context)) return;
    final Gender want = card.person.gender == Gender.male
        ? Gender.female
        : Gender.male;
    final Person? mine = await PersonPickerSheet.show(
      context,
      title: 'מי מהמאגר שלך ל${card.person.firstName}?',
      filterGender: card.person.gender == Gender.unknown ? null : want,
      sourcePerson: card.person,
      candidatePredicate: (Person p) =>
          !p.hidden && !SharedIdeas.isPartnersPerson(p.id),
    );
    if (mine == null || !context.mounted) return;
    await openIdeaWith(context, mine: mine, card: card);
  }

  static Future<void> openIdeaWith(
    BuildContext context, {
    required Person mine,
    required SharedCard card,
  }) async {
    if (mine.gender != Gender.unknown && mine.gender == card.person.gender) {
      AppNotice.show(
        context,
        '${mine.firstName} ו${card.person.firstName} מאותו מגדר — לא נפתח רעיון.',
        isError: true,
      );
      return;
    }
    final String? id = await PartnerSpace.openIdea(
      mine: mine,
      target: card,
      myName: context.read<UserProfileProvider>().fullName ?? '',
    );
    if (!context.mounted) return;
    AppNotice.show(
      context,
      id == null
          ? 'הרעיון לא נפתח. אפשר לנסות שוב.'
          : 'נפתח רעיון משותף: ${mine.firstName} ו${card.person.firstName}. '
                'הוא מופיע עכשיו אצל שניכם.',
      isError: id == null,
    );
  }
}

class _PartnerCardBody extends StatefulWidget {
  const _PartnerCardBody({
    required this.card,
    required this.scroll,
    required this.outer,
  });
  final SharedCard card;
  final ScrollController scroll;
  final BuildContext outer;

  @override
  State<_PartnerCardBody> createState() => _PartnerCardBodyState();
}

class _PartnerCardBodyState extends State<_PartnerCardBody> {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SharedCard card = widget.card;
    final Person p = card.person;
    final bool dark = theme.brightness == Brightness.dark;
    final List<String> facts = <String>[
      if (p.age != null) 'גיל ${p.age}',
      if (p.religiousLevel != null) p.religiousLevelLabel,
      if ((p.city ?? '').trim().isNotEmpty) p.city!.trim(),
      if (p.heightCm != null) '${p.heightCm} ס״מ',
      if (p.maritalStatus != null) p.maritalStatus!.filterLabel,
    ];
    final List<String> looking = <String>[
      if (p.preferredMinAge != null || p.preferredMaxAge != null)
        'גיל ${p.preferredMinAge ?? ''}–${p.preferredMaxAge ?? ''}',
      if (p.preferredReligiousLevels.isNotEmpty)
        p.preferredReligiousLevels
            .map((ReligiousLevel l) => l.displayName)
            .join(', '),
      if (p.preferredRegions.isNotEmpty)
        p.preferredRegions.map((Region r) => r.displayName).join(', '),
    ];
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    final double width = MediaQuery.sizeOf(context).width;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: <Widget>[
        if (card.photoPaths.isNotEmpty)
          SizedBox(
            height: 280,
            child: PageView.builder(
              itemCount: card.photoPaths.length,
              itemBuilder: (BuildContext context, int i) => ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FutureBuilder<File?>(
                  future: MatchmakerNetwork.photo(
                    card.ownerUid,
                    card.photoPaths[i],
                  ),
                  initialData: MatchmakerNetwork.photoNow(
                    card.ownerUid,
                    card.photoPaths[i],
                  ),
                  builder: (BuildContext context, AsyncSnapshot<File?> s) {
                    final File? f = s.data;
                    if (f == null) {
                      return ColoredBox(
                        color: AppColors.genderSurface(p.gender, dark: dark),
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }
                    return Image(
                      image: ResizeImage(
                        FileImage(f),
                        width: (width * ratio).round(),
                        policy: ResizeImagePolicy.fit,
                      ),
                      fit: BoxFit.contain,
                    );
                  },
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          p.fullName,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: AppColors.genderAccent(p.gender, dark: dark),
          ),
        ),
        if (facts.isNotEmpty)
          Text(facts.join(' · '), style: theme.textTheme.bodyMedium),
        Text(
          'מהמאגר של ${PartnerSpace.partnerFirstName} · צפייה בלבד',
          style: theme.textTheme.bodySmall,
        ),
        if ((p.description ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          SelectableText(
            p.description!.trim(),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (p.tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final String t in p.tags)
                Chip(label: Text(t), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
        if (looking.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            p.gender == Gender.female ? 'מה היא מחפשת' : 'מה הוא מחפש',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          for (final String l in looking)
            Text(l, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () async {
            Navigator.of(context).pop();
            await PartnerCardSheet.openIdea(widget.outer, card);
          },
          icon: const Icon(Icons.lightbulb_outline_rounded),
          label: const Text('פתיחת רעיון עם חבר מהמאגר שלי'),
        ),
      ],
    );
  }
}

/// The small "המרחב הזוגי שלנו" area on the profile: both faces and names,
/// and the partner's database, the chat and the shared ideas one tap away.
/// Before there is a couple space, one row that opens it.
class PartnerSpaceProfileArea extends StatelessWidget {
  const PartnerSpaceProfileArea({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Partnership?>(
      valueListenable: PartnerSpace.current,
      builder: (BuildContext context, Partnership? p, _) {
        final ThemeData theme = Theme.of(context);
        final String me = PartnerSpace.uid ?? '';
        if (p == null || !p.isActive) {
          final bool invited = p != null && p.toUid == me;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.favorite_border_rounded),
                title: Text(
                  invited
                      ? '${p.nameOf(p.otherOf(me))} מזמין/ה אותך למרחב זוגי'
                      : 'פתיחת מרחב זוגי',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  p == null
                      ? 'לחשוב יחד עם בן/בת הזוג — כל אחד עם המאגר שלו'
                      : invited
                      ? 'לצפייה ולאישור'
                      : 'ההזמנה ממתינה לאישור',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(PartnerSpaceScreen.route),
              ),
            ),
          );
        }
        final String partner = p.otherOf(me);
        final String name = p.nameOf(partner);
        final UserProfileProvider profile = context
            .watch<UserProfileProvider>();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: HomePaperCard(
            stripe: AppColors.femaleAccent,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                InkWell(
                  onTap: () => context.push(PartnerSpaceScreen.route),
                  child: Row(
                    children: <Widget>[
                      UserProfileAvatar(
                        photoPath: profile.photoPath,
                        gender: profile.gender,
                        name: profile.fullName,
                        radius: 20,
                      ),
                      const SizedBox(width: 4),
                      CircleAvatar(
                        radius: 20,
                        child: Text(name.isEmpty ? '?' : name.characters.first),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'המרחב הזוגי שלנו',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${profile.firstName ?? ''} · $name',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: () =>
                          context.push(PartnerDatabaseScreen.route),
                      icon: const Icon(Icons.groups_2_outlined, size: 18),
                      label: Text('המאגר של ${PartnerSpace.partnerFirstName}'),
                    ),
                    TextButton.icon(
                      onPressed: () => ChatLauncher.open(
                        context,
                        otherUid: partner,
                        otherName: name,
                        kind: 'partners',
                      ),
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('צ\'אט'),
                    ),
                    TextButton.icon(
                      onPressed: () => _SharedIdeasSheet.show(
                        context,
                        SharedIdeas.links.values
                            .where(
                              (SharedIdeaLink l) => l.partnerUid == partner,
                            )
                            .toList(),
                      ),
                      icon: const Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('רעיונות משותפים'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
