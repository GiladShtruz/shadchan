import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/core/constants/enums.dart';
import 'package:shadchan/core/theme/app_colors.dart';
import 'package:shadchan/core/utils/date_utils.dart';
import 'package:shadchan/core/utils/hebrew_date_utils.dart';
import 'package:shadchan/core/utils/share_utils.dart';
import 'package:shadchan/data/models/match_idea.dart';
import 'package:shadchan/data/models/person.dart';
import 'package:shadchan/data/repositories/match_repository.dart';
import 'package:shadchan/data/repositories/person_repository.dart';
import 'package:shadchan/presentation/shared/widgets/confirm_dialog.dart';
import 'package:shadchan/presentation/shared/widgets/person_avatar.dart';
import 'package:shadchan/presentation/shared/widgets/person_picker_sheet.dart';
import 'package:shadchan/presentation/shared/widgets/photo_viewer.dart';
import 'package:shadchan/presentation/shared/widgets/section_header.dart';
import 'package:url_launcher/url_launcher.dart';

class PersonDetailScreen extends StatelessWidget {
  const PersonDetailScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final PersonRepository personRepository = context.watch<PersonRepository>();
    final MatchRepository matchRepository = context.watch<MatchRepository>();

    final Person? person = personRepository.getById(personId);
    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('פרטי איש קשר'), centerTitle: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.person_off_outlined,
                  size: 72,
                  color: colorScheme.primaryContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  'האדם לא נמצא',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/people'),
                  child: const Text('חזרה לרשימה'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final List<MatchIdea> relatedMatches = matchRepository.getByPersonId(
      personId,
    );
    final List<String> quickInfoLabels = _buildQuickInfoLabels(person);

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            stretch: true,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Hero(
                  tag: 'person-${person.id}',
                  child: PersonAvatar(person: person, radius: 16),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    person.fullName.trim(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'שיתוף',
                onPressed: () => _sharePerson(context, person),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'עריכה',
                onPressed: () => context.push('/people/${person.id}/edit'),
              ),
              PopupMenuButton<String>(
                onSelected: (String value) async {
                  if (value != 'delete') {
                    return;
                  }

                  final bool shouldDelete = await _confirmDelete(
                    context,
                    person,
                  );
                  if (!shouldDelete) {
                    return;
                  }

                  await personRepository.delete(person.id);
                  if (context.mounted) {
                    context.go('/people');
                  }
                },
                itemBuilder: (BuildContext context) {
                  return const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('מחיקה'),
                    ),
                  ];
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _DetailHeader(person: person),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (quickInfoLabels.isNotEmpty)
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        scrollDirection: Axis.horizontal,
                        itemCount: quickInfoLabels.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final String label = quickInfoLabels[index];
                          return _QuickInfoChip(
                            label: label,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            textColor: theme.colorScheme.primary,
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          ElevatedButton.icon(
                            onPressed: () =>
                                _openMatchProposal(context, person),
                            icon: const Icon(Icons.favorite),
                            label: const Text('פתח הצעה'),
                          ),
                          const SizedBox(width: 12),
                          _FavoriteToggleButton(
                            isFavorite: person.isFavorite,
                            onPressed: () =>
                                personRepository.toggleFavorite(person.id),
                            activeColor: colorScheme.secondary,
                            inactiveColor: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _Section(
                    title: 'תמונות',
                    trailing: TextButton(
                      onPressed: () => _pickAndSavePhoto(context, person),
                      child: const Text('הוספה'),
                    ),
                    child: _PhotosSection(
                      person: person,
                      onTapPhoto: (int index) =>
                          _openPhotoViewer(context, person, index),
                    ),
                  ),
                  _Section(
                    title: 'תיאור',
                    trailing: TextButton(
                      onPressed: () =>
                          context.push('/people/${person.id}/edit'),
                      child: const Text('עריכה'),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        (person.description ?? '').trim().isNotEmpty
                            ? person.description!.trim()
                            : 'אין תיאור',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  _Section(
                    title: 'הערות פרטיות',
                    trailing: TextButton(
                      onPressed: () =>
                          context.push('/people/${person.id}/edit'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          const Text('עריכה'),
                        ],
                      ),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer.withValues(
                          alpha: 0.3,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        (person.notes ?? '').trim().isNotEmpty
                            ? person.notes!.trim()
                            : 'אין הערות',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  _Section(
                    title: 'הצעות קשורות',
                    child: _RelatedMatchesSection(
                      person: person,
                      matches: relatedMatches,
                      personRepository: personRepository,
                    ),
                  ),
                  _Section(
                    title: 'פרטים נוספים',
                    child: Column(
                      children: <Widget>[
                        if (_birthdayMessage(person, theme)
                            case final Widget birthdayBanner)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: birthdayBanner,
                          ),
                        _DetailRow(
                          label: 'מגדר',
                          value: person.gender.displayName,
                        ),
                        _DetailRow(
                          label: 'תאריך לידה',
                          value: person.birthDate != null
                              ? AppDateUtils.formatDate(person.birthDate!)
                              : 'לא הוזן',
                        ),
                        _DetailRow(
                          label: 'תאריך לידה עברי',
                          value: _hebrewBirthText(person),
                        ),
                        _DetailRow(
                          label: 'נוצר',
                          value: AppDateUtils.formatDate(person.createdAt),
                        ),
                        _DetailRow(
                          label: 'עודכן',
                          value: AppDateUtils.timeAgo(person.updatedAt),
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _hebrewBirthText(Person person) {
    final int? year = person.hebrewBirthYear;
    final int? month = person.hebrewBirthMonth;
    final int? day = person.hebrewBirthDay;
    if (year == null || month == null || day == null) {
      return 'לא הוזן';
    }
    final String formatted = HebrewDateUtils.format(
      year: year,
      month: month,
      day: day,
    );
    return formatted.isNotEmpty ? formatted : 'לא הוזן';
  }

  List<String> _buildQuickInfoLabels(Person person) {
    return <String>[
      '${person.profileStatus.emoji} ${person.profileStatus.displayName}',
      if (person.age != null) 'גיל ${person.age}',
      if (person.religiousLevel != null) person.religiousLevel!.displayName,
    ];
  }

  Widget? _birthdayMessage(Person person, ThemeData theme) {
    final int? hebrewMonth = person.hebrewBirthMonth;
    final int? hebrewDay = person.hebrewBirthDay;
    if (hebrewMonth != null &&
        hebrewDay != null &&
        HebrewDateUtils.isBirthdayToday(month: hebrewMonth, day: hebrewDay)) {
      return Text(
        '🎉 היום יום ההולדת העברי!',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final DateTime? birthDate = person.birthDate;
    if (birthDate == null) {
      return null;
    }

    if (AppDateUtils.isBirthdayToday(birthDate)) {
      return Text(
        '🎉 היום יום ההולדת!',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final int? daysUntil = AppDateUtils.daysUntilBirthday(birthDate);
    if (daysUntil != null && daysUntil > 0 && daysUntil <= 7) {
      return Text(
        '🎂 יום הולדת בעוד $daysUntil ימים',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return null;
  }

  Future<void> _callPerson(BuildContext context, String phone) async {
    final Uri uri = Uri(scheme: 'tel', path: phone);
    final bool launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      _showSnackBar(context, 'לא ניתן לפתוח את החיוג כרגע');
    }
  }

  Future<void> _pickAndSavePhoto(BuildContext context, Person person) async {
    final PersonRepository repository = context.read<PersonRepository>();
    const ImageSource source = ImageSource.gallery;

    if (!context.mounted) {
      return;
    }

    final bool hasPermission = await _ensureMediaPermission(context);
    if (!hasPermission || !context.mounted) {
      return;
    }

    try {
      final XFile? pickedFile = await ImagePicker().pickImage(source: source);
      if (pickedFile == null || !context.mounted) {
        return;
      }

      final Directory documentsDirectory =
          await getApplicationDocumentsDirectory();
      final Directory photosDirectory = Directory(
        '${documentsDirectory.path}${Platform.pathSeparator}photos',
      );

      if (!photosDirectory.existsSync()) {
        photosDirectory.createSync(recursive: true);
      }

      final String targetPath =
          '${photosDirectory.path}${Platform.pathSeparator}${person.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await File(pickedFile.path).copy(targetPath);

      person.photosPaths = List<String>.from(person.photosPaths)
        ..add(targetPath);
      await repository.update(person);

      if (context.mounted) {
        _showSnackBar(context, 'התמונה נוספה בהצלחה');
      }
    } on PlatformException catch (error) {
      if (!context.mounted) {
        return;
      }

      if (_looksLikePermissionError(error)) {
        await _showPermissionExplanationDialog(context);
        return;
      }

      _showSnackBar(context, 'לא הצלחנו לבחור תמונה כרגע');
    } catch (_) {
      if (context.mounted) {
        _showSnackBar(context, 'לא הצלחנו לשמור את התמונה');
      }
    }
  }

  Future<void> _openPhotoViewer(
    BuildContext context,
    Person person,
    int initialIndex,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return PhotoViewer(
            personId: person.id,
            photoPaths: person.photosPaths,
            initialIndex: initialIndex,
          );
        },
      ),
    );
  }

  Future<void> _openMatchProposal(
    BuildContext context,
    Person currentPerson,
  ) async {
    final Gender oppositeGender = currentPerson.gender == Gender.male
        ? Gender.female
        : Gender.male;

    final Person? selectedPerson = await PersonPickerSheet.show(
      context,
      title: 'בחרו ${oppositeGender.displayName}',
      filterGender: oppositeGender,
      excludeIds: <String>{currentPerson.id},
    );

    if (selectedPerson == null || !context.mounted) {
      return;
    }

    final Person male = currentPerson.gender == Gender.male
        ? currentPerson
        : selectedPerson;
    final Person female = currentPerson.gender == Gender.female
        ? currentPerson
        : selectedPerson;

    final MatchRepository matchRepository = context.read<MatchRepository>();
    final MatchIdea? existingMatch = matchRepository.findExisting(
      male.id,
      female.id,
    );

    if (existingMatch != null) {
      final bool shouldView = await _showDuplicateMatchDialog(
        context,
        nameA: male.fullName.trim(),
        nameB: female.fullName.trim(),
      );

      if (shouldView && context.mounted) {
        context.push('/matches/${existingMatch.id}');
      }
      return;
    }

    final MatchIdea? newMatch = await matchRepository.create(
      male.id,
      female.id,
    );
    if (newMatch != null && context.mounted) {
      context.push('/matches/${newMatch.id}');
    }
  }

  Future<void> _sharePerson(BuildContext context, Person person) async {
    try {
      await ShareUtils.sharePerson(person);
    } catch (_) {
      if (context.mounted) {
        _showSnackBar(context, 'לא ניתן לשתף כרגע');
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context, Person person) async {
    final MatchRepository matchRepository = context.read<MatchRepository>();
    final int activeMatches = matchRepository
        .getByPersonId(person.id)
        .where((MatchIdea match) => !match.status.isArchived)
        .length;
    final String warning = activeMatches > 0
        ? '\n\nלאדם זה יש $activeMatches הצעות פעילות. ההצעות לא יימחקו.'
        : '';

    return ConfirmDialog.show(
      context,
      title: 'למחוק את האיש קשר?',
      message: 'האם למחוק את ${person.fullName.trim()}?$warning',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
  }

  Future<bool> _showDuplicateMatchDialog(
    BuildContext context, {
    required String nameA,
    required String nameB,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('כבר קיימת הצעה'),
          content: Text('כבר קיימת הצעה בין $nameA ל-$nameB'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('סגור'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('צפה בהצעה'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _ensureMediaPermission(BuildContext context) async {
    if (Platform.isAndroid) {
      // `image_picker` uses the system photo picker / intents on Android,
      // so pre-requesting gallery permissions here can incorrectly block
      // the flow on newer Android versions.
      return true;
    }

    final PermissionStatus status = await _requestGalleryPermission();

    if (status.isGranted || status.isLimited) {
      return true;
    }

    if (context.mounted) {
      await _showPermissionExplanationDialog(
        context,
        openSettingsAction: status.isPermanentlyDenied || status.isRestricted,
      );
    }

    return false;
  }

  Future<PermissionStatus> _requestGalleryPermission() async {
    return Permission.photos.request();
  }

  bool _looksLikePermissionError(PlatformException error) {
    final String combined = '${error.code} ${error.message ?? ''}'
        .toLowerCase();
    return combined.contains('denied') || combined.contains('permission');
  }

  Future<void> _showPermissionExplanationDialog(
    BuildContext context, {
    bool openSettingsAction = false,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('נדרשת הרשאה'),
          content: const Text(
            'כדי להוסיף תמונה צריך לאשר גישה לגלריה בהגדרות המכשיר.',
          ),
          actions: <Widget>[
            if (openSettingsAction)
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await openAppSettings();
                },
                child: const Text('פתיחת הגדרות'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('הבנתי'),
            ),
          ],
        );
      },
    );
  }
}

class _QuickInfoChip extends StatelessWidget {
  const _QuickInfoChip({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final File? photoFile = _firstExistingPhoto(person.photosPaths);

    if (photoFile != null) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.file(photoFile, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x00000000), Color(0x99000000)],
              ),
            ),
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.colorScheme.primary,
            theme.colorScheme.primaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            person.fullName.trim(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  File? _firstExistingPhoto(List<String> paths) {
    for (final String path in paths) {
      final File file = File(path);
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }
}

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({required this.person, required this.onTapPhoto});

  final Person person;
  final ValueChanged<int> onTapPhoto;

  @override
  Widget build(BuildContext context) {
    if (person.photosPaths.isEmpty) {
      return Text('אין תמונות', style: Theme.of(context).textTheme.bodyMedium);
    }

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: person.photosPaths.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int index) {
          final String path = person.photosPaths[index];
          final File file = File(path);
          return GestureDetector(
            onTap: () => onTapPhoto(index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: file.existsSync()
                  ? Image.file(
                      file,
                      width: 100,
                      height: 120,
                      cacheWidth: 200,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 100,
                      height: 120,
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _RelatedMatchesSection extends StatelessWidget {
  const _RelatedMatchesSection({
    required this.person,
    required this.matches,
    required this.personRepository,
  });

  final Person person;
  final List<MatchIdea> matches;
  final PersonRepository personRepository;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return Text(
        'אין הצעות עדיין',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    return Column(
      children: matches.map((MatchIdea match) {
        final String otherPersonId = match.personAId == person.id
            ? match.personBId
            : match.personAId;
        final Person? otherPerson = personRepository.getById(otherPersonId);
        final String otherName = otherPerson?.fullName.trim().isNotEmpty == true
            ? otherPerson!.fullName.trim()
            : 'אדם נמחק';

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () => context.push('/matches/${match.id}'),
              title: Text(
                otherName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _StatusChip(status: match.status),
            ),
          ),
        );
      }).toList(),
    );
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

class _Section extends StatelessWidget {
  const _Section({this.title, required this.child, this.trailing});

  final String? title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: title ?? '', trailing: trailing),
          child,
        ],
      ),
    );
  }
}

class _FavoriteToggleButton extends StatefulWidget {
  const _FavoriteToggleButton({
    required this.isFavorite,
    required this.onPressed,
    required this.activeColor,
    required this.inactiveColor,
  });

  final bool isFavorite;
  final Future<void> Function() onPressed;
  final Color activeColor;
  final Color inactiveColor;

  @override
  State<_FavoriteToggleButton> createState() => _FavoriteToggleButtonState();
}

class _FavoriteToggleButtonState extends State<_FavoriteToggleButton> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.isFavorite ? 'הסר ממועדפים' : 'הוסף למועדפים',
      onPressed: _handlePressed,
      icon: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 180),
        child: Icon(
          widget.isFavorite ? Icons.star : Icons.star_outline,
          color: widget.isFavorite ? widget.activeColor : widget.inactiveColor,
        ),
      ),
    );
  }

  Future<void> _handlePressed() async {
    setState(() {
      _scale = 1.3;
    });

    await widget.onPressed();
    if (!mounted) {
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _scale = 1;
      });
    });
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );

    if (isLast) {
      return row;
    }

    return Column(
      children: <Widget>[
        row,
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
      ],
    );
  }
}
