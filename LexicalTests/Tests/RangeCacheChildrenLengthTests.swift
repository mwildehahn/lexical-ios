@testable import Lexical
import XCTest

@MainActor
final class RangeCacheChildrenLengthTests: XCTestCase {

  func testChildrenLengthUpdatesOnNestedEdits() throws {
    let flags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: false)
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: flags)
    let editor = ctx.editor

    var paragraphKey: NodeKey = ""
    var textKey: NodeKey = ""

    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let t = TextNode(text: "Hello", key: nil)
      try p.append([t])
      try root.append([p])
      paragraphKey = p.key
      textKey = t.key
    }

    let initialChildrenLength = editor.rangeCache[paragraphKey]?.childrenLength ?? -1
    XCTAssertGreaterThanOrEqual(initialChildrenLength, 0, "Expected paragraph in range cache")

    let oldTextLen = editor.rangeCache[textKey]?.textLength ?? 0

    // Update text to a longer string
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode(),
            let p = root.getFirstChild() as? ParagraphNode,
            let t = p.getChildren().first as? TextNode else { return }
      try t.setText("Hello world!")
    }

    let newTextLen = editor.rangeCache[textKey]?.textLength ?? 0
    let expectedDelta = newTextLen - oldTextLen
    let afterChildrenLength = editor.rangeCache[paragraphKey]?.childrenLength ?? -1

    XCTAssertEqual(afterChildrenLength, initialChildrenLength + expectedDelta,
                   "childrenLength should track nested text delta")

    // Insert a second text node and verify childrenLength grows
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode(),
            let p = root.getFirstChild() as? ParagraphNode else { return }
      let extra = TextNode(text: " EXTRA", key: nil)
      try p.append([extra])
    }

    let afterInsertChildrenLength = editor.rangeCache[paragraphKey]?.childrenLength ?? -1
    XCTAssertGreaterThan(afterInsertChildrenLength, afterChildrenLength,
                         "childrenLength should increase after inserting child text node")
  }
}

