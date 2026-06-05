import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/match_suggestion_flow.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/dashboard_summary.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/people_filters_sheet.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';

enum _HomePeopleSortOption {
  random,
  alphabetical,
  ageAscending,
  newest,
  recentlyUpdated,
}

/// The landing screen shown on every non-first launch (and after the user
/// finishes the initial contact import). It greets the matchmaker, features a
/// random contact to "think about", and lists everyone else in a shuffled
/// order that changes each time the app is opened.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.initialPageIndex = 0,
    this.initialSeed,
    this.initialSearch = '',
    this.initialSort = 'random',
  });

  final int initialPageIndex;
  final int? initialSeed;
  final String initialSearch;
  final String initialSort;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _peoplePageSize = 20;

  final TextEditingController _searchController = TextEditingController();

  /// Seed for the per-launch shuffle. Generated once so the order stays stable
  /// while this screen is alive, but differs on the next app launch.
  late final int _seed = widget.initialSeed ?? Random().nextInt(0x7fffffff);

  /// How many times the user pressed "skip" — advances the featured contact.
  int _skips = 0;
  late int _pageIndex = widget.initialPageIndex;
  bool _searchVisible = false;
  late _HomePeopleSortOption _sortOption = _sortFromName(widget.initialSort);

  /// Filters applied to the "החברים שלך" list. Mirrors the people screen.
  Gender? _selectedGender;
  RangeValues? _selectedAgeRange;
  List<ReligiousLevel> _selectedReligiousLevels = <ReligiousLevel>[];
  List<ProfileStatus> _selectedProfileStatuses = <ProfileStatus>[];
  String _cityFilter = '';
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialSearch;
    _searchVisible = widget.initialSearch.trim().isNotEmpty;
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
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final UserProfileProvider profile = context.watch<UserProfileProvider>();

    final List<Person> eligiblePeople = _orderedEligiblePeople(
      personRepository,
    );
    final List<Person> visiblePeople = _getVisiblePeople(personRepository);
    final int pendingCount = personRepository.getPending().length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('שדכן'),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon3.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'הגדרות',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildContent(
          theme,
          profile,
          eligiblePeople,
          visiblePeople,
          pendingCount,
        ),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    UserProfileProvider profile,
    List<Person> eligiblePeople,
    List<Person> visiblePeople,
    int pendingCount,
  ) {
    final Person? featured = eligiblePeople.isEmpty
        ? null
        : eligiblePeople[_skips % eligiblePeople.length];
    final int pageStart = _pageIndex * _peoplePageSize;
    final List<Person> pagedPeople = visiblePeople
        .skip(pageStart)
        .take(_peoplePageSize)
        .toList();
    final bool hasNextPeoplePage =
        visiblePeople.length > pageStart + pagedPeople.length;

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          sliver: SliverToBoxAdapter(child: _Greeting(profile: profile)),
        ),
        ...buildDashboardSummarySlivers(
          context,
          showSectionTitle: true,
          compact: true,
          bottomPadding: 8,
        ),
        if (eligiblePeople.isEmpty && pendingCount == 0)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(theme),
          ),
        if (featured != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            sliver: SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: _skipTransition,
                child: _FeaturedCard(
                  key: ValueKey<String>('featured-${featured.id}-$_skips'),
                  person: featured,
                  onOpenDetail: () => context.push('/people/${featured.id}'),
                  onSkip: _skip,
                  onMatch: () => _openMatches(featured),
                ),
              ),
            ),
          ),
        if (pendingCount > 0)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _PendingUpdateCard(
                count: pendingCount,
                onTap: () => context.push('/people/pending'),
              ),
            ),
          ),
        if (eligiblePeople.isNotEmpty) ...<Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: <Widget>[
                  Text('החברים שלך', style: theme.textTheme.titleLarge),
                  const SizedBox(width: 8),
                  const Spacer(),

                  IconButton(
                    tooltip: 'מיין לפי',
                    icon: const Icon(Icons.sort),
                    onPressed: _openSortSheet,
                  ),

                  IconButton(
                    tooltip: 'סינון',
                    icon: Icon(
                      _hasActiveFilters
                          ? Icons.filter_list_alt
                          : Icons.tune,
                      color: _hasActiveFilters
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    onPressed: _openFiltersSheet,
                  ),
                  IconButton(
                    tooltip: _searchVisible ? 'סגור חיפוש' : 'חיפוש',
                    icon: Icon(_searchVisible ? Icons.close : Icons.search),
                    onPressed: _toggleSearch,
                  ),
                ],
              ),
            ),
          ),
          if (_hasActiveFilters)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _buildActiveFilterChips(),
                  ),
                ),
              ),
            ),
          if (_searchVisible)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              sliver: SliverToBoxAdapter(child: _buildSearchField()),
            ),
          if (visiblePeople.isEmpty)
            const SliverToBoxAdapter(
              child: SizedBox(
                height: 260,
                child: EmptyState(
                  icon: Icons.search,
                  title: 'לא נמצאו תוצאות',
                  subtitle: 'נסו לשנות את החיפוש',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverList.builder(
                itemCount: pagedPeople.length + (hasNextPeoplePage ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  if (index == pagedPeople.length) {
                    return _NextPageButton(onPressed: _showNextPeoplePage);
                  }

                  final Person person = pagedPeople[index];
                  return PersonListCard(
                    person: person,
                    heroEnabled: false,
                    onTap: () => context.push('/people/${person.id}'),
                    onOpenMatches: () => _openMatches(person),
                    onOpenWhatsApp: () => _openWhatsApp(person),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'חיפוש לפי שם...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.trim().isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'ניקוי חיפוש',
                onPressed: _searchController.clear,
              ),
      ),
    );
  }

  void _toggleSearch() {
    if (_searchVisible) {
      _searchController.clear();
    }
    setState(() {
      _searchVisible = !_searchVisible;
    });
  }

  void _handleSearchChanged() {
    setState(() {
      _pageIndex = 0;
    });
  }

  Future<void> _openSortSheet() async {
    final _HomePeopleSortOption?
    selected = await showModalBottomSheet<_HomePeopleSortOption>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'מיין לפי',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              for (final ({_HomePeopleSortOption value, String label}) option
                  in const <({_HomePeopleSortOption value, String label})>[
                    (value: _HomePeopleSortOption.random, label: 'אקראי'),
                    (value: _HomePeopleSortOption.alphabetical, label: 'א-ב'),
                    (
                      value: _HomePeopleSortOption.ageAscending,
                      label: 'לפי גיל',
                    ),
                    (value: _HomePeopleSortOption.newest, label: 'חדשים'),
                    (
                      value: _HomePeopleSortOption.recentlyUpdated,
                      label: 'עודכנו לאחרונה',
                    ),
                  ])
                ListTile(
                  title: Text(option.label),
                  trailing: _sortOption == option.value
                      ? Icon(
                          Icons.check,
                          color: Theme.of(sheetContext).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option.value),
                ),
            ],
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }
    setState(() {
      _sortOption = selected;
      _pageIndex = 0;
    });
  }

  Future<void> _openFiltersSheet() async {
    final ({int min, int max})? bounds = context
        .read<PersonRepository>()
        .activeAgeBounds;
    final PeopleFilterState? result =
        await showModalBottomSheet<PeopleFilterState>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          builder: (BuildContext context) {
            return PeopleFiltersSheet(
              initialGender: _selectedGender,
              initialAgeRange: _selectedAgeRange,
              ageBounds: bounds,
              initialReligiousLevels: _selectedReligiousLevels,
              initialProfileStatuses: _selectedProfileStatuses,
              initialCity: _cityFilter,
              initialFavoritesOnly: _favoritesOnly,
            );
          },
        );

    if (result == null) {
      return;
    }

    setState(() {
      _selectedGender = result.gender;
      _selectedAgeRange = result.ageRange;
      _selectedReligiousLevels = result.religiousLevels;
      _selectedProfileStatuses = result.profileStatuses;
      _cityFilter = result.city.trim();
      _favoritesOnly = result.favoritesOnly;
      _pageIndex = 0;
    });
  }

  bool get _hasActiveFilters {
    return _selectedGender != null ||
        _selectedAgeRange != null ||
        _selectedReligiousLevels.isNotEmpty ||
        _selectedProfileStatuses.isNotEmpty ||
        _cityFilter.trim().isNotEmpty ||
        _favoritesOnly;
  }

  List<Widget> _buildActiveFilterChips() {
    final List<Widget> chips = <Widget>[];

    if (_selectedGender != null) {
      chips.add(
        InputChip(
          label: Text(_selectedGender!.displayName),
          onDeleted: () {
            setState(() {
              _selectedGender = null;
              _pageIndex = 0;
            });
          },
        ),
      );
    }

    final RangeValues? ageRange = _selectedAgeRange;
    if (ageRange != null) {
      chips.add(
        InputChip(
          label: Text('גיל ${ageRange.start.round()}-${ageRange.end.round()}'),
          onDeleted: () {
            setState(() {
              _selectedAgeRange = null;
              _pageIndex = 0;
            });
          },
        ),
      );
    }

    for (final ReligiousLevel level in _selectedReligiousLevels) {
      chips.add(
        InputChip(
          label: Text(level.displayName),
          onDeleted: () {
            setState(() {
              _selectedReligiousLevels = _selectedReligiousLevels
                  .where((ReligiousLevel item) => item != level)
                  .toList();
              _pageIndex = 0;
            });
          },
        ),
      );
    }

    for (final ProfileStatus status in _selectedProfileStatuses) {
      chips.add(
        InputChip(
          label: Text(status.displayName),
          onDeleted: () {
            setState(() {
              _selectedProfileStatuses = _selectedProfileStatuses
                  .where((ProfileStatus item) => item != status)
                  .toList();
              _pageIndex = 0;
            });
          },
        ),
      );
    }

    if (_cityFilter.trim().isNotEmpty) {
      chips.add(
        InputChip(
          label: Text(_cityFilter.trim()),
          onDeleted: () {
            setState(() {
              _cityFilter = '';
              _pageIndex = 0;
            });
          },
        ),
      );
    }

    if (_favoritesOnly) {
      chips.add(
        InputChip(
          label: const Text('מועדפים'),
          onDeleted: () {
            setState(() {
              _favoritesOnly = false;
              _pageIndex = 0;
            });
          },
        ),
      );
    }

    chips.add(
      ActionChip(
        avatar: const Icon(Icons.close, size: 18),
        label: const Text('נקה הכל'),
        onPressed: () {
          setState(() {
            _resetFilters();
            _pageIndex = 0;
          });
        },
      ),
    );

    return chips;
  }

  void _resetFilters() {
    _selectedGender = null;
    _selectedAgeRange = null;
    _selectedReligiousLevels = <ReligiousLevel>[];
    _selectedProfileStatuses = <ProfileStatus>[];
    _cityFilter = '';
    _favoritesOnly = false;
  }

  void _showNextPeoplePage() {
    context.push(_homePageLocation(_pageIndex + 1));
  }

  List<Person> _getVisiblePeople(PersonRepository repository) {
    final RangeValues? ageRange = _selectedAgeRange;
    final List<Person> filteredPeople = repository.filter(
      gender: _selectedGender,
      minAge: ageRange?.start.round(),
      maxAge: ageRange?.end.round(),
      religiousLevels: _selectedReligiousLevels,
      profileStatuses: _selectedProfileStatuses,
      favoritesOnly: _favoritesOnly ? true : null,
    );

    final String normalizedSearch = _searchController.text.trim().toLowerCase();
    final String normalizedCity = _cityFilter.trim().toLowerCase();

    final List<Person> people = filteredPeople.where((Person person) {
      final bool matchesSearch =
          normalizedSearch.isEmpty ||
          person.firstName.toLowerCase().contains(normalizedSearch) ||
          person.lastName.toLowerCase().contains(normalizedSearch) ||
          person.fullName.toLowerCase().contains(normalizedSearch);

      final bool matchesCity =
          normalizedCity.isEmpty ||
          (person.city ?? '').trim().toLowerCase().contains(normalizedCity);

      // The home list never shows archived profiles.
      final bool matchesArchive = !person.profileStatus.isArchived;

      return matchesSearch && matchesCity && matchesArchive;
    }).toList();

    _sortPeople(people);
    return people;
  }

  void _sortPeople(List<Person> people) {
    switch (_sortOption) {
      case _HomePeopleSortOption.random:
        people.sort(
          (Person a, Person b) => _shuffleKey(a).compareTo(_shuffleKey(b)),
        );
        return;
      case _HomePeopleSortOption.alphabetical:
        people.sort(_sortByName);
        return;
      case _HomePeopleSortOption.ageAscending:
        people.sort((Person a, Person b) {
          final int? ageA = a.age;
          final int? ageB = b.age;

          if (ageA == null && ageB == null) {
            return _sortByName(a, b);
          }
          if (ageA == null) {
            return 1;
          }
          if (ageB == null) {
            return -1;
          }

          final int ageComparison = ageA.compareTo(ageB);
          return ageComparison != 0 ? ageComparison : _sortByName(a, b);
        });
        return;
      case _HomePeopleSortOption.newest:
        people.sort((Person a, Person b) {
          final int comparison = b.createdAt.compareTo(a.createdAt);
          return comparison != 0 ? comparison : _sortByName(a, b);
        });
        return;
      case _HomePeopleSortOption.recentlyUpdated:
        people.sort((Person a, Person b) {
          final int comparison = b.updatedAt.compareTo(a.updatedAt);
          return comparison != 0 ? comparison : _sortByName(a, b);
        });
        return;
    }
  }

  int _sortByName(Person a, Person b) {
    final int firstNameComparison = a.firstName.toLowerCase().compareTo(
      b.firstName.toLowerCase(),
    );
    if (firstNameComparison != 0) {
      return firstNameComparison;
    }

    return a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.groups_outlined,
              size: 80,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'עוד אין חברים במאגר',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'בוא נוסיף כמה חברים כדי שנוכל להתחיל לחשוב על שידוכים',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push('/people/import'),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('הוספת חברים'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skipTransition(Widget child, Animation<double> animation) {
    final Animation<Offset> offset = Tween<Offset>(
      begin: const Offset(0.35, 0.18),
      end: Offset.zero,
    ).animate(animation);
    final Animation<double> scale = Tween<double>(
      begin: 0.82,
      end: 1.0,
    ).animate(animation);
    final Animation<double> rotation = Tween<double>(
      begin: 0.06,
      end: 0.0,
    ).animate(animation);

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: offset,
        child: RotationTransition(
          turns: rotation,
          child: ScaleTransition(scale: scale, child: child),
        ),
      ),
    );
  }

  void _skip() {
    HapticFeedback.selectionClick();
    setState(() => _skips++);
  }

  Future<void> _openMatches(Person person) async {
    await MatchSuggestionFlow.open(context, sourcePerson: person);
  }

  Future<void> _openWhatsApp(Person person) async {
    final bool launched = await WhatsAppUtils.openChat(person);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('לא הצלחנו לפתוח את וואטסאפ')),
        );
    }
  }

  List<Person> _orderedEligiblePeople(PersonRepository repository) {
    final List<Person> people = repository
        .getAll()
        .where(
          (Person p) =>
              !p.needsReview && !p.hidden && !p.profileStatus.isArchived,
        )
        .toList();
    people.sort(
      (Person a, Person b) => _shuffleKey(a).compareTo(_shuffleKey(b)),
    );
    return people;
  }

  /// Deterministic per-launch ordering key: stable for the lifetime of this
  /// screen (so the list doesn't jump around on rebuilds) yet reshuffled on the
  /// next launch via [_seed]. New contacts slot in deterministically too.
  int _shuffleKey(Person person) => (person.id.hashCode ^ _seed) & 0x7fffffff;

  String _homePageLocation(int pageIndex) {
    return Uri(
      path: '/home',
      queryParameters: <String, String>{
        'page': (pageIndex + 1).toString(),
        'seed': _seed.toString(),
        'sort': _sortOption.name,
        if (_searchController.text.trim().isNotEmpty)
          'q': _searchController.text.trim(),
      },
    ).toString();
  }

  static _HomePeopleSortOption _sortFromName(String name) {
    for (final _HomePeopleSortOption option in _HomePeopleSortOption.values) {
      if (option.name == name) {
        return option;
      }
    }
    return _HomePeopleSortOption.random;
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.profile});

  final UserProfileProvider profile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = profile.name ?? 'שדכן';
    final bool isFemale = profile.gender == Gender.female;
    // final String dear = isFemale ? 'היקרה' : 'היקר';
    final String letsGo = isFemale ? 'בואי נחשוב' : 'בוא נחשוב';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'היי $name,',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$letsGo על החברים שלך!',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PendingUpdateCard extends StatelessWidget {
  const _PendingUpdateCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = Colors.amber.shade800;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.4)),
      ),
      color: accent.withValues(alpha: 0.10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(Icons.edit_note, color: accent, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'נותרו עוד $count אנשים לעדכן במאגר שלך!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_left, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextPageButton extends StatelessWidget {
  const _NextPageButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          child: const Text('עמוד הבא'),
        ),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    super.key,
    required this.person,
    required this.onOpenDetail,
    required this.onSkip,
    required this.onMatch,
  });

  final Person person;
  final VoidCallback onOpenDetail;
  final VoidCallback onSkip;
  final VoidCallback onMatch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = <String>[
      if (person.age != null) '${person.age}',
      if (person.religiousLevel != null) person.religiousLevel!.displayName,
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ].join(' · ');

    return Card(
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: <Color>[
              theme.colorScheme.primaryContainer,
              theme.colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: Column(
          children: <Widget>[
            // Tapping the card body opens the full profile.
            InkWell(
              onTap: onOpenDetail,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
                child: Column(
                  children: <Widget>[
                    Hero(
                      tag: 'person-${person.id}',
                      child: PersonAvatar(person: person, radius: 52),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      person.fullName.trim(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),

                  ],
                ),
              ),
            ),
            // Actions that act on this card: the prominent matches button and
            // a small "הבא" button to advance to the next featured contact.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _CardActionButton(
                      label: 'להתאמות עבור ${person.firstName.trim()}',
                      background: theme.colorScheme.primary,
                      foreground: theme.colorScheme.onPrimary,
                      onTap: onMatch,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CardActionButton(
                    label: 'הבא',
                    background: theme.colorScheme.surface.withValues(
                      alpha: 0.85,
                    ),
                    foreground: theme.colorScheme.onSurface,
                    onTap: onSkip,
                    compact: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  /// A smaller, secondary button (e.g. "הבא") that sits next to the main one.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BorderRadius radius = BorderRadius.circular(18);

    return Material(
      color: background,
      borderRadius: radius,
      elevation: compact ? 1 : 2,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: compact
              ? const EdgeInsets.symmetric(vertical: 12, horizontal: 18)
              : const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (compact
                        ? theme.textTheme.bodyMedium
                        : theme.textTheme.titleMedium)
                    ?.copyWith(color: foreground, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
