import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/add_people_dialog.dart';
import 'package:shadchan/dialogs/reminders_panel.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/matchmaker_tips.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/couple_card.dart';
import 'package:shadchan/widgets/dashboard_summary.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/person_list_card.dart';

/// The landing screen: greeting, database stats, the two ways to grow the
/// database, and horizontal rows of what is currently moving — couples who are
/// dating, open ideas and recently updated friends. Search runs over the whole
/// database and shows its results in a panel above the page.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialSearch = ''});

  final String initialSearch;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _searchVisible = false;

  /// Picked once per visit to the screen, so every entry shows a different tip.
  late String _tip;

  @override
  void initState() {
    super.initState();
    _tip = MatchmakerTips.next();
    _searchController.text = widget.initialSearch;
    _searchVisible = widget.initialSearch.trim().isNotEmpty;
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final UserProfileProvider profile = context.watch<UserProfileProvider>();

    return Scaffold(
      appBar: _searchVisible
          ? _buildSearchAppBar(theme)
          : _buildGreetingAppBar(theme, profile),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            _buildHome(theme, profile),
            if (_searchVisible) _buildSearchPanel(theme, personRepository),
          ],
        ),
      ),
    );
  }

  // --- AppBars ------------------------------------------------------------

  AppBar _buildGreetingAppBar(ThemeData theme, UserProfileProvider profile) {
    final String name = profile.name ?? 'שדכן';
    final TimeOfDay now = TimeOfDay.fromDateTime(DateTime.now());

    return AppBar(
      titleSpacing: 16,
      centerTitle: false,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // First child sits at the start edge, which in RTL is the right.
          Icon(_timeOfDayIcon(now), size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${_timeOfDayGreeting(now)}, $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'תזכורות',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => RemindersPanel.show(context),
        ),
        IconButton(
          tooltip: 'חיפוש',
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searchVisible = true),
        ),
        IconButton(
          tooltip: 'הגדרות',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }

  AppBar _buildSearchAppBar(ThemeData theme) {
    final bool hasText = _searchController.text.trim().isNotEmpty;

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 8,
      // Centered inside the banner, capped in width so it never sits under the
      // search icon that stays visible in the actions.
      title: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textAlign: TextAlign.center,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                hintText: 'חפש במאגר שלך',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: hasText
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        tooltip: 'ניקוי',
                        onPressed: _searchController.clear,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'סגירת חיפוש',
          icon: const Icon(Icons.search),
          onPressed: () {
            _searchController.clear();
            setState(() => _searchVisible = false);
          },
        ),
      ],
    );
  }

  // --- Home body ----------------------------------------------------------

  Widget _buildHome(ThemeData theme, UserProfileProvider profile) {
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final PersonRepository personRepository = context.watch<PersonRepository>();

    final List<MatchIdea> allMatches = matchRepository.getAll();
    final List<MatchIdea> datingMatches =
        allMatches
            .where((MatchIdea m) => m.status == MatchStatus.dating)
            .toList()
          ..sort(
            (MatchIdea a, MatchIdea b) => b.updatedAt.compareTo(a.updatedAt),
          );
    // "Open" is everything still in play that has not become a couple yet, with
    // the newest ideas leading the row.
    final List<MatchIdea> openMatches =
        allMatches
            .where(
              (MatchIdea m) =>
                  !m.status.isArchived && m.status != MatchStatus.dating,
            )
            .toList()
          ..sort(
            (MatchIdea a, MatchIdea b) => b.createdAt.compareTo(a.createdAt),
          );
    final List<Person> recentPeople =
        personRepository.getAll().where((Person p) => !p.hidden).toList()
          ..sort((Person a, Person b) => b.updatedAt.compareTo(a.updatedAt));

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 8),
          sliver: SliverToBoxAdapter(child: _Subtitle(profile: profile)),
        ),
        ...buildDashboardSummarySlivers(
          context,
          showSectionTitle: true,
          compact: true,
          bottomPadding: 8,
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
          sliver: SliverToBoxAdapter(child: _QuickActions()),
        ),
        SliverToBoxAdapter(
          child: _CoupleRow(
            title: 'זוגות שיוצאים',
            icon: Icons.favorite_outline,
            subtitle: 'שומרים על קשר! כל זוג צריך חבר אחד שיאמין בו',
            emptyText: 'עוד אין זוגות שיוצאים — הראשון בדרך.',
            matches: datingMatches,
            repository: personRepository,
            centered: true,
            hideWhenEmpty: true,
          ),
        ),
        SliverToBoxAdapter(
          child: _CoupleRow(
            title: 'רעיונות פתוחים',
            icon: Icons.lightbulb_outline,
            emptyText: 'אין רעיונות פתוחים כרגע.',
            matches: openMatches,
            repository: personRepository,
          ),
        ),
        SliverToBoxAdapter(
          child: _RecentPeopleRow(people: recentPeople.take(15).toList()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          sliver: SliverToBoxAdapter(
            child: _TipCard(
              tip: _tip,
              onAnother: () {
                setState(() {
                  _tip = MatchmakerTips.next(previous: _tip);
                });
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
          sliver: SliverToBoxAdapter(
            child: _MonthlyStatsCard(onTap: () => context.push('/stats/month')),
          ),
        ),
      ],
    );
  }

  // --- Search -------------------------------------------------------------

  /// Live results over the home page, capped at half the screen height so the
  /// page underneath stays visible.
  Widget _buildSearchPanel(ThemeData theme, PersonRepository repository) {
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Person> people =
        repository.getAll().where((Person p) => !p.hidden).where((Person p) {
          return p.fullName.toLowerCase().contains(query) ||
              (p.phone ?? '').contains(query);
        }).toList()..sort(
          (Person a, Person b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          elevation: 6,
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: people.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: Text(
                      'לא נמצאו תוצאות',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    shrinkWrap: true,
                    itemCount: people.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Person person = people[index];
                      return PersonListCard(
                        person: person,
                        heroEnabled: false,
                        onTap: () => context.push('/people/${person.id}'),
                        onToggleFavorite: () =>
                            repository.toggleFavorite(person.id),
                        onOpenWhatsApp: () => _openWhatsApp(person),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
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

  /// Hebrew greeting for the current part of the day: morning until noon,
  /// afternoon until 17:00, evening until 21:00, night from then until 05:00.
  static String _timeOfDayGreeting(TimeOfDay now) {
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

  static IconData _timeOfDayIcon(TimeOfDay now) {
    final int hour = now.hour;
    if (hour >= 5 && hour < 17) {
      return Icons.wb_sunny_outlined;
    }
    if (hour >= 17 && hour < 21) {
      return Icons.wb_twilight;
    }
    return Icons.nightlight_outlined;
  }
}

/// The "בוא/י נחשוב על החברים שלך" line under the greeting.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.profile});

  final UserProfileProvider profile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isFemale = profile.gender == Gender.female;
    final String letsGo = isFemale ? 'בואי נחשוב' : 'בוא נחשוב';

    return Text(
      '$letsGo על החברים שלך!',
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The two matching shortcuts: add a friend (which asks how) and open an idea.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _QuickActionCard(
              icon: Icons.person_add_alt,
              title: 'הוסף חברים',
              subtitle: 'לא משאירים אף חבר/ה רווק/ה מאחור',
              highlighted: true,
              onTap: () => AddPeopleDialog.show(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.auto_awesome_outlined,
              title: 'הוסף רעיון',
              subtitle: 'שמור את כל הרעיונות שלך במקום אחד',
              onTap: () => context.push('/matches/add'),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Makes this the filled, primary call to action. The other card uses a
  /// clearly-tinted "tonal" style so it still reads as an enabled button rather
  /// than a washed-out, disabled-looking outline.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    // The light theme's `primary` is a pale blue-grey — too washed out to carry
    // a filled button, so the deeper tone is used there.
    final Color fill = dark ? theme.colorScheme.primary : AppColors.primaryDark;
    final Color onFill = theme.colorScheme.onPrimary;
    final Color accent = dark
        ? theme.colorScheme.secondary
        : AppColors.secondary;

    // Secondary card: a solid-enough copper tint with a defined border and full
    // accent-coloured text/icon, so it stands out as tappable next to the
    // primary card without competing with it.
    final Color tonalFill = accent.withValues(alpha: dark ? 0.22 : 0.14);
    final Color tonalBorder = accent.withValues(alpha: dark ? 0.55 : 0.5);

    final Color background = highlighted ? fill : tonalFill;
    final Color titleColor = highlighted ? onFill : accent;
    final Color subtitleColor = highlighted
        ? onFill.withValues(alpha: 0.85)
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      elevation: highlighted ? 3 : 0,
      shadowColor: fill.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: highlighted
                ? null
                : Border.all(color: tonalBorder, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: subtitleColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 30, color: titleColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The shortcut into "הנתונים שלך החודש".
class _MonthlyStatsCard extends StatelessWidget {
  const _MonthlyStatsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.insights_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'הנתונים שלך החודש',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal, side-scrolling row of couple cards.
class _CoupleRow extends StatelessWidget {
  const _CoupleRow({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.matches,
    required this.repository,
    this.subtitle,
    this.centered = false,
    this.hideWhenEmpty = false,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final String emptyText;
  final List<MatchIdea> matches;
  final PersonRepository repository;

  /// Centers the header and the couple cards, and — when there are more cards
  /// than fit — keeps them centered while allowing a horizontal scroll.
  final bool centered;

  /// Drops the whole section (header included) when there is nothing to show,
  /// instead of rendering an "empty" hint.
  final bool hideWhenEmpty;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty && hideWhenEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: <Widget>[
        _SectionHeader(
          title: title,
          icon: icon,
          subtitle: subtitle,
          centered: centered,
        ),
        if (matches.isEmpty)
          _EmptyRowHint(text: emptyText)
        else if (centered)
          _centeredCards(context)
        else
          SizedBox(
            height: 106,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: matches.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int index) {
                final MatchIdea match = matches[index];
                return CoupleCard(
                  personA: repository.getById(match.personAId),
                  personB: repository.getById(match.personBId),
                  onTap: () => context.push('/matches/${match.id}'),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, MatchIdea match) {
    return CoupleCard(
      personA: repository.getById(match.personAId),
      personB: repository.getById(match.personBId),
      onTap: () => context.push('/matches/${match.id}'),
    );
  }

  /// Centers the couple cards when they fit within the available width; once
  /// they overflow it falls back to a horizontally-scrolling row.
  Widget _centeredCards(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int count = matches.length;
        final double contentWidth =
            count * CoupleCard.width + (count - 1) * _gap;
        // Leave a little side padding before deciding it no longer fits.
        final bool fits = contentWidth <= constraints.maxWidth - 40;

        final List<Widget> cards = <Widget>[
          for (int i = 0; i < count; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: _gap),
            _buildCard(context, matches[i]),
          ],
        ];

        if (fits) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: cards,
            ),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cards,
          ),
        );
      },
    );
  }
}

/// A horizontal, side-scrolling row of the friends updated most recently.
class _RecentPeopleRow extends StatelessWidget {
  const _RecentPeopleRow({required this.people});

  final List<Person> people;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeader(
          title: 'חברים שעודכנו לאחרונה',
          icon: Icons.schedule,
        ),
        if (people.isEmpty)
          const _EmptyRowHint(text: 'עוד לא עודכנו חברים.')
        else
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int index) {
                final Person person = people[index];
                return _PersonMiniCard(
                  person: person,
                  onTap: () => context.push('/people/${person.id}'),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _PersonMiniCard extends StatelessWidget {
  const _PersonMiniCard({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: 108,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                PersonAvatar(person: person, radius: 24),
                const SizedBox(height: 10),
                Text(
                  _shortName(person),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "יעל ג." — the full name rarely fits on a card this small.
  static String _shortName(Person person) {
    final String first = person.firstName.trim();
    final String last = person.lastName.trim();
    if (first.isEmpty) {
      return last.isEmpty ? '—' : last;
    }
    return last.isEmpty ? first : '$first ${last.characters.first}.';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    this.subtitle,
    this.centered = false,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? sub = subtitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 10),
      child: Column(
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: centered
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: <Widget>[
              if (centered) ...<Widget>[
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ] else ...<Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(icon, size: 20, color: theme.colorScheme.primary),
              ],
            ],
          ),
          if (sub != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyRowHint extends StatelessWidget {
  const _EmptyRowHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The rotating piece of advice at the bottom of the page.
class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip, required this.onAnother});

  final String tip;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'טיפ לשדכן',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.lightbulb_outline,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(tip, style: theme.textTheme.bodyMedium),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onAnother,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('טיפ אחר'),
            ),
          ),
        ],
      ),
    );
  }
}
