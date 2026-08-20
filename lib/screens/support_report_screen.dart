import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/device_facts.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_links.dart';

/// "שליחת תקלה / רעיון לשיפור" — one box, one button.
///
/// **Deliberately not two flows.** Splitting "report a bug" from "suggest an
/// improvement" asks the reporter to classify their problem before they have
/// described it, and the answer is wrong often enough to matter: "it would be
/// better if…" is regularly a bug, and "it doesn't work" is regularly a feature
/// that was never built. Whoever reads the report can tell the difference; the
/// person hitting the problem should not have to.
///
/// What it *does* carry is one optional row of chips saying what kind of thing
/// this is. That is not a fork in the flow — the same box, the same button, and
/// leaving it alone is a real answer that files the report under "ללא סיווג".
/// It exists because the feedback console is worked through by kind, and a
/// label the sender gave costs one tap and is right more often than any guess
/// made later.
///
/// The three facts that make a report actionable — which phone, which OS, which
/// build — are attached automatically and shown before sending, so nobody has to
/// go and look them up and nobody has to wonder what went along with their
/// words.
class SupportReportScreen extends StatefulWidget {
  const SupportReportScreen({super.key, this.initialText = ''});

  /// Pre-filled text. The import-problem dialog hands its diagnostic report
  /// through here, so a failure that has already been described does not have
  /// to be described again.
  final String initialText;

  @override
  State<SupportReportScreen> createState() => _SupportReportScreenState();
}

class _SupportReportScreenState extends State<SupportReportScreen> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );

  DeviceFacts _facts = DeviceFacts.unknown;

  /// Unanswered until the sender taps a chip, and unanswered is allowed.
  SupportReportKind _kind = SupportReportKind.unsorted;

  String? _screenshotPath;
  bool _sending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _loadFacts();
  }

  Future<void> _loadFacts() async {
    final DeviceFacts facts = await DeviceFacts.read();
    if (mounted) {
      setState(() => _facts = facts);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canSend => !_sending && _text.text.trim().length >= 5;

  Future<void> _attachScreenshot() async {
    final String? path = await PhotoPickerService.pickSinglePhoto(
      context,
      namePrefix: 'report',
    );
    if (path != null && mounted) {
      setState(() => _screenshotPath = path);
    }
  }

  void _removeScreenshot() {
    final String? path = _screenshotPath;
    if (path == null) {
      return;
    }
    // The copy lives in the app's own photos directory; dropping it here keeps
    // an abandoned attachment from sitting there forever.
    PhotoPickerService.deletePhotoFiles(<String>[path]);
    setState(() => _screenshotPath = null);
  }

  Future<void> _send() async {
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? path = _screenshotPath;

    setState(() => _sending = true);
    final bool sent = await SupportService.submitReport(
      text: _text.text,
      authorName: profile.name ?? '',
      facts: _facts,
      kind: _kind,
      screenshot: path == null ? null : File(path),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
      _sent = sent;
    });
    if (sent) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'לא הצלחנו לשלוח כרגע. אפשר לנסות שוב או לכתוב לנו במייל.',
          ),
        ),
      );
  }

  /// The way out when the form cannot reach us — no network, or a device with
  /// no Firebase at all. Carries whatever has already been typed, so nothing
  /// written here has to be written twice.
  Future<void> _openEmail() async {
    final bool opened = await CommunityLinks.openSupportEmail(
      body: _text.text.trim(),
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('לא הצלחנו לפתוח את אפליקציית המייל')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('תקלה או רעיון לשיפור'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _sent
            ? _SentView(onClose: () => Navigator.of(context).maybePop())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: <Widget>[
                  _Intro(theme: theme),
                  const SizedBox(height: 16),
                  _KindPicker(
                    selected: _kind,
                    onChanged: (SupportReportKind kind) =>
                        setState(() => _kind = kind),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _text,
                    minLines: 6,
                    maxLines: 14,
                    maxLength: SupportService.maxReportLength,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'מה קרה, או מה היה עוזר?',
                      hintText:
                          'אפשר לכתוב בחופשיות — מה ניסית לעשות, מה קרה בפועל, '
                          'ומה היית מצפה שיקרה.',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  _ScreenshotField(
                    path: _screenshotPath,
                    onPick: _attachScreenshot,
                    onRemove: _removeScreenshot,
                  ),
                  const SizedBox(height: 16),
                  _AttachedFacts(facts: _facts),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _canSend ? _send : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.brightness == Brightness.dark
                            ? theme.colorScheme.primary
                            : AppColors.primaryDark,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: const StadiumBorder(),
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: const Text('שליחה'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton.icon(
                      onPressed: _openEmail,
                      icon: const Icon(Icons.mail_outline, size: 18),
                      label: const Text('או כתבו לנו במייל'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bool dark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: dark
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : AppColors.primaryLight.withValues(alpha: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.forum_outlined,
            color: dark ? theme.colorScheme.primary : AppColors.primaryDark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'תקלה, בקשה או רעיון — הכול לאותו מקום. אנחנו קוראים כל פנייה, '
              'וזה מה שמכוון את מה שנבנה בהמשך.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// "על מה מדובר?" — one optional row, never a required step.
///
/// The chips are a toggle rather than a radio group: tapping the selected one
/// again clears it, so a sender who guessed and changed their mind can go back
/// to saying nothing.
class _KindPicker extends StatelessWidget {
  const _KindPicker({required this.selected, required this.onChanged});

  final SupportReportKind selected;
  final ValueChanged<SupportReportKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'על מה מדובר? (לא חובה)',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            for (final SupportReportKind kind in SupportReportKind.values)
              ChoiceChip(
                label: Text(kind.label),
                selected: selected == kind,
                showCheckmark: false,
                onSelected: (_) => onChanged(
                  selected == kind ? SupportReportKind.unsorted : kind,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The optional screenshot: a button while there is none, a thumbnail with a
/// way to take it back once there is.
class _ScreenshotField extends StatelessWidget {
  const _ScreenshotField({
    required this.path,
    required this.onPick,
    required this.onRemove,
  });

  final String? path;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? current = path;

    if (current == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
          label: const Text('צירוף צילום מסך או תמונה'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(current),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 72,
                height: 72,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'התמונה תישלח יחד עם הפנייה',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'הסרת התמונה',
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// What goes along with the words, shown rather than promised.
class _AttachedFacts extends StatelessWidget {
  const _AttachedFacts({required this.facts});

  final DeviceFacts facts;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'נצרף אוטומטית, כדי שלא תצטרכו לחפש',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          line('מכשיר', facts.device),
          line('מערכת', facts.os),
          line('גרסה', facts.appVersion),
        ],
      ),
    );
  }
}

class _SentView extends StatelessWidget {
  const _SentView({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.mark_email_read_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'הפנייה נשלחה. תודה!',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'קראנו כל מה שנשלח. אם צריך פרטים נוספים, נכתוב לכם למייל '
              '${CommunityLinks.supportEmail}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onClose, child: const Text('סגירה')),
          ],
        ),
      ),
    );
  }
}
