import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerLegacyParityMultiEditTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let theme = Theme(); let cfg = EditorConfig(theme: theme, plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false, proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true, useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true, useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: true
    )
    let legFlags = FeatureFlags(reconcilerSanityCheck: false, proxyTextViewInputDelegate: false, useOptimizedReconciler: false)
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func testMultiSiblingTextAndPrePostEditsParity() throws {
    let (opt, leg) = makeEditors()
    // Build same initial tree on both
    func build(on editor: Editor) throws -> (NodeKey, NodeKey, NodeKey) {
      var k1: NodeKey = ""; var k2: NodeKey = ""; var pKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); pKey = p.getKey()
        let t1 = createTextNode(text: "Hello"); k1 = t1.getKey()
        let t2 = createTextNode(text: "World"); k2 = t2.getKey()
        try p.append([t1, t2]); try root.append([p])
      }
      return (k1, k2, pKey)
    }
    let (k1o, k2o, po) = try build(on: opt.0)
    let (k1l, k2l, pl) = try build(on: leg.0)

    // Apply identical multi-sibling edits in one update: change both texts
    try opt.0.update {
      guard let t1 = getNodeByKey(key: k1o) as? TextNode,
            let t2 = getNodeByKey(key: k2o) as? TextNode else { return }
      t1.setText_dangerousPropertyAccess("Hey")
      t2.setText_dangerousPropertyAccess("There!")
    }
    try leg.0.update {
      guard let t1 = getNodeByKey(key: k1l) as? TextNode,
            let t2 = getNodeByKey(key: k2l) as? TextNode else { return }
      t1.setText_dangerousPropertyAccess("Hey")
      t2.setText_dangerousPropertyAccess("There!")
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
