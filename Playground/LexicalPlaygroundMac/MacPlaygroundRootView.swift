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
  @Published var activeProfile: FeatureFlags.OptimizedProfile = .aggressiveEditor

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

  func indent() {
    dispatch(CommandType(rawValue: "indentContent"))
  }

  func outdent() {
    dispatch(CommandType(rawValue: "outdentContent"))
  }

  func applyProfile(_ profile: FeatureFlags.OptimizedProfile) {
    guard let controller else { return }
    let flags = FeatureFlags.optimizedProfile(profile)
    controller.applyFeatureFlags(flags, profile: profile)
    activeProfile = profile
  }

  func applyBlock(_ option: BlockOption) {
    guard let controller else { return }
    switch option {
    case .paragraph:
      controller.setBlock { createParagraphNode() }
    case .heading1:
      controller.setBlock { createHeadingNode(headingTag: .h1) }
    case .heading2:
      controller.setBlock { createHeadingNode(headingTag: .h2) }
    case .code:
      controller.setBlock { createCodeNode() }
    case .quote:
      controller.setBlock { createQuoteNode() }
    case .bullet:
      controller.insertList(type: .unordered)
    case .numbered:
      controller.insertList(type: .ordered)
    case .checklist:
      controller.insertList(type: .checklist)
    }
  }

  enum BlockOption: CaseIterable {
    case paragraph, heading1, heading2, code, quote, bullet, numbered, checklist

    var title: String {
      switch self {
      case .paragraph: return "Paragraph"
      case .heading1: return "Heading 1"
      case .heading2: return "Heading 2"
      case .code: return "Code Block"
      case .quote: return "Quote"
      case .bullet: return "Bulleted List"
      case .numbered: return "Numbered List"
      case .checklist: return "Checklist"
      }
    }

    var symbol: String {
      switch self {
      case .paragraph: return "text.justify"
      case .heading1: return "textformat.size.larger"
      case .heading2: return "textformat.size"
      case .code: return "chevron.left.forwardslash.chevron.right"
      case .quote: return "quote.bubble"
      case .bullet: return "list.bullet"
      case .numbered: return "list.number"
      case .checklist: return "checklist"
      }
    }
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

      formatButtons

      Divider()

      blockStyleMenu
      profileMenu

      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private var formatButtons: some View {
    Group {
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

      Button {
        session.toggleFormat(.code)
      } label: {
        Label("Inline Code", systemImage: "curlybraces")
          .labelStyle(.iconOnly)
      }

      Button {
        session.indent()
      } label: {
        Label("Increase Indent", systemImage: "increase.indent")
          .labelStyle(.iconOnly)
      }

      Button {
        session.outdent()
      } label: {
        Label("Decrease Indent", systemImage: "decrease.indent")
          .labelStyle(.iconOnly)
      }
    }
  }

  private var blockStyleMenu: some View {
    Menu {
      ForEach(MacPlaygroundSession.BlockOption.allCases, id: \.self) { option in
        Button {
          session.applyBlock(option)
        } label: {
          Label(option.title, systemImage: option.symbol)
        }
      }
    } label: {
      Label("Block Style", systemImage: "text.justify")
    }
  }

  private var profileMenu: some View {
    Menu {
      ForEach(profiles, id: \.self) { profile in
        Button {
          session.applyProfile(profile)
        } label: {
          HStack {
            Text(title(for: profile))
            if session.activeProfile == profile {
              Spacer()
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      Label("Profile", systemImage: "switch.2")
    }
  }

  private var profiles: [FeatureFlags.OptimizedProfile] {
    [.minimal, .balanced, .aggressive, .aggressiveEditor]
  }

  private func title(for profile: FeatureFlags.OptimizedProfile) -> String {
    switch profile {
    case .minimal: return "Minimal"
    case .minimalDebug: return "Minimal (Debug)"
    case .balanced: return "Balanced"
    case .aggressive: return "Aggressive"
    case .aggressiveDebug: return "Aggressive (Debug)"
    case .aggressiveEditor: return "Aggressive (Editor)"
    }
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
      session.activeProfile = newController.activeProfile
    }
  }
}

#Preview {
  MacPlaygroundRootView()
    .frame(minWidth: 960, minHeight: 640)
}
