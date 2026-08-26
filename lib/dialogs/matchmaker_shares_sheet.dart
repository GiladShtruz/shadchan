import 'package:flutter/material.dart';
import 'package:shadchan/models/community_profile.dart';

/// "מה תרצה ששדכנים אחרים ידעו עליך?" — one field on the profile, and a menu
/// of prompts behind it.
///
/// **One field instead of four, and that is the whole change.** The profile
/// asked separately for a region, a population, a role and so on: four labelled
/// boxes, which is a form, and a form asks everybody every question. Most
/// matchmakers have two of these and nothing honest to put in the rest, so what
/// came back was either mostly blank or padded — and the public page then had
/// to draw a table with holes in it.
///
/// So the sheet offers the prompts as a list to *pick from*. Every one of them
/// is optional, filling one in is a line of text, and what comes out is shown on
/// the public page as one tidy area rather than as separate fields. See
/// [MatchmakerShareKind].
///
/// **Nothing is written until "שמירה".** Each prompt opens its own small
/// editor, and closing the sheet with the back gesture leaves the profile
/// exactly as it was — which matters because this is the one screen in the app
/// whose contents other people will read.
class MatchmakerSharesSheet extends StatefulWidget {
  const MatchmakerSharesSheet({super.key, required this.initial});

  final List<MatchmakerShare> initial;

  /// Returns the new list, or null when the sheet was dismissed.
  static Future<List<MatchmakerShare>?> show(
    BuildContext context, {
    required List<MatchmakerShare> initial,
  }) {
    return showModalBottomSheet<List<MatchmakerShare>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) =>
          MatchmakerSharesSheet(initial: initial),
    );
  }

  @override
  State<MatchmakerSharesSheet> createState() => _MatchmakerSharesSheetState();
}

class _MatchmakerSharesSheetState extends State<MatchmakerSharesSheet> {
  late final Map<MatchmakerShareKind, TextEditingController> _fields =
      <MatchmakerShareKind, TextEditingController>{
        for (final MatchmakerShareKind kind in MatchmakerShareKind.values)
          kind: TextEditingController(
            text: widget.initial
                .where((MatchmakerShare share) => share.kind == kind)
                .map((MatchmakerShare share) => share.text)
                .firstOrNull,
          ),
      };

  @override
  void dispose() {
    for (final TextEditingController controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(<MatchmakerShare>[
      for (final MatchmakerShareKind kind in MatchmakerShareKind.values)
        if (_fields[kind]!.text.trim() case final String text
            when text.isNotEmpty)
          MatchmakerShare(
            kind: kind,
            text: text.length <= MatchmakerShare.maxLength
                ? text
                : text.substring(0, MatchmakerShare.maxLength),
          ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      // Above the keyboard: every row here is a text field, and a sheet whose
      // last field is under the keyboard is a sheet whose last field does not
      // exist.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'מה תרצה ששדכנים אחרים ידעו עליך?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'למלא רק את מה שרלוונטי. כל מה שתמלא יופיע יחד בפרופיל הציבורי '
                'שלך, ומה שתשאיר ריק פשוט לא יופיע.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              for (final MatchmakerShareKind kind
                  in MatchmakerShareKind.values) ...<Widget>[
                TextField(
                  controller: _fields[kind],
                  maxLength: MatchmakerShare.maxLength,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: kind.label,
                    hintText: kind.hint,
                    // The counter is noise on five fields at once; the cap is
                    // still enforced, it is simply not announced.
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('שמירה'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "הטבה לקהילה" — one line a matchmaker may offer other matchmakers.
///
/// A sheet of its own rather than a sixth prompt above, because it is a
/// different kind of thing: the prompts describe who somebody is, and this is
/// something they are offering. On the public page it gets its own area for the
/// same reason.
class CommunityBenefitSheet extends StatefulWidget {
  const CommunityBenefitSheet({super.key, required this.initial});

  final String initial;

  /// Returns the new text (possibly empty, meaning "remove it"), or null when
  /// the sheet was dismissed.
  static Future<String?> show(BuildContext context, {required String initial}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) =>
          CommunityBenefitSheet(initial: initial),
    );
  }

  @override
  State<CommunityBenefitSheet> createState() => _CommunityBenefitSheetState();
}

class _CommunityBenefitSheetState extends State<CommunityBenefitSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'הטבה לקהילה',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'משהו שתרצה להציע לשדכנים אחרים בקהילה. אם תוסיף, זה יופיע '
                'בפרופיל הציבורי שלך.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                maxLength: CommunityProfile.maxBenefitLength,
                decoration: const InputDecoration(
                  hintText:
                      'למשל: אשמח לייעץ בהתנעת מאגר · פגישת ייעוץ ללא '
                      'תשלום',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_controller.text.trim()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('שמירה'),
              ),
              if (widget.initial.trim().isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('הסרת ההטבה'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The number the WhatsApp button on the public page opens.
///
/// **Typed in, never taken from the database.** The app knows hundreds of phone
/// numbers and none of them belong here: this one goes into a collection every
/// installed copy of the app can read, so it has to be a number somebody
/// deliberately decided to publish. The sheet says so in as many words, because
/// a field labelled only "טלפון" on a profile screen would be filled in by
/// people who assumed it was private.
class CommunityPhoneSheet extends StatefulWidget {
  const CommunityPhoneSheet({super.key, required this.initial});

  final String initial;

  /// Returns the new number (possibly empty, meaning "remove it"), or null when
  /// the sheet was dismissed.
  static Future<String?> show(BuildContext context, {required String initial}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) =>
          CommunityPhoneSheet(initial: initial),
    );
  }

  @override
  State<CommunityPhoneSheet> createState() => _CommunityPhoneSheetState();
}

class _CommunityPhoneSheetState extends State<CommunityPhoneSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'מספר לפנייה בוואטסאפ',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'המספר הזה יופיע לשדכנים אחרים בפרופיל הציבורי שלך, ככפתור '
                'ווטסאפ. אפשר להשאיר ריק — אז פשוט לא יהיה כפתור.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.phone,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'מספר טלפון',
                  hintText: '050-0000000',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_controller.text.trim()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('שמירה'),
              ),
              if (widget.initial.trim().isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('הסרת המספר'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
