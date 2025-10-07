# AppKit Harness (Preview)

This lightweight harness helps you stand up the macOS editor while the AppKit integration is under active development.

## Usage
### Integrate in your own project
1. Add the `Lexical`, `LexicalAppKit`, and `LexicalUIKitAppKit` packages to your macOS app target (SwiftPM or Xcode workspace).
2. Copy `LexicalMacHarnessViewController` into your project or reference the file directly from `Examples/AppKitHarness`.
3. Present the view controller from your app delegate or window controller:

```swift
import Cocoa
import Lexical
import LexicalAppKit

class AppDelegate: NSObject, NSApplicationDelegate {
  @IBOutlet private var window: NSWindow!
  private var harnessController: LexicalMacHarnessViewController!

  func applicationDidFinishLaunching(_ notification: Notification) {
    harnessController = LexicalMacHarnessViewController()
    window.contentViewController = harnessController
    window.makeKeyAndOrderFront(nil)
  }
}
```

4. Run the app. You can type, use ⌥⌫ / ⌘B / ⌘I / ⌘U, and inspect console logs for command dispatch information.

### Run the bundled sample app (SwiftPM)
The package now ships a minimal SwiftUI wrapper so you can try the harness without creating your own project:

```bash
swift run LexicalMacHarnessApp
```

This builds the `LexicalMacHarnessApp` executable (macOS 14+) and opens a window that hosts the same view controller shown above. Use it as a quick manual QA surface before wiring the editor into a full macOS application.

## Notes
- The harness seeds a small demo document and sets a placeholder (`Start typing…`).
- Keyboard shortcuts are handled by `TextViewMac` and validated by the new macOS unit tests.
- Copy/cut/paste commands currently dispatch but the payload validation tests are skipped until AppKit pasteboard parity is finished.
- For manual QA, combine this harness with the performance metrics in `LexicalMacPerformanceTests` to compare typing and scroll responsiveness.
- The SwiftPM sample uses SwiftUI’s `NSViewControllerRepresentable` to embed the harness controller; feel free to adapt that code if you prefer SwiftUI over AppKit view controllers.
