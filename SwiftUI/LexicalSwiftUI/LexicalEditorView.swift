#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import Lexical

@available(iOS 17.0, *)
@MainActor
public struct LexicalEditorView: View {
  private let lexicalView: LexicalView

  public init(editorConfig: EditorConfig = EditorConfig(theme: Theme(), plugins: []),
              featureFlags: FeatureFlags = FeatureFlags()) {
    self.lexicalView = LexicalView(editorConfig: editorConfig, featureFlags: featureFlags)
  }

  public var body: some View {
    Representable(lexicalView: lexicalView)
  }

  public var editor: Editor {
    lexicalView.editor
  }

  private struct Representable: UIViewRepresentable {
    let lexicalView: LexicalView

    func makeUIView(context: Context) -> LexicalView {
      lexicalView
    }

    func updateUIView(_ uiView: LexicalView, context: Context) {
      // LexicalView manages its own updates.
    }
  }
}
#endif
