import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/dialogs/voice_recorder_sheet.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/private_looking_service.dart';
import 'package:shadchan/services/personal_area_service.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';

/// The quiet line under the recording actions.
const lookingImportHint =
    'כבר יש לך הקלטה ב־WhatsApp? אפשר להעביר אותה לכאן בקלות — ההקלטה נשמרת בשדכן ולא תלויה בקובץ המקורי.';

/// Under the owner's "מה אני מחפש/ת", small: who sees it, and that it does
/// not travel.
const lookingOwnerNotice =
    'לעיני השדכנים שאישרת בלבד. התוכן כאן לא ניתן לשיתוף מתוך שדכן.';

const privateLookingNotice =
    'המידע מיועד רק לחברים השדכנים שאישרת בנפרד. הוא לא יישלח למועמדים או למועמדות ולא יצורף לכרטיס שמשתפים איתם.';

class PrivateLookingBlock extends StatelessWidget {
  const PrivateLookingBlock({
    super.key,
    this.ownerUid,
    this.onSaved,
    this.ownerGender,
  });
  final Future<void> Function()? onSaved;
  final String? ownerUid;

  /// The single's gender, on a matchmaker's copy — "מה הוא מחפש" or "מה היא
  /// מחפשת".
  final Gender? ownerGender;

  /// The matchmaker's heading for [person]'s "מה אני מחפש/ת".
  static String headingFor(Gender? gender) => switch (gender) {
    Gender.male => 'מה הוא מחפש',
    Gender.female => 'מה היא מחפשת',
    _ => 'מה הוא/היא מחפש/ת',
  };
  @override
  Widget build(BuildContext context) {
    final access = context.watch<CardAccessProvider>();
    final owner = ownerUid == null;
    final uid = ownerUid ?? access.uid;
    if (uid == null) return const SizedBox.shrink();
    final row = owner ? null : access.accessTo(uid);
    if (!owner && !access.matchmakerAccessVerified) {
      return const SizedBox.shrink();
    }
    if (!owner && row?.canReadLooking != true) {
      if (row == null || row.status == CardAccessStatus.blocked) {
        return const SizedBox.shrink();
      }
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .doc('privateLookingPresence/$uid')
            .snapshots(),
        builder: (context, presence) {
          if (presence.hasError ||
              presence.data?.data()?['hasContent'] != true) {
            return const SizedBox.shrink();
          }
          return TextButton.icon(
            icon: const Icon(Icons.lock_outline),
            onPressed: row.lookingRequested
                ? null
                : () async {
                    final ok = await access.requestLooking(row);
                    if (context.mounted) {
                      AppNotice.show(
                        context,
                        ok ? 'בקשת הגישה נשלחה' : 'לא ניתן לשלוח בקשה כרגע',
                      );
                    }
                  },
            label: Text(
              row.lookingRequested
                  ? 'בקשה ל״מה אני מחפש/ת״ ממתינה לאישור'
                  : 'בקשת גישה ל״מה אני מחפש/ת״',
            ),
          );
        },
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      key: ValueKey('$uid:${row?.canReadLooking}'),
      stream: PrivateLookingService.doc(
        uid,
      ).snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        // Never resurrect private content from Firestore's persistent offline cache.
        if (snapshot.hasError ||
            (!owner && snapshot.data?.metadata.isFromCache != false)) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final text = data['text'] as String? ?? '';
        final audio = data['audioPath'] as String?;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: HomePaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  owner
                      ? 'מה אני {מחפש|מחפשת}'.forGender(context.userGender)
                      : headingFor(ownerGender),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!owner)
                  Text(
                    'לעיניך בלבד',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (owner && text.isEmpty && audio == null)
                  Text(
                    'עוד לא {כתבת|כתבת} מה {אתה מחפש|את מחפשת}. אפשר לכתוב או להקליט כמה מילים שיעזרו לחברים לחשוב על רעיונות מתאימים.'
                        .forGender(context.userGender),
                  ),
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(text),
                  ),
                if (audio != null)
                  PrivateAudioPlayer(
                    key: ValueKey(audio),
                    path: audio,
                    shareable: owner,
                  ),
                if (owner) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('עריכה'),
                    onPressed: snapshot.hasData
                        ? () => openPrivateLookingEditor(
                            context,
                            data: data,
                            onSaved: onSaved,
                          )
                        : null,
                  ),
                  const Text(privateLookingNotice),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Authenticated SDK download, temporary file, no download URL or export hook.
/// Removing the block on revocation disposes playback and deletes the file.
class PrivateAudioPlayer extends StatefulWidget {
  const PrivateAudioPlayer({
    super.key,
    required this.path,
    this.shareable = false,
  });
  final String path;

  /// The owner's own recording only: "שיתוף ל־WhatsApp" sends it back out.
  /// A matchmaker's player never offers it — what the single tells their
  /// matchmakers is not theirs to forward.
  final bool shareable;
  @override
  State<PrivateAudioPlayer> createState() => _PrivateAudioPlayerState();
}

class _PrivateAudioPlayerState extends State<PrivateAudioPlayer> {
  final _player = AudioPlayer();
  File? _file;
  bool _busy = false;
  bool _disposed = false;
  Future<File> _load() async {
    if (_file != null) return _file!;
    final folder = await Directory(
      '${(await getTemporaryDirectory()).path}/private_audio',
    ).create(recursive: true);
    final file = File(
      '${folder.path}/${DateTime.now().microsecondsSinceEpoch}_${widget.path.split('/').last}',
    );
    await FirebaseStorage.instance.ref(widget.path).writeToFile(file);
    if (_disposed) {
      await file.delete();
      throw StateError('הגישה הסתיימה');
    }
    _file = file;
    await _player.setFilePath(file.path);
    return file;
  }

  Future<void> _act() async {
    setState(() => _busy = true);
    try {
      await _load();
      if (!mounted) return;
      if (_player.playing) {
        await _player.pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        // play completes only when playback ends.
        _player.play();
      }
    } catch (_) {
      if (mounted) AppNotice.show(context, 'לא ניתן לפתוח את ההקלטה כרגע');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _player.dispose();
    final file = _file;
    if (file != null) file.delete().catchError((_) => file);
    super.dispose();
  }

  Future<void> _share(Rect? origin) async {
    setState(() => _busy = true);
    try {
      final file = await _load();
      await Share.shareXFiles([XFile(file.path)], sharePositionOrigin: origin);
    } catch (_) {
      if (mounted) AppNotice.show(context, 'לא ניתן לשתף את ההקלטה כרגע');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<PlayerState>(
    stream: _player.playerStateStream,
    builder: (context, snapshot) => Wrap(
      spacing: 4,
      children: [
        TextButton.icon(
          onPressed: _busy ? null : _act,
          icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow),
          label: const Text('הקלטה'),
        ),
        if (widget.shareable)
          Builder(
            builder: (anchor) => TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _share(ShareUtils.originOf(anchor)),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('שיתוף ל־WhatsApp'),
            ),
          ),
      ],
    ),
  );
}

/// What the editor does the moment it opens: nothing, the recorder, or the
/// file picker for a recording already in WhatsApp.
enum LookingEditorStart { edit, record, import }

Future<void> openPrivateLookingEditor(
  BuildContext context, {
  Map<String, dynamic>? data,
  String? incoming,
  Future<void> Function()? onSaved,
  LookingEditorStart start = LookingEditorStart.edit,
}) async {
  bool changed = false;
  try {
    if (data == null) {
      final uid = await PersonalCardService.durableUid();
      if (uid == null) return;
      data =
          (await PrivateLookingService.doc(
            uid,
          ).get(const GetOptions(source: Source.server))).data() ??
          {};
    }
    if (!context.mounted) return;
    final first = data['everFilled'] != true;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _LookingEditor(data: data!, incoming: incoming, start: start),
      ),
    );
    changed = saved == true;
    if (saved != true || !first || !context.mounted) return;
    final access = context.read<CardAccessProvider>();
    final rows = access.approved
        .where((r) => r.canReadCard && !r.canReadLooking)
        .toList();
    if (rows.isEmpty) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'לאשר גם לשדכנים שכבר נתת להם גישה לראות את ‘מה אני מחפש/ת’?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('דילוג'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: const Text('בחירה ידנית'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'all'),
            child: const Text('אישור לכולם'),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null || choice == 'skip') return;
    Set<String> selected = rows.map((r) => r.id).toSet();
    if (choice == 'manual') {
      selected = <String>{};
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('בחירת שדכנים'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final row in rows)
                    CheckboxListTile(
                      title: Text(row.matchmakerName),
                      value: selected.contains(row.id),
                      onChanged: (v) => setState(() {
                        v == true
                            ? selected.add(row.id)
                            : selected.remove(row.id);
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ביטול'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('אישור'),
              ),
            ],
          ),
        ),
      );
      if (ok != true) return;
    }
    var failed = false;
    for (final row in rows.where((r) => selected.contains(r.id))) {
      if (!await access.setPermissions(
        row,
        card: row.canReadCard,
        looking: true,
      )) {
        failed = true;
      }
    }
    if (failed && context.mounted) {
      AppNotice.show(
        context,
        'חלק מההרשאות לא נשמרו. אפשר לעדכן בניהול ההרשאות.',
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppNotice.show(context, 'לא ניתן לטעון כרגע. אפשר לנסות שוב.');
    }
  } finally {
    if (changed && context.mounted) {
      if (onSaved != null) {
        await onSaved();
      } else {
        await PersonalAreaService.offerUpdate(context);
      }
    }
  }
}

class _LookingEditor extends StatefulWidget {
  const _LookingEditor({
    required this.data,
    this.incoming,
    this.start = LookingEditorStart.edit,
  });
  final Map<String, dynamic> data;
  final String? incoming;
  final LookingEditorStart start;
  @override
  State<_LookingEditor> createState() => _LookingEditorState();
}

class _LookingEditorState extends State<_LookingEditor> {
  late final _text = TextEditingController(
    text: widget.data['text'] as String? ?? '',
  );
  late String? _audio = widget.data['audioPath'] as String?;
  String? _newAudio;
  int? _duration;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    if (widget.incoming != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _import(widget.incoming!),
      );
    } else if (widget.start != LookingEditorStart.edit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.start == LookingEditorStart.record ? _record() : _pick();
      });
    }
  }

  Future<void> _record() async {
    final recorded = await VoiceRecorderSheet.record(
      context,
      maxDuration: const Duration(minutes: 10),
    );
    if (recorded != null && mounted) {
      setState(() {
        _newAudio = recorded.fileName;
        _duration = recorded.durationMs;
      });
    }
  }

  Future<void> _pick() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: VoiceNoteStore.audioExtensions
          .map((e) => e.substring(1))
          .toList(),
    );
    final path = picked?.files.single.path;
    if (path != null && mounted) await _import(path);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _import(String path) async {
    setState(() => _busy = true);
    try {
      final result = await PrivateLookingService.importAudio(path);
      if (mounted) {
        setState(() {
          _newAudio = result.name;
          _duration = result.durationMs;
        });
      }
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          error is FormatException ? error.message : 'לא ניתן לייבא את ההקלטה',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await PrivateLookingService.save(
        text: _text.text,
        newAudio: _newAudio,
        audioPath: _audio,
        durationMs: _duration,
      );
      if (mounted) {
        Navigator.pop(
          context,
          _text.text.trim().isNotEmpty || _newAudio != null || _audio != null,
        );
      }
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'השמירה לא הצליחה. ההקלטה חייבת להיות עד 10 דקות. אפשר לנסות שוב.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('מה אני {מחפש|מחפשת}'.forGender(context.userGender)),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _text,
          minLines: 5,
          maxLines: 12,
          maxLength: 12000,
          decoration: const InputDecoration(
            hintText: 'מה חשוב לך שהשדכנים ידעו?',
          ),
        ),
        if (_newAudio != null || _audio != null)
          ListTile(
            title: const Text('הקלטה אחת מצורפת'),
            subtitle: const Text('הוספת הקלטה אחרת תחליף אותה'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _audio = null;
                      _newAudio = null;
                    }),
            ),
          ),
        if (_audio != null && _newAudio == null)
          PrivateAudioPlayer(path: _audio!),
        Wrap(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.mic),
              label: const Text('הקלטה עד 10 דקות'),
              onPressed: _busy ? null : _record,
            ),
            TextButton.icon(
              icon: const Icon(Icons.audio_file_outlined),
              label: const Text('ייבוא הקלטה מ־WhatsApp'),
              onPressed: _busy ? null : _pick,
            ),
          ],
        ),
        Text(lookingImportHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        const Text(privateLookingNotice),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'שומר…' : 'שמירה'),
        ),
      ],
    ),
  );
}
