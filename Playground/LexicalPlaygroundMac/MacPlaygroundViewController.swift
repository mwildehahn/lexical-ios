#if canImport(AppKit)
import AppKit
import Lexical
import LexicalAppKit

/// Hosts a Lexical editor instance for the macOS playground.
/// This mirrors the harness controller but will grow additional hooks for toolbars,
/// inspectors, and performance utilities.
extension NodeType {
  static let sampleDecorator = NodeType(rawValue: "sampleDecorator")
}

@MainActor
final class MacPlaygroundViewController: NSViewController {
  let hostView: LexicalNSView
  let textView: TextViewMac
  let overlayView: LexicalOverlayViewMac
  let adapter: AppKitFrontendAdapter
  private(set) var activeFeatureFlags: FeatureFlags
  private(set) var activeProfile: FeatureFlags.OptimizedProfile
  private let defaultPlaceholder = "Start typing…"
  private(set) var isPlaceholderVisible = true

  init(theme: Theme = Theme(), plugins: [Plugin] = []) {
    self.hostView = LexicalNSView(frame: .zero)
    self.textView = TextViewMac(editorConfig: EditorConfig(theme: theme, plugins: plugins))
    self.overlayView = LexicalOverlayViewMac(frame: .zero)
    self.adapter = AppKitFrontendAdapter(
      editor: textView.editor,
      hostView: hostView,
      textView: textView,
      overlayView: overlayView
    )
    self.activeProfile = .aggressiveEditor
    self.activeFeatureFlags = FeatureFlags.optimizedProfile(.aggressiveEditor)
    textView.editor.featureFlags = activeFeatureFlags
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    adapter.bind()
    togglePlaceholder(visible: true)
    seedDocumentIfNeeded()
    view = hostView
  }

  private func seedDocumentIfNeeded(force: Bool = false) {
    let editorState = adapter.editor.getEditorState()
    let shouldSeed = force || (editorState.getRootNode()?.getChildren().isEmpty ?? true)

    guard shouldSeed else {
      return
    }

    seedDocument()
  }

  func applyFeatureFlags(_ flags: FeatureFlags, profile: FeatureFlags.OptimizedProfile) {
    activeFeatureFlags = flags
    activeProfile = profile
    adapter.editor.featureFlags = flags
  }

  func resetDocument() {
    clearDocument()
    seedDocumentIfNeeded(force: true)
  }

  func setBlock(_ builder: @escaping () -> ElementNode) {
    try? adapter.editor.update {
      if let selection = try getSelection() as? RangeSelection {
        setBlocksType(selection: selection, createElement: builder)
        adapter.editor.resetTypingAttributes(for: try selection.anchor.getNode())
      }
    }
  }

  func insertList(type: FeatureFlagsListType) {
    switch type {
    case .unordered:
      adapter.editor.dispatchCommand(type: CommandType(rawValue: "insertUnorderedList"))
    case .ordered:
      adapter.editor.dispatchCommand(type: CommandType(rawValue: "insertOrderedList"))
    case .checklist:
      adapter.editor.dispatchCommand(type: CommandType(rawValue: "insertCheckList"))
    }
  }

  func togglePlaceholder(visible: Bool) {
    isPlaceholderVisible = visible
    textView.updatePlaceholder(visible ? defaultPlaceholder : nil)
  }

  func insertSampleDecorator() {
    try? adapter.editor.update {
      let node = MacSampleDecoratorNode()
      if let selection = try getSelection() {
        _ = try selection.insertNodes(nodes: [node], selectStart: false)
      } else if let root = getRoot() {
        try root.append([node])
      }
    }
  }

  func insertLoremIpsumParagraph() {
    let lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesent commodo nisl ac tellus pulvinar, a interdum nibh luctus."
    try? adapter.editor.update {
      let paragraph = createParagraphNode()
      try paragraph.append([createTextNode(text: lorem)])

      if let selection = try getSelection() {
        let inserted = try selection.insertNodes(nodes: [paragraph], selectStart: false)
        if !inserted, let root = getRoot() {
          try root.append([paragraph])
        }
      } else if let root = getRoot() {
        try root.append([paragraph])
      }
    }
  }

  private func clearDocument() {
    try? adapter.editor.update {
      guard let root = getRoot() else { return }
      for child in root.getChildren() {
        try child.remove()
      }
    }
  }

  private func seedDocument() {
    do {
      try adapter.editor.update {
        guard let root = getRoot() else { return }
        let intro = createParagraphNode()
        try intro.append([createTextNode(text: "Welcome to the Lexical macOS playground!\n")])

        let body = createParagraphNode()
        try body.append([
          createTextNode(text: "We’re working toward UI parity with the iOS playground. "),
          createTextNode(text: "Use this build to test AppKit editing flows.")
        ])

        try root.append([intro, body])
      }
    } catch {
      adapter.editor.log(.editor, .error, "Failed to seed mac playground document: \(error)")
    }
  }

  enum FeatureFlagsListType {
    case unordered
    case ordered
    case checklist
  }
}

final class MacSampleDecoratorNode: DecoratorBlockNode {
  private static let defaultHeight: CGFloat = 64

  override class func getType() -> NodeType {
    .sampleDecorator
  }

  override func createView() -> UXView {
    let container = UXView(frame: NSRect(x: 0, y: 0, width: 280, height: Self.defaultHeight))
    container.translatesAutoresizingMaskIntoConstraints = false
    container.wantsLayer = true
    container.layer?.cornerRadius = 12
    container.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor

    let label = NSTextField(labelWithString: "Sample Decorator")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.alignment = .center
    label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    label.textColor = NSColor.secondaryLabelColor
    container.addSubview(label)

    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
    ])

    return container
  }

  override func decorate(view: UXView) {
    view.wantsLayer = true
    view.layer?.cornerRadius = 12
    view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
  }

  override func sizeForDecoratorView(
    textViewWidth: CGFloat,
    attributes: [NSAttributedString.Key: Any]
  ) -> CGSize {
    CGSize(width: textViewWidth, height: Self.defaultHeight)
  }
}
#endif
