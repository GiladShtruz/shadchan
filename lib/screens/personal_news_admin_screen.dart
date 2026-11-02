import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/screens/personal_home_screen.dart';

class PersonalNewsAdminScreen extends StatelessWidget {
  const PersonalNewsAdminScreen({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: () => _edit(context),
          icon: const Icon(Icons.add),
          label: const Text('עדכון חדש לרווקים'),
        ),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('personalNews')
              .orderBy('updatedAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('לא ניתן לטעון את העדכונים'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              children: [
                for (final doc in snapshot.data!.docs)
                  ListTile(
                    title: Text(doc.data()['title'] as String? ?? ''),
                    subtitle: Text(
                      doc.data()['published'] == true
                          ? 'מפורסם${doc.data()['notify'] == true ? ' · מופיע גם בפעמון' : ''}'
                          : 'טיוטה',
                    ),
                    onTap: () => _edit(context, doc: doc),
                    trailing: IconButton(
                      tooltip: 'מחיקת עדכון',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (dialog) => AlertDialog(
                            title: const Text('להסיר את העדכון?'),
                            content: const Text(
                              'העדכון יוסר מעמוד הבית ומהפעמון.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialog, false),
                                child: const Text('ביטול'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(dialog, true),
                                child: const Text('הסרה'),
                              ),
                            ],
                          ),
                        );
                        if (yes != true) return;
                        try {
                          await doc.reference.delete();
                        } catch (_) {
                          if (context.mounted) {
                            AppNotice.show(context, 'לא ניתן להסיר כרגע');
                          }
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
  void _edit(
    BuildContext context, {
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _NewsEditor(
        id: doc?.id ?? const Uuid().v4(),
        data: doc?.data() ?? {},
      ),
    ),
  );
}

class _NewsEditor extends StatefulWidget {
  const _NewsEditor({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
  @override
  State<_NewsEditor> createState() => _NewsEditorState();
}

class _NewsEditorState extends State<_NewsEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.data['title'] as String? ?? '',
  );
  late final _text = TextEditingController(
    text: widget.data['text'] as String? ?? '',
  );
  late bool _published = widget.data['published'] != false;
  late bool _notify = widget.data['notify'] == true;
  late String? _imagePath = widget.data['imagePath'] as String?;
  Uint8List? _image;
  bool _busy = false;
  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    String? uploaded;
    try {
      if (_image != null) {
        uploaded = 'personalNews/${widget.id}/${const Uuid().v4()}.jpg';
        await FirebaseStorage.instance
            .ref(uploaded)
            .putData(_image!, SettableMetadata(contentType: 'image/jpeg'));
      }
      await FirebaseFirestore.instance.doc('personalNews/${widget.id}').set({
        'title': _title.text.trim(),
        'text': _text.text.trim(),
        'imagePath': uploaded ?? _imagePath,
        'published': _published,
        'notify': _notify,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Navigator.pop(context);
        AppNotice.show(context, 'העדכון נשמר');
      }
    } catch (_) {
      if (uploaded != null) {
        try {
          await FirebaseStorage.instance.ref(uploaded).delete();
        } catch (_) {}
      }
      if (mounted) AppNotice.show(context, 'השמירה נכשלה. יש לנסות שוב.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('עדכון לקהילת הרווקים')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _title,
            enabled: !_busy,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'כותרת'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'יש לכתוב כותרת' : null,
          ),
          TextFormField(
            controller: _text,
            enabled: !_busy,
            minLines: 4,
            maxLines: 12,
            maxLength: 4000,
            decoration: const InputDecoration(labelText: 'תוכן העדכון'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'יש לכתוב תוכן לעדכון' : null,
          ),
          if (_image != null)
            Image.memory(_image!, height: 180)
          else if (_imagePath != null)
            PersonalNewsImage(key: ValueKey(_imagePath), path: _imagePath!),
          Wrap(
            children: [
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final picked = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 1600,
                          imageQuality: 85,
                        );
                        if (picked == null) return;
                        final bytes = await picked.readAsBytes();
                        if (!mounted || !context.mounted) return;
                        if (bytes.length >= 12 * 1024 * 1024) {
                          AppNotice.show(
                            context,
                            'יש לבחור תמונה עד 12 מגה־בייט',
                          );
                          return;
                        }
                        setState(() => _image = bytes);
                      },
                icon: const Icon(Icons.image_outlined),
                label: const Text('בחירת תמונה'),
              ),
              if (_image != null || _imagePath != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _image = null;
                          _imagePath = null;
                        }),
                  child: const Text('הסרת התמונה'),
                ),
            ],
          ),
          SwitchListTile(
            title: const Text('פרסום בעמוד הבית'),
            value: _published,
            onChanged: _busy ? null : (v) => setState(() => _published = v),
          ),
          SwitchListTile(
            title: const Text('להציג גם בפעמון ההתראות'),
            subtitle: const Text('ההתראה נשמרת גם למי שלא אישר התראות בטלפון'),
            value: _notify,
            onChanged: _busy ? null : (v) => setState(() => _notify = v),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'שומר...' : 'שמירת העדכון'),
          ),
        ],
      ),
    ),
  );
}
