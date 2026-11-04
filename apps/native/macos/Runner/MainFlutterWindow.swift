import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let updates = FlutterMethodChannel(name: "app.nekodot/updates",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    updates.setMethodCallHandler { call, result in
      if call.method == "version" {
        result(["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
          "build": Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0])
      } else { result(FlutterMethodNotImplemented) }
    }

    super.awakeFromNib()
  }
}
