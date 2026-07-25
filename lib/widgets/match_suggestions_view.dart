import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';
import 'package:shadchan/utils/suggestion_dismissals.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// A popup that shows the full automatic-matches view for [sourcePerson] — the
/// same suggestions/accept/reject experience as the `התאמות` tab inside a
/// person card — without leaving the current screen. Opened as a bottom sheet
/// from the home screen's featured contact card.
abstract final class MatchSuggestionsSheet {
  static Future<void> show(
    BuildContext context, {
    required Person sourcePerson,
  }) {
    if (sourcePerson.gender == Gender.unknown) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('יש לבחור מגדר לאיש הקשר לפני פתיחת התאמות'),
          ),
        );
      return Future<void>.value();
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: MatchSuggestionsView(sourcePerson: sourcePerson),
        );
      },
    );
  }
}

/// The matches content itself. Computes the suggested candidates for
/// [sourcePerson] using the shared [MatchSuggestionUtils] rules (plus any saved
/// per-person filter) and renders them with accept/reject actions.
class MatchSuggestionsView extends StatefulWidget {
  const MatchSuggestionsView({super.key, required this.sourcePerson});

  final Person sourcePerson;

  @override
  State<MatchSuggestionsView> createState() => _MatchSuggestionsViewState();
}

class _MatchSuggestionsViewState extends State<MatchSuggestionsView> {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final Person person =
        personRepository.getById(widget.sourcePerson.id) ?? widget.sourcePerson;

    final MatchProposalFilters? savedFilters =
        MatchProposalFilterSheet.savedFiltersFor(person.id);
    final List<Person> suggestedPeople = _orderedSuggestions(
      source: person,
      personRepository: personRepository,
      matchRepository: matchRepository,
      savedFilters: savedFilters,
    );

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Text(
              'התאמות עבור ${person.fullName.trim()}',
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _FilterHeader(
            count: suggestedPeople.length,
            hasCustomFilters: savedFilters != null,
            onFilterPressed: () => _openFilters(context, person),
          ),
          Expanded(
            child: _buildBody(
              theme: theme,
              person: person,
              suggestedPeople: suggestedPeople,
              matchRepository: matchRepository,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required ThemeData theme,
    required Person person,
    required List<Person> suggestedPeople,
    required MatchRepository matchRepository,
  }) {
    if (person.gender == Gender.unknown) {
      return const _EmptyState(
        icon: Icons.wc_outlined,
        title: 'צריך לבחור מגדר',
        subtitle: 'אחרי עדכון מגדר יוצגו התאמות אוטומטיות',
      );
    }
    if (suggestedPeople.isEmpty) {
      return const _EmptyState(
        icon: Icons.favorite_border,
        title: 'לא נמצאו התאמות',
        subtitle: 'אפשר לשנות את הסינון ולנסות שוב',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: suggestedPeople.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final Person candidate = suggestedPeople[index];
        final MatchIdea? existingMatch = matchRepository.findExisting(
          person.id,
          candidate.id,
        );
        return _SuggestionCard(
          candidate: candidate,
          existingMatch: existingMatch,
          onTap: () => _openCandidate(context, candidate, existingMatch),
          onAvatarTap: () => _openCandidateProfile(context, candidate),
          onAccept: () => _acceptSuggestion(context, person, candidate),
          onReject: () => _rejectSuggestion(context, person, candidate),
        );
      },
    );
  }

  /// Mirrors the person-card suggestions ordering: candidates already in an
  /// open/בהמתנה proposal first, then the remaining active suggestions, then
  /// soft-dismissed candidates, then already-rejected candidates last. Within
  /// each tier, candidates that pause matches (תפוס/בהפסקה) drop after the
  /// available ones.
  List<Person> _orderedSuggestions({
    required Person source,
    required PersonRepository personRepository,
    required MatchRepository matchRepository,
    required MatchProposalFilters? savedFilters,
  }) {
    final List<Person> matching = personRepository
        .getAll()
        .where(
          (Person candidate) => _matchesFilters(
            source: source,
            candidate: candidate,
            filters: savedFilters,
          ),
        )
        .toList();

    final Set<String> dismissedIds = SuggestionDismissals.dismissedFor(
      source.id,
    );
    final List<Person> prioritized = <Person>[];
    final List<Person> active = <Person>[];
    final List<Person> dismissed = <Person>[];
    final List<Person> rejected = <Person>[];
    for (final Person candidate in matching) {
      final MatchStatus? status = matchRepository
          .findExisting(source.id, candidate.id)
          ?.status;
      if (status == MatchStatus.rejected) {
        rejected.add(candidate);
      } else if (status == MatchStatus.idea ||
          status == MatchStatus.checking ||
          status == MatchStatus.unavailable) {
        prioritized.add(candidate);
      } else if (dismissedIds.contains(candidate.id)) {
        dismissed.add(candidate);
      } else {
        active.add(candidate);
      }
    }

    List<Person> availableFirst(List<Person> people) => <Person>[
      ...people.where((Person p) => !p.profileStatus.pausesMatches),
      ...people.where((Person p) => p.profileStatus.pausesMatches),
    ];
    return <Person>[
      ...availableFirst(prioritized),
      ...availableFirst(active),
      ...availableFirst(dismissed),
      ...availableFirst(rejected),
    ];
  }

  bool _matchesFilters({
    required Person source,
    required Person candidate,
    required MatchProposalFilters? filters,
  }) {
    if (filters == null) {
      return MatchSuggestionUtils.isSuggestedCandidate(
        source: source,
        candidate: candidate,
      );
    }

    if (!MatchSuggestionUtils.isEligibleCandidate(
      source: source,
      candidate: candidate,
    )) {
      return false;
    }

    final int? candidateAge = candidate.age;
    if (filters.minAge != null &&
        (candidateAge == null || candidateAge < filters.minAge!)) {
      return false;
    }
    if (filters.maxAge != null &&
        (candidateAge == null || candidateAge > filters.maxAge!)) {
      return false;
    }
    final bool hasReligiousFilter =
        filters.religiousLevels.isNotEmpty ||
        filters.religiousLevelOtherLabels.isNotEmpty;
    if (hasReligiousFilter &&
        !filters.religiousLevels.contains(candidate.religiousLevel) &&
        !(candidate.religiousLevel == ReligiousLevel.other &&
            filters.religiousLevelOtherLabels.contains(
              candidate.religiousLevelOther?.trim(),
            ))) {
      return false;
    }
    if (filters.profileStatuses.isNotEmpty &&
        !filters.profileStatuses.contains(candidate.profileStatus)) {
      return false;
    }
    return true;
  }

  Future<void> _openFilters(BuildContext context, Person source) async {
    final Gender targetGender = source.gender == Gender.male
        ? Gender.female
        : Gender.male;
    final ({int minAge, int maxAge})? femaleAgeRange =
        source.gender == Gender.male
        ? MatchSuggestionUtils.femaleAgeRangeForMale(source.age)
        : null;

    final MatchProposalFilters? filters = await MatchProposalFilterSheet.show(
      context,
      targetGender: targetGender,
      sourcePersonId: source.id,
      initialFilters: MatchProposalFilters(
        minAge: femaleAgeRange?.minAge,
        maxAge: femaleAgeRange?.maxAge,
        religiousLevels: MatchSuggestionUtils.religiousLevelsFor(
          source.religiousLevel,
        ),
      ),
    );

    if (filters != null && mounted) {
      setState(() {});
    }
  }

  void _openCandidate(
    BuildContext context,
    Person candidate,
    MatchIdea? existingMatch,
  ) {
    Navigator.of(context).pop();
    if (existingMatch != null) {
      context.push('/matches/${existingMatch.id}');
    } else {
      context.push('/people/${candidate.id}');
    }
  }

  void _openCandidateProfile(BuildContext context, Person candidate) {
    Navigator.of(context).pop();
    context.push('/people/${candidate.id}');
  }

  Future<void> _acceptSuggestion(
    BuildContext context,
    Person source,
    Person candidate,
  ) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'פתיחת הצעה',
      message:
          'האם לפתוח הצעה בין ${source.fullName.trim()} '
          'ל${candidate.fullName.trim()}?',
      confirmText: 'פתיחה',
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    final MatchRepository matchRepository = context.read<MatchRepository>();
    final (Person, Person) pair = _maleFemale(source, candidate);
    final MatchIdea? existingMatch = matchRepository.findExisting(
      pair.$1.id,
      pair.$2.id,
    );
    final MatchIdea? match =
        existingMatch ?? await matchRepository.create(pair.$1.id, pair.$2.id);
    if (match == null || !context.mounted) {
      return;
    }

    Navigator.of(context).pop();
    context.push(
      existingMatch != null
          ? '/matches/${match.id}'
          : '/matches/${match.id}?justCreated=true',
    );
  }

  Future<void> _rejectSuggestion(
    BuildContext context,
    Person source,
    Person candidate,
  ) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'לא מתאים?',
      message: 'ההתאמה תעבור לסוף הרשימה.',
      confirmText: 'לא מתאים',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    // Soft dismissal only: the candidate drops to the end of the suggestions
    // list without creating a rejected proposal.
    await SuggestionDismissals.dismiss(source.id, candidate.id);
    if (mounted) {
      setState(() {});
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('ההתאמה הועברה לסוף הרשימה')),
        );
    }
  }

  (Person, Person) _maleFemale(Person source, Person candidate) {
    final Person male = source.gender == Gender.male ? source : candidate;
    final Person female = source.gender == Gender.female ? source : candidate;
    return (male, female);
  }
}

class _FilterHeader extends StatelessWidget {
  const _FilterHeader({
    required this.count,
    required this.hasCustomFilters,
    required this.onFilterPressed,
  });

  final int count;
  final bool hasCustomFilters;
  final VoidCallback onFilterPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              hasCustomFilters
                  ? '$count התאמות · סינון אישי'
                  : '$count התאמות · סינון אוטומטי',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: 'סינון',
            icon: Icon(
              hasCustomFilters ? Icons.filter_list_alt : Icons.tune,
              color: hasCustomFilters ? theme.colorScheme.primary : null,
            ),
            onPressed: onFilterPressed,
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.candidate,
    required this.existingMatch,
    required this.onTap,
    required this.onAvatarTap,
    required this.onAccept,
    required this.onReject,
  });

  final Person candidate;
  final MatchIdea? existingMatch;
  final VoidCallback onTap;
  final VoidCallback onAvatarTap;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: onAvatarTap,
                child: PersonAvatar(person: candidate, radius: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      candidate.fullName.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _summary(candidate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (existingMatch != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _StatusChip(status: existingMatch!.status),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _RoundIconButton(
                icon: Icons.close,
                tooltip: 'לא מתאים',
                background: theme.colorScheme.error.withValues(alpha: 0.12),
                foreground: theme.colorScheme.error,
                onPressed: onReject,
              ),
              const SizedBox(width: 8),
              _RoundIconButton(
                icon: Icons.favorite_outline,
                tooltip: 'פתיחת הצעה',
                background: theme.colorScheme.primary,
                foreground: theme.colorScheme.onPrimary,
                onPressed: onAccept,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _summary(Person person) {
    final List<String> parts = <String>[
      if (person.age != null) 'גיל ${person.age}',
      if (person.religiousLevelLabel.isNotEmpty) person.religiousLevelLabel,
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ];
    return parts.isEmpty ? 'פרטים חסרים' : parts.join(' · ');
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    final Color baseColor = AppColors.statusColor(status.name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.statusBackgroundColor(status.name),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.displayName,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: baseColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: foreground, size: 22),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
