import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// "חברים שהתחתנו" — the one page in the app that only holds good news.
///
/// **One count at the top, then everybody under it.** The page opens by saying
/// how many friends from this database are married and that the matchmaker had
/// a part in getting them there — which is true of all of them, and is the
/// thing worth saying first. "בזכותך" is a narrower claim, one the app can only
/// make about a proposal that was opened here and ended in a wedding, so it
/// keeps its own quieter heading over exactly those couples.
///
/// With no proposal of the matchmaker's own having reached a wedding yet, that
/// middle section is simply absent and no empty promise stands where it would
/// have been.
class MarriedFriendsScreen extends StatelessWidget {
  const MarriedFriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository people = context.watch<PersonRepository>();
    final MatchRepository matches = context.watch<MatchRepository>();

    final List<_Couple> couples = _couplesFrom(matches, people);
    final Set<String> inACouple = <String>{
      for (final _Couple couple in couples) ...<String>[
        couple.a.id,
        couple.b.id,
      ],
    };
    final List<Person> others =
        people
            .getAll()
            .where(
              (Person person) =>
                  person.profileStatus == ProfileStatus.mazelTov &&
                  !inACouple.contains(person.id),
            )
            .toList()
          ..sort((Person a, Person b) => b.updatedAt.compareTo(a.updatedAt));

    // Everybody the page is about, however they got there: both halves of
    // every wedding the matchmaker's own proposals reached, plus everybody
    // else marked "מזל טוב".
    final int marriedFriends = couples.length * 2 + others.length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        // No title. The first thing on the page says what the page is, at
        // length and in the right voice; the bar repeating "חברים שהתחתנו"
        // over it was the same words twice, the upper set in white on a strip.
      ),
      body: couples.isEmpty && others.isEmpty
          ? const EmptyState(
              icon: Icons.celebration_outlined,
              title: 'עוד לא סימנת אף חבר כ״מזל טוב״',
              subtitle:
                  'כל מי שיסומן במזל טוב יופיע כאן, וגם כל רעיון שיגיע לחתונה',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              children: <Widget>[
                _MarriedHeader(count: marriedFriends),
                const SizedBox(height: 14),
                if (couples.isNotEmpty) ...<Widget>[
                  _QuietHeader(
                    title: 'ואלה התחתנו בזכותך!!',
                    subtitle: 'הרעיונות שפתחת כאן והגיעו עד החופה',
                    lonely: true,
                  ),
                  const SizedBox(height: 10),
                  for (final _Couple couple in couples) ...<Widget>[
                    _CoupleCard(couple: couple),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 14),
                ],
                if (others.isNotEmpty) ...<Widget>[
                  _QuietHeader(
                    title: 'חברים שלך שהתחתנו',
                    subtitle: others.length == 1
                        ? 'חבר אחד שכבר מסודר'
                        : '${others.length} חברים שכבר מסודרים',
                    lonely: couples.isEmpty,
                  ),
                  const SizedBox(height: 10),
                  for (final Person person in others) ...<Widget>[
                    _MarriedFriendRow(person: person),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
    );
  }

  /// Every proposal that reached a wedding, newest first, with both sides still
  /// in the database. A couple one of whose cards was deleted is dropped rather
  /// than drawn with a hole in it.
  static List<_Couple> _couplesFrom(
    MatchRepository matches,
    PersonRepository people,
  ) {
    final List<MatchIdea> married =
        matches
            .getAll()
            .where((MatchIdea match) => match.status == MatchStatus.married)
            .toList()
          ..sort(
            (MatchIdea a, MatchIdea b) => b.updatedAt.compareTo(a.updatedAt),
          );

    return <_Couple>[
      for (final MatchIdea match in married)
        if (people.getById(match.personAId) case final Person a)
          if (people.getById(match.personBId) case final Person b)
            _Couple(match: match, a: a, b: b),
    ];
  }
}

class _Couple {
  const _Couple({required this.match, required this.a, required this.b});

  final MatchIdea match;
  final Person a;
  final Person b;
}

/// The top of the page, and the only thing on it that is addressed to the
/// matchmaker rather than about a friend.
///
/// **It counts everybody, and it credits the matchmaker for all of them.** The
/// page used to open with "חברים שלך שהתחתנו בזכותך!!" over the weddings the
/// app can actually claim, which meant a matchmaker whose own proposals had
/// not reached a wedding yet opened this page on nothing at all — and one who
/// had was told, by omission, that the other half of the page had nothing to
/// do with them. Neither is true to how a database of friends works: somebody
/// who was introduced, thought about, asked after or simply kept in mind is
/// part of how they got there, and this is the one page in the app where that
/// is worth saying out loud.
class _MarriedHeader extends StatelessWidget {
  const _MarriedHeader({required this.count});

  /// Everybody on the page: both halves of every couple, plus the friends
  /// marked "מזל טוב" on their own.
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? AppColors.secondaryDarkDm : AppColors.secondaryInk;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[
            AppColors.softYellow.withValues(alpha: dark ? 0.16 : 0.85),
            AppColors.softRose.withValues(alpha: dark ? 0.16 : 0.85),
          ],
        ),
      ),
      child: Column(
        children: <Widget>[
          Text('🎉', style: theme.textTheme.displaySmall),
          const SizedBox(height: 6),
          Text(
            count == 1
                ? 'חבר אחד מהמאגר שלך התחתן!'
                : '$count חברים מהמאגר שלך התחתנו!',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ink,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'גם אם לא אתה היית השדכן בפועל, היה לך חלק במסע שלהם לחתונה. '
            'כל הכבוד!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// The quieter half's heading. Still warm, deliberately smaller.
class _QuietHeader extends StatelessWidget {
  const _QuietHeader({
    required this.title,
    required this.subtitle,
    required this.lonely,
  });

  final String title;
  final String subtitle;

  /// True when this is the only section on the page, in which case it carries
  /// the celebration by itself and is allowed to be a size larger.
  final bool lonely;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Text('💍', style: theme.textTheme.titleLarge),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style:
                    (lonely
                            ? theme.textTheme.titleLarge
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One wedding the matchmaker made: the two faces, a heart between them, and
/// both names on one line.
class _CoupleCard extends StatelessWidget {
  const _CoupleCard({required this.couple});

  final _Couple couple;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.push('/matches/${couple.match.id}'),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.statusMarried.withValues(
                alpha: dark ? 0.45 : 0.3,
              ),
            ),
          ),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  PersonAvatar(person: couple.a, radius: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Icons.favorite,
                      size: 22,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  PersonAvatar(person: couple.b, radius: 32),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${couple.a.fullName.trim()} · ${couple.b.fullName.trim()}',
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'מזל טוב 💍',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.statusMarried,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One friend who is married, whoever made it happen.
class _MarriedFriendRow extends StatelessWidget {
  const _MarriedFriendRow({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/people/${person.id}'),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              PersonAvatar(person: person, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  person.fullName.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text('🎉', style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
