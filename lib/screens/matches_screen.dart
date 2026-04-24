import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/person_avatar.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchVisible = false;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.read<PersonRepository>();

    final String query = _searchController.text.trim();
    final List<MatchIdea> matches = _getMatches(
      matchRepository: matchRepository,
      personRepository: personRepository,
      query: query,
    );

    return Scaffold(
      appBar: AppBar(
        title: _isSearchVisible
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'חיפוש הצעה...',
                  border: InputBorder.none,
                  suffixIcon: query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _searchController.clear,
                        )
                      : null,
                ),
              )
            : Text(_showArchived ? 'ארכיון' : 'הצעות'),
        centerTitle: !_isSearchVisible,
        actions: <Widget>[
          IconButton(
            icon: Icon(_isSearchVisible ? Icons.close : Icons.search),
            tooltip: _isSearchVisible ? 'סגירת חיפוש' : 'חיפוש',
            onPressed: () {
              setState(() {
                if (_isSearchVisible) {
                  _searchController.clear();
                }
                _isSearchVisible = !_isSearchVisible;
              });
            },
          ),
          IconButton(
            icon: Icon(_showArchived ? Icons.list : Icons.archive_outlined),
            tooltip: _showArchived ? 'חזרה לפעילות' : 'מעבר לארכיון',
            onPressed: () {
              setState(() {
                _showArchived = !_showArchived;
              });
            },
          ),
        ],
      ),
      body: matches.isEmpty
          ? _EmptyMatchesState(
              isArchived: _showArchived,
              isSearchResult: query.isNotEmpty,
              onCreate: () => context.push('/matches/add'),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: matches.length,
              itemBuilder: (BuildContext context, int index) {
                final MatchIdea match = matches[index];
                final Person? personA = personRepository.getById(
                  match.personAId,
                );
                final Person? personB = personRepository.getById(
                  match.personBId,
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MatchCard(
                    match: match,
                    personA: personA,
                    personB: personB,
                    onTap: () => context.push('/matches/${match.id}'),
                    theme: theme,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/matches/add'),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  List<MatchIdea> _getMatches({
    required MatchRepository matchRepository,
    required PersonRepository personRepository,
    required String query,
  }) {
    final List<MatchIdea> baseMatches = query.isNotEmpty
        ? matchRepository.search(query, personRepository)
        : matchRepository.getAll();

    return baseMatches.where((MatchIdea match) {
      final Person? a = personRepository.getById(match.personAId);
      final Person? b = personRepository.getById(match.personBId);
      final bool archived =
          match.status.isArchived ||
          (a?.profileStatus.isArchived ?? false) ||
          (b?.profileStatus.isArchived ?? false);
      return _showArchived ? archived : !archived;
    }).toList();
  }

  void _handleSearchChanged() {
    setState(() {});
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.personA,
    required this.personB,
    required this.onTap,
    required this.theme,
  });

  final MatchIdea match;
  final Person? personA;
  final Person? personB;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = AppColors.statusColor(match.status.name);
    final String personAName = personA?.fullName.trim().isNotEmpty == true
        ? personA!.fullName.trim()
        : 'אדם נמחק';
    final String personBName = personB?.fullName.trim().isNotEmpty == true
        ? personB!.fullName.trim()
        : 'אדם נמחק';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(right: BorderSide(width: 4, color: statusColor)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _AvatarOrDeleted(person: personA),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        personAName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      ' ↔ ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        personBName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AvatarOrDeleted(person: personB),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${match.status.icon} ${match.status.displayName}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'נפתח: ${AppDateUtils.formatDateShort(match.createdAt)} · עודכן: ${AppDateUtils.timeAgo(match.updatedAt)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarOrDeleted extends StatelessWidget {
  const _AvatarOrDeleted({required this.person});

  final Person? person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (person == null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.person_off_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return PersonAvatar(person: person!, radius: 18);
  }
}

class _EmptyMatchesState extends StatelessWidget {
  const _EmptyMatchesState({
    required this.isArchived,
    required this.isSearchResult,
    required this.onCreate,
  });

  final bool isArchived;
  final bool isSearchResult;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (isSearchResult) {
      return const EmptyState(
        icon: Icons.search,
        title: 'לא נמצאו תוצאות',
        subtitle: 'נסו לחפש בשם אחר',
      );
    }

    if (isArchived) {
      return const EmptyState(
        icon: Icons.archive_outlined,
        title: 'הארכיון ריק',
        subtitle: 'הצעות שנדחו או לא פנויות יופיעו כאן',
      );
    }

    return EmptyState(
      icon: Icons.favorite_border,
      title: 'אין הצעות פעילות',
      subtitle: 'צרו הצעה חדשה בין שני אנשים',
      buttonText: 'הצעה חדשה',
      onButtonPressed: onCreate,
    );
  }
}
