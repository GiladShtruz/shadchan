import Foundation

/// The hand-off point between the share extension and the app.
///
/// iOS gives a share extension its own process and its own sandbox, so unlike
/// Android — where `MainActivity` receives the `SEND` intent directly — the
/// shared content has to be parked somewhere both processes can reach. That
/// place is the app group container: the extension writes a share into it and
/// then asks iOS to open the app, and the app drains it on launch, on the
/// incoming URL, and whenever it comes back to the foreground.
///
/// This file is compiled into *both* the Runner and the ShareExtension targets,
/// so the layout on disk only ever has one definition.
enum SharedProfileInbox {
  /// Must match the App Group capability on both targets' entitlements, and the
  /// group registered on the Apple Developer portal.
  static let appGroupIdentifier = "group.com.gilad.shadchan"

  /// The custom scheme the extension uses to bring the app forward. Declared in
  /// `Runner/Info.plist` under `CFBundleURLTypes`.
  static let hostAppURLScheme = "shadchan-share"

  private static let inboxDirectoryName = "incoming_shared_profiles"
  private static let payloadFileName = "payload.json"

  /// One share: the text that came with it, plus any images, already copied
  /// into the group container next to the payload.
  struct Payload {
    let id: String
    let text: String?
    let fileURLs: [URL]

    /// Kept so `discard` deletes exactly what was read, rather than rebuilding
    /// a path from `id` — a mismatch there would silently re-import the same
    /// share on every launch.
    let directory: URL
  }

  private static var inboxDirectory: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
      .appendingPathComponent(inboxDirectoryName, isDirectory: true)
  }

  // MARK: - Writing (share extension side)

  /// Creates the directory for one share and hands it back to be filled. Image
  /// files are written into it first; `finish` writes the manifest last.
  static func beginShare() -> URL? {
    guard let inboxDirectory else {
      return nil
    }

    discardUnfinishedShares(in: inboxDirectory)

    let shareDirectory = inboxDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )

    do {
      try FileManager.default.createDirectory(
        at: shareDirectory,
        withIntermediateDirectories: true
      )
      return shareDirectory
    } catch {
      return nil
    }
  }

  /// Clears out directories that never got a manifest, i.e. shares whose
  /// extension was killed part-way through writing them. The app skips them
  /// forever, so without this they would accumulate in the group container.
  ///
  /// Safe to do here because iOS only ever runs one share sheet at a time: any
  /// unfinished directory that exists as a *new* share begins is a leftover.
  private static func discardUnfinishedShares(in inboxDirectory: URL) {
    guard
      let shareDirectories = try? FileManager.default.contentsOfDirectory(
        at: inboxDirectory,
        includingPropertiesForKeys: nil
      )
    else {
      return
    }

    for shareDirectory in shareDirectories {
      let manifest = shareDirectory.appendingPathComponent(payloadFileName)
      if !FileManager.default.fileExists(atPath: manifest.path) {
        try? FileManager.default.removeItem(at: shareDirectory)
      }
    }
  }

  /// Writes the manifest, which is what makes the share visible to the app.
  ///
  /// It is deliberately the *last* thing written: the reader ignores any
  /// directory without a manifest, so a share that is still being assembled —
  /// or one whose extension was killed midway — is never half-imported.
  static func finishShare(
    at shareDirectory: URL,
    text: String?,
    fileNames: [String]
  ) -> Bool {
    var manifest: [String: Any] = [
      "id": shareDirectory.lastPathComponent,
      "files": fileNames,
    ]
    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      manifest["text"] = text
    }

    guard
      let data = try? JSONSerialization.data(withJSONObject: manifest, options: [])
    else {
      return false
    }

    do {
      try data.write(
        to: shareDirectory.appendingPathComponent(payloadFileName),
        options: .atomic
      )
      return true
    } catch {
      return false
    }
  }

  // MARK: - Reading (app side)

  /// Returns every completed share and removes it from the container, so a
  /// share is handed to Flutter exactly once.
  static func takeAll() -> [Payload] {
    guard
      let inboxDirectory,
      let shareDirectories = try? FileManager.default.contentsOfDirectory(
        at: inboxDirectory,
        includingPropertiesForKeys: nil
      )
    else {
      return []
    }

    var payloads: [Payload] = []
    for shareDirectory in shareDirectories.sorted(by: { $0.path < $1.path }) {
      guard let payload = read(shareDirectory: shareDirectory) else {
        continue
      }
      payloads.append(payload)
    }
    return payloads
  }

  /// Called once the app has copied the files into its own sandbox.
  static func discard(_ payload: Payload) {
    try? FileManager.default.removeItem(at: payload.directory)
  }

  private static func read(shareDirectory: URL) -> Payload? {
    let manifestURL = shareDirectory.appendingPathComponent(payloadFileName)
    guard
      let data = try? Data(contentsOf: manifestURL),
      let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
      return nil
    }

    let fileNames = manifest["files"] as? [String] ?? []
    return Payload(
      id: manifest["id"] as? String ?? shareDirectory.lastPathComponent,
      text: manifest["text"] as? String,
      fileURLs: fileNames.map { shareDirectory.appendingPathComponent($0) },
      directory: shareDirectory
    )
  }
}
