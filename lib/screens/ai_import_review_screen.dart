import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/community_dialogs.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/parsed_person.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:uuid/uuid.dart';

/// The last stop before an import is written.
///
/// The rule the user chose is that a complete, fully stated record does not
/// need looking at, and everything else does — so this screen leads with what
/// needs attention and keeps the rest folded away. It still lists the folded
/// ones: not reviewing a record is a choice about effort, not a reason to be
/// unable to see what is about to enter the database.
class AiImportReviewScreen extends StatefulWidget {
  const AiImportReviewScreen({
    super.key,
    required this.people,
    this.failedBatches = 0,
  });

  final List<ParsedPerson> people;
  final int failedBatches;

  @override
  State<AiImportReviewScreen> createState() => _AiImportReviewScreenState();
}

class _AiImportReviewScreenState extends State<AiImportReviewScreen> {
  late final List<_Draft> _drafts = widget.people
      .map(_Draft.fromParsed)
      .toList();
  bool _showReady = false;
  bool _showDuplicates = false;
  bool _isSaving = false;
  bool _duplicatesResolved = false;

  List<_Draft> get _kept => _drafts
      .where((_Draft draft) => draft.keep && !draft.isDuplicate)
      .toList();
  List<_Draft> get _attention =>
      _kept.where((_Draft draft) => draft.needsAttention).toList();
  List<_Draft> get _ready =>
      _kept.where((_Draft draft) => !draft.needsAttention).toList();
  List<_Draft> get _duplicates =>
      _drafts.where((_Draft draft) => draft.isDuplicate).toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_duplicatesResolved) {
      return;
    }
    _duplicatesResolved = true;
    // Drawn on its own in widget tests, where there is no repository to compare
    // against — an absent provider means "nothing to be a duplicate of", not a
    // crash.
    try {
      _markDuplicates(context.read<PersonRepository>());
    } on ProviderNotFoundException {
      return;
    }
  }

  /// Marks the records the database already holds.
  ///
  /// Re-importing the same group is the normal case, not the exception — a
  /// matchmaker exports the chat again a month later for the twelve new cards
  /// in it. Matching is by phone first, since that is the one field that is
  /// genuinely the same person, and falls back to the full name for the cards
  /// that carry no number.
  void _markDuplicates(PersonRepository repository) {
    final Set<String> phones = <String>{};
    final Set<String> names = <String>{};
    for (final Person person in repository.getAll()) {
      final String? phone = PhoneUtils.normalizeForComparison(person.phone);
      if (phone != null) {
        phones.add(phone);
      }
      final String name = person.fullName.trim().toLowerCase();
      if (name.isNotEmpty) {
        names.add(name);
      }
    }

    for (final _Draft draft in _drafts) {
      final String? phone = PhoneUtils.normalizeForComparison(
        draft.parsed.phone,
      );
      final String name = '${draft.firstName.trim()} ${draft.lastName.trim()}'
          .trim()
          .toLowerCase();
      draft.isDuplicate =
          (phone != null && phones.contains(phone)) ||
          (phone == null && name.isNotEmpty && names.contains(name));
    }
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    setState(() => _isSaving = true);

    final PersonRepository repository = context.read<PersonRepository>();
    final DateTime now = DateTime.now();
    // One id for everybody saved by this tap. Its only reader is the personal
    // weekly record, which refuses to be set by a batch of more than
    // `CommunityProfileStore.bulkImportRecordLimit` — see
    // `ActivityStats.countBetween`. Stamped on every import however small,
    // because the limit is a property of the batch and is read later.
    final String batchId = const Uuid().v4();
    int added = 0;
    for (final _Draft draft in _kept) {
      await repository.add(draft.toPerson(now, importBatchId: batchId));
      added++;
    }

    if (!mounted) {
      return;
    }

    // Recorded before it is shown, so an import that finishes as the app is
    // killed is still acknowledged on the next launch — and so the milestones
    // this import crossed are pre-empted by it there rather than arriving
    // beside it. See `CommunityPromptGate`.
    CommunityProfileStore.noteBulkImport(added);
    final bool celebrated = await BulkImportNoteDialog.maybeShow(context);
    if (!mounted) {
      return;
    }
    // The snackbar and the note say the same thing; a small import gets the
    // snackbar, a large one gets the note, and neither ever gets both.
    if (!celebrated) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('נוספו $added אנשים למאגר')));
    }
    context.go('/people');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color slate = dark ? AppColors.primaryDarkDm : AppColors.primaryDark;
    final List<_Draft> attention = _attention;
    final List<_Draft> ready = _ready;
    final List<_Draft> duplicates = _duplicates;

    return Scaffold(
      appBar: AppBar(title: const Text('בדיקה לפני הוספה')),
      body: _drafts.isEmpty
          ? const Center(child: Text('לא נמצאו אנשים בקובץ'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                _Summary(
                  readyCount: ready.length,
                  attentionCount: attention.length,
                  failedBatches: widget.failedBatches,
                  slate: slate,
                ),
                const SizedBox(height: 20),
                if (attention.isNotEmpty) ...<Widget>[
                  _SectionTitle(
                    title: 'דורשים תשומת לב',
                    subtitle: 'משהו כאן לא נכתב במפורש בקובץ',
                    slate: slate,
                  ),
                  const SizedBox(height: 10),
                  for (final _Draft draft in attention)
                    _DraftCard(
                      draft: draft,
                      slate: slate,
                      dark: dark,
                      onChanged: () => setState(() {}),
                      onRemove: () => setState(() => draft.keep = false),
                    ),
                  const SizedBox(height: 12),
                ],
                if (ready.isNotEmpty) ...<Widget>[
                  _SectionTitle(
                    title: 'מוכנים להוספה (${ready.length})',
                    subtitle: 'נקראו במלואם מהקובץ',
                    slate: slate,
                    trailing: TextButton(
                      onPressed: () => setState(() => _showReady = !_showReady),
                      child: Text(_showReady ? 'הסתר' : 'הצג'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_showReady)
                    for (final _Draft draft in ready)
                      _DraftCard(
                        draft: draft,
                        slate: slate,
                        dark: dark,
                        onChanged: () => setState(() {}),
                        onRemove: () => setState(() => draft.keep = false),
                      ),
                ],
                if (duplicates.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _SectionTitle(
                    title: 'כבר במאגר (${duplicates.length})',
                    subtitle: 'לא ייווצרו שוב, כדי שלא ייווצרו כפילויות',
                    slate: slate,
                    trailing: TextButton(
                      onPressed: () =>
                          setState(() => _showDuplicates = !_showDuplicates),
                      child: Text(_showDuplicates ? 'הסתר' : 'הצג'),
                    ),
                  ),
                  if (_showDuplicates)
                    for (final _Draft draft in duplicates)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.how_to_reg_outlined,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${draft.firstName} ${draft.lastName}'.trim(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ],
            ),
      bottomNavigationBar: _drafts.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _kept.isEmpty || _isSaving ? null : _save,
                  child: Text(
                    _isSaving ? 'מוסיף…' : 'הוספת ${_kept.length} אנשים למאגר',
                  ),
                ),
              ),
            ),
    );
  }
}

/// One person on their way in, with the fields the review actually turns on.
///
/// Only name, age and gender are editable here. They are the three that decide
/// whether a record needed attention in the first place, so fixing them is the
/// whole job; anything else is easier to correct on the person's own screen
/// than in a list of eighty.
class _Draft {
  _Draft({
    required this.parsed,
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.gender,
    required bool genderUnconfirmed,
  }) : _genderUnconfirmed = genderUnconfirmed;

  factory _Draft.fromParsed(ParsedPerson parsed) => _Draft(
    parsed: parsed,
    firstName: parsed.card.firstName ?? '',
    lastName: parsed.card.lastName ?? '',
    age: parsed.card.age,
    gender: parsed.card.gender,
    // A gender the model worked out from a first name arrives unconfirmed, so
    // it lands in the attention list until the user says yes to it.
    genderUnconfirmed: parsed.inferredFields.contains(ParsedField.gender),
  );

  final ParsedPerson parsed;
  String firstName;
  String lastName;
  int? age;
  Gender? gender;
  bool keep = true;

  /// True when this person is already in the database. They are listed but
  /// never written, so re-reading the same chat adds only what is new.
  bool isDuplicate = false;

  /// True until the record is complete. A gender the model worked out from a
  /// first name counts as incomplete until the user leaves it or changes it —
  /// touching the control is the confirmation.
  bool get needsAttention =>
      firstName.trim().isEmpty ||
      age == null ||
      gender == null ||
      _genderUnconfirmed;

  bool _genderUnconfirmed;

  /// Why this record is being shown, in the user's terms.
  String? get reason {
    if (firstName.trim().isEmpty) {
      return 'חסר שם';
    }
    if (gender == null) {
      return 'לא ברור אם זה בחור או בחורה';
    }
    if (_genderUnconfirmed) {
      return 'המגדר שוער מהשם — נא לאשר';
    }
    if (age == null) {
      return 'חסר גיל';
    }
    return null;
  }

  /// True when the only thing missing is a yes to the model's guess.
  ///
  /// This needs its own affordance: the segmented control shows the guess as
  /// selected, and tapping the selected segment clears it rather than
  /// confirming it — so agreeing would otherwise be the one thing the user
  /// could not express.
  bool get needsGenderConfirmation => _genderUnconfirmed && gender != null;

  void confirmGender(Gender value) {
    gender = value;
    _genderUnconfirmed = false;
  }

  Person toPerson(DateTime now, {String? importBatchId}) => Person(
    id: const Uuid().v4(),
    importBatchId: importBatchId,
    // The photo the export carried, already on this device.
    photosPaths: <String>[?parsed.photoPath],
    firstName: firstName.trim(),
    lastName: lastName.trim(),
    gender: gender ?? Gender.unknown,
    manualAge: age,
    manualAgeUpdatedAt: age == null ? null : now,
    city: parsed.card.city,
    heightCm: parsed.card.heightCm,
    maritalStatus: parsed.card.maritalStatus,
    religiousLevel: parsed.religiousLevelOther != null
        ? ReligiousLevel.other
        : parsed.religiousLevel,
    religiousLevelOther: parsed.religiousLevelOther,
    phone: parsed.phone,
    // The card itself, word for word from the message it arrived in. The
    // structured fields above are a summary of it; this is the thing a
    // matchmaker actually forwards.
    description: parsed.description,
    inquiryContactName: parsed.card.inquiryContactName,
    inquiryContactPhone: parsed.card.inquiryContactPhone,
    source: 'ייבוא AI',
    createdAt: now,
    updatedAt: now,
  );
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.readyCount,
    required this.attentionCount,
    required this.failedBatches,
    required this.slate,
  });

  final int readyCount;
  final int attentionCount;
  final int failedBatches;
  final Color slate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'נמצאו ${readyCount + attentionCount} אנשים בקובץ',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          attentionCount == 0
              ? 'הכל נקרא במלואו. אפשר לעבור עליהם או פשוט להוסיף.'
              : '$attentionCount דורשים תשומת לב, $readyCount נקראו במלואם.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (failedBatches > 0) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'חלק מהקובץ לא נקרא ($failedBatches קטעים). ייתכן שחסרים '
                    'אנשים ברשימה — כדאי לבדוק מול הקובץ.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.slate,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Color slate;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: slate,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.slate,
    required this.dark,
    required this.onChanged,
    required this.onRemove,
  });

  final _Draft draft;
  final Color slate;
  final bool dark;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? reason = draft.reason;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Shown because a photo attached to the wrong person is the one
              // mistake here that is obvious at a glance and invisible later.
              if (draft.parsed.photoPath != null) ...<Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(draft.parsed.photoPath!),
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: TextFormField(
                  initialValue: <String>[
                    draft.firstName,
                    draft.lastName,
                  ].where((String part) => part.isNotEmpty).join(' '),
                  decoration: const InputDecoration(
                    labelText: 'שם',
                    isDense: true,
                  ),
                  onChanged: (String value) {
                    final List<String> parts = value.trim().split(
                      RegExp(r'\s+'),
                    );
                    draft
                      ..firstName = parts.isEmpty ? '' : parts.first
                      ..lastName = parts.length > 1
                          ? parts.sublist(1).join(' ')
                          : '';
                    onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip: 'הסרה מהרשימה',
                icon: const Icon(Icons.close_rounded),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: draft.age?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'גיל',
                    isDense: true,
                  ),
                  onChanged: (String value) {
                    draft.age = int.tryParse(value);
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<Gender>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<Gender>>[
                    ButtonSegment<Gender>(
                      value: Gender.male,
                      label: Text('בחור'),
                    ),
                    ButtonSegment<Gender>(
                      value: Gender.female,
                      label: Text('בחורה'),
                    ),
                  ],
                  selected: draft.gender == null
                      ? <Gender>{}
                      : <Gender>{draft.gender!},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (Set<Gender> selection) {
                    if (selection.isNotEmpty) {
                      draft.confirmGender(selection.first);
                      onChanged();
                    }
                  },
                ),
              ),
            ],
          ),
          if (_details(draft).isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _details(draft),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (reason != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                if (draft.needsGenderConfirmation)
                  TextButton(
                    onPressed: () {
                      draft.confirmGender(draft.gender!);
                      onChanged();
                    },
                    child: const Text('נכון'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The fields that came along but are not worth editing here — shown so the
  /// user can see the record is more than the three boxes above it.
  static String _details(_Draft draft) {
    return <String>[
      if (draft.parsed.card.city != null) draft.parsed.card.city!,
      if (draft.parsed.card.heightCm != null)
        '${draft.parsed.card.heightCm} ס״מ',
      if (draft.parsed.card.maritalStatus != null)
        draft.parsed.card.maritalStatus!.displayNameFor(
          draft.gender ?? Gender.male,
        ),
    ].join(' · ');
  }
}
