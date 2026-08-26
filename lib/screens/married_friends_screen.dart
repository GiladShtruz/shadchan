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
/// **Two halves, and the order between them is the whole point.** A matchmaker
/// marks a friend "מזל טוב" whoever made the shidduch; the app only knows which
/// ones *it* was part of, and those are the ones worth putting at the top of
/// the screen in the largest type it has. "בזכותך" is a claim the app can only
/// make about a proposal that was opened here and ended in a wedding, so that
/// is exactly what the first section is built from — married ideas — and the
/// second is everybody else who is celebrating.
///
/// With no proposal of the matchmaker's own having reached a wedding yet, there
/// is no first section and no empty promise where it would have been: the page
/// is simply the friends who married, on the same paper.
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('חברים שהתחתנו'),
        centerTitle: true,
      ),
      body: couples.isEmpty && others.isEmpty
          ? const EmptyState(
              icon: Icons.celebration_outlined,
              title: 'עוד לא סימנת אף חבר כ״מזל טוב״',
              subtitle:
                  'כל מי שיסומן במזל טוב יופיע כאן, וגם כל רעיון שיגיע לחתונה',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: <Widget>[
                if (couples.isNotEmpty) ...<Widget>[
                  const _ThanksToYouHeader(),
                  const SizedBox(height: 14),
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

/// The loud half of the page.
class _ThanksToYouHeader extends StatelessWidget {
  const _ThanksToYouHeader();

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
            'חברים שלך שהתחתנו בזכותך!!',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ink,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'הרעיונות שפתחת כאן והגיעו עד החופה',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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
