import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';
import 'package:shadchan/dialogs/suggested_matches_sheet.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/widgets/person_avatar.dart';

/// How the screen should open the other side of the proposal when it is
/// reached from a candidate's "הוסף הצעה" shortcut.
enum CreateMatchPick { database, outsideDatabase }

/// "רעיון חדש": pick a man, pick a woman, optionally jot down a thought, and
/// the proposal is created straight away.
class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({
    super.key,
    this.preSelectedPersonId,
    this.initialPick,
  });

  final String? preSelectedPersonId;

  /// Opens the picker for the missing side as soon as the screen appears.
  final CreateMatchPick? initialPick;

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  final TextEditingController _noteController = TextEditingController();

  Person? _personA;
  Person? _personB;
  bool _didApplyPreSelection = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didApplyPreSelection) {
      return;
    }

    final String? preSelectedPersonId = widget.preSelectedPersonId;
    if (preSelectedPersonId != null && preSelectedPersonId.isNotEmpty) {
      final Person? person = context.read<PersonRepository>().getById(
        preSelectedPersonId,
      );
      if (person != null) {
        if (person.gender == Gender.male) {
          _personA = person;
        } else {
          _personB = person;
        }
      }
    }

    _didApplyPreSelection = true;

    final CreateMatchPick? pick = widget.initialPick;
    if (pick != null && (_personA == null) != (_personB == null)) {
      final Gender missing = _personA == null ? Gender.male : Gender.female;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        switch (pick) {
          case CreateMatchPick.database:
            _selectPerson(missing);
          case CreateMatchPick.outsideDatabase:
            _addOutsideDatabase(missing);
        }
      });
    }
  }

  Future<void> _addOutsideDatabase(Gender gender) async {
    final Person? person = await PersonPickerSheet.addOutsideDatabase(
      context,
      gender: gender,
    );
    if (person == null || !mounted) {
      return;
    }

    setState(() {
      if (gender == Gender.male) {
        _personA = person;
      } else {
        _personB = person;
      }
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    // Watched so a person edited mid-flow refreshes their card here.
    context.watch<PersonRepository>();

    final MatchIdea? existingMatch = _existingMatch(matchRepository);
    final bool canCreate =
        _personA != null && _personB != null && existingMatch == null;

    // The suggestions shortcut only makes sense while one side is still open.
    final Person? suggestionSource = _personA == null && _personB != null
        ? _personB
        : _personB == null && _personA != null
        ? _personA
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('רעיון חדש'), centerTitle: true),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    children: <Widget>[
                      _Header(),
                      const SizedBox(height: 16),
                      _SelectionCard(
                        title: 'בחירת בחור',
                        emptyLabel: 'בחר בחור',
                        gender: Gender.male,
                        person: _personA,
                        onTap: () => _selectPerson(Gender.male),
                      ),
                      const _HeartDivider(),
                      _SelectionCard(
                        title: 'בחירת בחורה',
                        emptyLabel: 'בחר בחורה',
                        gender: Gender.female,
                        person: _personB,
                        onTap: () => _selectPerson(Gender.female),
                      ),
                      if (suggestionSource != null) ...<Widget>[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openSuggestions(suggestionSource),
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: Text(
                              'התאמות עבור ${_shortName(suggestionSource)}',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _NoteField(controller: _noteController),
                      if (existingMatch != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _DuplicateWarningCard(
                          onView: () =>
                              context.go('/matches/${existingMatch.id}'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canCreate ? _createMatch : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('הוספת הצעה'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  MatchIdea? _existingMatch(MatchRepository matchRepository) {
    if (_personA == null || _personB == null) {
      return null;
    }

    final ({Person male, Person female}) orderedPeople = _orderedPeople(
      _personA!,
      _personB!,
    );

    return matchRepository.findExisting(
      orderedPeople.male.id,
      orderedPeople.female.id,
    );
  }

  Future<void> _selectPerson(Gender gender) async {
    final Set<String> excludeIds = <String>{
      if (gender == Gender.male && _personB != null) _personB!.id,
      if (gender == Gender.female && _personA != null) _personA!.id,
    };

    final Person? selectedPerson = await PersonPickerSheet.show(
      context,
      title: gender == Gender.male ? 'בחירת בחור' : 'בחירת בחורה',
      filterGender: gender,
      excludeIds: excludeIds,
      allowCreateOutsideDatabase: true,
    );

    if (selectedPerson == null || !mounted) {
      return;
    }

    setState(() {
      if (gender == Gender.male) {
        _personA = selectedPerson;
      } else {
        _personB = selectedPerson;
      }
    });
  }

  /// Picking a suggestion fills in whichever side is still empty.
  Future<void> _openSuggestions(Person source) async {
    final Person? selected = await SuggestedMatchesSheet.show(
      context,
      source: source,
    );
    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      if (selected.gender == Gender.male) {
        _personA = selected;
      } else {
        _personB = selected;
      }
    });
  }

  Future<void> _createMatch() async {
    final Person? personA = _personA;
    final Person? personB = _personB;
    if (personA == null || personB == null) {
      return;
    }

    final ({Person male, Person female}) orderedPeople = _orderedPeople(
      personA,
      personB,
    );
    final MatchRepository matchRepository = context.read<MatchRepository>();
    final MatchIdea? newMatch = await matchRepository.create(
      orderedPeople.male.id,
      orderedPeople.female.id,
    );
    if (newMatch == null) {
      return;
    }

    final String note = _noteController.text.trim();
    if (note.isNotEmpty) {
      await matchRepository.addNote(newMatch.id, note);
    }

    if (!mounted) {
      return;
    }
    context.go('/matches/${newMatch.id}?justCreated=true');
  }

  ({Person male, Person female}) _orderedPeople(Person first, Person second) {
    if (first.gender == Gender.male && second.gender == Gender.female) {
      return (male: first, female: second);
    }

    if (first.gender == Gender.female && second.gender == Gender.male) {
      return (male: second, female: first);
    }

    return (male: first, female: second);
  }

  static String _shortName(Person person) {
    final String first = person.firstName.trim();
    return first.isNotEmpty ? first : person.fullName.trim();
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.favorite,
              size: 14,
              color: theme.colorScheme.secondary.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'על מי חשבת היום?',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.favorite,
              size: 14,
              color: theme.colorScheme.secondary.withValues(alpha: 0.5),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'בחר שני חברים כדי ליצור רעיון חדש',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// One side of the proposal: an empty "בחר…" row before a choice is made, and
/// the person's photo, name and age afterwards.
class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.title,
    required this.emptyLabel,
    required this.gender,
    required this.person,
    required this.onTap,
  });

  final String title;
  final String emptyLabel;
  final Gender gender;
  final Person? person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = AppColors.genderAccent(gender, dark: dark);
    final Person? selected = person;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.person, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Material(
            color: accent.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: selected == null
                    ? _EmptyRow(label: emptyLabel, accent: accent)
                    : _SelectedRow(person: selected, onChange: onTap),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 22,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.person_outline,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.search, size: 16, color: accent),
              const SizedBox(width: 4),
              Text(
                'חיפוש',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectedRow extends StatelessWidget {
  const _SelectedRow({required this.person, required this.onChange});

  final Person person;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? age = person.age;

    return Row(
      children: <Widget>[
        PersonAvatar(person: person, radius: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                person.fullName.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (age != null)
                Text(
                  'גיל $age',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        TextButton(
          onPressed: onChange,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: const Text('שינוי'),
        ),
      ],
    );
  }
}

/// The heart between the two cards, with a soft dotted line to each side.
class _HeartDivider extends StatelessWidget {
  const _HeartDivider();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = theme.colorScheme.secondary.withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(child: CustomPaint(painter: _DottedLinePainter(color: color), size: const Size.fromHeight(1))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.favorite,
              size: 26,
              color: theme.colorScheme.secondary,
            ),
          ),
          Expanded(child: CustomPaint(painter: _DottedLinePainter(color: color), size: const Size.fromHeight(1))),
        ],
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  const _DottedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    const double dash = 2;
    const double gap = 6;
    final double y = size.height / 2;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Optional free text saved as the proposal's first journal note.
class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(
              Icons.sticky_note_2_outlined,
              size: 20,
              color: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                border: InputBorder.none,
                labelText: 'הערות או פרטים שחשוב לזכור',
                hintText: 'הערות או פרטים שחשוב לזכור...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateWarningCard extends StatelessWidget {
  const _DuplicateWarningCard({required this.onView});

  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.info_outline,
                size: 20,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ההצעה הזו כבר קיימת במערכת',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: onView,
              child: const Text('מעבר להצעה הקיימת'),
            ),
          ),
        ],
      ),
    );
  }
}
