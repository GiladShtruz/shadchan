import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // First line of the app's own code, so the log can tell "we never got
    // here" — a dyld failure loading an embedded framework — apart from
    // anything that happens afterwards. See StartupBreadcrumbs.
    StartupBreadcrumbs.start()
    StartupBreadcrumbs.note("· app_did_finish_launching")
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    StartupBreadcrumbs.note("· app_did_finish_launching_done (\(launched))")
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Bracketed on both sides: registering twenty-odd plugins is the single
    // most likely place for a launch to die, and knowing whether it finished
    // is the difference between "a plugin" and "everything after the plugins".
    StartupBreadcrumbs.note("· plugins_begin")
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    StartupBreadcrumbs.note("· plugins_done")
  }
}
