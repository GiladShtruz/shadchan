import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadchan/services/community_engagements_service.dart';

/// The two halves of "מזל טוב! זוג חדש התארס!": the note everybody sees, and
/// the decision the one matchmaker who was there gets to make about it.
///
/// They are in one file because the second is only meaningful as an answer to
/// the first. What the community is shown by default is a sentence with nobody
/// in it; [PublishEngagementSheet] is the narrow, deliberate, revocable way a
/// matchmaker can put two first names and a photograph into that sentence, and
/// keeping the two side by side is what stops the default quietly drifting.

/// What happens the moment a proposal becomes a wedding.
///
/// **The anonymous record is written first and unconditionally; the offer to
/// say more comes second and may be declined by doing nothing.** That order is
/// the feature. If the sheet came first, "not now" would mean the community
/// heard nothing at all, and the natural fix for that would be to publish the
/// names by default — which is exactly the design this avoids.
abstract final class EngagementFlow {
  /// Records the engagement and then offers to put names to it.
  ///
  /// Silent on every failure. A matchmaker who has just marked a wedding is
  /// having the best moment this app has to offer, and a network error is not
  /// worth interrupting it — the couple is already recorded locally, and the
  /// community note is the part that can afford to be lost.
  static Future<void> celebrate(
    BuildContext context, {
    required String matchId,
    required String firstNameA,
    required String firstNameB,
    required String matchmakerName,
    required bool shareName,
    required bool private,
  }) async {
    // "שמור על הפרטיות שלי" covers this too. A wedding is something this
    // matchmaker did, and somebody who asked for none of what they do to be
    // shared has not made an exception for the best of it.
    if (private) {
      return;
    }
    final String? engagementId = await CommunityEngagementsService.record(
      // Carried so other matchmakers can send a bracha back into this
      // proposal's own journal. A uuid from this phone, meaningless anywhere
      // else — see `CommunityEngagement.matchId`.
      matchId: matchId,
      // Only for somebody who already publishes their name on the leaderboard.
      // Everybody else's couple is announced without one, and can still be
      // congratulated.
      matchmakerName: shareName ? matchmakerName : '',
    );
    if (engagementId == null || !context.mounted) {
      return;
    }
    // Most matchmakers never connect an account, and for them the anonymous
    // note is the whole feature — the sheet is not offered rather than offered
    // and then refused by the rules.
    if (!await CommunityEngagementsService.canPublishNames() ||
        !context.mounted) {
      return;
    }
    final String names = <String>[
      firstNameA.trim(),
      firstNameB.trim(),
    ].where((String name) => name.isNotEmpty).join(' ו');
    if (names.isEmpty) {
      // Nothing to offer — the anonymous note has gone out and that is all
      // this couple will ever be to anybody else.
      return;
    }
    await PublishEngagementSheet.show(
      context,
      engagementId: engagementId,
      firstNames: names,
      matchmakerName: matchmakerName,
    );
  }
}

/// The congratulation, shown once per couple and then never again.
///
/// Small, warm and gone in a few seconds — the same shape as the achievement
/// note, because it is the same kind of moment. There is no button and there is
/// nowhere to tap through to: this is news, not a screen.
/// `MazelTovDialog` used to live here: somebody else's engagement, announced by
/// taking over the screen on the next launch. It is `HomeEngagementCard` now —
/// a card on the home page for one launch, read when the eye reaches it. The
/// news was always worth carrying; the interruption never was.

/// The offer to say more than "a couple", made once, to the one person who
/// could possibly have the right to make it.
///
/// **Nothing is published without the tick.** The confirm button is disabled
/// until the matchmaker states that the couple agreed, the service refuses the
/// write without it, and the security rules refuse it a third time. Three
/// checks for one box is not belt and braces — it is the only thing standing
/// between a private database and two real people's names on a server that
/// every installed copy of this app can read.
///
/// **First names only, and that is not editable.** A surname turns an
/// announcement into an identification, and the choice of which one to publish
/// is not a choice worth offering.
abstract final class PublishEngagementSheet {
  static Future<void> show(
    BuildContext context, {
    required String engagementId,
    required String firstNames,
    required String matchmakerName,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => _PublishBody(
        engagementId: engagementId,
        firstNames: firstNames,
        matchmakerName: matchmakerName,
      ),
    );
  }
}

class _PublishBody extends StatefulWidget {
  const _PublishBody({
    required this.engagementId,
    required this.firstNames,
    required this.matchmakerName,
  });

  final String engagementId;
  final String firstNames;
  final String matchmakerName;

  @override
  State<_PublishBody> createState() => _PublishBodyState();
}

class _PublishBodyState extends State<_PublishBody> {
  bool _approved = false;
  bool _withMyName = true;
  bool _working = false;
  File? _photo;

  Future<void> _pickPhoto() async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() => _photo = File(picked.path));
    } catch (_) {
      if (mounted) {
        _say('לא הצלחנו לבחור תמונה כרגע');
      }
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _publish() async {
    if (!_approved || _working) {
      return;
    }
    setState(() => _working = true);

    // Taken before the sheet closes: after the pop this State's context is on
    // its way out, and the confirmation belongs to the screen underneath.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool ok = await CommunityEngagementsService.publish(
      engagementId: widget.engagementId,
      firstNames: widget.firstNames,
      matchmakerName: _withMyName ? widget.matchmakerName : '',
      coupleApproved: _approved,
      photo: _photo,
    );

    if (mounted) {
      Navigator.of(context).pop();
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'פורסם. מזל טוב!'
                : 'לא הצלחנו לפרסם כרגע. ההודעה האנונימית פורסמה בכל מקרה.',
          ),
          // The way back. There is deliberately no screen listing published
          // couples — that would be the archive this feature is not — so the
          // moment right after publishing is the one place an accidental
          // publication can be undone, and it has to actually be offered here.
          // Withdrawing deletes the document and the photograph; the anonymous
          // "מזל טוב" goes with them, which is the correct reading of a couple
          // who changed their mind.
          duration: ok
              ? const Duration(seconds: 8)
              : const Duration(seconds: 4),
          action: ok
              ? SnackBarAction(
                  label: 'ביטול הפרסום',
                  onPressed: () async {
                    final bool removed =
                        await CommunityEngagementsService.withdraw(
                          widget.engagementId,
                        );
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            removed
                                ? 'הפרסום בוטל והוסר.'
                                : 'לא הצלחנו לבטל כרגע. כדאי לנסות שוב כשיש '
                                      'חיבור לאינטרנט.',
                          ),
                        ),
                      );
                  },
                )
              : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'לפרסם את הזוג לקהילה?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'ההודעה על הזוג כבר פורסמה לקהילה — בלי שמות ובלי שום פרט. '
              'כאן אפשר לבחור להוסיף לה את השמות הפרטיים, תמונה ואת שמך.\n\n'
              'זה יוצא מהמכשיר ונראה לכל מי שמשתמש באפליקציה, אז מותר רק אם '
              'בני הזוג אמרו לך במפורש שזה בסדר.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 18),
            _Line(label: 'שמות פרטיים', value: widget.firstNames),
            if (_withMyName && widget.matchmakerName.trim().isNotEmpty)
              _Line(label: 'שם השדכן', value: widget.matchmakerName),
            const SizedBox(height: 6),
            if (_photo != null) ...<Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  _photo!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _working ? null : _pickPhoto,
                icon: const Icon(Icons.photo_outlined, size: 20),
                label: Text(
                  _photo == null ? 'הוספת תמונה (לא חובה)' : 'החלפת התמונה',
                ),
              ),
            ),
            if (widget.matchmakerName.trim().isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _withMyName,
                onChanged: _working
                    ? null
                    : (bool value) => setState(() => _withMyName = value),
                title: Text(
                  'להציג גם את שמי כשדכן',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            const Divider(height: 24),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _approved,
              onChanged: _working
                  ? null
                  : (bool? value) => setState(() => _approved = value ?? false),
              title: Text(
                'קיבלתי מבני הזוג אישור מפורש לפרסם את השמות והתמונה',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: _working
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('להשאיר אנונימי'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    // Disabled, not merely refused on tap: the box is the
                    // decision, and a button that looks available until it is
                    // pressed teaches people to press first and read after.
                    onPressed: _approved && !_working ? _publish : null,
                    child: Text(_working ? 'מפרסם…' : 'לפרסם'),
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

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
