import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/account_provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/services/tips_service.dart';
import 'package:shadchan/utils/matchmaker_tips.dart';
import 'package:shadchan/widgets/app_notice.dart';

/// The approval queue for community tips, as a panel.
///
/// A tip written by a matchmaker is **never** shown to anybody else until it is
/// approved here: it is created `pending`, the rotation only ever queries
/// approved tips, and `firestore.rules` refuses a client that tries to publish
/// straight into it. So this queue is the one gate between "somebody wrote a
/// tip" and "every matchmaker reads it", and it lives inside the feedback
/// console beside the reports rather than on a screen of its own.
///
/// Two views: "ממתינים" — approve or reject — and "כל הטיפים", where every
/// existing tip can be opened and edited: its words, whether it is shown, or
/// deleted. That includes the tips that ship with the app, whose edits are
/// stored as override documents (see [CommunityTip.builtInText]).
///
/// The panel is only *drawn* for an administrator; every write it makes is
/// separately checked in `firestore.rules` against the same verified address,
/// so reaching it some other way produces a list of buttons that all fail.
class PendingTipsReview extends StatefulWidget {
  const PendingTipsReview({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 28),
  });

  final EdgeInsetsGeometry padding;

  @override
  State<PendingTipsReview> createState() => _PendingTipsReviewState();
}

class _PendingTipsReviewState extends State<PendingTipsReview> {
  /// false: the approval queue. true: every tip.
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TipsProvider>().refreshPending();
        context.read<TipsProvider>().refreshAll();
      }
    });
  }

  Future<void> _review(CommunityTip tip, TipStatus status) async {
    final OverlayState? notices = AppNotice.capture(context);
    final bool done = await context.read<TipsProvider>().review(tip.id, status);
    if (!mounted || done) {
      return;
    }
    AppNotice.showOn(notices, 'הפעולה נכשלה');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TipsProvider tips = context.watch<TipsProvider>();
    final AccountProvider account = context.watch<AccountProvider>();

    if (!account.isTipsAdmin) {
      return const _Message(text: 'החשבון המחובר אינו חשבון הניהול.');
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: <ButtonSegment<bool>>[
                ButtonSegment<bool>(
                  value: false,
                  label: Text(
                    tips.pending.isEmpty
                        ? 'ממתינים'
                        : 'ממתינים (${tips.pending.length})',
                  ),
                ),
                const ButtonSegment<bool>(
                  value: true,
                  label: Text('כל הטיפים'),
                ),
              ],
              selected: <bool>{_showAll},
              onSelectionChanged: (Set<bool> value) =>
                  setState(() => _showAll = value.first),
            ),
          ),
        ),
        Expanded(
          child: _showAll
              ? _AllTipsList(padding: widget.padding)
              : _pendingList(context, theme, tips),
        ),
      ],
    );
  }

  Widget _pendingList(
    BuildContext context,
    ThemeData theme,
    TipsProvider tips,
  ) {
    if (tips.pending.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<TipsProvider>().refreshPending(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            _Message(
              text: tips.isBusy ? 'טוען…' : 'אין כרגע טיפים שממתינים לאישור.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<TipsProvider>().refreshPending(),
      child: ListView.separated(
        padding: widget.padding,
        itemCount: tips.pending.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return _WaitingBanner(count: tips.pending.length, theme: theme);
          }
          final CommunityTip tip = tips.pending[index - 1];
          return _PendingTipCard(
            tip: tip,
            onApprove: () => _review(tip, TipStatus.approved),
            onReject: () => _review(tip, TipStatus.rejected),
          );
        },
      ),
    );
  }
}

/// Every existing tip — the app's own and the community's — each one opening
/// an editor on a tap.
class _AllTipsList extends StatelessWidget {
  const _AllTipsList({required this.padding});

  final EdgeInsetsGeometry padding;

  Future<void> _editBuiltIn(BuildContext context, BuiltInTip tip) async {
    final TipsProvider provider = context.read<TipsProvider>();
    final OverlayState? notices = AppNotice.capture(context);
    final _TipEdit? edit = await _TipEditorSheet.show(
      context,
      text: tip.text,
      shown: !tip.hidden,
      builtIn: true,
      canRestore: tip.edited,
    );
    if (edit == null) {
      return;
    }
    final bool done;
    if (edit.delete) {
      done = await provider.delete(tip.override!.id);
    } else {
      done = await provider.editBuiltIn(
        tip,
        text: edit.text,
        hidden: !edit.shown,
      );
    }
    AppNotice.showOn(notices, done ? 'הטיפ עודכן' : 'העדכון נכשל');
  }

  Future<void> _editCommunity(BuildContext context, CommunityTip tip) async {
    final TipsProvider provider = context.read<TipsProvider>();
    final OverlayState? notices = AppNotice.capture(context);
    final _TipEdit? edit = await _TipEditorSheet.show(
      context,
      text: tip.text,
      shown: tip.status == TipStatus.approved && !tip.hidden,
      builtIn: false,
      canRestore: true,
    );
    if (edit == null) {
      return;
    }
    final bool done = edit.delete
        ? await provider.delete(tip.id)
        : await provider.edit(
            tip,
            text: edit.text,
            status: edit.shown ? TipStatus.approved : TipStatus.rejected,
            hidden: false,
          );
    AppNotice.showOn(
      notices,
      done ? (edit.delete ? 'הטיפ נמחק' : 'הטיפ עודכן') : 'העדכון נכשל',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TipsProvider tips = context.watch<TipsProvider>();
    final List<BuiltInTip> builtIn = tips.builtInTips(MatchmakerTips.tips);
    final List<CommunityTip> community = <CommunityTip>[
      for (final CommunityTip tip in tips.all)
        if (!tip.isBuiltInOverride && tip.status != TipStatus.pending) tip,
    ];

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: () => context.read<TipsProvider>().refreshAll(),
      child: ListView(
        padding: padding,
        children: <Widget>[
          heading('טיפים של שדכנים (${community.length})'),
          if (community.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                tips.isBusy ? 'טוען…' : 'אין עדיין טיפים של שדכנים.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final CommunityTip tip in community)
            _EditableTipRow(
              text: tip.text,
              caption: <String>[
                if (tip.authorName.isNotEmpty) tip.authorName,
                tip.status == TipStatus.approved ? 'מוצג' : 'לא מוצג',
              ].join(' · '),
              dimmed: tip.status != TipStatus.approved,
              onTap: () => _editCommunity(context, tip),
            ),
          const SizedBox(height: 12),
          heading('טיפים מובנים באפליקציה (${builtIn.length})'),
          for (final BuiltInTip tip in builtIn)
            _EditableTipRow(
              text: tip.text,
              caption: tip.hidden
                  ? 'מוסתר'
                  : tip.edited
                  ? 'נערך'
                  : null,
              dimmed: tip.hidden,
              onTap: () => _editBuiltIn(context, tip),
            ),
        ],
      ),
    );
  }
}

class _EditableTipRow extends StatelessWidget {
  const _EditableTipRow({
    required this.text,
    required this.onTap,
    this.caption,
    this.dimmed = false,
  });

  final String text;
  final String? caption;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          color: dimmed
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                      if (caption != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          caption!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the editor answered.
class _TipEdit {
  const _TipEdit({
    required this.text,
    required this.shown,
    this.delete = false,
  });

  final String text;
  final bool shown;

  /// Delete the tip — or, for a built-in one, drop the edit and restore the
  /// app's own words.
  final bool delete;
}

class _TipEditorSheet extends StatefulWidget {
  const _TipEditorSheet({
    required this.text,
    required this.shown,
    required this.builtIn,
    required this.canRestore,
  });

  final String text;
  final bool shown;
  final bool builtIn;
  final bool canRestore;

  static Future<_TipEdit?> show(
    BuildContext context, {
    required String text,
    required bool shown,
    required bool builtIn,
    required bool canRestore,
  }) {
    return showModalBottomSheet<_TipEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _TipEditorSheet(
        text: text,
        shown: shown,
        builtIn: builtIn,
        canRestore: canRestore,
      ),
    );
  }

  @override
  State<_TipEditorSheet> createState() => _TipEditorSheetState();
}

class _TipEditorSheetState extends State<_TipEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  late bool _shown = widget.shown;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            widget.builtIn ? 'עריכת טיפ מובנה' : 'עריכת טיפ',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (widget.builtIn) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'אפשר להשאיר צורות כמו {אתה|את} — הן יוצגו לפי המגדר של השדכן.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 8,
            maxLength: TipsService.maxLength,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('מוצג לכל השדכנים'),
            value: _shown,
            onChanged: (bool value) => setState(() => _shown = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final String text = _controller.text.trim();
                    if (text.isEmpty) {
                      return;
                    }
                    Navigator.of(
                      context,
                    ).pop(_TipEdit(text: text, shown: _shown));
                  },
                  child: const Text('שמירה'),
                ),
              ),
              if (widget.canRestore) ...<Widget>[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    _TipEdit(text: widget.text, shown: _shown, delete: true),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: widget.builtIn
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.error,
                  ),
                  child: Text(widget.builtIn ? 'שחזור הנוסח המקורי' : 'מחיקה'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The standalone screen, kept for the settings row and the old route. It is
/// the same panel with a bar over it.
class TipsAdminScreen extends StatelessWidget {
  const TipsAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TipsProvider tips = context.watch<TipsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('אישור טיפים'),
        actions: <Widget>[
          IconButton(
            tooltip: 'רענון',
            onPressed: tips.isBusy ? null : tips.refreshPending,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: const SafeArea(child: PendingTipsReview()),
    );
  }
}

/// "יש טיפים שממתינים לאישור" — the alert the queue raises the moment somebody
/// sends one, so the console says what is waiting before it is scrolled.
class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner({required this.count, required this.theme});

  final int count;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.notifications_active_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? 'טיפ אחד ממתין לאישור. עד שיאושר הוא לא מוצג לאף שדכן.'
                  : '$count טיפים ממתינים לאישור. עד שיאושרו הם לא מוצגים '
                        'לאף שדכן.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingTipCard extends StatelessWidget {
  const _PendingTipCard({
    required this.tip,
    required this.onApprove,
    required this.onReject,
  });

  final CommunityTip tip;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            tip.text,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 8),
          Text(
            tip.authorName.isEmpty ? 'ללא שם' : tip.authorName,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('אישור'),
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onReject,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                child: const Text('דחייה'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
