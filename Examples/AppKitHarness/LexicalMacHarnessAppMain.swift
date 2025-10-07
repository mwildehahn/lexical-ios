#if os(macOS)
import SwiftUI
import Lexical
import LexicalAppKit

@main
struct LexicalMacHarnessApp: App {
  var body: some Scene {
    WindowGroup("Lexical Harness") {
      HarnessContainer()
        .frame(minWidth: 720, minHeight: 520)
    }
  }
}

private struct HarnessContainer: NSViewControllerRepresentable {
  func makeNSViewController(context: Context) -> LexicalMacHarnessViewController {
    LexicalMacHarnessViewController()
  }

  func updateNSViewController(
    _ nsViewController: LexicalMacHarnessViewController,
    context: Context
  ) {
    // LexicalMacHarnessViewController manages its own updates.
  }
}
#endif
