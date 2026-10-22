import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/dialogs/voice_recorder_sheet.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/services/personal_card_service.dart';
import 'package:shadchan/services/private_looking_service.dart';
import 'package:shadchan/services/voice_note_store.dart';
import 'package:shadchan/utils/share_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/home_section.dart';

const privateLookingNotice =
    'לעיני השדכנים שאישרת בלבד. התוכן כאן לא ניתן לשיתוף מתוך שדכן.';

class PrivateLookingBlock extends StatelessWidget {
  const PrivateLookingBlock({super.key, this.ownerUid});
  final String? ownerUid;
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
                  owner ? 'מה אני מחפש/ת' : 'מה הוא/היא מחפש/ת',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!owner) const Text('לעיניך בלבד'),
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(text),
                  ),
                if (audio != null)
                  PrivateAudioPlayer(
                    key: ValueKey(audio),
                    path: audio,
                    owner: owner,
                  ),
                if (owner) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('עריכה'),
                    onPressed: snapshot.hasData
                        ? () => openPrivateLookingEditor(context, data: data)
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
  const PrivateAudioPlayer({super.key, required this.path, this.owner = false});
  final String path;
  final bool owner;
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

  Future<void> _act(bool share) async {
    setState(() => _busy = true);
    try {
      final file = await _load();
      if (!mounted) return;
      if (share && widget.owner) {
        await Share.shareXFiles([
          XFile(file.path),
        ], sharePositionOrigin: ShareUtils.originOf(context));
      } else if (_player.playing) {
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

  @override
  Widget build(BuildContext context) => StreamBuilder<PlayerState>(
    stream: _player.playerStateStream,
    builder: (context, snapshot) => Wrap(
      children: [
        TextButton.icon(
          onPressed: _busy ? null : () => _act(false),
          icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow),
          label: const Text('הקלטה'),
        ),
        if (widget.owner)
          TextButton.icon(
            onPressed: _busy ? null : () => _act(true),
            icon: const Icon(Icons.share_outlined),
            label: const Text('שיתוף ההקלטה ל־WhatsApp'),
          ),
      ],
    ),
  );
}

Future<void> openPrivateLookingEditor(
  BuildContext context, {
  Map<String, dynamic>? data,
  String? incoming,
}) async {
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
        builder: (_) => _LookingEditor(data: data!, incoming: incoming),
      ),
    );
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
  }
}

class _LookingEditor extends StatefulWidget {
  const _LookingEditor({required this.data, this.incoming});
  final Map<String, dynamic> data;
  final String? incoming;
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
    }
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
    appBar: AppBar(title: const Text('מה אני מחפש/ת')),
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
          PrivateAudioPlayer(path: _audio!, owner: true),
        Wrap(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.mic),
              label: const Text('הקלטה עד 10 דקות'),
              onPressed: _busy
                  ? null
                  : () async {
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
                    },
            ),
            TextButton.icon(
              icon: const Icon(Icons.audio_file_outlined),
              label: const Text('ייבוא הקלטה מ־WhatsApp / קובץ'),
              onPressed: _busy
                  ? null
                  : () async {
                      final picked = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: VoiceNoteStore.audioExtensions
                            .map((e) => e.substring(1))
                            .toList(),
                      );
                      final path = picked?.files.single.path;
                      if (path != null && mounted) await _import(path);
                    },
            ),
          ],
        ),
        const Text(
          'אפשר גם לשתף הקלטה מ־WhatsApp אל שדכן ולבחור ״מה אני מחפש/ת״. הקלטה מיובאת נשמרת בשדכן.',
        ),
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
