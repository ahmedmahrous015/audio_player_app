import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open at a comfortable size for the two-column (library + player)
    // layout, centred, and never shrink below a phone-like width.
    self.contentMinSize = NSSize(width: 420, height: 640)
    // Applied after the nib finishes configuring the window, which would
    // otherwise restore its own default frame.
    DispatchQueue.main.async {
      self.setContentSize(NSSize(width: 1180, height: 760))
      self.center()
    }

    // Seamless title bar: transparent and title-less, showing the window
    // background in the app's own base colour (iOS system greys).
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.backgroundColor = NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? .black
        : NSColor(srgbRed: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1)
    }
    flutterViewController.backgroundColor = .clear

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Same channel as Android: "deleteFiles" moves files to the Trash (the
    // Mac convention, so a mistaken delete can be undone from Finder).
    let deviceChannel = FlutterMethodChannel(
      name: "com.example.audio_player_app/device",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    deviceChannel.setMethodCallHandler { call, result in
      guard call.method == "deleteFiles" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let paths = args["paths"] as? [String] else {
        result(FlutterError(code: "INVALID_ARG", message: "paths is required", details: nil))
        return
      }
      var removed: [String] = []
      for path in paths {
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
          removed.append(path)
          continue
        }
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
          removed.append(path)
        }
      }
      result(removed)
    }

    super.awakeFromNib()
  }
}
