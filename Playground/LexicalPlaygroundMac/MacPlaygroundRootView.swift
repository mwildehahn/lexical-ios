import SwiftUI
import AppKit
import LexicalAppKit

struct MacPlaygroundRootView: View {
  @State private var selectedSidebarItem: SidebarItem? = .flags

  var body: some View {
    NavigationSplitView(columnVisibility: .constant(.all)) {
      List(selection: $selectedSidebarItem) {
        Section("Inspector") {
          Label("Feature Flags", systemImage: "slider.horizontal.3")
            .tag(SidebarItem.flags)
          Label("Node Hierarchy", systemImage: "tree")
            .tag(SidebarItem.hierarchy)
          Label("Performance Runs", systemImage: "speedometer")
            .tag(SidebarItem.performance)
        }
      }
      .navigationTitle("Playground")
      .frame(minWidth: 220)
    } detail: {
      MacPlaygroundEditorContainer()
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Editor")
    }
  }

  private enum SidebarItem: Hashable {
    case flags
    case hierarchy
    case performance
  }
}

private struct MacPlaygroundEditorContainer: NSViewControllerRepresentable {
  func makeNSViewController(context: Context) -> MacPlaygroundViewController {
    MacPlaygroundViewController()
  }

  func updateNSViewController(_ nsViewController: MacPlaygroundViewController, context: Context) {
    // State will be plumbed through in later subtasks.
  }
}

#Preview {
  MacPlaygroundRootView()
    .frame(minWidth: 960, minHeight: 640)
}
