import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/services/community_prompts_store.dart';
import 'package:shadchan/services/mazel_tov_service.dart';
import 'package:shadchan/services/notification_service.dart';

/// Collects the congratulations addressed to this device and files them.
///
/// **Runs at the two moments everything else in this app runs at** — app open
/// and app pause, from `CloudSyncScheduler`. There is no listener and no push:
/// a "מזל טוב" is warm, not urgent, and the difference between hearing about it
/// now and hearing about it when the app is next opened is not worth a socket
/// held open on somebody's phone all day.
///
/// The order is deliberate and is the whole of the delivery guarantee:
///
/// 1. read the inbox,
/// 2. write each message into its proposal's journal and remember its id,
/// 3. raise **one** notification per proposal, and only the first time,
/// 4. delete the messages from the server.
///
/// A crash between any two steps loses nothing and duplicates nothing: an
/// undeleted message is recognised by its id on the next run and skipped, and a
/// proposal that has already raised its notification never raises another.
abstract final class MazelTovInbox {
  /// Files whatever is waiting. Returns how many messages were written into a
  /// journal, which is only used by tests — nothing in the app cares.
  static Future<int> drain(MatchRepository matches) async {
    final List<MazelTovMessage> messages = await MazelTovService.inbox();
    if (messages.isEmpty) {
      return 0;
    }

    final List<String> collected = <String>[];
    final Set<String> touchedMatches = <String>{};
    int filed = 0;

    for (final MazelTovMessage message in messages) {
      // Already in a journal: the server delete failed last time, and filing
      // it again would show the same bracha twice.
      if (CommunityPromptsStore.hasDeliveredMazelTov(message.id)) {
        collected.add(message.id);
        continue;
      }
      final bool written = await matches.addMazelTov(
        matchId: message.matchId,
        text: message.text,
        fromName: message.fromName,
        at: message.at,
      );
      // Collected either way. A message for a proposal that has since been
      // deleted has nowhere to go, and leaving it on the server would mean
      // retrying it for ever.
      collected.add(message.id);
      CommunityPromptsStore.markMazelTovDelivered(message.id);
      if (written) {
        filed++;
        touchedMatches.add(message.matchId);
      }
    }

    for (final String matchId in touchedMatches) {
      if (CommunityPromptsStore.hasNotifiedMazelTov(matchId)) {
        continue;
      }
      CommunityPromptsStore.markMazelTovNotified(matchId);
      await NotificationService.showMazelTov(matchId);
    }

    await MazelTovService.markDelivered(collected);
    return filed;
  }
}
