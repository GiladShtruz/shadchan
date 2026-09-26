import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/deleted_matches_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/empty_state.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// "רעיונות שנמחקו" — every idea deleted in the last month, each with a way
/// back.
///
/// A deleted idea is kept whole in [DeletedMatchesStore]: its journal, its
/// stage and its reminder come back with it. An idea whose friend has since
/// been deleted cannot be restored — there would be half a couple — and says
/// so instead of offering a button that does nothing.
class DeletedIdeasScreen extends StatelessWidget {
  const DeletedIdeasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository people = context.watch<PersonRepository>();
    context.watch<MatchRepository>();

    return ListenableBuilder(
      listenable: DeletedMatchesStore.instance,
      builder: (BuildContext context, _) {
        final List<DeletedMatch> items = DeletedMatchesStore.instance.all;
        return Scaffold(
          appBar: AppBar(title: const Text('רעיונות שנמחקו')),
          body: items.isEmpty
              ? const EmptyState(
                  icon: Icons.delete_outline_rounded,
                  title: 'אין רעיונות שנמחקו',
                  subtitle:
                      'רעיון שנמחק נשמר כאן חודש, ואפשר להחזיר אותו בלחיצה',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'רעיון שנמחק נשמר כאן חודש, עם היומן שלו. '
                        'שחזור מחזיר אותו בדיוק כפי שהיה.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    for (final DeletedMatch item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _DeletedIdeaRow(
                          item: item,
                          a: people.getById(item.personAId),
                          b: people.getById(item.personBId),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _DeletedIdeaRow extends StatelessWidget {
  const _DeletedIdeaRow({required this.item, required this.a, required this.b});

  final DeletedMatch item;
  final Person? a;
  final Person? b;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    // Her first, on the right, as on every idea card.
    final Person? female = a?.gender == Gender.female ? a : b;
    final Person? male = identical(female, a) ? b : a;
    final bool restorable = a != null && b != null;

    Widget name(Person? person, Gender gender) {
      return Text(
        person?.fullName.trim().isNotEmpty == true
            ? person!.fullName.trim()
            : 'חבר שנמחק',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: person == null
              ? theme.colorScheme.onSurfaceVariant
              : AppColors.genderAccent(person.gender, dark: dark),
        ),
      );
    }

    return HomePaperCard(
      stripe: AppColors.secondary,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: <Widget>[
          _Face(person: female),
          const SizedBox(width: 4),
          _Face(person: male),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(child: name(female, Gender.female)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.favorite_rounded,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Flexible(child: name(male, Gender.male)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  restorable
                      ? 'נמחק ${AppDateUtils.formatDateShort(item.deletedAt)}'
                      : 'אחד החברים כבר לא במאגר, ולכן אי אפשר לשחזר',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (restorable)
            TextButton(
              onPressed: () => _restore(context),
              child: const Text('שחזור'),
            )
          else
            IconButton(
              tooltip: 'מחיקה לצמיתות',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => DeletedMatchesStore.instance.purge(item.matchId),
            ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final PersonRepository people = context.read<PersonRepository>();
    final OverlayState? overlay = AppNotice.capture(context);
    final bool restored = await context.read<MatchRepository>().restoreDeleted(
      item.matchId,
      personExists: (String id) => people.getById(id) != null,
    );
    AppNotice.showOn(
      overlay,
      restored ? 'הרעיון שוחזר' : 'לא הצלחנו לשחזר את הרעיון',
      atBottom: true,
      isError: !restored,
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.person});

  final Person? person;

  @override
  Widget build(BuildContext context) {
    final Person? current = person;
    if (current == null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.person_off_outlined, size: 16),
      );
    }
    return PersonAvatar(person: current, radius: 18);
  }
}
