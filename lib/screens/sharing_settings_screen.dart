import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/network_onboarding.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// "שיתוף כרטיסים עם השדכנים שאני מכיר" — which cards of this database the
/// matchmakers connected with this one may see.
///
/// Private by default. Three ways to share — הכל | אנשים מסוימים | הכל חוץ
/// מ... — as options of one choice, never separate lists; never more than
/// complete cards (a photo and text); and **cards already in the database
/// before sharing started are never opened by themselves** — they are offered
/// to add, in one go. Every time cards join the share the matchmaker is asked
/// once, for the whole group ([confirmAdding]).
class SharingSettingsScreen extends StatelessWidget {
  const SharingSettingsScreen({super.key});

  /// The one warning, said once for every group of cards added.
  static const String addWarning =
      'הכרטיסים שבחרת יהיו זמינים לשדכנים {שאתה|שאת} {מכיר|מכירה}. '
      '{ודא|ודאי} שנוח לחברים האלה שהכרטיס שלהם יוצג במסגרת הזו.';

  /// Asks once before [count] cards (or every new card, for "שתף הכל") join
  /// the share. True when the matchmaker agreed.
  static Future<bool> confirmAdding(BuildContext context, {int? count}) async {
    Gender? gender;
    try {
      gender = context.read<UserProfileProvider>().gender;
    } on ProviderNotFoundException {
      gender = null;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(
          count == null
              ? 'לשתף כרטיסים חדשים מהמאגר?'
              : count == 1
              ? 'להוסיף כרטיס אחד לשיתוף?'
              : 'להוסיף $count כרטיסים לשיתוף?',
        ),
        content: Text(addWarning.forGender(gender)),
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
    return ok == true;
  }

  /// Picks cards from [people] and adds them to the share — one warning for
  /// the whole group.
  static Future<void> addCards(
    BuildContext context,
    List<Person> people, {
    String title = 'הוספת כרטיסים לשיתוף',
  }) async {
    if (!OfflineGuard.allow(context)) return;
    if (people.isEmpty) {
      AppNotice.show(context, 'אין כרטיסים מלאים שאפשר להוסיף כרגע.');
      return;
    }
    final Set<String>? ids = await ShareCardsPicker.show(
      context,
      people: people,
      title: title,
    );
    if (ids == null || ids.isEmpty || !context.mounted) return;
    if (!await confirmAdding(context, count: ids.length)) return;
    NetworkSharing.add(ids);
  }

  Future<void> _choose(BuildContext context, ShareMode mode) async {
    if (mode == NetworkSharing.mode) return;
    if (!OfflineGuard.allow(context)) return;
    final bool opening =
        (mode == ShareMode.all || mode == ShareMode.allExcept) &&
        NetworkSharing.mode != ShareMode.all &&
        NetworkSharing.mode != ShareMode.allExcept;
    if (opening && !await confirmAdding(context)) return;
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
          final List<Person> awaiting =
              byState[ShareEligibility.awaitingConsent] ?? const <Person>[];
          final int incomplete =
              (byState[ShareEligibility.incomplete] ?? const <Person>[]).length;
          final List<Person> shared = NetworkSharing.sharedNow(
            people,
            accessTo: access.accessTo,
          );
          final List<Person> addable = NetworkSharing.addable(
            people,
            accessTo: access.accessTo,
          );
          final List<Person> earlier = NetworkSharing.earlierNotShared(
            people,
            accessTo: access.accessTo,
          );
          final List<Person> kept = <Person>[
            for (final Person p in people)
              if (NetworkSharing.excluded.contains(p.id)) p,
          ];
          final ShareMode mode = NetworkSharing.mode;
          final int connected = MatchmakerNetwork.connectedNames.length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              if (mode == ShareMode.none && !NetworkSharing.onboardingDone)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: NetworkOnboardingCard(onSharingScreen: true),
                ),
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
                        subtitle: Text('המאגר שלי פרטי'),
                      ),
                      RadioListTile<ShareMode>(
                        value: ShareMode.all,
                        title: Text('שתף הכל'),
                        subtitle: Text(
                          'כל כרטיס מלא שאוסיף מעכשיו. כרטיסים קודמים — רק '
                          'אם אבחר להוסיף אותם',
                        ),
                      ),
                      RadioListTile<ShareMode>(
                        value: ShareMode.selected,
                        title: Text('שתף אנשים מסוימים'),
                        subtitle: Text('רק מי שאבחר'),
                      ),
                      RadioListTile<ShareMode>(
                        value: ShareMode.allExcept,
                        title: Text('שתף הכל חוץ מ...'),
                        subtitle: Text('כמו "שתף הכל", בלי מי שאחריג'),
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
                    'משותפים עכשיו: ${shared.length}',
                    if (incomplete > 0)
                      '$incomplete כרטיסים לא מלאים (חסרה תמונה או טקסט) לא ישותפו',
                    if (awaiting.isNotEmpty)
                      '${awaiting.length} מנהלים כרטיס אישי וכיבו את השיתוף דרך השדכנים',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (earlier.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _ActionTile(
                  icon: Icons.history_rounded,
                  title:
                      '${earlier.length} כרטיסים מלאים מלפני שהתחלת לשתף לא נפתחו אוטומטית',
                  action: 'בחירה',
                  onPressed: () => addCards(
                    context,
                    earlier,
                    title: 'כרטיסים מלפני שהתחלת לשתף',
                  ),
                ),
              ],
              if (mode != ShareMode.none) ...<Widget>[
                const SizedBox(height: 8),
                _ActionTile(
                  icon: Icons.add_circle_outline_rounded,
                  title: 'הוספת כרטיסים לשיתוף',
                  action: 'בחירה',
                  onPressed: () => addCards(context, addable),
                ),
              ],
              if (shared.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  mode == ShareMode.allExcept
                      ? 'משותפים · אפשר להחריג'
                      : 'משותפים',
                  style: theme.textTheme.titleSmall,
                ),
                for (final Person p in shared)
                  _PersonRow(
                    person: p,
                    trailing: TextButton(
                      onPressed: () {
                        if (!OfflineGuard.allow(context)) return;
                        NetworkSharing.remove(p);
                      },
                      child: Text(
                        mode == ShareMode.allExcept ? 'להחריג' : 'הסרה',
                      ),
                    ),
                  ),
              ],
              if (kept.isNotEmpty && mode != ShareMode.none) ...<Widget>[
                const SizedBox(height: 16),
                Text('לא ישותפו', style: theme.textTheme.titleSmall),
                for (final Person p in kept)
                  _PersonRow(
                    person: p,
                    trailing: TextButton(
                      onPressed: () async {
                        if (!OfflineGuard.allow(context)) return;
                        if (!await confirmAdding(context, count: 1)) return;
                        NetworkSharing.add(<String>[p.id]);
                      },
                      child: const Text('להחזיר'),
                    ),
                  ),
              ],
              if (awaiting.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'מנהלים כרטיס אישי וכיבו את השיתוף',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  'החברים האלה ביקשו שהשדכנים שלהם לא יציגו את הכרטיס לשדכנים '
                  'נוספים. אפשר לבקש מהם לשנות זאת באזור האישי שלהם.',
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return HomePaperCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.bodyMedium),
        trailing: TextButton(onPressed: onPressed, child: Text(action)),
        onTap: onPressed,
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.trailing});

  final Person person;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: PersonAvatar(person: person, radius: 20),
      title: Text(
        person.fullName,
        style: TextStyle(color: AppColors.genderAccent(person.gender)),
      ),
      subtitle: Text(
        <String>[
          if (person.age != null) '${person.age}',
          if ((person.cardOwnerUid ?? '').isNotEmpty) 'כרטיס אישי',
        ].join(' · '),
      ),
      trailing: trailing,
    );
  }
}

/// Several cards at once: a searchable list with a box on each, "בחירת הכל",
/// and one button that returns the choice.
class ShareCardsPicker extends StatefulWidget {
  const ShareCardsPicker({
    super.key,
    required this.people,
    required this.title,
  });

  final List<Person> people;
  final String title;

  static Future<Set<String>?> show(
    BuildContext context, {
    required List<Person> people,
    required String title,
  }) => showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.9,
      child: ShareCardsPicker(people: people, title: title),
    ),
  );

  @override
  State<ShareCardsPicker> createState() => _ShareCardsPickerState();
}

class _ShareCardsPickerState extends State<ShareCardsPicker> {
  final Set<String> _picked = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String q = _query.trim();
    final List<Person> shown = <Person>[
      for (final Person p in widget.people)
        if (q.isEmpty || p.fullName.contains(q)) p,
    ];
    final bool all =
        shown.isNotEmpty && shown.every((Person p) => _picked.contains(p.id));
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(widget.title, style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  onChanged: (String v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'חיפוש בשם',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  if (all) {
                    _picked.removeAll(shown.map((Person p) => p.id));
                  } else {
                    _picked.addAll(shown.map((Person p) => p.id));
                  }
                }),
                child: Text(all ? 'ניקוי' : 'בחירת הכל'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (BuildContext context, int i) {
              final Person p = shown[i];
              return CheckboxListTile(
                value: _picked.contains(p.id),
                onChanged: (bool? on) => setState(() {
                  on == true ? _picked.add(p.id) : _picked.remove(p.id);
                }),
                secondary: PersonAvatar(person: p, radius: 20),
                title: Text(
                  p.fullName,
                  style: TextStyle(color: AppColors.genderAccent(p.gender)),
                ),
                subtitle: p.age == null ? null : Text('${p.age}'),
                controlAffinity: ListTileControlAffinity.trailing,
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _picked.isEmpty
                    ? null
                    : () => Navigator.pop(context, Set<String>.of(_picked)),
                child: Text(
                  _picked.isEmpty
                      ? 'בחירת כרטיסים'
                      : 'הוספה לשיתוף (${_picked.length})',
                ),
              ),
            ),
          ),
        ),
      ],
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
      subtitle: Text(asked ? 'הבקשה נשלחה' : 'השיתוף דרך השדכנים כבוי'),
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
              child: const Text('לבקש'),
            ),
    );
  }
}
