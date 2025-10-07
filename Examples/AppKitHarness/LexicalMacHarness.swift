#if canImport(AppKit)
import AppKit
import Lexical
import LexicalAppKit

/// Minimal view controller that hosts the AppKit Lexical editor.
/// Embed this in your macOS application's window to experiment with editing behaviour.
public final class LexicalMacHarnessViewController: NSViewController {
  public let hostView: LexicalNSView
  public let textView: TextViewMac
  public let overlayView: LexicalOverlayViewMac
  public let adapter: AppKitFrontendAdapter

  public init(
    theme: Theme = Theme(),
    plugins: [Plugin] = []
  ) {
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
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public override func loadView() {
    adapter.bind()
    view = hostView
    hostView.translatesAutoresizingMaskIntoConstraints = false
    configureDemoDocument()
  }

  /// Seeds the editor with a simple document and sets a placeholder.
  private func configureDemoDocument() {
    textView.updatePlaceholder("Start typing…")
    do {
      try adapter.editor.update {
        guard let root = getRoot() else { return }
        let intro = createParagraphNode()
        try intro.append([createTextNode(text: "Welcome to Lexical on AppKit!\n")])

        let paragraph = createParagraphNode()
        try paragraph.append([
          createTextNode(text: "This harness demonstrates the AppKit frontend. "),
          createTextNode(text: "Try typing, deleting words (⌥⌫) or toggling bold (⌘B).")
        ])

        try root.append([intro, paragraph])
      }
    } catch {
      adapter.editor.log(.editor, .error, "Failed to seed demo document: \(error)")
    }
  }
}
#endif
