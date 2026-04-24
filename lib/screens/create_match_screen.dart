import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/widgets/person_avatar.dart';
import 'package:shadchan/dialogs/person_picker_sheet.dart';

class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({super.key, this.preSelectedPersonId});

  final String? preSelectedPersonId;

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
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
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MatchRepository matchRepository = context.watch<MatchRepository>();
    final MatchIdea? existingMatch = _existingMatch(matchRepository);
    final bool canCreate =
        _personA != null && _personB != null && existingMatch == null;

    return Scaffold(
      appBar: AppBar(title: const Text('הצעה חדשה'), centerTitle: true),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                  child: Column(
                    children: <Widget>[
                      _SelectionCard(
                        label: 'בחור',
                        person: _personA,
                        onTap: () => _selectPerson(Gender.male),
                        onChange: () => _selectPerson(Gender.male),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: <Widget>[
                          Container(
                            width: 2,
                            height: 18,
                            color: theme.colorScheme.secondary.withValues(
                              alpha: 0.35,
                            ),
                          ),
                          Icon(
                            Icons.favorite,
                            color: theme.colorScheme.secondary,
                            size: 32,
                          ),
                          Container(
                            width: 2,
                            height: 18,
                            color: theme.colorScheme.secondary.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SelectionCard(
                        label: 'בחורה',
                        person: _personB,
                        onTap: () => _selectPerson(Gender.female),
                        onChange: () => _selectPerson(Gender.female),
                      ),
                      if (existingMatch != null) ...<Widget>[
                        const SizedBox(height: 20),
                        _DuplicateWarningCard(
                          nameA: _personA!.fullName.trim(),
                          nameB: _personB!.fullName.trim(),
                          onView: () =>
                              context.go('/matches/${existingMatch.id}'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canCreate ? _createMatch : null,
                    child: const Text('צור הצעה'),
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
    if (!mounted || newMatch == null) {
      return;
    }

    context.go('/matches/${newMatch.id}');
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
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.label,
    required this.person,
    required this.onTap,
    required this.onChange,
  });

  final String label;
  final Person? person;
  final VoidCallback onTap;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: CustomPaint(
        painter: person == null
            ? _DashedBorderPainter(color: theme.colorScheme.outline, radius: 20)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: person == null ? null : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: person == null
                ? null
                : Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
          ),
          child: person == null
              ? _EmptySelectionState(label: label)
              : _SelectedPersonState(
                  label: label,
                  person: person!,
                  onChange: onChange,
                ),
        ),
      ),
    );
  }
}

class _EmptySelectionState extends StatelessWidget {
  const _EmptySelectionState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(label, style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        Icon(Icons.add, color: theme.colorScheme.primary, size: 28),
        const SizedBox(height: 8),
        Text(
          label == 'בחור' ? 'בחרו בחור' : 'בחרו בחורה',
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _SelectedPersonState extends StatelessWidget {
  const _SelectedPersonState({
    required this.label,
    required this.person,
    required this.onChange,
  });

  final String label;
  final Person person;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> summaryParts = <String>[
      if (person.age != null) 'גיל ${person.age}',
      if (person.religiousLevel != null) person.religiousLevel!.displayName,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            PersonAvatar(person: person, radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    person.fullName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (summaryParts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        summaryParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            TextButton(onPressed: onChange, child: const Text('שנה')),
          ],
        ),
      ],
    );
  }
}

class _DuplicateWarningCard extends StatelessWidget {
  const _DuplicateWarningCard({
    required this.nameA,
    required this.nameB,
    required this.onView,
  });

  final String nameA;
  final String nameB;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '⚠️ כבר קיימת הצעה בין $nameA ל-$nameB',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onView, child: const Text('צפה בהצעה')),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final RRect rRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rRect);

    const double dashWidth = 8;
    const double dashSpace = 6;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double nextDistance = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, nextDistance), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
