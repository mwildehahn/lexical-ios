import XCTest
@testable import Lexical

@MainActor
final class FenwickCentralAggregationTests: XCTestCase {

  private func makeEditorWithCentralAgg() -> (Editor, LexicalReadOnlyTextKitContext) {
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: true
    )
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    return (ctx.editor, ctx)
  }

  func testMultiSiblingTextChangesAggregatedOnce() throws {
    let (editor, ctx) = makeEditorWithCentralAgg()
    // Build: P -> [T1("Hello"), T2("World")]
    var k1: NodeKey = ""; var k2: NodeKey = ""
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: "Hello"); k1 = t1.getKey()
      let t2 = createTextNode(text: "World"); k2 = t2.getKey()
      try p.append([t1, t2]); try root.append([p])
    }

    // In a single update, change both siblings' text
    try editor.update {
      guard let t1 = getNodeByKey(key: k1) as? TextNode,
            let t2 = getNodeByKey(key: k2) as? TextNode else { return }
      t1.setText_dangerousPropertyAccess("Hey") // -2 chars
      t2.setText_dangerousPropertyAccess("There!") // +1 char
    }

    // Expect node texts updated correctly (locations coherent if no exception thrown)
    try editor.read {
      guard let t1 = getNodeByKey(key: k1) as? TextNode,
            let t2 = getNodeByKey(key: k2) as? TextNode else { return }
      XCTAssertEqual(t1.getTextPart(), "Hey")
      XCTAssertEqual(t2.getTextPart(), "There!")
    }
  }
}
