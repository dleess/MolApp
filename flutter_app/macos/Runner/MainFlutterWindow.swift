import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let files = FlutterMethodChannel(name: "molapp/files", binaryMessenger: flutterViewController.engine.binaryMessenger)
    files.setMethodCallHandler(Self.handleFileMethod)

    super.awakeFromNib()
  }

  static func handleFileMethod(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "writeAtomically" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String, !path.isEmpty,
          let bytes = arguments["bytes"] as? FlutterStandardTypedData else {
      result(FlutterError(code: "invalidArguments", message: "Expected a file path and bytes.", details: nil))
      return
    }
    do {
      // Foundation's safe-save supports a file-only NSSavePanel grant; sibling staging does not.
      try bytes.data.write(to: URL(fileURLWithPath: path), options: .atomic)
      result(nil)
    } catch {
      result(FlutterError(code: "writeFailed", message: error.localizedDescription, details: nil))
    }
  }
}
