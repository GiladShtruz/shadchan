import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/home_section.dart';

/// Puts something on "הלוח שלי" by hand.
///
/// Until now the board could only be filled from *inside* a record — open a
/// person, open its menu, pin it — which is the wrong way round for the one
/// case the board exists for: sitting down with the home screen and deciding
/// what this week is about. That requires walking out to a record and back for
/// every item, and it means a matchmaker who has never opened that menu does
/// not know the board can be filled at all.
///
/// Two steps, because a friend and a proposal are picked from different lists
/// and one combined list of both would be a list of things that are not
/// comparable.
abstract final class BoardAddSheet {
  /// Returns what was pinned, or null when the flow was left.
  static Future<HomeItemKind?> show(BuildContext context) async {
    final HomeItemKind? kind = await showModalBottomSheet<HomeItemKind>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text(
                  'הוספה ללוח',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text('מה שחשוב לזכור השבוע'),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('הוספת חבר'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(HomeItemKind.person),
              ),
              ListTile(
                leading: const Icon(Icons.favorite_outline),
                title: const Text('הוספת רעיון'),
                onTap: () => Navigator.of(sheetContext).pop(HomeItemKind.idea),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (kind == null || !context.mounted) {
      return null;
    }

    return switch (kind) {
      HomeItemKind.person => _pinPerson(context),
      HomeItemKind.idea => _pinIdea(context),
    };
  }

  /// Anyone already on the board is left out of the picker — offering to pin
  /// what is already pinned is an action with nothing behind it.
  static Future<HomeItemKind?> _pinPerson(BuildContext context) async {
    final Set<String> pinned = <String>{
      for (final HomeBoardEntry entry in HomeBoardStore.instance.entries)
        if (entry.kind == HomeItemKind.person) entry.targetId,
    };

    final Person? person = await PersonPickerSheet.show(
      context,
      title: 'הוספת חבר ללוח',
      excludeIds: pinned,
      emptySubtitle: '{נסה|נסי} לחפש בשם אחר',
      filterKey: 'board.person',
    );
    if (person == null) {
      return null;
    }
    HomeBoardStore.instance.add(HomeItemKind.person, person.id);
    return HomeItemKind.person;
  }

  static Future<HomeItemKind?> _pinIdea(BuildContext context) async {
    final MatchIdea? match = await MatchPickerSheet.show(context);
    if (match == null) {
      return null;
    }
    HomeBoardStore.instance.add(HomeItemKind.idea, match.id);
    return HomeItemKind.idea;
  }
}

/// Picks one proposal out of the live ones, by either candidate's name.
///
/// Archived proposals are not offered: the board is a list of what to come back
/// to, and there is nothing to come back to on a proposal that closed. Anything
/// already on the board is left out for the same reason.
class MatchPickerSheet extends StatefulWidget {
  const MatchPickerSheet({super.key});

  static Future<MatchIdea?> show(BuildContext context) {
    return showModalBottomSheet<MatchIdea>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => const FractionallySizedBox(
        heightFactor: 0.85,
        child: MatchPickerSheet(),
      ),
    );
  }

  @override
  State<MatchPickerSheet> createState() => _MatchPickerSheetState();
}

class _MatchPickerSheetState extends State<MatchPickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matches = context.watch<MatchRepository>();
    final PersonRepository people = context.watch<PersonRepository>();

    final Set<String> pinned = <String>{
      for (final HomeBoardEntry entry in HomeBoardStore.instance.entries)
        if (entry.kind == HomeItemKind.idea) entry.targetId,
    };
    final String query = _search.text.trim().toLowerCase();

    String nameOf(String? id) =>
        (id == null ? null : people.getById(id)?.fullName.trim()) ?? '';

    final List<MatchIdea> options = matches
        .getActive()
        .where((MatchIdea match) => !pinned.contains(match.id))
        .where((MatchIdea match) {
          if (query.isEmpty) {
            return true;
          }
          return nameOf(match.personAId).toLowerCase().contains(query) ||
              nameOf(match.personBId).toLowerCase().contains(query);
        })
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'הוספת רעיון ללוח',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'חיפוש לפי שם',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: options.isEmpty
                ? EmptyState(
                    icon: Icons.favorite_border,
                    title: query.isEmpty
                        ? 'אין רעיונות פעילים להוספה'
                        : 'לא נמצאו רעיונות',
                    subtitle: query.isEmpty
                        ? 'רעיון שייפתח יופיע כאן'
                        : '{נסה|נסי} לחפש בשם אחר',
                  )
                : ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final MatchIdea match = options[index];
                      final Person? personA = people.getById(match.personAId);
                      final Person? personB = people.getById(match.personBId);
                      return _MatchOption(
                        personA: personA,
                        personB: personB,
                        status: match.status,
                        onTap: () => Navigator.of(context).pop(match),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MatchOption extends StatelessWidget {
  const _MatchOption({
    required this.personA,
    required this.personB,
    required this.status,
    required this.onTap,
  });

  final Person? personA;
  final Person? personB;
  final MatchStatus status;
  final VoidCallback onTap;

  static String _name(Person? person) {
    final String full = person?.fullName.trim() ?? '';
    return full.isEmpty ? '—' : full;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              HomeCardCoupleAvatars(
                personA: personA,
                personB: personB,
                radius: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${_name(personA)} & ${_name(personB)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.displayName,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.statusColor(status.name),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.push_pin_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
