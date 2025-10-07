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
}
#endif
