import SwiftUI
import AppKit
import Lexical
import LexicalAppKit

struct MacPlaygroundRootView: View {
  @StateObject private var session = MacPlaygroundSession()
  @State private var selectedSidebarItem: SidebarItem? = .flags

  var body: some View {
    NavigationSplitView {
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
      VStack(spacing: 0) {
        MacPlaygroundToolbar(session: session)
        Divider()
        MacPlaygroundEditorContainer(session: session)
      }
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

@MainActor
private final class MacPlaygroundSession: ObservableObject {
  @Published var controller: MacPlaygroundViewController?

  var editor: Editor? {
    controller?.adapter.editor
  }

  func dispatch(_ type: CommandType, payload: Any? = nil) {
    guard let editor else { return }
    _ = editor.dispatchCommand(type: type, payload: payload)
  }

  func toggleFormat(_ format: TextFormatType) {
    dispatch(.formatText, payload: format)
  }
}

private struct MacPlaygroundToolbar: View {
  @ObservedObject var session: MacPlaygroundSession

  var body: some View {
    HStack(spacing: 12) {
      Button {
        session.dispatch(CommandType(rawValue: "undo"))
      } label: {
        Label("Undo", systemImage: "arrow.uturn.backward")
          .labelStyle(.iconOnly)
      }
      .keyboardShortcut("z", modifiers: .command)

      Button {
        session.dispatch(CommandType(rawValue: "redo"))
      } label: {
        Label("Redo", systemImage: "arrow.uturn.forward")
          .labelStyle(.iconOnly)
      }
      .keyboardShortcut("Z", modifiers: [.command, .shift])

      Divider()

      Button {
        session.toggleFormat(.bold)
      } label: {
        Label("Bold", systemImage: "bold")
          .labelStyle(.iconOnly)
      }
      .keyboardShortcut("b", modifiers: .command)

      Button {
        session.toggleFormat(.italic)
      } label: {
        Label("Italic", systemImage: "italic")
          .labelStyle(.iconOnly)
      }
      .keyboardShortcut("i", modifiers: .command)

      Button {
        session.toggleFormat(.underline)
      } label: {
        Label("Underline", systemImage: "underline")
          .labelStyle(.iconOnly)
      }
      .keyboardShortcut("u", modifiers: .command)

      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

private struct MacPlaygroundEditorContainer: NSViewControllerRepresentable {
  @ObservedObject var session: MacPlaygroundSession

  func makeCoordinator() -> Coordinator {
    Coordinator(session: session)
  }

  func makeNSViewController(context: Context) -> MacPlaygroundViewController {
    let controller = MacPlaygroundViewController()
    context.coordinator.updateController(controller)
    return controller
  }

  func updateNSViewController(_ nsViewController: MacPlaygroundViewController, context: Context) {
    context.coordinator.updateController(nsViewController)
  }

  @MainActor
  final class Coordinator {
    private weak var controller: MacPlaygroundViewController?
    private let session: MacPlaygroundSession

    init(session: MacPlaygroundSession) {
      self.session = session
    }

    func updateController(_ newController: MacPlaygroundViewController) {
      guard controller !== newController else { return }
      controller = newController
      session.controller = newController
    }
  }
}

#Preview {
  MacPlaygroundRootView()
    .frame(minWidth: 960, minHeight: 640)
}
