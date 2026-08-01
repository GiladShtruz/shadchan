import UIKit
import UniformTypeIdentifiers

/// Receives a share from WhatsApp (or anything else) and hands it to the app.
///
/// This is the iOS counterpart of the `SEND` / `SEND_MULTIPLE` intent filters in
/// `AndroidManifest.xml`. There is no compose UI on purpose: the matchmaker
/// picks "שדכן" in the share sheet and lands straight in the app's own
/// new-person / existing-person flow, exactly like on Android.
final class ShareViewController: UIViewController {
  /// The share sheet caps how many images can be picked (see the activation
  /// rule in Info.plist); this is the belt-and-braces limit on what is copied.
  private static let maximumImageCount = 20

  private var hasHandledShare = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    // viewDidAppear can run more than once (e.g. the share sheet animating
    // back); the share itself must only be written once.
    guard !hasHandledShare else {
      return
    }
    hasHandledShare = true

    Task {
      await handleShare()
      await MainActor.run { self.finish() }
    }
  }

  private func handleShare() async {
    guard
      let extensionItems = extensionContext?.inputItems as? [NSExtensionItem],
      let shareDirectory = SharedProfileInbox.beginShare()
    else {
      return
    }

    var textFragments: [String] = []
    var fileNames: [String] = []

    for item in extensionItems {
      // The subject line (WhatsApp does not set one, Mail does) is part of the
      // shared text as far as the person card is concerned.
      if let subject = item.attributedContentText?.string,
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        textFragments.append(subject)
      }

      for attachment in item.attachments ?? [] {
        if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          guard fileNames.count < Self.maximumImageCount else {
            continue
          }
          if let fileName = await copyImage(
            from: attachment,
            into: shareDirectory,
            index: fileNames.count
          ) {
            fileNames.append(fileName)
          }
          continue
        }

        if let text = await loadText(from: attachment) {
          textFragments.append(text)
        }
      }
    }

    // Nothing usable came through — don't leave an empty directory behind for
    // the app to trip over.
    let text = deduplicated(textFragments)
    guard !fileNames.isEmpty || text != nil else {
      try? FileManager.default.removeItem(at: shareDirectory)
      return
    }

    guard
      SharedProfileInbox.finishShare(
        at: shareDirectory,
        text: text,
        fileNames: fileNames
      )
    else {
      try? FileManager.default.removeItem(at: shareDirectory)
      return
    }

    await MainActor.run { self.openHostApp() }
  }

  // MARK: - Attachments

  private func copyImage(
    from attachment: NSItemProvider,
    into shareDirectory: URL,
    index: Int
  ) async -> String? {
    guard
      let item = await loadItem(
        from: attachment,
        typeIdentifier: UTType.image.identifier
      )
    else {
      return nil
    }

    // Depending on the sending app, an image arrives as a file URL, as raw
    // data, or as an already-decoded UIImage. All three have to be handled.
    switch item {
    case let url as URL:
      // Some senders hand over a security-scoped URL rather than a copy in the
      // extension's own sandbox.
      let didAccess = url.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }

      let fileName = "\(index)_\(sanitized(url.lastPathComponent))"
      guard let data = try? Data(contentsOf: url) else {
        return nil
      }
      return write(data, named: fileName, into: shareDirectory)
    case let data as Data:
      return write(data, named: "\(index)_shared_image.jpg", into: shareDirectory)
    case let image as UIImage:
      guard let data = image.jpegData(compressionQuality: 0.9) else {
        return nil
      }
      return write(data, named: "\(index)_shared_image.jpg", into: shareDirectory)
    default:
      return nil
    }
  }

  private func loadText(from attachment: NSItemProvider) async -> String? {
    for typeIdentifier in [UTType.plainText.identifier, UTType.url.identifier] {
      guard attachment.hasItemConformingToTypeIdentifier(typeIdentifier) else {
        continue
      }

      guard let item = await loadItem(from: attachment, typeIdentifier: typeIdentifier) else {
        continue
      }

      switch item {
      case let text as String:
        return text
      case let url as URL:
        return url.absoluteString
      default:
        continue
      }
    }

    return nil
  }

  private func loadItem(
    from attachment: NSItemProvider,
    typeIdentifier: String
  ) async -> NSSecureCoding? {
    await withCheckedContinuation { continuation in
      attachment.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
        continuation.resume(returning: item)
      }
    }
  }

  private func write(_ data: Data, named fileName: String, into directory: URL) -> String? {
    do {
      try data.write(
        to: directory.appendingPathComponent(fileName),
        options: .atomic
      )
      return fileName
    } catch {
      return nil
    }
  }

  /// A share often carries the same string twice — once as the item's content
  /// text and once as a plain-text attachment. Keep the order, drop the repeat.
  private func deduplicated(_ fragments: [String]) -> String? {
    var seen: Set<String> = []
    var kept: [String] = []

    for fragment in fragments {
      let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
        continue
      }
      kept.append(trimmed)
    }

    return kept.isEmpty ? nil : kept.joined(separator: "\n")
  }

  private func sanitized(_ fileName: String) -> String {
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    )
    let cleaned = String(
      fileName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    )
    return cleaned.isEmpty ? "shared_image.jpg" : cleaned
  }

  // MARK: - Hand-off

  /// Brings the app forward so the share lands in the same flow Android uses.
  ///
  /// `extensionContext.open(_:)` is documented as unsupported for share
  /// extensions, so the responder chain is walked for the `UIApplication` first
  /// (`UIApplication.shared` itself is unavailable to extensions). If neither
  /// route works nothing is lost: the share is already in the app group, and
  /// the app drains it the next time it is opened.
  private func openHostApp() {
    guard let url = URL(string: "\(SharedProfileInbox.hostAppURLScheme)://drafts") else {
      return
    }

    let openSelector = NSSelectorFromString("openURL:")
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication, application.responds(to: openSelector) {
        application.perform(openSelector, with: url)
        return
      }
      responder = current.next
    }

    extensionContext?.open(url, completionHandler: nil)
  }

  private func finish() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
