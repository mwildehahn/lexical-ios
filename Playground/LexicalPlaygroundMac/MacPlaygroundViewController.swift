#if canImport(AppKit)
import AppKit
import Lexical
import LexicalAppKit

/// Hosts a Lexical editor instance for the macOS playground.
/// This mirrors the harness controller but will grow additional hooks for toolbars,
/// inspectors, and performance utilities.
@MainActor
final class MacPlaygroundViewController: NSViewController {
  let hostView: LexicalNSView
  let textView: TextViewMac
  let overlayView: LexicalOverlayViewMac
  let adapter: AppKitFrontendAdapter
  private(set) var activeFeatureFlags: FeatureFlags
  private(set) var activeProfile: FeatureFlags.OptimizedProfile

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
    textView.updatePlaceholder("Start typing…")
    seedDocumentIfNeeded()
    view = hostView
  }

  private func seedDocumentIfNeeded() {
    let editorState = adapter.editor.getEditorState()
    let shouldSeed = editorState.getRootNode()?.getChildren().isEmpty ?? true

    guard shouldSeed else {
      return
    }

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

  func applyFeatureFlags(_ flags: FeatureFlags, profile: FeatureFlags.OptimizedProfile) {
    activeFeatureFlags = flags
    activeProfile = profile
    adapter.editor.featureFlags = flags
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

  enum FeatureFlagsListType {
    case unordered
    case ordered
    case checklist
  }
}
#endif
