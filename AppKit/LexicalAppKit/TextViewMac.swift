#if canImport(AppKit)
import AppKit
import Lexical

/// Placeholder NSTextView subclass for AppKit integration.
@MainActor
public class TextViewMac: NSTextView {
  public var placeholderString: String?
  public let editor: Editor
  public let lexicalTextStorage: TextStorage
  public let lexicalLayoutManager: LayoutManager
  public let lexicalTextContainer: TextContainer

  public init(editorConfig: EditorConfig = EditorConfig(theme: Theme(), plugins: []),
              featureFlags: FeatureFlags = FeatureFlags()) {
    lexicalTextStorage = TextStorage()
    lexicalLayoutManager = LayoutManager()
    lexicalTextContainer = TextContainer()
    lexicalLayoutManager.addTextContainer(lexicalTextContainer)
    lexicalTextStorage.addLayoutManager(lexicalLayoutManager)

    editor = Editor(featureFlags: featureFlags, editorConfig: editorConfig)
    lexicalTextStorage.editor = editor

    super.init(frame: .zero, textContainer: lexicalTextContainer)

    isEditable = true
    isRichText = true
    drawsBackground = true
    font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public func updatePlaceholder(_ placeholder: String?) {
    placeholderString = placeholder
  }
}
#endif
