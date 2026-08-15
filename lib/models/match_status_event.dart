import 'package:hive/hive.dart';
import 'package:shadchan/utils/enums.dart';

part 'match_status_event.g.dart';

/// One recorded move of a proposal from one status to another.
///
/// This exists because a proposal's status changes were, until now, the only
/// meaningful thing the app did that left no dated record of its own. The
/// proposal carries `updatedAt`, which is overwritten by the next change and
/// says nothing about what the change *was*; the journal carries an automatic
/// note for some transitions and not others. Counting "how much did I do this
/// month" from either was guesswork, and the earlier version of
/// [ActivityStats] had to infer a status change from the presence of an
/// automatic journal note and then guess, from a five-second window, which
/// person events were the same act propagating.
///
/// Now every transition writes one of these, and the counting is arithmetic.
///
/// Deliberately **not** in the backup, and not in the cloud sync — exactly like
/// [PersonEvent], which this mirrors. What a backup restores is the database: a
/// person, a proposal, a note the matchmaker wrote. The trail of how a record
/// got to its current state is a local ledger, it is worthless without the
/// records it describes, and it is by far the fastest-growing thing here.
@HiveType(typeId: 15)
class MatchStatusEvent extends HiveObject {
  MatchStatusEvent({
    required this.id,
    required this.matchId,
    required this.fromStatus,
    required this.toStatus,
    required this.createdAt,
    this.automatic = false,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String matchId;

  /// Where the proposal was. Null only for a record written by a future
  /// migration that cannot know.
  @HiveField(2)
  final MatchStatus? fromStatus;

  @HiveField(3)
  final MatchStatus toStatus;

  @HiveField(4)
  final DateTime createdAt;

  /// True when the app moved the proposal itself rather than the matchmaker
  /// moving it — a candidate going on a break pushes their open proposals to
  /// "בהמתנה", and that is one decision about a person, not five about
  /// proposals. Still recorded, because it is real history and it explains why
  /// a proposal moved; simply not counted as work.
  @HiveField(5)
  final bool automatic;
}
