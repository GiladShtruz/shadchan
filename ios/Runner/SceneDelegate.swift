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
  }

  private func handleIncomingURL(_ url: URL) {
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
