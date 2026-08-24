import 'package:flutter/foundation.dart';
import 'package:shadchan/services/ai_card_parser.dart';
import 'package:shadchan/services/ai_import_memory.dart';
import 'package:shadchan/services/ai_people_parser.dart';
import 'package:shadchan/services/excel_import_service.dart';
import 'package:shadchan/services/whatsapp_import_service.dart';
import 'package:shadchan/utils/parsed_person.dart';

/// What a finished import produced, including what it failed to read.
@immutable
class AiImportOutcome {
  const AiImportOutcome({
    required this.people,
    required this.failedBatches,
    required this.totalBatches,
    this.firstFailure,
    this.processedKeys = const <String>{},
  });

  /// Fingerprints of the messages that were **successfully** read, for
  /// [AiImportMemory] to record once the user actually keeps the result.
  ///
  /// Only successful batches contribute. A batch that threw has been paid for
  /// but produced nothing, and remembering its messages would mean the retry
  /// that was supposed to fix it skips exactly the cards that failed — the one
  /// outcome worse than paying twice.
  final Set<String> processedKeys;

  /// What went wrong first, kept so the screen can say *why* an import found
  /// nothing instead of offering "try again" to someone whose device is simply
  /// not attested.
  final AiParseException? firstFailure;

  final List<ParsedPerson> people;

  /// Batches that threw. Reported rather than swallowed: sixty rows that come
  /// back as forty people look exactly like a successful import of a shorter
  /// file, and the user is the only one who can tell the difference.
  final int failedBatches;

  final int totalBatches;

  bool get isComplete => failedBatches == 0;
  bool get isEmpty => people.isEmpty;
}

/// What an import is about to cost, worked out before anything is sent.
///
/// Built so the screen can ask first. An import is the one action in the app
/// that spends tokens on somebody's behalf and runs for minutes, and it used to
/// start the instant a file was picked — so a mis-picked 20,000-message export
/// was already running before its owner could see what they had chosen.
@immutable
class AiImportPlan {
  const AiImportPlan({
    required this.batches,
    required this.skipped,
    required this.duplicatesDropped,
    required this.mediaPaths,
    required this.messageTexts,
  });

  /// The requests that would be made, in order.
  final List<List<({int index, WhatsAppMessage message})>> batches;

  /// Candidate messages left out because this device has already read them —
  /// the saving from [AiImportMemory], and the number worth showing, because
  /// on a re-export it is most of the file.
  final int skipped;

  /// Messages the file itself repeated, or that carried no person at all.
  /// Everything between the raw chat and the candidate list.
  final int duplicatesDropped;

  final Map<String, String> mediaPaths;
  final Map<int, String> messageTexts;

  int get batchCount => batches.length;

  int get messageCount => batches.fold<int>(
    0,
    (int sum, List<({int index, WhatsAppMessage message})> b) => sum + b.length,
  );

  /// True when the memory accounted for the whole file — a re-export with
  /// nothing new in it, which must be said rather than run as an import that
  /// finds nobody.
  bool get isEmpty => batches.isEmpty;
}

/// Feeds a workbook through the model a batch at a time.
///
/// Batching is what keeps a large file honest — see [AiPeopleParser.rowsPerBatch]
/// — and it also means one bad chunk costs its own rows instead of the file.
abstract final class AiImportRunner {
  /// How many batches are in flight at once.
  ///
  /// Batches are independent requests, so running them one after another made
  /// an import take the *sum* of every round trip when it only ever needed the
  /// slowest one. Bounded rather than unlimited because a large chat produces
  /// dozens of batches, and firing all of them at Vertex at once trades a slow
  /// import for a rate-limited one.
  static const int maxConcurrentBatches = 5;

  /// Runs [count] independent batches, at most [maxConcurrentBatches] at a
  /// time, and returns their people in batch order.
  ///
  /// Order is preserved deliberately: results arrive as they finish, but a
  /// person's place in the review list should follow the file, not the network.
  static Future<AiImportOutcome> _runBatches(
    int count,
    Future<List<ParsedPerson>> Function(int index) runBatch, {
    void Function(int done, int total)? onProgress,
    Set<String> Function(int index)? keysFor,
  }) async {
    final List<List<ParsedPerson>> results = List<List<ParsedPerson>>.filled(
      count,
      const <ParsedPerson>[],
    );
    final Map<int, AiParseException> failures = <int, AiParseException>{};
    final Set<String> processedKeys = <String>{};
    int nextIndex = 0;
    int done = 0;
    onProgress?.call(0, count);

    Future<void> worker() async {
      while (true) {
        if (nextIndex >= count) {
          return;
        }
        final int index = nextIndex++;
        try {
          results[index] = await runBatch(index);
          if (keysFor != null) {
            processedKeys.addAll(keysFor(index));
          }
          debugPrint(
            'AI_IMPORT batch ${index + 1}/$count: ${results[index].length} people',
          );
        } on AiParseException catch (error) {
          failures[index] = error;
          debugPrint(
            'AI_IMPORT batch ${index + 1}/$count FAILED '
            'reason=${error.reason} cause=${error.cause}',
          );
        }
        onProgress?.call(++done, count);
      }
    }

    await Future.wait(<Future<void>>[
      for (
        int i = 0;
        i < (count < maxConcurrentBatches ? count : maxConcurrentBatches);
        i++
      )
        worker(),
    ]);

    // Reported by lowest batch index rather than by whichever failed first, so
    // the same file always explains itself the same way.
    final List<int> failedIndexes = failures.keys.toList()..sort();

    return AiImportOutcome(
      people: <ParsedPerson>[
        for (final List<ParsedPerson> batch in results) ...batch,
      ],
      failedBatches: failures.length,
      totalBatches: count,
      firstFailure: failedIndexes.isEmpty
          ? null
          : failures[failedIndexes.first],
      processedKeys: processedKeys,
    );
  }

  /// Messages per request for a chat.
  ///
  /// **Raised from 40, to stop paying for the same instruction a hundred
  /// times.** Every batch resends [AiPeopleParser]'s chat instruction — about a
  /// thousand tokens of it — so at 40 messages a batch, a large group export
  /// spent roughly a quarter of the whole import restating the rules to a model
  /// that had just been told them. At 100 that overhead falls to under a tenth,
  /// and a 4,000-message group costs 40 requests instead of 100.
  ///
  /// Not raised further, and this is the ceiling rather than a step on the way
  /// to one: the model has to hold every card in the window at once to place a
  /// photo against the right one, and a batch that overruns costs a whole
  /// hundred messages when it fails rather than forty. The gain past here is
  /// small — the overhead is already down to a tenth — and the failure gets
  /// steadily more expensive. Worth re-measuring against a real export before
  /// moving it again.
  static const int messagesPerBatch = 100;

  static Future<AiImportOutcome> runChat(
    AiImportPlan plan, {
    void Function(int done, int total)? onProgress,
  }) async {
    debugPrint(
      'AI_IMPORT chat: ${plan.messageCount} candidate messages '
      '(${plan.skipped} already imported), ${plan.batchCount} batches, '
      '${plan.mediaPaths.length} media files',
    );

    return _runBatches(
      plan.batchCount,
      (int index) => AiPeopleParser.parseChunk(
        WhatsAppChat.toTranscript(plan.batches[index]),
        isChat: true,
        mediaPaths: plan.mediaPaths,
        messageTexts: plan.messageTexts,
      ),
      onProgress: onProgress,
      keysFor: (int index) => <String>{
        for (final ({int index, WhatsAppMessage message}) entry
            in plan.batches[index])
          AiImportMemory.fingerprint(
            sender: entry.message.sender,
            text: entry.message.text,
            attachmentName: entry.message.attachmentName,
          ),
      },
    );
  }

  /// Works out what would be sent, without sending it.
  ///
  /// [alreadyImported] is [AiImportMemory.seen] — the fingerprints this device
  /// has read before. Filtering here rather than inside [runChat] is what lets
  /// the screen say "1,240 of these were already imported" *before* the user
  /// commits to anything.
  static AiImportPlan planChat(
    WhatsAppChat chat, {
    Set<String> alreadyImported = const <String>{},
  }) {
    final List<({int index, WhatsAppMessage message})> candidates =
        chat.candidateMessages;
    final List<({int index, WhatsAppMessage message})> fresh =
        <({int index, WhatsAppMessage message})>[
          for (final ({int index, WhatsAppMessage message}) entry in candidates)
            if (!alreadyImported.contains(
              AiImportMemory.fingerprint(
                sender: entry.message.sender,
                text: entry.message.text,
                attachmentName: entry.message.attachmentName,
              ),
            ))
              entry,
        ];

    return AiImportPlan(
      batches: _splitChat(fresh),
      skipped: candidates.length - fresh.length,
      duplicatesDropped: chat.messages.length - candidates.length,
      mediaPaths: chat.mediaPaths,
      // Indexed here so a person's card can be kept word for word: the model
      // points at the message it read them from, and the text comes from the
      // export rather than from the answer. Built over *every* candidate, not
      // just the fresh ones — a photo posted last month can still belong to a
      // card posted today.
      messageTexts: <int, String>{
        for (final ({int index, WhatsAppMessage message}) entry in candidates)
          if (entry.message.text.isNotEmpty) entry.index: entry.message.text,
      },
    );
  }

  /// Splits the conversation without separating a photo from the card it
  /// belongs to.
  ///
  /// A cut between the two is invisible in the result — each half parses fine,
  /// the person simply arrives with no picture — so the boundary walks forward
  /// past any run of messages carrying attachments before it settles.
  static List<List<({int index, WhatsAppMessage message})>> _splitChat(
    List<({int index, WhatsAppMessage message})> candidates,
  ) {
    final List<List<({int index, WhatsAppMessage message})>> batches =
        <List<({int index, WhatsAppMessage message})>>[];
    int start = 0;
    while (start < candidates.length) {
      int end = (start + messagesPerBatch).clamp(0, candidates.length);
      // Never end on, or immediately after, an attachment: the card that
      // explains it is likely to be on the other side of the cut.
      while (end < candidates.length &&
          end - start < messagesPerBatch * 2 &&
          (candidates[end - 1].message.hasAttachment ||
              candidates[end].message.hasAttachment)) {
        end++;
      }
      batches.add(candidates.sublist(start, end));
      start = end;
    }
    return batches;
  }

  static Future<AiImportOutcome> runTables(
    List<ExcelTable> tables, {
    void Function(int done, int total)? onProgress,
  }) async {
    final List<({ExcelTable table, int startRow})> batches =
        <({ExcelTable table, int startRow})>[];
    for (final ExcelTable table in tables) {
      for (
        int start = 0;
        start < table.rows.length;
        start += AiPeopleParser.rowsPerBatch
      ) {
        batches.add((table: table, startRow: start));
      }
    }

    debugPrint(
      'AI_IMPORT excel: ${tables.length} sheet(s), '
      '${tables.fold(0, (int sum, ExcelTable t) => sum + t.rows.length)} rows, '
      '${batches.length} batches',
    );

    return _runBatches(batches.length, (int index) {
      final ({ExcelTable table, int startRow}) batch = batches[index];
      // Each batch carries its sheet's name, because a workbook split into
      // "גברים" and "נשים" says something about its rows that the rows
      // themselves do not.
      return AiPeopleParser.parseChunk(
        'גיליון: ${batch.table.sheetName}\n'
        '${batch.table.toPromptText(startRow: batch.startRow, maxRows: AiPeopleParser.rowsPerBatch)}',
      );
    }, onProgress: onProgress);
  }
}
