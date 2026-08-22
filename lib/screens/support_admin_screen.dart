import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/confirm_dialog.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/screens/tips_admin_screen.dart';
import 'package:shadchan/services/support_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/date_utils.dart';

/// מרכז הפידבק — the one place everything users send arrives.
///
/// **One screen, because it is one job.** Feedback used to land in two
/// unrelated places: the tips waiting for approval on a settings row of their
/// own, and everything else in a console reached from the bottom of the profile
/// page. Nobody triages across two screens they have to remember to visit, so
/// the tips queue moved in here beside the reports, and the whole thing is
/// reached from the app's overflow menu.
///
/// Four tabs:
/// * **פידבק** — every report, grouped by what it is about: המלצות ורעיונות,
///   הערות ותיקונים, תקלות ובאגים.
/// * **טיפים** — the approval queue. A tip reaches other matchmakers only from
///   here.
/// * **מה חדש** — the notes that go back out.
/// * **מנהלים** — who else may see any of it.
///
/// Drawn only for an administrator, and that is a *display* gate — every read
/// and write behind it is refused by `firestore.rules` for anybody else, so a
/// patched client gets a screen full of permission errors rather than a screen
/// full of other people's reports.
class SupportAdminScreen extends StatefulWidget {
  const SupportAdminScreen({super.key});

  @override
  State<SupportAdminScreen> createState() => _SupportAdminScreenState();
}

class _SupportAdminScreenState extends State<SupportAdminScreen> {
  @override
  Widget build(BuildContext context) {
    final AccountProvider account = context.watch<AccountProvider>();

    if (!account.isSupportAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('מרכז הפידבק'), centerTitle: true),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'האזור הזה פתוח למנהלי המערכת בלבד.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // The tip queue's own count rides on the tab label, so "somebody sent a
    // tip" is visible from the moment the screen opens rather than after the
    // third tab is found.
    final int waitingTips = context.watch<TipsProvider>().pending.length;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מרכז הפידבק'),
          centerTitle: true,
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              const Tab(text: 'פידבק'),
              Tab(text: waitingTips == 0 ? 'טיפים' : 'טיפים ($waitingTips)'),
              const Tab(text: 'מה חדש'),
              const Tab(text: 'מנהלים'),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: <Widget>[
              _ReportsTab(),
              PendingTipsReview(),
              _AnnouncementsTab(),
              _AdminsTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Reports ----------------------------------------------------------------

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  List<SupportReport>? _reports;

  /// Null means "everything"; otherwise only this status.
  SupportReportStatus? _filter;

  /// Null means "every kind"; otherwise only הצעות, הערות or תקלות.
  ///
  /// A second axis rather than a second tab, because the two questions a
  /// triager asks — "what is still new?" and "what kind of thing is this?" —
  /// are asked together, and tabs cannot be crossed with each other.
  SupportReportKind? _kind;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<SupportReport> reports = await SupportService.fetchReports();
    if (mounted) {
      setState(() => _reports = reports);
    }
  }

  Future<void> _setStatus(
    SupportReport report,
    SupportReportStatus status,
  ) async {
    final bool ok = await SupportService.setReportStatus(report.id, status);
    if (!mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('העדכון לא נשמר')));
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<SupportReport>? all = _reports;

    if (all == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<SupportReport> shown = all
        .where((SupportReport r) => _filter == null || r.status == _filter)
        .where((SupportReport r) => _kind == null || r.kind == _kind)
        .toList();

    // The counts are of what the *other* filter already left standing, so the
    // two rows agree with each other instead of each describing a different
    // list.
    final List<SupportReport> byKind = all
        .where((SupportReport r) => _kind == null || r.kind == _kind)
        .toList();
    final List<SupportReport> byStatus = all
        .where((SupportReport r) => _filter == null || r.status == _filter)
        .toList();
    final int waiting = all
        .where((SupportReport r) => r.status == SupportReportStatus.isNew)
        .length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          if (waiting > 0) ...<Widget>[
            _WaitingReportsBanner(count: waiting, theme: theme),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            children: <Widget>[
              _StatusFilterChip(
                label: 'כל הסוגים (${byStatus.length})',
                selected: _kind == null,
                onTap: () => setState(() => _kind = null),
              ),
              for (final SupportReportKind kind in SupportReportKind.values)
                _StatusFilterChip(
                  label:
                      '${kind.pluralLabel} '
                      '(${byStatus.where((SupportReport r) => r.kind == kind).length})',
                  selected: _kind == kind,
                  onTap: () => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              _StatusFilterChip(
                label: 'הכול (${byKind.length})',
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              for (final SupportReportStatus status
                  in SupportReportStatus.values)
                _StatusFilterChip(
                  label:
                      '${status.label} '
                      '(${byKind.where((SupportReport r) => r.status == status).length})',
                  selected: _filter == status,
                  onTap: () => setState(() => _filter = status),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text(
                'אין פניות להצגה.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final SupportReport report in shown) ...<Widget>[
              _ReportCard(
                report: report,
                onSetStatus: (SupportReportStatus status) =>
                    _setStatus(report, status),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

/// "יש פניות חדשות" — the same alert the tips queue raises, for the same
/// reason: what arrived should be visible before the list is scrolled.
class _WaitingReportsBanner extends StatelessWidget {
  const _WaitingReportsBanner({required this.count, required this.theme});

  final int count;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.secondary.withValues(alpha: 0.14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.mark_email_unread_outlined,
            size: 20,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? 'פנייה אחת חדשה ממתינה לטיפול.'
                  : '$count פניות חדשות ממתינות לטיפול.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.onSetStatus});

  final SupportReport report;
  final ValueChanged<SupportReportStatus> onSetStatus;

  Color _tone(ThemeData theme) {
    switch (report.status) {
      case SupportReportStatus.isNew:
        return AppColors.secondary;
      case SupportReportStatus.inProgress:
        return theme.colorScheme.primary;
      case SupportReportStatus.done:
        return AppColors.statusDating;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = _tone(theme);
    final String name = report.authorName.isEmpty
        ? 'ללא שם'
        : report.authorName;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (report.kind != SupportReportKind.unsorted) ...<Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    report.kind.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  report.status.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            report.text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          if (report.imagePath != null || report.imageUrl != null) ...<Widget>[
            const SizedBox(height: 10),
            _ReportScreenshot(report: report),
          ],
          const SizedBox(height: 10),
          Text(
            <String>[
              AppDateUtils.formatDateShort(report.createdAt),
              if (report.device.isNotEmpty) report.device,
              if (report.os.isNotEmpty) report.os,
              if (report.appVersion.isNotEmpty) 'גרסה ${report.appVersion}',
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final SupportReportStatus status
                  in SupportReportStatus.values)
                if (status != report.status)
                  OutlinedButton(
                    onPressed: () => onSetStatus(status),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text('סימון כ${status.label}'),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The screenshot attached to a report, fetched under the administrator's own
/// credentials rather than through a public link.
///
/// Reports written from now on carry `imagePath`, and the bytes are read with
/// [SupportService.loadScreenshot] — an authenticated call that `storage.rules`
/// refuses for anybody who is not an administrator. Older reports carry a
/// `getDownloadURL` token link instead, which is exactly the thing that was
/// wrong with the old design; they still render, because a console that cannot
/// show yesterday's screenshots is not an improvement, but nothing writes one
/// any more.
class _ReportScreenshot extends StatefulWidget {
  const _ReportScreenshot({required this.report});

  final SupportReport report;

  @override
  State<_ReportScreenshot> createState() => _ReportScreenshotState();
}

class _ReportScreenshotState extends State<_ReportScreenshot> {
  late final Future<ImageProvider?> _image = _load();

  Future<ImageProvider?> _load() async {
    final String? path = widget.report.imagePath;
    if (path != null) {
      final Uint8List? bytes = await SupportService.loadScreenshot(path);
      return bytes == null ? null : MemoryImage(bytes);
    }
    final String? url = widget.report.imageUrl;
    return url == null ? null : NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return FutureBuilder<ImageProvider?>(
      future: _image,
      builder: (BuildContext context, AsyncSnapshot<ImageProvider?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            height: 60,
            alignment: Alignment.center,
            color: theme.colorScheme.surfaceContainerHighest,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final ImageProvider? image = snapshot.data;
        if (image == null) {
          return Container(
            height: 60,
            alignment: Alignment.center,
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Text('התמונה לא נטענה'),
          );
        }
        return GestureDetector(
          onTap: () => _openFullImage(context, image),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: image,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 60,
                alignment: Alignment.center,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Text('התמונה לא נטענה'),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The attached screenshot at full size. A plain black page with a pinchable
/// image — nothing here edits or deletes what it is showing.
///
/// Takes the already-loaded provider rather than an address, so the full-size
/// view cannot become a second place that fetches by URL.
Future<void> _openFullImage(BuildContext context, ImageProvider image) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('צילום מסך'),
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image(
              image: image,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Text(
                'התמונה לא נטענה',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// --- Announcements ----------------------------------------------------------

class _AnnouncementsTab extends StatefulWidget {
  const _AnnouncementsTab();

  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  List<Announcement>? _published;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<Announcement> notes = await SupportService.fetchAnnouncements();
    if (mounted) {
      setState(() => _published = notes);
    }
  }

  Future<void> _publish() async {
    setState(() => _sending = true);
    final bool ok = await SupportService.publishAnnouncement(
      title: _title.text,
      body: _body.text,
    );
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('הפרסום לא נשמר')));
      return;
    }
    _title.clear();
    _body.clear();
    await _load();
  }

  Future<void> _delete(Announcement note) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'למחוק את ההודעה?',
      message: 'מי שכבר ראה אותה לא יראה אותה שוב בכל מקרה.',
      confirmText: 'מחיקה',
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }
    await SupportService.deleteAnnouncement(note.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Announcement>? published = _published;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        Text(
          'ההודעה תוצג לכל משתמש פעם אחת בלבד, בכניסה הבאה שלו לאפליקציה.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'כותרת',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _body,
          minLines: 3,
          maxLines: 8,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'טקסט קצר',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sending || _title.text.trim().isEmpty ? null : _publish,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.campaign_outlined, size: 18),
            label: const Text('פרסום'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'פורסמו',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (published == null)
          const Center(child: CircularProgressIndicator())
        else if (published.isEmpty)
          Text(
            'עדיין לא פורסמה הודעה.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final Announcement note in published)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(note.title),
              subtitle: Text(
                <String>[
                  AppDateUtils.formatDateShort(note.publishedAt),
                  if (note.body.isNotEmpty) note.body,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'מחיקה',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(note),
              ),
            ),
      ],
    );
  }
}

// --- Administrators ---------------------------------------------------------

class _AdminsTab extends StatefulWidget {
  const _AdminsTab();

  @override
  State<_AdminsTab> createState() => _AdminsTabState();
}

class _AdminsTabState extends State<_AdminsTab> {
  final TextEditingController _email = TextEditingController();
  List<String>? _admins;

  @override
  void initState() {
    super.initState();
    _email.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<String> admins = await SupportService.fetchAdmins();
    if (mounted) {
      setState(() => _admins = admins);
    }
  }

  Future<void> _add() async {
    final bool ok = await SupportService.addAdmin(_email.text);
    if (!mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('לא הצלחנו להוסיף את הכתובת')),
        );
      return;
    }
    _email.clear();
    await _load();
  }

  Future<void> _remove(String email) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: 'להסיר מנהל?',
      message: '$email לא יוכל יותר לפתוח את מסך הניהול.',
      confirmText: 'הסרה',
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }
    await SupportService.removeAdmin(email);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AccountProvider account = context.watch<AccountProvider>();
    final bool isRoot = SupportService.isRootAdmin(account.email);
    final List<String>? admins = _admins;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        Text(
          isRoot
              ? 'הוספה והסרה של מנהלים לפי כתובת מייל. הכתובת חייבת להיות זו '
                    'שאיתה הם מתחברים לאפליקציה.'
              : 'רשימת המנהלים. הוספה והסרה שמורות למנהל הראשי.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        if (isRoot) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'כתובת מייל',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _email.text.trim().contains('@') ? _add : null,
                child: const Text('הוספה'),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.shield_outlined),
          title: Text(SupportService.rootAdminEmail),
          subtitle: const Text('מנהל ראשי — לא ניתן להסרה מתוך האפליקציה'),
        ),
        if (admins == null)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final String email in admins)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(email),
              trailing: isRoot
                  ? IconButton(
                      tooltip: 'הסרה',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(email),
                    )
                  : null,
            ),
      ],
    );
  }
}
