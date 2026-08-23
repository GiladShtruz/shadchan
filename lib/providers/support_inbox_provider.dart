import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/notification_service.dart';
import 'package:shadchan/services/support_service.dart';

/// One thread worth showing on the notifications page.
class SupportThread {
  const SupportThread({required this.report, required this.unread});

  final SupportReport report;

  /// Whether the last thing said in it arrived after this device last looked.
  final bool unread;
}

/// What the support side of the app has to say, and whether any of it is new.
///
/// **Two audiences, one provider, because it is one question asked twice.** An
/// administrator wants to know that a report arrived; the person who sent a
/// report wants to know that somebody answered. Both are "has something
/// happened on a `supportReports` document since I last looked", both are read
/// at the same two moments as everything else in this app (open and resume),
/// and both end up on the same notifications page.
///
/// **Read is remembered locally, not on the server.** A "seen" flag in
/// Firestore would be a write per glance from every device, and would make the
/// answer wrong the moment somebody opens the app on a second phone. What is
/// stored here is one timestamp per side in the settings box: the newest thing
/// this device has been shown.
class SupportInboxProvider extends ChangeNotifier {
  SupportInboxProvider(this._settings, {this.enabled = true});

  final Box<dynamic> _settings;

  /// False in widget tests. Same seam as `SyncProvider` and `TipsProvider`:
  /// every read here goes through `FirebaseBootstrap.ensureReady`, whose
  /// thirty-second deadline never resolves inside `testWidgets`' fake-async
  /// zone and fails the test with a pending timer.
  final bool enabled;

  /// The newest report `createdAt` an administrator on this device has seen.
  static const String _seenReportsKey = 'support_seen_reports_at';

  /// The newest `lastMessageAt` this device has been shown, per side.
  static const String _seenThreadsKey = 'support_seen_threads_at';

  List<SupportReport> _newReports = const <SupportReport>[];
  List<SupportThread> _threads = const <SupportThread>[];
  bool _refreshing = false;

  /// Reports that arrived since this administrator last looked. Always empty
  /// for an account that is not an administrator.
  List<SupportReport> get newReports => _newReports;

  /// Every conversation this account is part of — the administrator's whole
  /// console, or the reporter's own handful — newest first.
  List<SupportThread> get threads => _threads;

  /// What the bell counts: reports nobody has looked at plus threads that have
  /// moved since this device last saw them.
  int get unreadCount =>
      _newReports.length +
      _threads.where((SupportThread thread) => thread.unread).length;

  /// Re-reads both sides.
  ///
  /// [isAdmin] decides which query runs: the console's whole list, or this
  /// account's own reports. Never throws — the whole feature is additive, and a
  /// network that is not there must not be visible anywhere but here.
  Future<void> refresh({required bool isAdmin}) async {
    if (_refreshing || !enabled) {
      return;
    }
    _refreshing = true;
    try {
      final DateTime seenReports = _readStamp(_seenReportsKey);
      final DateTime seenThreads = _readStamp(_seenThreadsKey);

      final List<SupportReport> reports = isAdmin
          ? await SupportService.fetchReports()
          : await SupportService.fetchMyReports();

      final List<SupportReport> arrived = isAdmin
          ? reports
                .where(
                  (SupportReport report) =>
                      report.createdAt.isAfter(seenReports),
                )
                .toList()
          : const <SupportReport>[];

      final List<SupportThread> threads =
          <SupportThread>[
            for (final SupportReport report in reports)
              if (report.lastMessageAt case final DateTime at)
                SupportThread(
                  report: report,
                  // A thread is only "new" to the side that did not write the last
                  // message — an administrator's own reply must not come back as
                  // something for them to read.
                  unread:
                      at.isAfter(seenThreads) &&
                      report.lastMessageFromAdmin != isAdmin,
                ),
          ]..sort(
            (SupportThread a, SupportThread b) =>
                b.report.lastMessageAt!.compareTo(a.report.lastMessageAt!),
          );

      final bool changed =
          arrived.length != _newReports.length ||
          threads.length != _threads.length ||
          threads.where((SupportThread t) => t.unread).length !=
              _threads.where((SupportThread t) => t.unread).length;

      _newReports = arrived;
      _threads = threads;
      notifyListeners();

      if (changed) {
        await _announce(arrived, threads);
      }
    } catch (_) {
      // Nothing to show is a perfectly good answer here.
    } finally {
      _refreshing = false;
    }
  }

  /// Marks everything currently on screen as seen. Called when the
  /// notifications page is opened, which is the moment it has been.
  Future<void> markAllSeen() async {
    final DateTime now = DateTime.now();
    await _settings.put(_seenReportsKey, now.toIso8601String());
    await _settings.put(_seenThreadsKey, now.toIso8601String());
    _newReports = const <SupportReport>[];
    _threads = <SupportThread>[
      for (final SupportThread thread in _threads)
        SupportThread(report: thread.report, unread: false),
    ];
    notifyListeners();
  }

  /// The tray notification, so a report that arrives while the app is closed is
  /// still noticed.
  ///
  /// One notification per refresh rather than one per report: the point is "go
  /// and look", and five separate lines about the same queue is a queue nobody
  /// looks at.
  Future<void> _announce(
    List<SupportReport> arrived,
    List<SupportThread> threads,
  ) async {
    final int unreadThreads = threads
        .where((SupportThread thread) => thread.unread)
        .length;
    if (arrived.isNotEmpty) {
      await NotificationService.showSupportAlert(
        title: arrived.length == 1
            ? 'הגיעה פנייה חדשה'
            : 'הגיעו ${arrived.length} פניות חדשות',
        body: arrived.first.text,
      );
      return;
    }
    if (unreadThreads > 0) {
      await NotificationService.showSupportAlert(
        title: 'יש לך תשובה מצוות שדכן',
        body: threads
            .firstWhere((SupportThread thread) => thread.unread)
            .report
            .text,
      );
    }
  }

  DateTime _readStamp(String key) {
    final Object? raw = _settings.get(key);
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
