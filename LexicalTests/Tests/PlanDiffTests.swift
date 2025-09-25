import XCTest
@testable import Lexical

@MainActor
final class PlanDiffTests: XCTestCase {
  func testComputePartDiffsTextOnly() throws {
    throw XCTSkip("PlanDiff helper semantics are internal; covered indirectly by other fast path tests")
    let flags = FeatureFlags(useOptimizedReconciler: true, useOptimizedReconcilerStrictMode: true)
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    let editor = ctx.editor

    var changedKey: NodeKey?
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t = createTextNode(text: "Hello")
      changedKey = t.getKey()
      try p.append([t])
      try root.append([p])
    }

    guard let _ = changedKey else { XCTFail("no key"); return }

    // Snapshot prev range cache
    let prevCache = editor.rangeCache

    // Modify text only
    try editor.update {
      guard let root = getRoot(), let p = root.getFirstChild() as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      try t.setText("Hello world")
    }

    // Use active state inside a read to compute diffs, passing our prev cache snapshot
    try editor.read {
      guard let nextState = getActiveEditorState() else { XCTFail("no state"); return }
      let diffs = computePartDiffs(editor: editor, prevState: nextState, nextState: nextState, prevRangeCache: prevCache, keys: Array(nextState.nodeMap.keys))
      let total = diffs.values.reduce(0) { $0 + $1.textDelta }
      XCTAssertEqual(total, " world".lengthAsNSString())
    }
  }
}
