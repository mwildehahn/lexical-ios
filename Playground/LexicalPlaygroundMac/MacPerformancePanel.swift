#if canImport(AppKit)
import AppKit
import SwiftUI
import Lexical

struct MacPerformancePanel: View {
  @ObservedObject var session: MacPlaygroundSession

  var body: some View {
    VStack(spacing: 16) {
      Text("Performance benchmarks are not available on macOS yet.")
        .font(.headline)
        .multilineTextAlignment(.center)
      Text("When the PerfRunEngine harness is ported, this panel will expose the same scenarios as the iOS playground, including legacy vs optimized reconciler comparisons and metric exports.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}
#endif
