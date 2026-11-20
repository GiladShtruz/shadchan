import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/matchmaker_shares.dart';
import 'package:shadchan/screens/known_matchmakers_screen.dart';
import 'package:shadchan/screens/network_screen.dart';
import 'package:shadchan/utils/known_matchmakers.dart';
import 'package:shadchan/services/network_sharing.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/services/shared_ideas.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// What this matchmaker shares with **one** other matchmaker — or, without
/// [readerUid], the list of everybody they share with.
///
/// **One decision per matchmaker.** Three ways to share — כל המאגר | אנשים
/// נבחרים | כל המאגר חוץ מ… — as options of one choice; never more than
/// complete cards (a photo and text) the matchmaker may share; and a
/// single's own personal card only with their consent. Every time cards
/// they keep by hand join a share, the matchmaker is warned once for the
/// whole group ([confirmAdding]). Stopping is one tap, no question: the
/// other side is told, and ideas already opened stay.
class SharingSettingsScreen extends StatelessWidget {
  const SharingSettingsScreen({super.key, this.readerUid, this.readerName});

  final String? readerUid;
  final String? readerName;

  /// The route of the screen for one matchmaker.
  static String routeFor(String readerUid, String name) => Uri(
    path: SharingSettingsRoute.path,
    queryParameters: <String, String>{'with': readerUid, 'name': name},
  ).toString();

  /// The one warning, said once for every group of cards added.
  static const String addWarning =
      'הכרטיסים שבחרת יהיו זמינים לשדכן הזה. '
      '{ודא|ודאי} שנוח לחברים האלה שהכרטיס שלהם יוצג במסגרת שידוכים בין '
      'אנשים {שאתה מכיר|שאת מכירה}.';

  /// Asks once before [count] cards (or every complete card, for "כל
  /// המאגר") are shared with this matchmaker. True when the matchmaker agreed.
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
              ? 'לשתף את כל הכרטיסים המלאים?'
              : count == 1
              ? 'לשתף כרטיס אחד?'
              : 'לשתף $count כרטיסים?',
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

  @override
  Widget build(BuildContext context) {
    final String? reader = readerUid;
    if (reader == null || reader.isEmpty) return const _SharingOverview();
    return _ShareWithScreen(readerUid: reader, readerName: readerName ?? '');
  }
}

/// The friends of this database that can be shared at all, and the rest.
List<Person> _candidates(BuildContext context) {
  final PersonRepository repo = context.read<PersonRepository>();
  return <Person>[
    for (final Person p in repo.getAll())
      if (!p.hidden && !SharedIdeas.isPartnersPerson(p.id)) p,
  ];
}

/// Every matchmaker this one shares with, and what — one row each.
class _SharingOverview extends StatefulWidget {
  const _SharingOverview();

  @override
  State<_SharingOverview> createState() => _SharingOverviewState();
}

class _SharingOverviewState extends State<_SharingOverview> {
  VoidCallback? _release;

  @override
  void initState() {
    super.initState();
    _release = MatchmakerShares.watch();
  }

  @override
  void dispose() {
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('מה אני משתף/ת עם כל שדכן')),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          MatchmakerShares.rows,
          NetworkSharing.revision,
        ]),
        builder: (BuildContext context, _) {
          final List<MapEntry<String, ShareChoice>> on =
              <MapEntry<String, ShareChoice>>[
                for (final MapEntry<String, ShareChoice> e
                    in NetworkSharing.choices.entries)
                  if (e.value.isOn) e,
              ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              Text(
                'כל שדכן/ית מקבל/ת רק מה שבחרת לשתף איתו/ה — בנפרד. '
                'השיתוף עם אחד לא משפיע על השני.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (on.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'עוד לא שיתפת כרטיסים עם אף שדכן/ית.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              else
                HomePaperCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      for (final MapEntry<String, ShareChoice> e in on)
                        ListTile(
                          title: Text(_nameOf(e.key)),
                          subtitle: Text(
                            '${_modeLabel(e.value.mode)} · '
                            '${MatchmakerShares.iShareCount(e.key)} כרטיסים',
                          ),
                          trailing: const Icon(Icons.chevron_left_rounded),
                          onTap: () => context.push(
                            SharingSettingsScreen.routeFor(
                              e.key,
                              _nameOf(e.key),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => context.push('/known-matchmakers'),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('פתיחת שיתוף עם שדכן/ית'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _nameOf(String uid) {
    final String n = MatchmakerShares.mine(uid)?.readerName ?? '';
    return n.isEmpty ? 'שדכן/ית' : n;
  }
}

String _modeLabel(ShareMode mode) => switch (mode) {
  ShareMode.none => 'לא משתף/ת',
  ShareMode.all => 'כל המאגר',
  ShareMode.selected => 'אנשים נבחרים',
  ShareMode.allExcept => 'כל המאגר חוץ מכמה',
};

/// What I share with one matchmaker.
class _ShareWithScreen extends StatefulWidget {
  const _ShareWithScreen({required this.readerUid, required this.readerName});

  final String readerUid;
  final String readerName;

  @override
  State<_ShareWithScreen> createState() => _ShareWithScreenState();
}

class _ShareWithScreenState extends State<_ShareWithScreen> {
  bool _saving = false;

  String get _name => widget.readerName.trim().isEmpty
      ? (MatchmakerShares.mine(widget.readerUid)?.readerName ?? 'שדכן/ית')
      : widget.readerName.trim();

  String get _first {
    final String n = _name.trim();
    return n.isEmpty ? 'שדכן/ית' : n.split(RegExp(r'\s+')).first;
  }

  Future<void> _apply(ShareChoice choice) async {
    if (!OfflineGuard.allow(context)) return;
    setState(() => _saving = true);
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final bool ok = await NetworkSharing.setChoice(
      readerUid: widget.readerUid,
      choice: choice,
      myName: context.read<UserProfileProvider>().fullName ?? '',
      theirName: _name,
      people: context.read<PersonRepository>().getAll(),
      accessTo: access.accessTo,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      AppNotice.show(context, 'השינוי לא נשמר. נסו שוב.', isError: true);
    }
  }

  Future<void> _choose(ShareMode mode) async {
    final ShareChoice current = NetworkSharing.choiceFor(widget.readerUid);
    if (mode == current.mode) return;
    final List<Person> people = _candidates(context);
    final CardAccessProvider access = context.read<CardAccessProvider>();
    final List<Person> ready = <Person>[
      for (final Person p in people)
        if (NetworkSharing.eligibilityOf(p, accessTo: access.accessTo) ==
            ShareEligibility.ready)
          p,
    ];
    switch (mode) {
      case ShareMode.none:
        await _apply(ShareChoice.off);
      case ShareMode.all:
        if (!await SharingSettingsScreen.confirmAdding(context)) return;
        await _apply(const ShareChoice(ShareMode.all));
      case ShareMode.allExcept:
        if (!await SharingSettingsScreen.confirmAdding(context)) return;
        if (!mounted) return;
        final Set<String>? out = await ShareCardsPicker.show(
          context,
          people: ready,
          title: 'מי לא ישותף עם $_first?',
          confirmLabel: 'לא לשתף',
          allowEmpty: true,
        );
        if (out == null) return;
        await _apply(ShareChoice(ShareMode.allExcept, excluded: out));
      case ShareMode.selected:
        final Set<String>? picked = await ShareCardsPicker.show(
          context,
          people: ready,
          title: 'אילו כרטיסים לשתף עם $_first?',
          initial: current.mode == ShareMode.selected
              ? current.selected
              : <String>{
                  for (final Person p in ready)
                    if (current.includes(p)) p.id,
                },
        );
        if (picked == null || picked.isEmpty || !mounted) return;
        final int added = picked.difference(current.selected).length;
        if (added > 0 &&
            !await SharingSettingsScreen.confirmAdding(context, count: added)) {
          return;
        }
        await _apply(ShareChoice(ShareMode.selected, selected: picked));
    }
  }

  Future<void> _editList(ShareChoice current, List<Person> ready) async {
    if (current.mode == ShareMode.selected) {
      final Set<String>? picked = await ShareCardsPicker.show(
        context,
        people: ready,
        title: 'אילו כרטיסים לשתף עם $_first?',
        initial: current.selected,
      );
      if (picked == null || !mounted) return;
      final int added = picked.difference(current.selected).length;
      if (added > 0 &&
          !await SharingSettingsScreen.confirmAdding(context, count: added)) {
        return;
      }
      await _apply(
        picked.isEmpty
            ? ShareChoice.off
            : ShareChoice(ShareMode.selected, selected: picked),
      );
    } else if (current.mode == ShareMode.allExcept) {
      final Set<String>? out = await ShareCardsPicker.show(
        context,
        people: ready,
        title: 'מי לא ישותף עם $_first?',
        initial: current.excluded,
        confirmLabel: 'לא לשתף',
        allowEmpty: true,
      );
      if (out == null || !mounted) return;
      final int returned = current.excluded.difference(out).length;
      if (returned > 0 &&
          !await SharingSettingsScreen.confirmAdding(
            context,
            count: returned,
          )) {
        return;
      }
      await _apply(ShareChoice(ShareMode.allExcept, excluded: out));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    context.watch<PersonRepository>();
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    return Scaffold(
      appBar: AppBar(title: Text('מה אני משתף/ת עם $_first')),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          NetworkSharing.revision,
          MatchmakerShares.rows,
        ]),
        builder: (BuildContext context, _) {
          final ShareChoice choice = NetworkSharing.choiceFor(widget.readerUid);
          final List<Person> people = _candidates(context);
          final List<Person> ready = <Person>[];
          final List<Person> awaiting = <Person>[];
          for (final Person p in people) {
            switch (NetworkSharing.eligibilityOf(
              p,
              accessTo: access.accessTo,
            )) {
              case ShareEligibility.ready:
                ready.add(p);
              case ShareEligibility.awaitingConsent:
                awaiting.add(p);
              case ShareEligibility.incomplete:
              case ShareEligibility.notApplicable:
                break;
            }
          }
          final List<Person> shared = <Person>[
            for (final Person p in ready)
              if (choice.includes(p)) p,
          ];
          final bool theyAsked = MatchmakerShares.askedBy(widget.readerUid);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              if (theyAsked && !choice.isOn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: HomePaperCard(
                    stripe: AppColors.secondary,
                    child: Text(
                      '$_first ביקש/ה שתשתף/י איתו/ה כרטיסים. את/ה מחליט/ה מה.',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              Text(
                choice.isOn
                    ? 'את/ה משתף/ת עם $_first ${shared.length} כרטיסים'
                    : 'עוד לא שיתפת כרטיסים עם $_first',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'רק כרטיסים מלאים (תמונה וטקסט). לצפייה בלבד — בלי טלפון ובלי '
                'ההערות שלך, וכל פנייה עוברת דרכך. אפשר לשנות או להפסיק בכל רגע.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (final ShareMode m in <ShareMode>[
                ShareMode.all,
                ShareMode.selected,
                ShareMode.allExcept,
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ModeTile(
                    label: _modeLabel(m),
                    hint: switch (m) {
                      ShareMode.all =>
                        'כל ${ready.length} הכרטיסים המלאים, וכל כרטיס מלא שיתווסף',
                      ShareMode.selected => 'רק מי שבחרת',
                      ShareMode.allExcept => 'הכל, חוץ ממי שבחרת להשאיר בחוץ',
                      ShareMode.none => '',
                    },
                    selected: choice.mode == m,
                    onTap: _saving ? null : () => _choose(m),
                  ),
                ),
              if (choice.mode == ShareMode.selected ||
                  choice.mode == ShareMode.allExcept)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _saving ? null : () => _editList(choice, ready),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      choice.mode == ShareMode.selected
                          ? 'עריכת הבחירה (${choice.selected.length})'
                          : 'מי לא משותף (${choice.excluded.length})',
                    ),
                  ),
                ),
              if (choice.isOn) ...<Widget>[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _apply(ShareChoice.off),
                  icon: const Icon(Icons.link_off_rounded),
                  label: Text('הפסקת השיתוף עם $_first'),
                ),
              ],
              if (awaiting.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                Text(
                  'חברים שמנהלים כרטיס אישי וכיבו שיתוף בין שדכנים',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  'הכרטיס שלהם לא יוצג לשדכנים אחרים, גם אם בחרת "כל המאגר".',
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

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: selected ? AppColors.primaryLight : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.primary : theme.colorScheme.outline,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.primary : theme.colorScheme.outline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: theme.textTheme.titleSmall),
                    Text(hint, style: theme.textTheme.bodySmall),
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

class ShareCardsPicker extends StatefulWidget {
  const ShareCardsPicker({
    super.key,
    required this.people,
    required this.title,
    this.initial = const <String>{},
    this.confirmLabel = 'שיתוף',
    this.allowEmpty = false,
  });

  final List<Person> people;
  final String title;
  final Set<String> initial;
  final String confirmLabel;
  final bool allowEmpty;

  static Future<Set<String>?> show(
    BuildContext context, {
    required List<Person> people,
    required String title,
    Set<String> initial = const <String>{},
    String confirmLabel = 'שיתוף',
    bool allowEmpty = false,
  }) => showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.9,
      child: ShareCardsPicker(
        people: people,
        title: title,
        initial: initial,
        confirmLabel: confirmLabel,
        allowEmpty: allowEmpty,
      ),
    ),
  );

  @override
  State<ShareCardsPicker> createState() => _ShareCardsPickerState();
}

class _ShareCardsPickerState extends State<ShareCardsPicker> {
  late final Set<String> _picked = Set<String>.of(widget.initial);
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
          // Built lazily: a database of hundreds draws only what is on screen.
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
                onPressed: _picked.isEmpty && !widget.allowEmpty
                    ? null
                    : () => Navigator.pop(context, Set<String>.of(_picked)),
                child: Text(
                  _picked.isEmpty && !widget.allowEmpty
                      ? 'בחירת כרטיסים'
                      : '${widget.confirmLabel} (${_picked.length})',
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

/// "שיתוף עם שדכנים…" on one friend's profile: which matchmakers see this
/// card — one switch per matchmaker this one knows. Adding warns once;
/// removing never asks.
abstract final class PersonShareSheet {
  static Future<void> show(BuildContext context, Person person) async {
    if (!OfflineGuard.allow(context)) return;
    final CardAccessProvider access = context.read<CardAccessProvider>();
    if (NetworkSharing.eligibilityOf(person, accessTo: access.accessTo) !=
        ShareEligibility.ready) {
      AppNotice.show(
        context,
        'אפשר לשתף רק כרטיס מלא — תמונה וטקסט — של חבר/ה שמותר לשתף.',
        isError: true,
      );
      return;
    }
    await MatchmakerShares.refresh();
    if (!context.mounted) return;
    final List<KnownMatchmaker> known = knownMatchmakerGroups(
      access,
    ).all.toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) => FractionallySizedBox(
        heightFactor: 0.75,
        child: _PersonShareList(person: person, known: known, host: context),
      ),
    );
  }
}

class _PersonShareList extends StatefulWidget {
  const _PersonShareList({
    required this.person,
    required this.known,
    required this.host,
  });

  final Person person;
  final List<KnownMatchmaker> known;
  final BuildContext host;

  @override
  State<_PersonShareList> createState() => _PersonShareListState();
}

class _PersonShareListState extends State<_PersonShareList> {
  final Set<String> _busy = <String>{};

  Future<void> _toggle(KnownMatchmaker m, bool on) async {
    final ShareChoice c = NetworkSharing.choiceFor(m.uid);
    final String id = widget.person.id;
    if (on && !await SharingSettingsScreen.confirmAdding(context, count: 1)) {
      return;
    }
    final ShareChoice next = switch (c.mode) {
      ShareMode.none =>
        on ? ShareChoice(ShareMode.selected, selected: <String>{id}) : c,
      ShareMode.selected => ShareChoice(
        ShareMode.selected,
        selected: on
            ? <String>{...c.selected, id}
            : (<String>{...c.selected}..remove(id)),
      ),
      ShareMode.all =>
        on ? c : ShareChoice(ShareMode.allExcept, excluded: <String>{id}),
      ShareMode.allExcept => ShareChoice(
        ShareMode.allExcept,
        excluded: on
            ? (<String>{...c.excluded}..remove(id))
            : <String>{...c.excluded, id},
      ),
    };
    final ShareChoice applied =
        next.mode == ShareMode.selected && next.selected.isEmpty
        ? ShareChoice.off
        : next;
    if (!mounted) return;
    setState(() => _busy.add(m.uid));
    await NetworkSharing.setChoice(
      readerUid: m.uid,
      choice: applied,
      myName: widget.host.read<UserProfileProvider>().fullName ?? '',
      theirName: m.name,
      people: widget.host.read<PersonRepository>().getAll(),
      accessTo: widget.host.read<CardAccessProvider>().accessTo,
    );
    if (mounted) setState(() => _busy.remove(m.uid));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'מי רואה את הכרטיס של ${widget.person.firstName}?',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'שדכנים מאנשי הקשר שלך. צפייה בלבד — כל פנייה עוברת דרכך.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: widget.known.isEmpty
              ? const Center(child: Text('עוד לא נמצאו שדכנים מאנשי הקשר שלך.'))
              : ListView.builder(
                  itemCount: widget.known.length,
                  itemBuilder: (BuildContext context, int i) {
                    final KnownMatchmaker m = widget.known[i];
                    final bool on = NetworkSharing.choiceFor(
                      m.uid,
                    ).includes(widget.person);
                    return SwitchListTile(
                      value: on,
                      onChanged: _busy.contains(m.uid)
                          ? null
                          : (bool v) => _toggle(m, v),
                      title: Text(m.name.isEmpty ? 'שדכן/ית' : m.name),
                      secondary: KnownMatchmakerFace(
                        name: m.name,
                        photoUrl: m.photoUrl,
                        radius: 18,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
