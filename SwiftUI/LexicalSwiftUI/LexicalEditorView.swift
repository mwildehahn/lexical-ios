#if canImport(SwiftUI)
import SwiftUI
import Lexical

#if os(iOS)
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
#elseif os(macOS)
@available(macOS 14.0, *)
@MainActor
public struct LexicalEditorView: View {
  public init(editorConfig: EditorConfig = EditorConfig(theme: Theme(), plugins: []),
              featureFlags: FeatureFlags = FeatureFlags()) {}

  public var body: some View {
    Text("LexicalEditorView is not yet available on macOS")
      .font(.system(.body, design: .rounded))
      .foregroundStyle(.secondary)
  }
}
#endif
#endif
