import 'package:flutter/material.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/home_search.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';

/// The home search's results, the way WhatsApp lays out its own: the people
/// whose name matches at the top, and under a heading of its own everything
/// the words were found in — each one the person's name, where on the card it
/// was, and a few words either side with the match in bold.
///
/// Drawn in the app's own paper and palette; only the arrangement is
/// borrowed.
class HomeSearchResultsList extends StatelessWidget {
  const HomeSearchResultsList({
    super.key,
    required this.results,
    required this.onOpenPerson,
    required this.onOpenHit,
    required this.onToggleFavorite,
    required this.onOpenWhatsApp,
  });

  final HomeSearchResults results;
  final ValueChanged<Person> onOpenPerson;
  final ValueChanged<ContentHit> onOpenHit;
  final ValueChanged<Person> onToggleFavorite;
  final ValueChanged<Person> onOpenWhatsApp;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[
      if (results.people.isNotEmpty) ...<Widget>[
        _SectionTitle(title: 'אנשים', count: results.people.length),
        for (final Person person in results.people)
          PersonListCard(
            person: person,
            heroEnabled: false,
            onTap: () => onOpenPerson(person),
            onToggleFavorite: () => onToggleFavorite(person),
            onOpenWhatsApp: () => onOpenWhatsApp(person),
          ),
      ],
      if (results.content.isNotEmpty) ...<Widget>[
        _SectionTitle(title: 'מתוך הכרטיסים', count: results.content.length),
        for (final ContentHit hit in results.content)
          _ContentHitRow(hit: hit, onTap: () => onOpenHit(hit)),
      ],
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      shrinkWrap: true,
      children: rows,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Text('$count', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// One place a word was found: whose card, where on it, and the words around
/// it with the match in bold on a light wash of the brand's copper.
class _ContentHitRow extends StatelessWidget {
  const _ContentHitRow({required this.hit, required this.onTap});

  final ContentHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color mark = dark ? AppColors.secondaryDarkDm : AppColors.secondary;
    final TextStyle? base = theme.textTheme.bodyMedium?.copyWith(height: 1.35);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PersonAvatar(person: hit.person, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            hit.person.fullName.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.genderAccent(
                                hit.person.gender,
                                dark: dark,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '· ${hit.field.label}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(text: hit.excerpt.before),
                          TextSpan(
                            text: hit.excerpt.match,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.onSurface,
                              backgroundColor: mark.withValues(alpha: 0.22),
                            ),
                          ),
                          TextSpan(text: hit.excerpt.after),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: base,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
