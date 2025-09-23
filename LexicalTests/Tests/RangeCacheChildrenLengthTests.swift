@testable import Lexical
@testable import Lexical
import XCTest
import XCTest


@MainActor
@MainActor
final class RangeCacheChildrenLengthTests: XCTestCase {
final class RangeCacheChildrenLengthTests: XCTestCase {


  func testChildrenLengthUpdatesOnNestedEdits() throws {
  func testChildrenLengthUpdatesOnNestedEdits() throws {
    // Use legacy reconciler for this structural test to avoid
    // Use legacy reconciler for this structural test to avoid
    // optimized path range-cache/Fenwick ordering effects under development.
    // optimized path range-cache/Fenwick ordering effects under development.
    let flags = FeatureFlags(optimizedReconciler: false, reconcilerMetrics: false)
    let flags = FeatureFlags(optimizedReconciler: false, reconcilerMetrics: false)
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: flags)
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: flags)
    let editor = ctx.editor
    let editor = ctx.editor


    var paragraphKey: NodeKey = ""
    var paragraphKey: NodeKey = ""
    var textKey: NodeKey = ""
    var textKey: NodeKey = ""


    try editor.update {
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let p = ParagraphNode()
      let t = TextNode(text: "Hello", key: nil)
      let t = TextNode(text: "Hello", key: nil)
      try p.append([t])
      try p.append([t])
      try root.append([p])
      try root.append([p])
      paragraphKey = p.key
      paragraphKey = p.key
      textKey = t.key
      textKey = t.key
    }
    }


    let initialChildrenLength = editor.rangeCache[paragraphKey]?.childrenLength ?? -1
    let initialChildrenLength = editor.rangeCache[paragraphKey]?.childrenLength ?? -1
    XCTAssertGreaterThanOrEqual(initialChildrenLength, 0, "Expected paragraph in range cache")
    XCTAssertGreaterThanOrEqual(initialChildrenLength, 0, "Expected paragraph in range cache")


    let oldTextLen = editor.rangeCache[textKey]?.textLength ?? 0
    let oldTextLen = editor.rangeCache[textKey]?.textLength ?? 0


    // Update text to a longer string
    // Update text to a longer string
    try editor.update {
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode(),
      guard let root = getActiveEditorState()?.getRootNode(),
            let p = root.getFirstChild() as? ParagraphNode,
            let p = root.getFirstChild() as? ParagraphNode,
            let t = p.getChildren().first as? TextNode else { return }
            let t = p.getChildren().first as? TextNode else { return }
      try t.setText("Hello world!")
      try t.setText("Hello world!")
    }
    }


    let newTextLen = editor.rangeCache[textKey]?.textLength ?? 0
    let newTextLen = editor.rangeCache[textKey]?.textLength ?? 0
    let expectedDelta = newTextLen - oldTextLen
    let expectedDelta = newTextLen - oldTextLen
    let afterChildrenLength = editor.rangeCache[paragraphKey]?.childrenLength ?? -1
    let afterChildrenLength = editor.rangeCache[paragraphKey]?.childrenLength ?? -1


    XCTAssertEqual(afterChildrenLength, initialChildrenLength + expectedDelta,
    XCTAssertEqual(afterChildrenLength, initialChildrenLength + expectedDelta,
                   "childrenLength should track nested text delta")
                   "childrenLength should track nested text delta")


    // Insert a second text node and verify childrenLength grows
    // Insert a second text node and verify childrenLength grows
    try editor.update {
    try editor.update {
      guard let p: ParagraphNode = getNodeByKey(key: paragraphKey) else { return }
      guard let p: ParagraphNode = getNodeByKey(key: paragraphKey) else { return }
      let extra = TextNode(text: " EXTRA", key: nil)
      let extra = TextNode(text: " EXTRA", key: nil)
      try p.append([extra])
      try p.append([extra])
    }
    }


    let afterInsertChildrenLength = editor.rangeCache[paragraphKey]?.childrenLength ?? -1
    print("DEBUG childrenLength: initial=\(initialChildrenLength) afterText=\(afterChildrenLength) afterInsert=\(afterInsertChildrenLength)")
    XCTAssertGreaterThan(afterInsertChildrenLength, afterChildrenLength,
                         "childrenLength should increase after inserting child text node")
  }
}
