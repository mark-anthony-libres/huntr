import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Share to story (Guest link): the card straight into Instagram's or
    // Facebook's story editor.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HuntrStoryShare") {
      let channel = FlutterMethodChannel(
        name: "huntr/story_share", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "share",
          let args = call.arguments as? [String: Any],
          let png = args["png"] as? FlutterStandardTypedData,
          let appId = args["appId"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        let target = args["target"] as? String ?? "instagram"
        result(AppDelegate.shareToStory(target: target, png: png.data, appId: appId))
      }
    }
  }

  /// Opens [target]'s story editor with [png] as the story (handed over on
  /// the pasteboard, briefly); false when that app isn't there.
  static func shareToStory(target: String, png: Data, appId: String) -> Bool {
    let instagram = target == "instagram"
    let link = instagram
      ? "instagram-stories://share?source_application=\(appId)"
      : "facebook-stories://share"
    guard let url = URL(string: link), UIApplication.shared.canOpenURL(url) else {
      return false
    }
    let items: [String: Any] = instagram
      ? ["com.instagram.sharedSticker.backgroundImage": png]
      : [
        "com.facebook.sharedSticker.backgroundImage": png,
        "com.facebook.sharedSticker.appID": appId,
      ]
    UIPasteboard.general.setItems(
      [items], options: [.expirationDate: Date().addingTimeInterval(300)])
    UIApplication.shared.open(url)
    return true
  }
}
