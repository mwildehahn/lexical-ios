import SwiftUI
import AppKit
import Lexical
import LexicalAppKit

struct MacPlaygroundRootView: View {
  @StateObject private var session = MacPlaygroundSession()
  @State private var selectedSidebarItem: SidebarItem? = .hierarchy

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedSidebarItem) {
        Section("Inspector") {
          Label("Node Hierarchy", systemImage: "tree")
            .tag(SidebarItem.hierarchy)
          Label("Feature Flags", systemImage: "slider.horizontal.3")
            .tag(SidebarItem.flags)
          Label("Performance Runs", systemImage: "speedometer")
            .tag(SidebarItem.performance)
          Label("Export & Console", systemImage: "terminal")
            .tag(SidebarItem.console)
        }
      }
      .navigationTitle("Playground")
      .frame(minWidth: 220)
    } content: {
      InspectorContainer(session: session, selection: selectedSidebarItem)
    } detail: {
      MacPlaygroundEditorContainer(session: session)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Editor")
        .toolbar {
          MacPlaygroundToolbar(session: session)
        }
    }
  }

  enum SidebarItem: Hashable {
    case flags
    case hierarchy
    case performance
    case console
  }
}

@MainActor
final class MacPlaygroundSession: ObservableObject {
  @Published var controller: MacPlaygroundViewController?
  @Published var activeProfile: FeatureFlags.OptimizedProfile = .aggressiveEditor
  @Published fileprivate var flagBuilder = FeatureFlagsBuilder(flags: FeatureFlags.optimizedProfile(.aggressiveEditor))
  @Published var hierarchyText: String = "-"
  @Published var consoleText: String = ""
  @Published var placeholderVisible: Bool = true
  private var logEntries: [String] = []
  private static let logFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  private var updateListener: Editor.RemovalHandler?

  var editor: Editor? {
    controller?.adapter.editor
  }

  func dispatch(_ type: CommandType, payload: Any? = nil) {
    guard let editor else { return }
    _ = editor.dispatchCommand(type: type, payload: payload)
    logEvent("Dispatch command: \(type.rawValue)")
  }

  func toggleFormat(_ format: TextFormatType) {
    dispatch(.formatText, payload: format)
    logEvent("Toggle format: \(format)")
  }

  func toggleStrikethrough() {
    toggleFormat(.strikethrough)
  }

  func indent() {
    dispatch(CommandType(rawValue: "indentContent"))
    logEvent("Increase indent")
  }

  func outdent() {
    dispatch(CommandType(rawValue: "outdentContent"))
    logEvent("Decrease indent")
  }

  func applyProfile(_ profile: FeatureFlags.OptimizedProfile) {
    guard let controller else { return }
    let flags = FeatureFlags.optimizedProfile(profile)
    controller.applyFeatureFlags(flags, profile: profile)
    activeProfile = profile
    flagBuilder = FeatureFlagsBuilder(flags: flags)
    logEvent("Switched profile -> \(profile)")
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
    logEvent("Apply block style -> \(option.title)")
  }

  func insertSampleDecorator() {
    guard let controller else { return }
    controller.insertSampleDecorator()
    logEvent("Inserted sample decorator node")
  }

  func insertLoremIpsum() {
    guard let controller else { return }
    controller.insertLoremIpsumParagraph()
    logEvent("Inserted lorem ipsum paragraph")
  }

  func resetDocument() {
    guard let controller else { return }
    controller.resetDocument()
    placeholderVisible = controller.isPlaceholderVisible
    logEvent("Reset document to welcome copy")
  }

  func togglePlaceholder() {
    guard let controller else { return }
    placeholderVisible.toggle()
    controller.togglePlaceholder(visible: placeholderVisible)
    logEvent(placeholderVisible ? "Placeholder enabled" : "Placeholder hidden")
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

  enum FlagSection: String, CaseIterable, Identifiable {
    case reconciler = "Reconciler"
    case fenwick = "Fenwick / Locations"
    case misc = "Misc"

    var id: String { rawValue }
  }

  struct FlagDescriptor: Identifiable {
    let id: String
    let title: String
    let keyPath: WritableKeyPath<FeatureFlagsBuilder, Bool>
    let section: FlagSection
  }

  private(set) lazy var flagDescriptors: [FlagDescriptor] = [
    FlagDescriptor(id: "optimized", title: "Use Optimized Reconciler", keyPath: \.useOptimizedReconciler, section: .reconciler),
    FlagDescriptor(id: "strict", title: "Strict Mode (no legacy)", keyPath: \.useOptimizedReconcilerStrictMode, section: .reconciler),
    FlagDescriptor(id: "keyedDiff", title: "Keyed Diff (reorder)", keyPath: \.useReconcilerKeyedDiff, section: .reconciler),
    FlagDescriptor(id: "blockRebuild", title: "Block Rebuild", keyPath: \.useReconcilerBlockRebuild, section: .reconciler),
    FlagDescriptor(id: "shadowCompare", title: "Shadow Compare (debug)", keyPath: \.useReconcilerShadowCompare, section: .reconciler),
    FlagDescriptor(id: "fenwickDelta", title: "Fenwick Delta (locations)", keyPath: \.useReconcilerFenwickDelta, section: .fenwick),
    FlagDescriptor(id: "centralAgg", title: "Central Aggregation", keyPath: \.useReconcilerFenwickCentralAggregation, section: .fenwick),
    FlagDescriptor(id: "insertBlock", title: "Insert-Block Fenwick", keyPath: \.useReconcilerInsertBlockFenwick, section: .fenwick),
    FlagDescriptor(id: "deleteBlock", title: "Delete-Block Fenwick", keyPath: \.useReconcilerDeleteBlockFenwick, section: .fenwick),
    FlagDescriptor(id: "sanityCheck", title: "Reconciler Sanity Check", keyPath: \.reconcilerSanityCheck, section: .misc),
    FlagDescriptor(id: "proxyInput", title: "Proxy InputDelegate", keyPath: \.proxyTextViewInputDelegate, section: .misc),
    FlagDescriptor(id: "prePost", title: "Pre/Post Attrs Only", keyPath: \.useReconcilerPrePostAttributesOnly, section: .misc),
    FlagDescriptor(id: "modernTextKit", title: "Modern TextKit Optimizations", keyPath: \.useModernTextKitOptimizations, section: .misc),
    FlagDescriptor(id: "verbose", title: "Verbose Logging", keyPath: \.verboseLogging, section: .misc),
  ]

  func binding(for descriptor: FlagDescriptor) -> Binding<Bool> {
    Binding(get: {
      self.flagBuilder[keyPath: descriptor.keyPath]
    }, set: { newValue in
      self.flagBuilder[keyPath: descriptor.keyPath] = newValue
      if let controller = self.controller {
        let flags = self.flagBuilder.build()
        controller.applyFeatureFlags(flags, profile: self.activeProfile)
      }
      self.logEvent("Flag \(descriptor.title) -> \(newValue ? "ON" : "OFF")")
    })
  }

  func descriptors(for section: FlagSection) -> [FlagDescriptor] {
    flagDescriptors.filter { $0.section == section }
  }

  func observeEditor(_ controller: MacPlaygroundViewController) {
    updateListener?()
    let editor = controller.adapter.editor
    updateListener = editor.registerUpdateListener { [weak self] activeState, _, _ in
      guard let self else { return }
      Task { @MainActor in
        self.flagBuilder = FeatureFlagsBuilder(flags: controller.activeFeatureFlags)
        self.hierarchyText = (try? getNodeHierarchy(editorState: activeState)) ?? "-"
        self.placeholderVisible = controller.isPlaceholderVisible
      }
    }
    Task { @MainActor in
      self.flagBuilder = FeatureFlagsBuilder(flags: controller.activeFeatureFlags)
      self.hierarchyText = (try? getNodeHierarchy(editorState: editor.getEditorState())) ?? "-"
      self.placeholderVisible = controller.isPlaceholderVisible
    }
    logEvent("Editor session bound")
  }

  func logEvent(_ message: String) {
    let timestamp = Self.logFormatter.string(from: Date())
    let entry = "[\(timestamp)] \(message)"
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.logEntries.append(entry)
      if self.logEntries.count > 200 {
        self.logEntries.removeFirst(self.logEntries.count - 200)
      }
      self.consoleText = self.logEntries.joined(separator: "\n")
    }
  }

  func exportPlainText() -> String {
    guard let editor else { return "" }
    var text = ""
    do {
      try editor.read {
        if let root = getRoot() {
          text = (try? root.getTextContent()) ?? ""
        }
      }
    } catch {
      text = "Error generating text: \(error)"
    }
    return text
  }

  func exportJSON() -> String {
    guard let json = try? editor?.getEditorState().toJSON() else {
      return "Error generating JSON"
    }
    return json
  }

  func copy(_ string: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
    logEvent("Copied export to clipboard (\(string.count) chars)")
  }
}

private struct MacPlaygroundToolbar: ToolbarContent {
  @ObservedObject var session: MacPlaygroundSession

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .automatic) {
      Button {
        session.dispatch(CommandType(rawValue: "undo"))
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      .keyboardShortcut("z", modifiers: .command)

      Button {
        session.dispatch(CommandType(rawValue: "redo"))
      } label: {
        Image(systemName: "arrow.uturn.forward")
      }
      .keyboardShortcut("Z", modifiers: [.command, .shift])

      Button {
        session.toggleFormat(.bold)
      } label: { Image(systemName: "bold") }
      .keyboardShortcut("b", modifiers: .command)

      Button {
        session.toggleFormat(.italic)
      } label: { Image(systemName: "italic") }
      .keyboardShortcut("i", modifiers: .command)

      Button {
        session.toggleFormat(.underline)
      } label: { Image(systemName: "underline") }
      .keyboardShortcut("u", modifiers: .command)

      Button {
        session.toggleFormat(.code)
      } label: { Image(systemName: "curlybraces") }
      .keyboardShortcut("`", modifiers: .command)

      Button {
        session.toggleStrikethrough()
      } label: { Image(systemName: "strikethrough") }
      .keyboardShortcut("x", modifiers: [.command, .shift])

      Button {
        session.indent()
      } label: { Image(systemName: "increase.indent") }
      .keyboardShortcut("]", modifiers: .command)

      Button {
        session.outdent()
      } label: { Image(systemName: "decrease.indent") }
      .keyboardShortcut("[", modifiers: .command)

      Menu {
        ForEach(MacPlaygroundSession.BlockOption.allCases, id: \.self) { option in
          Button {
            session.applyBlock(option)
          } label: {
            Label(option.title, systemImage: option.symbol)
          }
        }
      } label: {
        Image(systemName: "text.justify")
      }

      Menu {
        ForEach(blockProfiles, id: \.self) { profile in
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
        Image(systemName: "switch.2")
      }

      Menu {
        Button("Reset Document", systemImage: "arrow.counterclockwise") {
          session.resetDocument()
        }

        Button(
          session.placeholderVisible ? "Hide Placeholder" : "Show Placeholder",
          systemImage: session.placeholderVisible ? "eye.slash" : "eye"
        ) {
          session.togglePlaceholder()
        }

        Button("Insert Sample Decorator", systemImage: "rectangle.fill") {
          session.insertSampleDecorator()
        }

        Button("Insert Lorem Ipsum", systemImage: "text.append") {
          session.insertLoremIpsum()
        }
      } label: {
        Image(systemName: "wand.and.stars")
      }
    }
  }

  private var blockProfiles: [FeatureFlags.OptimizedProfile] {
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
      session.placeholderVisible = newController.isPlaceholderVisible
      session.observeEditor(newController)
    }
  }
}

private struct InspectorContainer: View {
  @ObservedObject var session: MacPlaygroundSession
  var selection: MacPlaygroundRootView.SidebarItem?

  var body: some View {
    switch selection {
    case .flags, .none:
      FlagsInspectorView(session: session)
    case .hierarchy:
      HierarchyInspectorView(session: session)
    case .performance:
      MacPerformancePanel(session: session)
    case .console:
      ConsoleInspectorView(session: session)
    }
  }
}

private struct FlagsInspectorView: View {
  @ObservedObject var session: MacPlaygroundSession

  var body: some View {
    List {
      ForEach(MacPlaygroundSession.FlagSection.allCases) { section in
        Section(section.rawValue) {
          ForEach(session.descriptors(for: section)) { descriptor in
            Toggle(descriptor.title, isOn: session.binding(for: descriptor))
          }
        }
      }
    }
    .frame(minWidth: 260)
  }
}

private struct HierarchyInspectorView: View {
  @ObservedObject var session: MacPlaygroundSession

  var body: some View {
    ScrollView {
      Text(session.hierarchyText)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    .background(Color(NSColor.textBackgroundColor))
    .frame(minWidth: 260)
  }
}

private struct ConsoleInspectorView: View {
  @ObservedObject var session: MacPlaygroundSession

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Export")
        .font(.headline)
      HStack {
        Button("Copy Plain Text") {
          session.copy(session.exportPlainText())
        }
        Button("Copy JSON") {
          session.copy(session.exportJSON())
        }
        Spacer()
      }

      Divider()

      Text("Console")
        .font(.headline)
      ScrollView {
        Text(session.consoleText.isEmpty ? "No events yet." : session.consoleText)
          .font(.system(.callout, design: .monospaced))
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
          .padding()
      }
      .background(Color(NSColor.textBackgroundColor))
      .frame(minHeight: 240)
    }
    .padding()
    .frame(minWidth: 260, maxHeight: .infinity, alignment: .topLeading)
  }
}

struct FeatureFlagsBuilder {
  var reconcilerSanityCheck: Bool
  var proxyTextViewInputDelegate: Bool
  var useOptimizedReconciler: Bool
  var useReconcilerFenwickDelta: Bool
  var useReconcilerKeyedDiff: Bool
  var useReconcilerBlockRebuild: Bool
  var useOptimizedReconcilerStrictMode: Bool
  var useReconcilerFenwickCentralAggregation: Bool
  var useReconcilerShadowCompare: Bool
  var useReconcilerInsertBlockFenwick: Bool
  var useReconcilerDeleteBlockFenwick: Bool
  var useReconcilerPrePostAttributesOnly: Bool
  var useModernTextKitOptimizations: Bool
  var verboseLogging: Bool
  var prePostAttrsOnlyMaxTargets: Int

  init(flags: FeatureFlags) {
    self.reconcilerSanityCheck = flags.reconcilerSanityCheck
    self.proxyTextViewInputDelegate = flags.proxyTextViewInputDelegate
    self.useOptimizedReconciler = flags.useOptimizedReconciler
    self.useReconcilerFenwickDelta = flags.useReconcilerFenwickDelta
    self.useReconcilerKeyedDiff = flags.useReconcilerKeyedDiff
    self.useReconcilerBlockRebuild = flags.useReconcilerBlockRebuild
    self.useOptimizedReconcilerStrictMode = flags.useOptimizedReconcilerStrictMode
    self.useReconcilerFenwickCentralAggregation = flags.useReconcilerFenwickCentralAggregation
    self.useReconcilerShadowCompare = flags.useReconcilerShadowCompare
    self.useReconcilerInsertBlockFenwick = flags.useReconcilerInsertBlockFenwick
    self.useReconcilerDeleteBlockFenwick = flags.useReconcilerDeleteBlockFenwick
    self.useReconcilerPrePostAttributesOnly = flags.useReconcilerPrePostAttributesOnly
    self.useModernTextKitOptimizations = flags.useModernTextKitOptimizations
    self.verboseLogging = flags.verboseLogging
    self.prePostAttrsOnlyMaxTargets = flags.prePostAttrsOnlyMaxTargets
  }

  func build() -> FeatureFlags {
    FeatureFlags(
      reconcilerSanityCheck: reconcilerSanityCheck,
      proxyTextViewInputDelegate: proxyTextViewInputDelegate,
      useOptimizedReconciler: useOptimizedReconciler,
      useReconcilerFenwickDelta: useReconcilerFenwickDelta,
      useReconcilerKeyedDiff: useReconcilerKeyedDiff,
      useReconcilerBlockRebuild: useReconcilerBlockRebuild,
      useOptimizedReconcilerStrictMode: useOptimizedReconcilerStrictMode,
      useReconcilerFenwickCentralAggregation: useReconcilerFenwickCentralAggregation,
      useReconcilerShadowCompare: useReconcilerShadowCompare,
      useReconcilerInsertBlockFenwick: useReconcilerInsertBlockFenwick,
      useReconcilerDeleteBlockFenwick: useReconcilerDeleteBlockFenwick,
      useReconcilerPrePostAttributesOnly: useReconcilerPrePostAttributesOnly,
      useModernTextKitOptimizations: useModernTextKitOptimizations,
      verboseLogging: verboseLogging,
      prePostAttrsOnlyMaxTargets: prePostAttrsOnlyMaxTargets
    )
  }
}

#Preview {
  MacPlaygroundRootView()
    .frame(minWidth: 960, minHeight: 640)
}
