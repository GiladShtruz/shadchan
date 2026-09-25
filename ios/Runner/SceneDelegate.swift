import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    configureBridges()

    for context in connectionOptions.urlContexts {
      handleIncomingURL(context.url)
    }

    // Cold start: the share extension may have parked a share while the app
    // was not running, and the URL that brought us here is not guaranteed to
    // arrive as a urlContext.
    IncomingSharedProfileBridge.shared.drainSharedInbox()
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    configureBridges()

    for context in URLContexts {
      handleIncomingURL(context.url)
    }
  }

  private func configureBridges() {
    let controller = window?.rootViewController as? FlutterViewController
    IncomingBackupFileBridge.shared.configure(with: controller)
    IncomingSharedProfileBridge.shared.configure(with: controller)
    InviteLinkBridge.shared.configure(with: controller)
  }

  private func handleIncomingURL(_ url: URL) {
    // A matchmaker's invitation to write a personal card. Parked until Dart
    // asks for it — it may arrive before the Flutter side is listening.
    if url.scheme == InviteLinkBridge.scheme {
      InviteLinkBridge.shared.pending = url.absoluteString
      return
    }

    // The share extension's own scheme carries no payload — the share itself is
    // in the app group container.
    if IncomingSharedProfileBridge.isSharedInboxURL(url) {
      IncomingSharedProfileBridge.shared.drainSharedInbox()
      return
    }

    if IncomingSharedProfileBridge.canHandle(url: url) {
      IncomingSharedProfileBridge.shared.handleIncomingFile(url: url)
      return
    }

    IncomingBackupFileBridge.shared.handleIncomingFile(url: url)
  }
}

/// Hands an invitation link (`shadchan-invite://join?from=…&name=…`) to Dart,
/// on the same `shadchan/invite_links` channel Android answers. Kept in this
/// file so no new source has to be added to the Xcode project.
final class InviteLinkBridge {
  static let shared = InviteLinkBridge()
  static let scheme = "shadchan-invite"

  var pending: String?
  private var channel: FlutterMethodChannel?

  func configure(with controller: FlutterViewController?) {
    guard channel == nil, let controller = controller else {
      return
    }
    let methodChannel = FlutterMethodChannel(
      name: "shadchan/invite_links",
      binaryMessenger: controller.binaryMessenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "takePendingInvite":
        result(self?.pending)
        self?.pending = nil
      case "takeInstallReferrer":
        // iOS has no install referrer: an invitation does not survive an
        // App Store install, and the link is simply opened again afterwards.
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = methodChannel
  }
}
