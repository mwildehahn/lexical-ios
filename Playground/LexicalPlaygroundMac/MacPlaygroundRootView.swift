import SwiftUI
import AppKit
import LexicalAppKit

struct MacPlaygroundRootView: View {
  var body: some View {
    VStack(spacing: 16) {
      Text("Lexical Playground for macOS")
        .font(.system(size: 24, weight: .semibold, design: .default))
      Text(
        "AppKit playground coming soon. This target is intentionally minimal while we port the inspector, toolbar, and performance panels from the iOS playground."
      )
      .multilineTextAlignment(.center)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
    .background(Color(NSColor.windowBackgroundColor))
  }
}

#Preview {
  MacPlaygroundRootView()
}
