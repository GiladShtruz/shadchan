import 'package:flutter/foundation.dart';
import 'package:shadchan/services/ai_card_parser.dart';
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
  });

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
  }) async {
    final List<List<ParsedPerson>> results = List<List<ParsedPerson>>.filled(
      count,
      const <ParsedPerson>[],
    );
    final Map<int, AiParseException> failures = <int, AiParseException>{};
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
    );
  }

  /// Messages per request for a chat. Smaller than the spreadsheet batch: a
  /// message is longer than a row, and a card can run to a dozen lines.
  static const int messagesPerBatch = 40;

  static Future<AiImportOutcome> runChat(
    WhatsAppChat chat, {
    void Function(int done, int total)? onProgress,
  }) async {
    final List<({int index, WhatsAppMessage message})> candidates =
        chat.candidateMessages;
    final List<List<({int index, WhatsAppMessage message})>> batches =
        _splitChat(candidates);

    debugPrint(
      'AI_IMPORT chat: ${candidates.length} candidate messages, '
      '${batches.length} batches, ${chat.mediaPaths.length} media files',
    );

    // Indexed here so a person's card can be kept word for word: the model
    // points at the message it read them from, and the text comes from the
    // export rather than from the answer.
    final Map<int, String> messageTexts = <int, String>{
      for (final ({int index, WhatsAppMessage message}) entry in candidates)
        if (entry.message.text.isNotEmpty) entry.index: entry.message.text,
    };

    return _runBatches(
      batches.length,
      (int index) => AiPeopleParser.parseChunk(
        WhatsAppChat.toTranscript(batches[index]),
        isChat: true,
        mediaPaths: chat.mediaPaths,
        messageTexts: messageTexts,
      ),
      onProgress: onProgress,
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
