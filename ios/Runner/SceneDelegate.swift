import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    IncomingBackupFileBridge.shared.configure(
      with: window?.rootViewController as? FlutterViewController
    )
    IncomingSharedProfileBridge.shared.configure(
      with: window?.rootViewController as? FlutterViewController
    )

    for context in connectionOptions.urlContexts {
      handleIncomingURL(context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    IncomingBackupFileBridge.shared.configure(
      with: window?.rootViewController as? FlutterViewController
    )
    IncomingSharedProfileBridge.shared.configure(
      with: window?.rootViewController as? FlutterViewController
    )

    for context in URLContexts {
      handleIncomingURL(context.url)
    }
  }

  private func handleIncomingURL(_ url: URL) {
    if IncomingSharedProfileBridge.canHandle(url: url) {
      IncomingSharedProfileBridge.shared.handleIncomingFile(url: url)
      return
    }

    IncomingBackupFileBridge.shared.handleIncomingFile(url: url)
  }
}
