// `Darwin` explicitly, even though Foundation re-exports it: everything the
// signal path uses — `open`, `write`, `signal`, `backtrace_symbols_fd` — comes
// from there, and naming it keeps that obvious.
import Darwin
import Foundation
import UIKit

/// A native flight recorder for the part of launch that happens before Dart.
///
/// **`lib/services/diagnostics_log.dart` cannot see any of this.** That file is
/// the same idea one layer up, and it was written first — but it only starts
/// recording once `main()` runs, and the failure this exists for happens before
/// that: the app showed its launch image on an iPhone and died, with no error
/// screen (so no Dart exception reached `runZonedGuarded`) and nothing legible
/// in the store's crash report.
///
/// So the app writes down the launch itself, from Swift, one line at a time:
/// the delegate starting, the plugins registering, the scene connecting, the
/// engine handing over. A run that stops between two of those lines has named
/// its own culprit. A file with **no lines at all** is just as much of an
/// answer — it means the process died before `didFinishLaunching`, which is
/// dyld failing to load a framework and nothing the app can do about it from
/// inside.
///
/// **Written with `write(2)` to a file descriptor, not with `String.write`.**
/// The interesting failures here are signals and uncaught exceptions, and the
/// handlers for those run in a process that is already dying: allocating,
/// taking locks, or touching Foundation is how a crash reporter loses the crash
/// it was reporting. The signal path therefore writes only a fixed signal name
/// to an already-open descriptor. The system `.ips` remains the source of the
/// native backtrace.
///
/// Lives in `Documents/` on purpose — see `UIFileSharingEnabled` in
/// `Info.plist` for how the file is read off a phone with no Mac attached, and
/// for the note that says to turn that back off.
enum StartupBreadcrumbs {
  private static let fileName = "shadchan_startup.log"

  /// Kept open for the life of the process, so a signal handler never has to
  /// open a file to report that the process is ending.
  private static var descriptor: Int32 = -1

  private static var logURL: URL? {
    FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)
      .first?
      .appendingPathComponent(fileName)
  }

  /// Opens the log, trims it if it has grown, writes this run's header and
  /// installs the crash handlers. Safe to call more than once.
  static func start() {
    guard descriptor < 0, let url = logURL else {
      return
    }

    let manager = FileManager.default
    // Old runs are worth comparing against; twenty of them are not. Past a
    // quarter of a megabyte the file starts again rather than growing without
    // limit on a phone that relaunches all day.
    if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int,
       size > 256 * 1024 {
      try? manager.removeItem(at: url)
    }
    if !manager.fileExists(atPath: url.path) {
      manager.createFile(atPath: url.path, contents: nil)
    }

    descriptor = open(url.path, O_WRONLY | O_APPEND)
    guard descriptor >= 0 else {
      return
    }

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    note("=== launch \(stamp()) · iOS \(UIDevice.current.systemVersion) · \(version)+\(build) ===")

    installHandlers()
  }

  /// One step of launch, by a fixed name. Never call this with anything about a
  /// candidate in it — this file leaves the device by hand, in a bug report.
  static func note(_ line: String) {
    append("\(stamp()) \(line)\n")
  }

  // MARK: - Crash handlers

  private static var handlersInstalled = false

  private static func installHandlers() {
    guard !handlersInstalled else {
      return
    }
    handlersInstalled = true

    NSSetUncaughtExceptionHandler { exception in
      StartupBreadcrumbs.append(
        "!! uncaught \(exception.name.rawValue): \(exception.reason ?? "")\n"
      )
      for frame in exception.callStackSymbols.prefix(24) {
        StartupBreadcrumbs.append("   \(frame)\n")
      }
    }

    // SIGKILL is deliberately absent: it cannot be caught, and it is what the
    // watchdog uses. Its signature here is a log that simply stops after the
    // last thing the app was doing — which is still the answer.
    for signalNumber in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
      signal(signalNumber) { received in
        StartupBreadcrumbs.appendSignal(received)
        // Put the default handler back and re-raise, so the system still
        // produces its own crash report rather than this one swallowing it.
        signal(received, SIG_DFL)
        raise(received)
      }
    }
  }

  /// The signal path, kept to one `write(2)`. No allocation, no Foundation, no
  /// locks — this runs inside a signal handler. Do not add Swift arrays or
  /// `backtrace_symbols` here: both allocate while the process is already
  /// compromised and can hide the original crash.
  private static func appendSignal(_ number: Int32) {
    guard descriptor >= 0 else {
      return
    }
    let name: StaticString
    switch number {
    case SIGABRT: name = "!! signal SIGABRT\n"
    case SIGSEGV: name = "!! signal SIGSEGV\n"
    case SIGBUS: name = "!! signal SIGBUS\n"
    case SIGILL: name = "!! signal SIGILL\n"
    case SIGFPE: name = "!! signal SIGFPE\n"
    case SIGTRAP: name = "!! signal SIGTRAP\n"
    default: name = "!! signal (other)\n"
    }
    name.withUTF8Buffer { buffer in
      _ = write(descriptor, buffer.baseAddress, buffer.count)
    }

  }

  // MARK: - Plumbing

  private static func append(_ text: String) {
    guard descriptor >= 0, let data = text.data(using: .utf8) else {
      return
    }
    data.withUnsafeBytes { buffer in
      _ = write(descriptor, buffer.baseAddress, buffer.count)
    }
  }

  private static func stamp() -> String {
    var now = time(nil)
    var parts = tm()
    localtime_r(&now, &parts)
    return String(
      format: "%02d:%02d:%02d",
      parts.tm_hour,
      parts.tm_min,
      parts.tm_sec
    )
  }
}
