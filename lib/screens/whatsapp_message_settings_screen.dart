import 'package:flutter/material.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';

class WhatsAppMessageSettingsScreen extends StatefulWidget {
  const WhatsAppMessageSettingsScreen({super.key});

  @override
  State<WhatsAppMessageSettingsScreen> createState() =>
      _WhatsAppMessageSettingsScreenState();
}

class _WhatsAppMessageSettingsScreenState
    extends State<WhatsAppMessageSettingsScreen> {
  final TextEditingController _messageController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _messageController.text = WhatsAppUtils.currentOnboardingMessage();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('הודעת וואטסאפ'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            tooltip: 'שמירה',
            onPressed: _isSaving ? null : _save,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: <Widget>[
            Text('הודעה לבקשת פרטים', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'זו ההודעה שתיפתח אוטומטית בוואטסאפ עבור אנשים שבהמתנה לעדכון. '
              'הנוסח כאן הוא ברירת המחדל עבור כל החברים במאגר, ולא עבור מועמד '
              'אחד בלבד.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _messageController,
              minLines: 8,
              maxLines: 14,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: 'תוכן ההודעה',
                alignLabelWithHint: true,
              ),
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return 'יש להזין הודעה';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _resetToDefault,
              icon: const Icon(Icons.restore),
              label: const Text('חזרה לברירת המחדל'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _save,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
        label: const Text('שמירה'),
        shape: const StadiumBorder(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await WhatsAppUtils.saveOnboardingMessage(_messageController.text);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _resetToDefault() async {
    await WhatsAppUtils.resetOnboardingMessage();
    if (!mounted) {
      return;
    }

    // The field filling back up with the default text is the confirmation.
    setState(() {
      _messageController.text = WhatsAppUtils.defaultOnboardingMessage;
    });
  }
}
