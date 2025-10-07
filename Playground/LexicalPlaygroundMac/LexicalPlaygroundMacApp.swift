import SwiftUI
import AppKit

@main
struct LexicalPlaygroundMacApp: App {
  var body: some Scene {
    WindowGroup("Lexical Playground") {
      MacPlaygroundRootView()
        .frame(minWidth: 900, minHeight: 700)
    }
    .commands {
      CommandGroup(after: .appInfo) {
        Button("About Lexical Playground") {
          NSApplication.shared.orderFrontStandardAboutPanel(nil)
        }
      }
    }
  }
}
