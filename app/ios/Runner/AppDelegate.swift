import Flutter
import UIKit

#if canImport(MusicCore)
import MusicCore
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "app.soundisle/backend"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MusicCoreBridge") else {
      return
    }
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        self.startCore(call: call, result: result)
      case "stop":
        self.stopCore(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startCore(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let dataDir = args["dataDir"] as? String,
      let token = args["token"] as? String
    else {
      result(FlutterError(code: "bad_args", message: "dataDir and token are required", details: nil))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        #if canImport(MusicCore)
        let port = try MobileStart(dataDir, token)
        DispatchQueue.main.async {
          result(Int(port))
        }
        #else
        throw NSError(
          domain: "app.soundisle",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "音乐核心未集成：请先运行 scripts/build_mobile_core.sh ios 生成 MusicCore.xcframework"]
        )
        #endif
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "core_error", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func stopCore(result: FlutterResult) {
    #if canImport(MusicCore)
    try? MobileStop()
    #endif
    result(true)
  }
}
