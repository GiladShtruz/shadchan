import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/widgets/home_section.dart';

/// "שיתוף כרטיסים עם שדכנים מחוברים" — which cards of this database the
/// matchmakers connected with this one may see.
///
/// Three ways to share — everything, some, everything but some — and never
/// more than complete cards (a photo and text). A card a single keeps
/// themselves is shared only after the single says so in their own area.
class SharingSettingsScreen extends StatelessWidget {
  const SharingSettingsScreen({super.key});

  static const String allConfirmation =
      'לשתף את כל הכרטיסים המלאים שלך עם השדכנים המחוברים? כדאי לוודא שאין '
      'חברים שמעדיפים להישאר פרטיים. רק כרטיסים עם תמונה וטקסט יוצגו.';

  Future<void> _choose(BuildContext context, ShareMode mode) async {
    if (mode == NetworkSharing.mode) return;
    if (!OfflineGuard.allow(context)) return;
    if (mode == ShareMode.all) {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('שיתוף כל המאגר'),
          content: const Text(allConfirmation),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('לשתף'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    NetworkSharing.setMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PersonRepository repo = context.watch<PersonRepository>();
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('שיתוף כרטיסים עם שדכנים')),
      body: ValueListenableBuilder<int>(
        valueListenable: NetworkSharing.revision,
        builder: (BuildContext context, _, _) {
          final List<Person> people = <Person>[
            for (final Person p in repo.getAll())
              if (!p.hidden && !SharedIdeas.isPartnersPerson(p.id)) p,
          ];
          final Map<ShareEligibility, List<Person>> byState =
              <ShareEligibility, List<Person>>{};
          for (final Person p in people) {
            byState
                .putIfAbsent(
                  NetworkSharing.eligibilityOf(p, accessTo: access.accessTo),
                  () => <Person>[],
                )
                .add(p);
          }
          final List<Person> ready =
              byState[ShareEligibility.ready] ?? const <Person>[];
          final List<Person> awaiting =
              byState[ShareEligibility.awaitingConsent] ?? const <Person>[];
          final int incomplete =
              (byState[ShareEligibility.incomplete] ?? const <Person>[]).length;
          final int shared = NetworkSharing.sharedNow(
            people,
            accessTo: access.accessTo,
          ).length;
          final ShareMode mode = NetworkSharing.mode;
          final int connected = MatchmakerNetwork.connectedNames.length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              HomePaperCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'רשת של שדכנים שמכירים אחד את השני',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'הכרטיסים שתבחר/י יוצגו רק לשדכנים שמחוברים אליך — '
                        'מאנשי הקשר שלך, שאישרו חיבור. לא מאגר ציבורי. '
                        'הם יראו תמונות, פרטי הכרטיס, "מה מחפש/ת" ותגיות — '
                        'לא טלפון ולא ההערות שלך — ולא יוכלו לערוך, לשמור '
                        'או לשתף הלאה. כל פנייה עוברת דרכך.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        connected == 0
                            ? 'עוד אין שדכנים מחוברים אליך.'
                            : 'מחוברים אליך: $connected שדכנים.',
                        style: theme.textTheme.labelLarge,
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: () => context.push('/known-matchmakers'),
                          child: const Text('לשדכנים שאני מכיר'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              HomePaperCard(
                padding: EdgeInsets.zero,
                child: RadioGroup<ShareMode>(
                  groupValue: mode,
                  onChanged: (ShareMode? m) {
                    if (m != null) _choose(context, m);
                  },
                  child: const Column(
                    children: <Widget>[
                      RadioListTile<ShareMode>(
                        value: ShareMode.none,
                        title: Text('לא לשתף'),
                      ),
                      RadioListTile<ShareMode>(
                        value: ShareMode.all,
                        title: Text('לשתף את כל המאגר'),
                        subtitle: Text('כל הכרטיסים המלאים'),
                      ),
                      RadioListTile<ShareMode>(
                        value: ShareMode.selected,
                        title: Text('לשתף אנשים ספציפיים'),
                      ),
                      RadioListTile<ShareMode>(
                        value: ShareMode.allExcept,
                        title: Text('לשתף את כל המאגר חוץ מ...'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  <String>[
                    'משותפים עכשיו: $shared',
                    if (incomplete > 0)
                      '$incomplete כרטיסים לא מלאים (חסרה תמונה או טקסט) לא ישותפו',
                    if (awaiting.isNotEmpty)
                      '${awaiting.length} מנהלים כרטיס אישי וממתינים לאישור שלהם',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (mode == ShareMode.selected ||
                  mode == ShareMode.allExcept) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  mode == ShareMode.selected ? 'מי ישותף' : 'מי לא ישותף',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                for (final Person p in ready) _PickRow(person: p, mode: mode),
              ],
              if (awaiting.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'ממתינים לאישור החבר/ה',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  'חברים שמנהלים כרטיס אישי צריכים לאשר באזור האישי שלהם '
                  'שמותר לך להציג את הכרטיס גם לשדכנים שאתה מכיר.',
                  style: theme.textTheme.bodySmall,
                ),
                for (final Person p in awaiting) _ConsentRow(person: p),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.person, required this.mode});

  final Person person;
  final ShareMode mode;

  @override
  Widget build(BuildContext context) {
    final bool picked = mode == ShareMode.selected
        ? NetworkSharing.selected.contains(person.id)
        : NetworkSharing.excluded.contains(person.id);
    return CheckboxListTile(
      value: picked,
      onChanged: (bool? on) {
        if (!OfflineGuard.allow(context)) return;
        final Set<String> set = mode == ShareMode.selected
            ? NetworkSharing.selected
            : NetworkSharing.excluded;
        on == true ? set.add(person.id) : set.remove(person.id);
        mode == ShareMode.selected
            ? NetworkSharing.setSelected(set)
            : NetworkSharing.setExcluded(set);
      },
      secondary: PersonAvatar(person: person, radius: 20),
      title: Text(
        person.fullName,
        style: TextStyle(color: AppColors.genderAccent(person.gender)),
      ),
      subtitle: person.age == null ? null : Text('${person.age}'),
      controlAffinity: ListTileControlAffinity.trailing,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final String? owner = person.cardOwnerUid;
    final bool asked =
        owner != null &&
        (access.accessTo(owner)?.shareOnwardRequested ?? false);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: PersonAvatar(person: person, radius: 20),
      title: Text(person.fullName),
      subtitle: Text(asked ? 'הבקשה נשלחה · ממתין לאישור' : 'טרם אישר/ה'),
      trailing: asked || owner == null
          ? null
          : TextButton(
              onPressed: () async {
                if (!OfflineGuard.allow(context)) return;
                final bool ok = await access.requestShareOnward(owner);
                if (!context.mounted) return;
                AppNotice.show(
                  context,
                  ok
                      ? 'הבקשה נשלחה ל${person.firstName}'
                      : 'לא הצלחנו לשלוח את הבקשה',
                  isError: !ok,
                );
              },
              child: const Text('לבקש אישור'),
            ),
    );
  }
}
