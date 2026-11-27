import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/match_status_event.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/models/person_event.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/personal_area_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/services/personal_helpers_store.dart';
import 'package:shadchan/services/workspace_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/app_tokens.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/matchmaker_friends.dart';
import 'package:shadchan/utils/personal_nav.dart';
import 'package:shadchan/utils/personal_whats_new.dart';
import 'package:shadchan/utils/personal_next_step.dart';
import 'package:shadchan/utils/whats_new_feed.dart';
import 'package:shadchan/widgets/app_glyphs.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/notification_center.dart';
import 'package:shadchan/widgets/personal_home_sections.dart';
import 'package:shadchan/services/personal_area_service.dart';

T? _maybeWatch<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

/// "מה חדש אצלי" on בית — a small, living feed for every kind of user: what
/// happened lately around them, newest first, each line a tap away from the
/// thing it is about. See [WhatsNewFeed] for what counts.
///
/// Drawn nothing at all when nothing happened lately: an empty "nothing new"
/// box teaches people to stop looking.
class HomeWhatsNew extends StatefulWidget {
  const HomeWhatsNew({super.key});

  static const String title = 'מה חדש אצלי';

  @override
  State<HomeWhatsNew> createState() => _HomeWhatsNewState();
}

class _HomeWhatsNewState extends State<HomeWhatsNew> {
  bool _expanded = false;

  /// Every event the feed could hold, from what the device already has.
  List<WhatsNewEvent> _collect(BuildContext context, DateTime now) {
    final bool matchmaker = WorkspaceStore.matchmakerEnabled;
    final PersonRepository? people = _maybeWatch<PersonRepository>(context);
    final MatchRepository? matches = _maybeWatch<MatchRepository>(context);
    final InboxProvider? inbox = _maybeWatch<InboxProvider>(context);
    final CardAccessProvider? access = _maybeWatch<CardAccessProvider>(context);
    final PersonalCardProvider? cards = _maybeWatch<PersonalCardProvider>(
      context,
    );
    final PersonalAreaProvider? area = _maybeWatch<PersonalAreaProvider>(
      context,
    );
    final List<WhatsNewEvent> out = <WhatsNewEvent>[];

    // --- What the server told this account -------------------------------
    for (final InboxItem item in inbox?.items ?? const <InboxItem>[]) {
      final WhatsNewSide? side = WhatsNewFeed.inboxKinds[item.kind];
      final DateTime? at = item.createdAt;
      if (side == null || at == null || item.title.trim().isEmpty) continue;
      final Person? person = people == null
          ? null
          : NotificationCenter.personOfNotice(people, item);
      out.add(
        WhatsNewEvent(
          // One line per friend and kind: a card announced twice is one.
          key: item.ownerUid == null
              ? 'inbox:${item.id}'
              : '${item.kind}:${item.ownerUid}',
          kind: WhatsNewFeed.kindOfInbox(item.kind),
          side: side,
          text: item.title.trim(),
          at: at,
          personId: person?.id,
          uid: item.ownerUid,
          payload: item,
        ),
      );
    }

    // --- The matchmaker's own work ---------------------------------------
    if (matchmaker && people != null && matches != null) {
      final List<MatchIdea> all = matches.getAll();
      final WhatsNewEvent? opened = WhatsNewFeed.ideasOpened(<DateTime>[
        for (final MatchIdea m in all) m.createdAt,
      ], now: now);
      if (opened != null) out.add(opened);

      final Map<String, MatchIdea> byId = <String, MatchIdea>{
        for (final MatchIdea m in all) m.id: m,
      };
      for (final MatchStatusEvent e in matches.getAllStatusEvents()) {
        if (now.difference(e.createdAt) > WhatsNewFeed.freshFor) continue;
        final bool dating =
            e.toStatus == MatchStatus.dating &&
            e.fromStatus != MatchStatus.dating;
        final bool married =
            e.toStatus == MatchStatus.married &&
            e.fromStatus != MatchStatus.married;
        if (!dating && !married) continue;
        final MatchIdea? m = byId[e.matchId];
        if (m == null || m.status != e.toStatus) continue;
        final Person? a = people.getById(m.personAId);
        final Person? b = people.getById(m.personBId);
        // The man first, as everywhere a couple is named.
        final bool swap = b?.gender == Gender.male;
        final Person? man = swap ? b : a;
        final Person? woman = swap ? a : b;
        final String pair =
            '${man?.firstName.trim() ?? 'הבחור'} ו${woman?.firstName.trim() ?? 'הבחורה'}';
        out.add(
          WhatsNewEvent(
            key: 'couple:${m.id}',
            kind: married
                ? WhatsNewKind.coupleEngaged
                : WhatsNewKind.coupleDating,
            side: WhatsNewSide.matchmaker,
            text: married ? 'מזל טוב! $pair התארסו' : '$pair התחילו לצאת',
            at: e.createdAt,
            personId: man?.id,
            secondPersonId: woman?.id,
            route: '/matches/${m.id}',
          ),
        );
      }

      // A friend who keeps their own card changed it.
      final Map<String, PersonEvent> lastCard = <String, PersonEvent>{};
      for (final PersonEvent e in people.getAllEvents()) {
        if (e.type != PersonEventType.cardSynced) continue;
        if (now.difference(e.createdAt) > WhatsNewFeed.freshFor) continue;
        final PersonEvent? known = lastCard[e.personId];
        if (known == null || e.createdAt.isAfter(known.createdAt)) {
          lastCard[e.personId] = e;
        }
      }
      lastCard.forEach((String id, PersonEvent e) {
        final Person? p = people.getById(id);
        if (p == null || p.hidden || p.cardOwnerUid == null) return;
        out.add(
          WhatsNewEvent(
            key: 'card:$id',
            kind: WhatsNewKind.cardUpdated,
            side: WhatsNewSide.matchmaker,
            text: '${p.firstName.trim()} {עדכן|עדכנה} את הכרטיס שלו{|ה}'
                .forGender(p.gender),
            at: e.createdAt,
            personId: id,
            route: '/people/$id?focus=card',
          ),
        );
      });
    }

    // --- Meaningful messages: an idea or a card sent to me ---------------
    final String me = ChatService.uid ?? '';
    for (final ChatThread t in ChatService.threads.value) {
      final DateTime? at = t.lastAt;
      if (me.isEmpty || at == null || t.lastFromUid == me) continue;
      final ChatMessageType type = t.lastType;
      if (type != ChatMessageType.ideaOffer &&
          type != ChatMessageType.card &&
          type != ChatMessageType.idea) {
        continue;
      }
      final String name = t.titleFor(me);
      out.add(
        WhatsNewEvent(
          key: 'chat:${t.id}',
          kind: type == ChatMessageType.card
              ? WhatsNewKind.message
              : WhatsNewKind.idea,
          side: type == ChatMessageType.ideaOffer
              ? WhatsNewSide.personal
              : WhatsNewSide.matchmaker,
          text: type == ChatMessageType.card
              ? '$name שלח/ה לך כרטיס בצ\'אט'
              : type == ChatMessageType.ideaOffer
              ? '$name: יש לי רעיון בשבילך'
              : '$name שלח/ה לך רעיון בצ\'אט',
          at: at,
          uid: t.otherOf(me),
          route: ChatService.routeTo(
            me: me,
            otherUid: t.otherOf(me),
            theirName: name,
          ),
        ),
      );
    }

    // --- The user's own card ---------------------------------------------
    if (access != null) {
      final Person? card = cards?.card;
      final bool live = card != null && !(cards?.isDeleted ?? true);
      final List<PersonalNews> news = area?.news ?? const <PersonalNews>[];
      final List<MatchmakerFriend> friends = matchmakerFriendsOf(access);
      final List<PersonalWhatsNewItem> personal = PersonalWhatsNew.build(
        friends: friends,
        singleFriends: access.mutualFriends,
        hidden: PersonalHelpersStore.hidden,
        reviewDue: live && PersonalNextAction.reviewDueFor(context, card),
        latestNewsId: news.isEmpty ? null : news.first.id,
        latestNewsTitle: news.isEmpty ? null : news.first.title,
        seenNews: PersonalWhatsNewSection.seenNews,
        now: now,
      );
      // What "הפעולה הבאה שלך" already asks for is not said twice here.
      final Set<PersonalNextStepKind> asked = <PersonalNextStepKind>{
        for (final PersonalNextStep step in PersonalNextAction.stepsFor(
          context,
        ))
          step.kind,
      };
      for (final PersonalWhatsNewItem item in personal) {
        if (item.kind == PersonalWhatsNewKind.request &&
            asked.contains(PersonalNextStepKind.request)) {
          continue;
        }
        if (item.kind == PersonalWhatsNewKind.review &&
            (asked.contains(PersonalNextStepKind.review) ||
                asked.contains(PersonalNextStepKind.refresh))) {
          continue;
        }
        final MatchmakerFriend? f = item.friend;
        final DateTime at = switch (item.kind) {
          PersonalWhatsNewKind.request => f?.row?.updatedAt ?? now,
          PersonalWhatsNewKind.matchmakerJoined => f?.joinedAt ?? now,
          // Undated: drawn as of a day ago, so dated news reads above it.
          _ => now.subtract(const Duration(days: 1)),
        };
        out.add(
          WhatsNewEvent(
            key: switch (item.kind) {
              PersonalWhatsNewKind.request => 'request',
              PersonalWhatsNewKind.matchmakerJoined =>
                'matchmakerJoined:${f?.uid}',
              PersonalWhatsNewKind.friendJoined => 'friendJoined',
              PersonalWhatsNewKind.news => 'news:${item.newsId}',
              PersonalWhatsNewKind.review => 'review',
            },
            kind: switch (item.kind) {
              PersonalWhatsNewKind.request => WhatsNewKind.request,
              PersonalWhatsNewKind.matchmakerJoined =>
                WhatsNewKind.matchmakerJoined,
              PersonalWhatsNewKind.friendJoined => WhatsNewKind.friendJoined,
              PersonalWhatsNewKind.news => WhatsNewKind.news,
              PersonalWhatsNewKind.review => WhatsNewKind.review,
            },
            // "A matchmaker from my contacts joined" is news to both sides.
            side: item.kind == PersonalWhatsNewKind.matchmakerJoined
                ? WhatsNewSide.both
                : WhatsNewSide.personal,
            text: item.text,
            at: at,
            uid: f?.uid,
            payload: item,
          ),
        );
      }
    }
    return out;
  }

  Future<void> _open(BuildContext context, WhatsNewEvent e) async {
    final Object? payload = e.payload;
    if (payload is InboxItem) {
      await NotificationCenter.openNotice(context, payload);
      return;
    }
    if (payload is PersonalWhatsNewItem) {
      switch (payload.kind) {
        case PersonalWhatsNewKind.request ||
            PersonalWhatsNewKind.matchmakerJoined:
          final MatchmakerFriend? friend = payload.friend;
          if (friend != null) {
            await MatchmakerFriendSheet.show(context, friend);
          } else {
            PersonalNav.openMatchmakers(context);
          }
        case PersonalWhatsNewKind.friendJoined:
          PersonalNav.openMatchmakers(context);
        case PersonalWhatsNewKind.news:
          PersonalWhatsNewSection.markNewsSeen(payload.newsId!);
          if (context.mounted) {
            await context.push('/me/news/${payload.newsId}');
          }
        case PersonalWhatsNewKind.review:
          await PersonalAreaService.editCard(context);
      }
      return;
    }
    final String? route = e.route;
    if (route != null) await context.push(route);
  }

  static AppGlyph glyphOf(WhatsNewKind kind) => switch (kind) {
    WhatsNewKind.matchmakerJoined => AppGlyph.people,
    WhatsNewKind.friendAddedCard => AppGlyph.card,
    WhatsNewKind.accessApproved => AppGlyph.key,
    WhatsNewKind.shareOpened => AppGlyph.share,
    WhatsNewKind.coupleDating => AppGlyph.heart,
    WhatsNewKind.coupleEngaged => AppGlyph.ring,
    WhatsNewKind.ideasOpened => AppGlyph.spark,
    WhatsNewKind.cardUpdated => AppGlyph.card,
    WhatsNewKind.message => AppGlyph.chat,
    WhatsNewKind.request => AppGlyph.key,
    WhatsNewKind.friendJoined => AppGlyph.person,
    WhatsNewKind.news => AppGlyph.bell,
    WhatsNewKind.idea => AppGlyph.spark,
    WhatsNewKind.review => AppGlyph.card,
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ChatThread>>(
      valueListenable: ChatService.threads,
      builder: (BuildContext context, _, _) => ListenableBuilder(
        listenable: PersonalHelpersStore.revision,
        builder: (BuildContext context, _) => _build(context),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final DateTime now = DateTime.now();
    final UserProfileProvider? profile = _maybeWatch<UserProfileProvider>(
      context,
    );
    final List<WhatsNewEvent> feed = WhatsNewFeed.build(
      _collect(context, now),
      // Never neither: somebody without the matchmaker's tools keeps a card.
      single: (profile?.isSingle ?? false) || !WorkspaceStore.matchmakerEnabled,
      matchmaker: WorkspaceStore.matchmakerEnabled,
      now: now,
    );
    if (feed.isEmpty) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final PersonRepository? people = _maybeWatch<PersonRepository>(context);
    final int count = _expanded
        ? feed.length
        : feed.length.clamp(0, WhatsNewFeed.shown);
    final Color accent = context.tokens.maleAccent;

    Widget leading(WhatsNewEvent e) {
      final Person? a = e.personId == null
          ? null
          : people?.getById(e.personId!);
      final Person? b = e.secondPersonId == null
          ? null
          : people?.getById(e.secondPersonId!);
      if (a != null && b != null) {
        return HomeCardCoupleAvatars(personA: a, personB: b, radius: 17);
      }
      if (a != null) return HomeCardAvatar(person: a, radius: 19);
      return CircleAvatar(
        radius: 19,
        backgroundColor: context.tokens.maleWash,
        child: AppGlyphIcon(glyphOf(e.kind), size: 19, color: accent),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            HomeWhatsNew.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        HomePaperCard(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          stripe: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < count; i++) ...<Widget>[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.7,
                    ),
                  ),
                InkWell(
                  key: ValueKey<String>('whatsNew:${feed[i].key}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _open(context, feed[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: <Widget>[
                        leading(feed[i]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            feed[i].text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppDateUtils.notificationTime(feed[i].at),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.muted(
                              dark: theme.brightness == Brightness.dark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (feed.length > WhatsNewFeed.shown)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: context.tokens.ctaInk,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? 'פחות' : 'עוד'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
