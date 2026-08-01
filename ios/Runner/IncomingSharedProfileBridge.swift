import Flutter
import Foundation
import UIKit
import UniformTypeIdentifiers

final class IncomingSharedProfileBridge: NSObject, FlutterStreamHandler {
  static let shared = IncomingSharedProfileBridge()

  private let methodChannelName = "shadchan/incoming_shared_profiles/methods"
  private let eventChannelName = "shadchan/incoming_shared_profiles/events"
  private var isConfigured = false
  private var pendingDrafts: [[String: Any]] = []
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
      case "takePendingDrafts":
        result(self.takePendingDrafts())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel.setStreamHandler(self)

    // The fallback path for the share extension: if iOS refuses to let it open
    // the app, the share still sits in the app group and the matchmaker opens
    // the app themselves. Observing the notification rather than overriding
    // sceneWillEnterForeground keeps this working whichever scene is active.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(sceneWillEnterForeground),
      name: UIScene.willEnterForegroundNotification,
      object: nil
    )

    isConfigured = true
  }

  @objc private func sceneWillEnterForeground() {
    drainSharedInbox()
  }

  func handleIncomingFile(url: URL) {
    guard let copiedPath = copyToTemporaryDirectory(url: url) else {
      return
    }

    pendingDrafts.append([
      "id": UUID().uuidString,
      "filePaths": [copiedPath],
    ])
    flushPendingDrafts()
  }

  /// Picks up everything the share extension parked in the app group and turns
  /// it into drafts, in the same shape `handleIncomingFile` produces.
  ///
  /// Files are copied out of the group container into this app's own temporary
  /// directory before the container copy is dropped, so Flutter keeps seeing
  /// paths it owns and the shared container never accumulates images.
  func drainSharedInbox() {
    for payload in SharedProfileInbox.takeAll() {
      let copiedPaths = payload.fileURLs.compactMap { copyToTemporaryDirectory(url: $0) }
      SharedProfileInbox.discard(payload)

      // A share whose files all failed to copy and that carried no text has
      // nothing left to offer; Flutter would drop it anyway.
      guard !copiedPaths.isEmpty || payload.text != nil else {
        continue
      }

      var draft: [String: Any] = [
        "id": payload.id,
        "filePaths": copiedPaths,
      ]
      if let text = payload.text {
        draft["text"] = text
      }
      pendingDrafts.append(draft)
    }

    flushPendingDrafts()
  }

  /// Whether [url] is the share extension asking the app to come forward.
  static func isSharedInboxURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == SharedProfileInbox.hostAppURLScheme
  }

  static func canHandle(url: URL) -> Bool {
    let pathExtension = url.pathExtension.lowercased()
    if ["jpg", "jpeg", "png", "heic", "webp", "gif"].contains(pathExtension) {
      return true
    }

    if #available(iOS 14.0, *) {
      let type = UTType(filenameExtension: pathExtension)
      return type?.conforms(to: .image) == true
    }

    return false
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    flushPendingDrafts()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func takePendingDrafts() -> [[String: Any]] {
    let drafts = pendingDrafts
    pendingDrafts.removeAll()
    return drafts
  }

  private func flushPendingDrafts() {
    guard let eventSink else {
      return
    }

    let drafts = pendingDrafts
    pendingDrafts.removeAll()
    for draft in drafts {
      eventSink(draft)
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
      "incoming_shared_profiles",
      isDirectory: true
    )

    do {
      try fileManager.createDirectory(
        at: incomingDirectory,
        withIntermediateDirectories: true
      )

      let suggestedName = url.lastPathComponent.isEmpty ? "shared_profile_image.jpg" : url.lastPathComponent
      let safeName = sanitizeFileName(suggestedName)
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

  private func sanitizeFileName(_ fileName: String) -> String {
    let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    return String(
      fileName.unicodeScalars.map { scalar in
        allowedCharacters.contains(scalar) ? Character(scalar) : "_"
      }
    )
  }
}
