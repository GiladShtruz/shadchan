import Flutter
import Foundation

final class IncomingBackupFileBridge: NSObject, FlutterStreamHandler {
  static let shared = IncomingBackupFileBridge()

  private let methodChannelName = "shadchan/incoming_backup_files/methods"
  private let eventChannelName = "shadchan/incoming_backup_files/events"
  private var isConfigured = false
  private var pendingFilePaths: [String] = []
  private var eventSink: FlutterEventSink?

  func configure(with controller: FlutterViewController?) {
    guard let controller, !isConfigured else {
      return
    }

    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }

      switch call.method {
      case "takePendingFilePaths":
        result(self.takePendingFilePaths())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel.setStreamHandler(self)

    isConfigured = true
  }

  func handleIncomingFile(url: URL) {
    guard let copiedPath = copyToTemporaryDirectory(url: url) else {
      return
    }

    pendingFilePaths.append(copiedPath)
    flushPendingFilePaths()
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    flushPendingFilePaths()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func takePendingFilePaths() -> [String] {
    let paths = pendingFilePaths
    pendingFilePaths.removeAll()
    return paths
  }

  private func flushPendingFilePaths() {
    guard let eventSink else {
      return
    }

    let paths = pendingFilePaths
    pendingFilePaths.removeAll()
    for path in paths {
      eventSink(path)
    }
  }

  private func copyToTemporaryDirectory(url: URL) -> String? {
    let didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
    defer {
      if didAccessSecurityScopedResource {
        url.stopAccessingSecurityScopedResource()
      }
    }

    let fileManager = FileManager.default
    let incomingDirectory = fileManager.temporaryDirectory.appendingPathComponent(
      "incoming_backups",
      isDirectory: true
    )

    do {
      try fileManager.createDirectory(
        at: incomingDirectory,
        withIntermediateDirectories: true
      )

      let suggestedName = url.lastPathComponent.isEmpty ? "shadchan_backup.json" : url.lastPathComponent
      let safeName = sanitizeFileName(ensureJsonExtension(suggestedName))
      let destination = incomingDirectory.appendingPathComponent(
        "\(UUID().uuidString)_\(safeName)"
      )
      let data = try Data(contentsOf: url)
      try data.write(to: destination, options: .atomic)
      return destination.path
    } catch {
      return nil
    }
  }

  private func ensureJsonExtension(_ fileName: String) -> String {
    if fileName.lowercased().hasSuffix(".json") {
      return fileName
    }

    return "\(fileName).json"
  }

  private func sanitizeFileName(_ fileName: String) -> String {
    let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    return String(
      fileName.unicodeScalars.map { scalar in
        allowedCharacters.contains(scalar) ? Character(scalar) : "_"
      }
    )
  }
}
