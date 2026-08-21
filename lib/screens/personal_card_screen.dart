import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/person_photo_editor.dart';

/// "כרטיס השידוכים שלי" — the single matchmaker's own card, on a page of its
/// own.
///
/// It used to be a preview card wedged into the top of the profile, above the
/// settings, whether or not anything had ever been written in it. That put a
/// mostly-empty box between somebody and everything else on their page, and it
/// gave the card no room to be read — four lines and an ellipsis.
///
/// Now the profile carries one row, and this is what it opens. **Two states,
/// one screen**: a card that exists is shown in full with the only two things
/// anybody does with it — send it, change it — and a card that does not is an
/// invitation to write one, which is exactly what somebody who tapped that row
/// came for either way.
class PersonalCardScreen extends StatefulWidget {
  const PersonalCardScreen({super.key});

  @override
  State<PersonalCardScreen> createState() => _PersonalCardScreenState();
}

class _PersonalCardScreenState extends State<PersonalCardScreen> {
  @override
  Widget build(BuildContext context) {
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    final Gender? gender = profile.gender;
    final String card = (profile.personalCard ?? '').trim();
    final List<String> photos = profile.personalCardPhotos;
    final bool hasCard = card.isNotEmpty || photos.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('כרטיס השידוכים שלי'),
        centerTitle: true,
        actions: <Widget>[
          if (hasCard)
            IconButton(
              onPressed: () => _edit(profile),
              tooltip: 'עריכת הכרטיס',
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: hasCard
            ? _CardView(
                card: card,
                photos: photos,
                onEdit: () => _edit(profile),
                onShare: () => _share(profile),
              )
            : _EmptyCardView(gender: gender, onCreate: () => _edit(profile)),
      ),
    );
  }

  Future<void> _edit(UserProfileProvider profile) =>
      openPersonalCardEditor(context, profile);

  Future<void> _share(UserProfileProvider profile) async {
    final String card = profile.personalCard ?? '';
    final List<String> photos = profile.personalCardPhotos;
    if (card.isEmpty && photos.isEmpty) {
      return;
    }
    await ShareUtils.shareText(card, photoPaths: photos);
  }
}

/// Opens the editor and writes whatever comes back.
///
/// A free function because two screens need it — this one and the profile row
/// that opens straight into writing a first card — and because the deletion of
/// dropped photo files belongs with the save, not with either caller.
Future<void> openPersonalCardEditor(
  BuildContext context,
  UserProfileProvider profile,
) async {
  final List<String> initialPhotos = profile.personalCardPhotos;
  final _PersonalCardDraft? draft =
      await showModalBottomSheet<_PersonalCardDraft>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (BuildContext sheetContext) {
          return _PersonalCardEditorSheet(
            initialText: profile.personalCard ?? '',
            initialPhotos: initialPhotos,
          );
        },
      );
  if (draft == null) {
    return;
  }
  await profile.setPersonalCardContent(
    text: draft.text,
    photoPaths: draft.photos,
  );
  PhotoPickerService.deletePhotoFiles(
    initialPhotos.where((String path) => !draft.photos.contains(path)),
  );
}

/// The card as it will be read by whoever it is sent to.
class _CardView extends StatelessWidget {
  const _CardView({
    required this.card,
    required this.photos,
    required this.onEdit,
    required this.onShare,
  });

  final String card;
  final List<String> photos;
  final VoidCallback onEdit;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            children: <Widget>[
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  child: Text(
                    card.isEmpty ? 'הכרטיס שלך שמור כאן.' : card,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                  ),
                ),
              ),
              if (photos.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                PersonalCardPhotos(photos: photos),
              ],
            ],
          ),
        ),
        // The two actions, pinned where a thumb reaches them rather than at the
        // end of however long the card happens to be.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('עריכה'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('שיתוף'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What somebody who has never written a card sees: the reason to write one,
/// and the way to.
class _EmptyCardView extends StatelessWidget {
  const _EmptyCardView({required this.gender, required this.onCreate});

  final Gender? gender;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
              child: Icon(
                Icons.badge_outlined,
                size: 44,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'עוד לא מילאת את הכרטיס שלך',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'כשהכרטיס שלך שמור כאן, אפשר לשלוח אותו בהודעה אחת לכל מי '
                    '{שיחשוב|שתחשוב} עליך — בלי לחפש אותו כל פעם מחדש.'
                .forGender(gender),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('מילוי הכרטיס שלי'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every photo saved on the personal card, laid out under its text.
///
/// The card used to show its text and nothing else, so the only way to find out
/// which photos were attached — or how many — was to open the editor. That is
/// the wrong moment to discover it: this card exists to be *shared*, the photos
/// go with it, and nobody should have to send it once to learn what it sends.
/// They are all here, in the order they will go out in, with the first one
/// marked because that is the one that leads.
class PersonalCardPhotos extends StatelessWidget {
  const PersonalCardPhotos({super.key, required this.photos});

  final List<String> photos;

  static const double _thumbSize = 74;

  Future<void> _open(BuildContext context, int index) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext dialogContext) =>
          _PersonalCardPhotoViewer(photos: photos, initialIndex: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.photo_library_outlined,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                photos.length == 1
                    ? 'תמונה אחת תישלח יחד עם הכרטיס'
                    : '${photos.length} תמונות יישלחו יחד עם הכרטיס',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _thumbSize,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              return _PersonalCardThumb(
                path: photos[index],
                isFirst: index == 0,
                size: _thumbSize,
                onTap: () => _open(context, index),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PersonalCardThumb extends StatelessWidget {
  const _PersonalCardThumb({
    required this.path,
    required this.isFirst,
    required this.size,
    required this.onTap,
  });

  final String path;
  final bool isFirst;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox.square(
      dimension: size,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.file(
                File(path),
                fit: BoxFit.cover,
                // A photo whose file has gone is shown as a gap rather than as
                // a red error box on the matchmaker's own profile.
                errorBuilder: (_, _, _) => Icon(
                  Icons.broken_image_outlined,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (isFirst)
                PositionedDirectional(
                  start: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    color: Colors.black54,
                    child: const Text(
                      'ראשית',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The photos at full size, swipeable, on a dark ground.
class _PersonalCardPhotoViewer extends StatelessWidget {
  const _PersonalCardPhotoViewer({
    required this.photos,
    required this.initialIndex,
  });

  final List<String> photos;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: photos.length,
              itemBuilder: (BuildContext context, int index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.file(File(photos[index]), fit: BoxFit.contain),
                  ),
                );
              },
            ),
          ),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 8,
            end: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'סגירה',
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalCardDraft {
  const _PersonalCardDraft({required this.text, required this.photos});

  final String text;
  final List<String> photos;
}

class _PersonalCardEditorSheet extends StatefulWidget {
  const _PersonalCardEditorSheet({
    required this.initialText,
    required this.initialPhotos,
  });

  final String initialText;
  final List<String> initialPhotos;

  @override
  State<_PersonalCardEditorSheet> createState() =>
      _PersonalCardEditorSheetState();
}

class _PersonalCardEditorSheetState extends State<_PersonalCardEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  late final List<String> _photos = List<String>.of(widget.initialPhotos);
  final Set<String> _newPhotos = <String>{};
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    if (!_submitted) {
      PhotoPickerService.deletePhotoFiles(_newPhotos);
    }
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final List<String> added = await PhotoPickerService.pickPhotos(
      context,
      personId: 'my_personal_card',
    );
    if (!mounted || added.isEmpty) {
      return;
    }
    setState(() {
      _photos.addAll(added);
      _newPhotos.addAll(added);
    });
  }

  void _setPrimary(int index) {
    if (index <= 0 || index >= _photos.length) {
      return;
    }
    setState(() {
      final String path = _photos.removeAt(index);
      _photos.insert(0, path);
    });
  }

  void _removePhoto(int index) {
    final String removed = _photos.removeAt(index);
    if (_newPhotos.remove(removed)) {
      PhotoPickerService.deletePhotoFiles(<String>[removed]);
    }
    setState(() {});
  }

  void _reorderPhotos(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final String path = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, path);
    });
  }

  void _save() {
    _submitted = true;
    Navigator.of(context).pop(
      _PersonalCardDraft(
        text: _controller.text.trim(),
        photos: List<String>.unmodifiable(_photos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, keyboard + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'עריכת הכרטיס האישי',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'אפשר לשמור טקסט חופשי, להוסיף כמה תמונות שרוצים ולסדר אותן.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                children: <Widget>[
                  TextField(
                    controller: _controller,
                    minLines: 6,
                    maxLines: 12,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'הטקסט שלי',
                      hintText: 'אפשר לכתוב או להדביק כאן את הכרטיס שלך',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PersonPhotoEditor(
                    photoPaths: _photos,
                    onAddPhoto: _addPhotos,
                    onSetPrimary: _setPrimary,
                    onRemove: _removePhoto,
                    onReorder: _reorderPhotos,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ביטול'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('שמירת הכרטיס'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
