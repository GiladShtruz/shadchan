import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadchan/services/community_service.dart';
import 'package:shadchan/services/device_facts.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/widgets/app_notice.dart';

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
/// build — ride along automatically and are no longer spelled out on the form.
/// They were shown as a panel above the send button, and it was the only part of
/// the page that asked the sender to read plumbing: a person reporting that a
/// button does nothing does not need to be told the app version they are running
/// before they may press "שליחה".
///
/// **The report is shared, not submitted (since 2026-09-13).** The button
/// copies the whole report — text, device facts and the community diagnostics —
/// and opens the system share sheet, so it can go out over WhatsApp, Telegram or
/// anything else the phone offers. The app is not in production yet, and the
/// iPhone build is only reachable through TestFlight with no Mac attached; a
/// message that can be pasted anywhere is the shortest path from that phone to
/// a readable report. `SupportService.submitReport` is left in place for when
/// the Firestore route comes back.
class SupportReportScreen extends StatefulWidget {
  const SupportReportScreen({
    super.key,
    this.initialText = '',
    this.initialKind = SupportReportKind.unsorted,
  });

  /// Pre-filled text. The import-problem dialog hands its diagnostic report
  /// through here, so a failure that has already been described does not have
  /// to be described again.
  final String initialText;

  /// Pre-selected classification. A report opened from the flag on a published
  /// tip arrives already marked as a content report, so the sender writes what
  /// is wrong with it rather than filing it themselves.
  final SupportReportKind initialKind;

  @override
  State<SupportReportScreen> createState() => _SupportReportScreenState();
}

class _SupportReportScreenState extends State<SupportReportScreen> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );

  DeviceFacts _facts = DeviceFacts.unknown;

  /// Unanswered until the sender taps a chip, and unanswered is allowed —
  /// unless the flow that opened the form already knows (see [initialKind]).
  late SupportReportKind _kind = widget.initialKind;

  String? _screenshotPath;

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

  /// Copies the report and opens the share sheet.
  ///
  /// Copied first, because some targets drop the text half of a share — most
  /// visibly WhatsApp once an image is attached — and a report that only
  /// arrived as a screenshot is missing the part that says what went wrong.
  Future<void> _share() async {
    final String report = _composeReport();
    final String? path = _screenshotPath;
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) {
      return;
    }
    AppNotice.show(context, 'הדיווח הועתק, אפשר גם להדביק אותו');
    if (path != null && File(path).existsSync()) {
      await Share.shareXFiles(<XFile>[XFile(path)], text: report);
    } else {
      await Share.share(report);
    }
  }

  /// What was typed, then the facts that make it actionable. The community
  /// block is TEMPORARY — see `CommunityService.diagnostics`.
  String _composeReport() {
    final String typed = _text.text.trim();
    return <String>[
      if (typed.isNotEmpty) typed,
      '---',
      'סוג: ${_kind.label}',
      'מכשיר: ${_facts.device}',
      'מערכת: ${_facts.os}',
      'גרסה: ${_facts.appVersion}',
      '',
      '[community]',
      CommunityService.diagnostics(maxChars: 6000),
    ].join('\n');
  }

  /// The way out when the form cannot reach us — no network, or a device with
  /// no Firebase at all. Carries whatever has already been typed, so nothing
  /// written here has to be written twice.
  Future<void> _openEmail() async {
    final bool opened = await CommunityLinks.openSupportEmail(
      body: _text.text.trim(),
    );
    if (!opened && mounted) {
      AppNotice.show(context, 'לא הצלחנו לפתוח את אפליקציית המייל');
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
        child: ListView(
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _share,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.brightness == Brightness.dark
                      ? theme.colorScheme.primary
                      : AppColors.primaryDark,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('העתקה ושיתוף'),
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
              'התמונה תשותף יחד עם הפנייה',
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
