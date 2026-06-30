import Flutter
import UIKit
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // US-018: register the background-sync task identifier with BGTaskScheduler.
    // The Dart side (Workmanager().initialize + registerPeriodicTask) drives
    // scheduling; this registers the permitted identifier with the OS.
    WorkmanagerPlugin.registerTask(withIdentifier: "com.clawhub.background-sync")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
